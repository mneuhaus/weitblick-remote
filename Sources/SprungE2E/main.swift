// sprung-e2e: end-to-end test against the test VM (scripts/e2e.sh): keyboard, clipboard (text,
// images, HTML, RTF, files), drive redirection, printers, audio and auto-reconnect.
//
//   sprung-e2e [--env PATH] [--out DIR] [--runs N]
//
// Each run prepares the VM (prlctl) and a shared folder under build/e2e-work, connects as the test
// user, opens Notepad through Win+R and drives keys through the KeyboardEngine (real German layout)
// and the clipboard through ClipboardSync on a private pasteboard; Windows-side checks run as
// PowerShell inside the session. Never posts OS-level events, never touches the general
// pasteboard, unplugs only the VM's network adapter. Exits 0 when every check of every run passed.
import AppKit
import Darwin
import SprungKit

struct Options {
    var envFile: URL?
    var evidence = URL(fileURLWithPath: "build/evidence/m3-e2e")
    var runs = 1

    init(_ arguments: [String]) throws {
        var iterator = arguments.dropFirst().makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--env": envFile = iterator.next().map { URL(fileURLWithPath: $0) }
            case "--out": evidence = URL(fileURLWithPath: iterator.next() ?? evidence.path)
            case "--runs": runs = Int(iterator.next() ?? "") ?? runs
            default: throw E2EFailure("unknown argument \(argument)")
            }
        }
    }
}

func log(_ message: String) {
    let time = Date().formatted(.dateTime.hour().minute().second().secondFraction(.fractional(3)))
    print("[\(time)] \(message)")
    fflush(stdout)
}

/// Test files (the shared folder, files to copy) live here, never in the user's own folders.
let work = URL(fileURLWithPath: "build/e2e-work", isDirectory: true).standardizedFileURL
/// FreeRDP logs to a file in the evidence folder, with rdpsnd at debug level for the audio check.
nonisolated(unsafe) var freerdpLog = URL(fileURLWithPath: "/dev/null")

func logFreeRDPToFile(in directory: URL) {
    freerdpLog = directory.appendingPathComponent("freerdp.log")
    setenv("WLOG_APPENDER", "FILE", 1)
    setenv("WLOG_FILEAPPENDER_OUTPUT_FILE_PATH", directory.path, 1)
    setenv("WLOG_FILEAPPENDER_OUTPUT_FILE_NAME", freerdpLog.lastPathComponent, 1)
    setenv("WLOG_FILTER", "com.freerdp.channels.rdpsnd.client:DEBUG", 1)
}

@MainActor
func runOnce(_ vm: TestVMEnvironment, number: Int, evidence: URL) async throws -> [String] {
    let directory = evidence.appendingPathComponent("run-\(number)")
    try? FileManager.default.removeItem(at: directory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    log("run \(number): preparing the VM and the shared folder")
    try TestVM().prepare(scripts: ["clip.ps1": SessionScript.data, FileScript.name: FileScript.data])
    let share = work.appendingPathComponent("share", isDirectory: true)
    let scratch = work.appendingPathComponent("scratch", isDirectory: true)
    try Scenario.prepareShare(share)

    var configuration = SessionConfiguration(host: vm.host, username: vm.username, password: vm.password,
                                             desktopSize: PixelSize(width: 1440, height: 900))
    configuration.keyboardLayout = 0x0407 // German, like the German Mac layout the driver types with
    // Run 1 plays audio on the Mac, runs 2 and 3 check that "remote" and "off" send nothing.
    configuration.audio = AudioPlayback.allCases[(number - 1) % AudioPlayback.allCases.count]
    configuration.printers = true
    configuration.drives = [SharedDrive(name: FileScript.shareName, localPath: share)]
    guard let probe = SmokeProbe(configuration: configuration) else { throw E2EFailure("could not create session") }
    // A private pasteboard: the user's clipboard stays untouched.
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("nrw.neuhaus.sprung.e2e.\(getpid())"))
    pasteboard.clearContents()
    defer { pasteboard.releaseGlobally() }

    let scenario = try Scenario(vm: TestVM(), probe: probe, pasteboard: pasteboard, evidence: directory,
                                share: share, scratch: scratch, freerdpLog: freerdpLog)
    log("run \(number): connecting to \(vm.host) as \(vm.username), audio \(configuration.audio.rawValue)")
    probe.session.connect()
    try await probe.wait("connection", timeout: 30) { probe.isConnected }
    try await probe.waitForSettledFrame()
    try await Task.sleep(for: .seconds(2)) // shell ready for Win+R after (re)logon

    var failures: [String]
    do {
        try await scenario.run()
        failures = scenario.failures
    } catch {
        failures = scenario.failures + ["aborted: \(error)"]
        if let snapshot = FramebufferSnapshot(session: probe.session) {
            try? snapshot.writePNG(to: directory.appendingPathComponent("aborted.png"))
        }
    }
    log("run \(number): \(scenario.summary)\(failures.isEmpty ? "" : ", \(failures.count) failures")")
    probe.session.disconnect()
    try await probe.wait("disconnect", timeout: 15) { probe.ending != nil }
    await probe.session.closeAndWait()
    return failures
}

@MainActor
func main() async -> Int32 {
    do {
        let options = try Options(CommandLine.arguments)
        guard let envFile = options.envFile ?? TestVMEnvironment.locate() else {
            throw E2EFailure(".testvm.env not found (pass --env)")
        }
        let vm = try TestVMEnvironment(contentsOf: envFile)
        try FileManager.default.createDirectory(at: options.evidence, withIntermediateDirectories: true)
        logFreeRDPToFile(in: options.evidence) // before FreeRDP's first log line
        var failedRuns = 0
        for number in 1...max(1, options.runs) {
            let failures = try await runOnce(vm, number: number, evidence: options.evidence)
            failures.forEach { log("  FAILED: \($0)") }
            if !failures.isEmpty { failedRuns += 1 }
        }
        log(failedRuns == 0 ? "E2E OK: \(options.runs) runs green" : "E2E FAIL: \(failedRuns) of \(options.runs) runs failed")
        return failedRuns == 0 ? 0 : 1
    } catch {
        log("E2E FAIL: \(error)")
        return 1
    }
}

let status = await main()
RDPSession.waitForAllSessionsToClose(timeout: 15)
exit(status)
