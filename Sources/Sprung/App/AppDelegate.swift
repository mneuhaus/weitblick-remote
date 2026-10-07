import AppKit
import ConnectionStore
import SprungKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: WindowCoordinator!

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    /// Before launch finishes: files opened from Finder arrive before `applicationDidFinishLaunching`.
    func applicationWillFinishLaunching(_ notification: Notification) {
        let options = LaunchOptions()
        let library = ConnectionLibrary(store: ConnectionStore(fileURL: options.storeURL),
                                        credentials: Self.credentialStore(options))
        coordinator = WindowCoordinator(library: library, options: options)
        NSApp.mainMenu = MainMenu.make(coordinator: coordinator)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No activate(): launched from Finder or the Dock, macOS activates the app anyway; launched
        // in the background (open -g) it must stay there.
        Task {
            await coordinator.start()
            #if DEBUG
            DebugHooks(coordinator: coordinator).run()
            #endif
        }
    }

    private static func credentialStore(_ options: LaunchOptions) -> any CredentialStore {
        #if DEBUG
        if let store = DebugHooks.credentialStore(options) { return store }
        #endif
        return KeychainCredentialStore()
    }

    func application(_ sender: NSApplication, open urls: [URL]) {
        coordinator.open(urls)
    }

    /// The overview can be closed while no session runs; the Dock icon brings it back.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { coordinator.showOverview() }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        coordinator.shouldTerminate()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.closeAllSessions()
        // exit() tears down FreeRDP's global state; the session threads must be gone first.
        RDPSession.waitForAllSessionsToClose(timeout: 5)
    }
}
