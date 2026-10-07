import AppKit
import ConnectionStore
import os
import SprungKit

/// Owns the overview and the session windows: opens sessions as native tabs next to the overview
/// (or as own windows), switches tabs, opens files and decides about quitting.
@MainActor
final class WindowCoordinator: NSObject, NSMenuItemValidation, NSMenuDelegate {
    /// Shared by the overview and every session window so they form one tab group.
    static let tabbingIdentifier = "nrw.neuhaus.sprung.main"

    let library: ConnectionLibrary
    let options: LaunchOptions
    let activity = SessionActivity()
    let overview: OverviewWindowController
    private(set) var sessions: [SessionWindowController] = []
    private lazy var settings = SettingsWindowController(storeURL: library.store.fileURL)
    private var started = false
    private var pendingFiles: [URL] = []

    private static let logger = Logger(subsystem: "nrw.neuhaus.sprung", category: "windows")

    init(library: ConnectionLibrary, options: LaunchOptions) {
        self.library = library
        self.options = options
        overview = OverviewWindowController(library: library, activity: activity, options: options)
        super.init()
        overview.connect = { [weak self] ids in ids.forEach { self?.connect($0) } }
        overview.canClose = { [weak self] in self?.sessions.isEmpty ?? true }
    }

    /// Loads the connections, shows the overview and offers the Jump migration on the first start.
    func start() async {
        await library.load()
        showOverview()
        started = true
        if library.isFirstStart, library.loadError == nil, overview.jumpAvailable {
            overview.importFromJump()
        }
        if !pendingFiles.isEmpty {
            overview.importRDPFiles(pendingFiles)
            pendingFiles = []
        }
    }

    @objc func showOverview(_ sender: Any? = nil) {
        overview.window?.tabGroup?.selectedWindow = overview.window
        overview.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: Menu commands (Ablage, Einstellungen)

    @objc func newConnection(_ sender: Any?) {
        showOverview()
        overview.newConnection()
    }

    @objc func importFromJump(_ sender: Any?) {
        showOverview()
        overview.importFromJump()
    }

    @objc func importRDPFile(_ sender: Any?) {
        showOverview()
        overview.chooseRDPFiles()
    }

    @objc func showSettings(_ sender: Any?) {
        settings.showWindow(nil)
    }

    // MARK: Sessions

    /// Opens a session for the connection, or brings its running session to the front.
    func connect(_ id: UUID) {
        if let running = sessions.first(where: { $0.connectionID == id }) {
            running.activate()
            return
        }
        guard let connection = library.connection(with: id) else { return }
        if connection.protocol == .vnc {
            openScreenSharing(connection)
            return
        }
        let controller = SessionWindowController(connection: connection, library: library, activity: activity)
        controller.onClose = { [weak self, weak controller] in
            self?.sessions.removeAll { $0 === controller }
        }
        sessions.append(controller)
        present(controller)
        controller.start()
    }

    private func openScreenSharing(_ connection: Connection) {
        guard let url = connection.vncURL else { return }
        NSWorkspace.shared.open(url)
        Task { await library.markConnected(connection.id) }
    }

    /// As the last tab of the overview's group, or as an own window (setting, or overview closed).
    private func present(_ controller: SessionWindowController) {
        guard let window = controller.window, let overviewWindow = overview.window else { return }
        if AppSettings.sessionsInOwnWindows {
            // .disallowed only while showing it, so automatic tabbing can't pull it into a group;
            // "Fenster zusammenführen" still works afterwards.
            window.tabbingMode = .disallowed
            window.makeKeyAndOrderFront(nil)
            window.tabbingMode = .automatic
        } else {
            if !overviewWindow.isVisible, overviewWindow.tabGroup?.windows.count ?? 1 <= 1 { showOverview() }
            let last = overviewWindow.tabGroup?.windows.last ?? overviewWindow
            last.addTabbedWindow(window, ordered: .above)
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// Closes every session without asking (quitting).
    func closeAllSessions() {
        sessions.forEach { $0.close() }
    }

    func shouldTerminate() -> NSApplication.TerminateReply {
        let open = sessions.count
        guard open > 0 else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "\(AppInfo.name) beenden?"
        alert.informativeText = open == 1
            ? "Die offene Sitzung wird getrennt." : "Die \(open) offenen Sitzungen werden getrennt."
        alert.addButton(withTitle: "Beenden")
        alert.addButton(withTitle: "Abbrechen")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    // MARK: Files

    /// .rdp files from Finder ("Öffnen mit") or dropped on the Dock icon: imported, never connected.
    func open(_ urls: [URL]) {
        let files = urls.filter { $0.pathExtension.lowercased() == "rdp" }
        guard !files.isEmpty else { return }
        guard started else {
            pendingFiles += files
            return
        }
        showOverview()
        overview.importRDPFiles(files)
    }

    // MARK: Tabs (⌃⌥⌘1…9, ⌃⌥⌘← / →)

    /// Tab order: the overview's group as shown, then sessions in own windows in opening order.
    var orderedWindows: [NSWindow] {
        guard let overviewWindow = overview.window else { return [] }
        var windows = overviewWindow.tabGroup?.windows ?? []
        if windows.isEmpty, overviewWindow.isVisible { windows = [overviewWindow] }
        for case let window? in sessions.map(\.window) where !windows.contains(window) {
            windows.append(window)
        }
        return windows
    }

    /// Session windows in tab order (⌃⌥⌘2 is the first).
    private var sessionWindowsInOrder: [NSWindow] {
        orderedWindows.filter { $0 !== overview.window }
    }

    /// Tag 0 is the overview, tag n the n-th session.
    @objc func selectTab(_ sender: NSMenuItem) {
        guard sender.tag > 0 else { return showOverview() }
        let windows = sessionWindowsInOrder
        guard windows.indices.contains(sender.tag - 1) else { return }
        select(windows[sender.tag - 1])
    }

    @objc func selectNextTab(_ sender: Any?) { selectAdjacent(1) }
    @objc func selectPreviousTab(_ sender: Any?) { selectAdjacent(-1) }

    private func selectAdjacent(_ step: Int) {
        let windows = orderedWindows
        guard windows.count > 1 else { return }
        let current = windows.firstIndex { $0 === NSApp.keyWindow || $0 === NSApp.mainWindow } ?? 0
        select(windows[(current + step + windows.count) % windows.count])
    }

    private func select(_ window: NSWindow) {
        window.tabGroup?.selectedWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    @objc func toggleSessionsInOwnWindows(_ sender: Any?) {
        AppSettings.sessionsInOwnWindows.toggle()
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(selectTab(_:)):
            return item.tag == 0 || sessionWindowsInOrder.indices.contains(item.tag - 1)
        case #selector(selectNextTab(_:)), #selector(selectPreviousTab(_:)):
            return orderedWindows.count > 1
        case #selector(toggleSessionsInOwnWindows(_:)):
            item.state = AppSettings.sessionsInOwnWindows ? .on : .off
            return true
        case #selector(importFromJump(_:)):
            return overview.jumpAvailable && library.loadError == nil
        case #selector(newConnection(_:)), #selector(importRDPFile(_:)):
            return library.loadError == nil
        default:
            return true
        }
    }

    /// Window menu: the tab entries are named after the current tab order each time it opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
        let windows = sessionWindowsInOrder
        for item in menu.items where item.action == #selector(selectTab(_:)) && item.tag > 0 {
            let index = item.tag - 1
            item.isHidden = !windows.indices.contains(index)
            if !item.isHidden { item.title = windows[index].title }
        }
    }
}
