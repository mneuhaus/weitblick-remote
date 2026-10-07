import AppKit
import SprungKit
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var connectWindow: NSWindow?
    private var sessions: [SessionWindowController] = []
    private var isTerminating = false

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        let request = Self.initialRequest()
        if CommandLine.arguments.contains("--autoconnect"), !request.host.isEmpty {
            open(request, retina: !CommandLine.arguments.contains("--no-retina"))
        } else {
            showConnectWindow(request)
        }
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
        sessions.forEach { $0.close() }
        // exit() tears down FreeRDP's global state; the session threads must be gone first.
        RDPSession.waitForAllSessionsToClose(timeout: 5)
    }

    private func showConnectWindow(_ request: ConnectRequest) {
        let form = ConnectForm(request: request) { [weak self] request, retina in
            self?.open(request, retina: retina)
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: form))
        window.title = "Sprung"
        window.styleMask.remove(.resizable)
        window.center()
        window.makeKeyAndOrderFront(nil)
        connectWindow = window
    }

    private func open(_ request: ConnectRequest, retina: Bool) {
        var configuration = SessionConfiguration(
            host: request.host, username: request.username, password: request.password,
            desktopSize: PixelSize(width: 1280, height: 800))
        configuration.domain = request.domain
        guard let controller = SessionWindowController(configuration: configuration, retina: retina) else {
            NSAlert(error: CocoaError(.featureUnsupported)).runModal()
            return
        }
        controller.onClose = { [weak self, weak controller] in
            guard let self else { return }
            sessions.removeAll { $0 === controller }
            if sessions.isEmpty && !isTerminating { returnToConnectWindow() }
        }
        sessions.append(controller)
        connectWindow?.orderOut(nil)
        controller.start()
    }

    private func returnToConnectWindow() {
        if let connectWindow {
            connectWindow.makeKeyAndOrderFront(nil)
        } else {
            showConnectWindow(Self.initialRequest())
        }
    }

    /// DEBUG builds prefill the form from `.testvm.env`.
    private static func initialRequest() -> ConnectRequest {
        #if DEBUG
        if let url = TestVMEnvironment.locate(), let vm = try? TestVMEnvironment(contentsOf: url) {
            return ConnectRequest(host: vm.host, username: vm.username, password: vm.password)
        }
        #endif
        return ConnectRequest()
    }
}
