// weitblick-smoke: headless end-to-end check against the test VM.
//
//   weitblick-smoke [--env PATH] [--out DIR] [--cycles N] [--soak SECONDS] [--no-nla]
//
// Connects, waits for a settled first frame (DIR/smoke.png), moves the mouse, resizes to
// 1600x1000 and waits for the server's desktop resize (DIR/smoke-resized.png), hovers the
// search box for a text cursor (DIR/cursors/*.png) and disconnects. Then optionally soaks
// (mouse, right-click + Esc, wheel and resizes for SECONDS) and runs N connect/disconnect
// cycles (each asking for a resize during logon) watching memory. In between, sessions that must
// fail check the end reason the app gets (certificate, wrong password, closed port, NLA off; see
// EndReasonChecks.swift). Exits 0 or 1 with a reason.
//
// --no-nla connects without Network Level Authentication (TLS, else standard RDP security; the VM
// must allow it: UserAuthentication = 0) and skips the end-reason checks, which assume NLA.
import Darwin
import Foundation
import WeitblickKit

struct Options {
    var envFile: URL?
    var outputDirectory = URL(fileURLWithPath: "build")
    var cycles = 10
    var soakSeconds = 0
    var nla = true

    init(_ arguments: [String]) throws {
        var iterator = arguments.dropFirst().makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--env": envFile = iterator.next().map { URL(fileURLWithPath: $0) }
            case "--out": outputDirectory = URL(fileURLWithPath: iterator.next() ?? "build")
            case "--cycles": cycles = Int(iterator.next() ?? "") ?? cycles
            case "--soak": soakSeconds = Int(iterator.next() ?? "") ?? soakSeconds
            case "--no-nla": nla = false
            default: throw SmokeFailure("unknown argument \(argument)")
            }
        }
    }
}

func log(_ message: String) {
    let time = Date().formatted(.dateTime.hour().minute().second().secondFraction(.fractional(3)))
    print("[\(time)] \(message)")
    fflush(stdout)
}

/// Physical memory footprint of this process (what Activity Monitor shows).
func memoryFootprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
}

/// Set from --no-nla.
nonisolated(unsafe) var useNLA = true

@MainActor
func makeConfiguration(_ vm: TestVMEnvironment, size: PixelSize) -> SessionConfiguration {
    var configuration = SessionConfiguration(host: vm.host, username: vm.username, password: vm.password, desktopSize: size)
    configuration.nla = useNLA
    configuration.audio = .off
    configuration.clipboard = false // covered by weitblick-e2e
    return configuration
}

@MainActor
func connect(_ vm: TestVMEnvironment, size: PixelSize) async throws -> SmokeProbe {
    try await connect(makeConfiguration(vm, size: size))
}

@MainActor
func connect(_ configuration: SessionConfiguration) async throws -> SmokeProbe {
    guard let probe = SmokeProbe(configuration: configuration) else {
        throw SmokeFailure("could not create session")
    }
    probe.session.connect()
    try await probe.wait("connection", timeout: 30) { probe.isConnected }
    return probe
}

@MainActor
func disconnect(_ probe: SmokeProbe) async throws {
    probe.session.disconnect()
    try await probe.wait("disconnect", timeout: 15) { probe.ending != nil }
    if let ending = probe.ending, ending.code != 0 {
        throw SmokeFailure("disconnect reported an error: \(ending.message)")
    }
    guard probe.session.disconnectReason == .requested else {
        throw SmokeFailure("disconnect reason is \(String(describing: probe.session.disconnectReason)), expected requested")
    }
    await probe.session.closeAndWait()
}

@MainActor
func saveSnapshot(_ probe: SmokeProbe, to url: URL, expecting size: PixelSize) throws {
    guard let snapshot = FramebufferSnapshot(session: probe.session) else { throw SmokeFailure("no framebuffer") }
    try snapshot.writePNG(to: url)
    let colors = snapshot.sampledColorCount
    log("wrote \(url.path) (\(snapshot.width)x\(snapshot.height), \(colors) sampled colors, alpha \(snapshot.alphaRange))")
    guard snapshot.width == size.width, snapshot.height == size.height else {
        throw SmokeFailure("framebuffer is \(snapshot.width)x\(snapshot.height), expected \(size)")
    }
    guard colors >= 8 else { throw SmokeFailure("frame looks blank (\(colors) colors)") }
}

@MainActor
func runScenario(_ vm: TestVMEnvironment, output: URL) async throws {
    let initial = PixelSize(width: 1280, height: 800)
    log("connecting to \(vm.host) as \(vm.username) at \(initial)")
    let probe = try await connect(vm, size: initial)
    log("connected")

    try await probe.waitForSettledFrame()
    // Without NLA Windows logs on inside the session ("Bitte warten", please wait, on black) before the desktop.
    let desktopDeadline = Date().addingTimeInterval(90)
    while (FramebufferSnapshot(session: probe.session)?.sampledColorCount ?? 0) < 8, Date() < desktopDeadline {
        try await Task.sleep(for: .seconds(1))
        try await probe.waitForSettledFrame()
    }
    log("first frame settled after \(probe.frameCount) frame signals, \(probe.pointerImages.count) cursor shapes")
    try saveSnapshot(probe, to: output.appendingPathComponent("smoke.png"), expecting: initial)

    for step in 0...20 {
        probe.session.sendMouseMove(to: RemotePoint(x: 100 + step * 40, y: 100 + step * 25))
        try await Task.sleep(for: .milliseconds(10))
    }
    log("mouse moved")

    let resized = PixelSize(width: 1600, height: 1000)
    probe.session.setResolution(resized, scale: .standard)
    try await probe.wait("desktop resize to \(resized)", timeout: 20) { probe.resizes.contains(resized) }
    log("desktop resized to \(resized)")
    try await probe.waitForSettledFrame()
    try saveSnapshot(probe, to: output.appendingPathComponent("smoke-resized.png"), expecting: resized)

    try await checkCursors(probe, desktop: resized, output: output.appendingPathComponent("cursors"))

    try await disconnect(probe)
    log("disconnected cleanly")
}

/// Hovers the taskbar search box (text cursor) and the wallpaper (arrow) and saves every cursor
/// shape the server showed.
@MainActor
func checkCursors(_ probe: SmokeProbe, desktop: PixelSize, output: URL) async throws {
    let searchBox = RemotePoint(x: desktop.width / 2 - 100, y: desktop.height - 24)
    let wallpaper = RemotePoint(x: desktop.width * 3 / 5, y: desktop.height * 2 / 5)
    let before = Set(probe.shownPointers)
    for point in [searchBox, wallpaper] {
        probe.session.sendMouseMove(to: point)
        try await Task.sleep(for: .seconds(1))
    }
    try? FileManager.default.removeItem(at: output)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    var seen = Set<UInt64>()
    for id in probe.shownPointers where seen.insert(id).inserted {
        guard let image = probe.pointerImages[id] else { continue }
        let url = output.appendingPathComponent("cursor-\(seen.count)-\(image.width)x\(image.height)-hot\(image.hotspotX),\(image.hotspotY).png")
        try writeBGRAPNG(image.bgra, width: image.width, height: image.height, bytesPerRow: image.width * 4, alpha: .first, to: url)
    }
    log("cursors: \(seen.count) shapes shown (\(Set(probe.shownPointers).subtracting(before).count) new while hovering), saved to \(output.path)")
    guard !seen.isEmpty else { throw SmokeFailure("server never set a cursor shape") }
}

/// Keeps one session busy: mouse sweeps, right-click + Esc, wheel and a resize every 10 s.
@MainActor
func runSoak(_ vm: TestVMEnvironment, seconds: Int) async throws {
    guard seconds > 0 else { return }
    let sizes = [PixelSize(width: 1280, height: 800), PixelSize(width: 1440, height: 900)]
    let probe = try await connect(vm, size: sizes[0])
    try await probe.wait("first frame", timeout: 20) { probe.frameCount > 0 }
    let baseline = memoryFootprintMB()
    let start = Date()
    var tick = 0
    var size = sizes[0]
    while Date().timeIntervalSince(start) < Double(seconds) {
        let t = Double(tick) / 50
        let point = RemotePoint(x: Int(Double(size.width) * (0.5 + 0.4 * sin(t))),
                                y: Int(Double(size.height) * (0.45 + 0.35 * cos(t * 1.3))))
        probe.session.sendMouseMove(to: point)
        if tick % 200 == 100 { // right-click the wallpaper, then close the menu with Esc
            let wallpaper = RemotePoint(x: size.width * 3 / 5, y: size.height * 2 / 5)
            probe.session.sendMouseButton(.right, down: true, at: wallpaper)
            probe.session.sendMouseButton(.right, down: false, at: wallpaper)
            try await Task.sleep(for: .milliseconds(400))
            probe.session.sendScancode(0x01, extended: false, down: true)
            probe.session.sendScancode(0x01, extended: false, down: false)
        }
        if tick % 150 == 50 {
            probe.session.sendMouseWheel(vertical: -240, horizontal: 0, at: point)
            probe.session.sendMouseWheel(vertical: 240, horizontal: 0, at: point)
        }
        if tick % 500 == 499 {
            size = size == sizes[0] ? sizes[1] : sizes[0]
            let target = size
            let count = probe.resizes.count
            probe.session.setResolution(target, scale: .standard)
            try await probe.wait("soak resize to \(target)", timeout: 10) {
                probe.resizes.count > count && probe.resizes.last == target
            }
            log(String(format: "soak %3.0f s: resized to %@, %d frames, footprint %.1f MB",
                       Date().timeIntervalSince(start), target.description, probe.frameCount, memoryFootprintMB()))
        }
        tick += 1
        try await Task.sleep(for: .milliseconds(20))
    }
    try await disconnect(probe)
    log(String(format: "soak done: %d s, %d frames, footprint %.1f MB -> %.1f MB", seconds, probe.frameCount,
               baseline, memoryFootprintMB()))
}

@MainActor
func runCycles(_ vm: TestVMEnvironment, count: Int) async throws {
    guard count > 0 else { return }
    let baseline = memoryFootprintMB()
    let early = PixelSize(width: 1152, height: 864)
    for cycle in 1...count {
        let probe = try await connect(vm, size: PixelSize(width: 1024, height: 768))
        // Asked for while Windows is still logging on, like a window resized during connect.
        probe.session.setResolution(early, scale: .standard)
        try await probe.wait("first frame", timeout: 20) { probe.frameCount > 0 }
        try await probe.wait("early resize to \(early)", timeout: 20) { probe.resizes.contains(early) }
        try await disconnect(probe)
        log(String(format: "cycle %d/%d ok, footprint %.1f MB", cycle, count, memoryFootprintMB()))
    }
    log(String(format: "footprint %.1f MB -> %.1f MB after %d cycles", baseline, memoryFootprintMB(), count))
}

@MainActor
func main() async -> Int32 {
    do {
        let options = try Options(CommandLine.arguments)
        guard let envFile = options.envFile ?? TestVMEnvironment.locate() else {
            throw SmokeFailure(".testvm.env not found (pass --env)")
        }
        let vm = try TestVMEnvironment(contentsOf: envFile)
        try FileManager.default.createDirectory(at: options.outputDirectory, withIntermediateDirectories: true)
        useNLA = options.nla
        try await runScenario(vm, output: options.outputDirectory)
        if options.nla { try await runEndReasonChecks(vm) }
        try await runSoak(vm, seconds: options.soakSeconds)
        try await runCycles(vm, count: options.cycles)
        log("SMOKE OK")
        return 0
    } catch {
        log("SMOKE FAIL: \(error)")
        return 1
    }
}

let status = await main()
// A session that ended in an error is still being torn down; exit() must not race its threads.
RDPSession.waitForAllSessionsToClose(timeout: 15)
exit(status)
