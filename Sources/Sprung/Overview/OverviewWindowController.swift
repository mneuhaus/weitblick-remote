import AppKit
import ConnectionStore
import os
import SwiftUI
import UniformTypeIdentifiers

/// The "Übersicht" window (first tab): the connection list with its toolbar, and every flow that
/// starts there (new, edit, duplicate, delete, export, Jump and .rdp import).
@MainActor
final class OverviewWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate, NSMenuItemValidation {
    let model: OverviewModel
    private let library: ConnectionLibrary
    private let options: LaunchOptions
    /// Opens or activates sessions (the window coordinator).
    var connect: (Set<UUID>) -> Void = { _ in }
    /// False while sessions are open: the overview tab stays.
    var canClose: () -> Bool = { true }

    private static let logger = Logger(subsystem: "nrw.neuhaus.sprung", category: "overview")
    private static let rdpType = UTType(filenameExtension: "rdp") ?? .data

    init(library: ConnectionLibrary, activity: SessionActivity, options: LaunchOptions) {
        self.library = library
        self.options = options
        model = OverviewModel(library: library, activity: activity)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Übersicht"
        window.tabbingIdentifier = WindowCoordinator.tabbingIdentifier
        window.collectionBehavior = [.fullScreenPrimary]
        window.contentMinSize = NSSize(width: 480, height: 320)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        let hosting = NSHostingController(rootView: OverviewView(model: model, actions: actions))
        hosting.sizingOptions = []
        contentViewController = hosting
        // The hosting controller shrinks the window to the view's minimum; start from a useful
        // size, then let a remembered frame win.
        window.setContentSize(NSSize(width: 760, height: 540))
        window.center()
        window.setFrameAutosaveName("Übersicht")

        let toolbar = NSToolbar(identifier: "Übersicht")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var actions: OverviewActions {
        OverviewActions(
            connect: { [weak self] in self?.connect($0) },
            edit: { [weak self] in self?.edit($0) },
            duplicate: { [weak self] in self?.duplicate($0) },
            export: { [weak self] in self?.export($0) },
            delete: { [weak self] in self?.confirmDelete($0) },
            newConnection: { [weak self] in self?.newConnection() },
            importFromJump: { [weak self] in self?.importFromJump() },
            jumpAvailable: jumpAvailable)
    }

    var jumpAvailable: Bool { FileManager.default.fileExists(atPath: options.jumpDirectory.path) }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        canClose()
    }

    // MARK: Editing

    func newConnection() {
        showEditor(ConnectionDraft.new())
    }

    func edit(_ id: UUID) {
        guard let connection = library.connection(with: id) else { return }
        showEditor(ConnectionDraft(connection: connection, isNew: false,
                                   hasStoredPassword: library.password(for: id) != nil))
    }

    private func showEditor(_ draft: ConnectionDraft) {
        guard let window, window.attachedSheet == nil else { return }
        weak var sheet: NSWindow? // weak: the sheet's own view holds this closure
        let editor = ConnectionEditorView(
            draft: draft,
            onSave: { [weak self] edited in
                Task { @MainActor in
                    guard let self, await self.save(edited), let sheet else { return }
                    window.endSheet(sheet)
                }
            },
            onCancel: { if let sheet { window.endSheet(sheet) } })
        sheet = window.presentSheet(editor)
    }

    /// Stores the edited connection and its password; false (with an alert) if that failed.
    private func save(_ draft: ConnectionDraft) async -> Bool {
        var connection = draft.saved()
        do {
            if draft.isNew {
                try await library.add(connection)
            } else {
                // Changes made meanwhile by a session (last connected) are not reverted.
                connection.lastConnected = library.connection(with: connection.id)?.lastConnected ?? connection.lastConnected
                try await library.update(connection)
            }
        } catch {
            presentError("Verbindung nicht gesichert", error)
            return false
        }
        do {
            switch draft.passwordChange {
            case .keep: break
            case .set(let password): try library.setPassword(password, for: connection.id)
            case .remove: try library.deletePassword(for: connection.id)
            }
        } catch {
            presentError("Passwort nicht im Schlüsselbund gesichert", error)
        }
        model.selection = [connection.id]
        return true
    }

    func duplicate(_ id: UUID) {
        Task {
            do {
                let copy = try await library.duplicate(id)
                model.selection = [copy.id]
            } catch {
                presentError("Duplizieren fehlgeschlagen", error)
            }
        }
    }

    func confirmDelete(_ ids: Set<UUID>) {
        let names = library.connections.filter { ids.contains($0.id) }.map(\.name)
        guard let window, !names.isEmpty, window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = names.count == 1 ? "„\(names[0])“ löschen?" : "\(names.count) Verbindungen löschen?"
        alert.informativeText = "Gesicherte Passwörter werden ebenfalls aus dem Schlüsselbund entfernt."
        alert.addButton(withTitle: "Löschen").hasDestructiveAction = true
        alert.addButton(withTitle: "Abbrechen")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            Task {
                do {
                    try await self.library.delete(ids)
                    self.model.selection.subtract(ids)
                } catch {
                    self.presentError("Löschen fehlgeschlagen", error)
                }
            }
        }
    }

    // MARK: .rdp files

    func export(_ id: UUID) {
        guard let window, let connection = library.connection(with: id) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.rdpType]
        panel.nameFieldStringValue = "\(connection.name).rdp"
        panel.message = "Ohne Passwort, Laufwerke und Zertifikate."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try RDPFile.encode(connection).write(to: url, options: .atomic)
            } catch {
                self?.presentError("Export fehlgeschlagen", error)
            }
        }
    }

    func chooseRDPFiles() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.rdpType]
        panel.allowsMultipleSelection = true
        panel.prompt = "Importieren"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            self?.importRDPFiles(panel.urls)
        }
    }

    /// Adds each file as a new connection and selects them; problems are listed in one alert.
    func importRDPFiles(_ urls: [URL]) {
        Task {
            var imported: [UUID] = []
            var notes: [String] = []
            for url in urls {
                do {
                    let result = try RDPFile.read(url)
                    try await library.add(result.connection)
                    imported.append(result.connection.id)
                    notes += result.warnings.map { "\(url.lastPathComponent): \($0)" }
                } catch {
                    notes.append("\(url.lastPathComponent): ließ sich nicht importieren (\(Self.describe(error))).")
                }
            }
            model.searchText = ""
            model.selection = Set(imported)
            if !notes.isEmpty {
                presentAlert(imported.isEmpty ? "Import fehlgeschlagen" : "Importiert, mit Hinweisen", notes.joined(separator: "\n"))
            }
        }
    }

    // MARK: Jump

    func importFromJump() {
        guard let window, window.attachedSheet == nil else { return }
        let flow: JumpImportFlow
        do {
            flow = try JumpImportFlow(importer: JumpImporter(directory: options.jumpDirectory),
                                      inputProfileURL: options.jumpInputProfileURL, library: library)
        } catch {
            presentAlert("Jump-Verbindungen nicht lesbar",
                         "Der Ordner „\(options.jumpDirectory.path)“ ließ sich nicht lesen (\(Self.describe(error))).")
            return
        }
        weak var sheet: NSWindow? // weak: the sheet's own view holds this closure
        sheet = window.presentSheet(JumpImportView(flow: flow) { if let sheet { window.endSheet(sheet) } })
    }

    // MARK: Toolbar

    private enum Item {
        static let add = NSToolbarItem.Identifier("add")
        static let sort = NSToolbarItem.Identifier("sort")
        static let search = NSToolbarItem.Identifier("search")
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Item.add, .flexibleSpace, Item.sort, Item.search]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch identifier {
        case Item.add:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = "Neue Verbindung"
            item.toolTip = "Neue Verbindung (⌘N)"
            item.image = NSImage(systemSymbolName: "plus", accessibilityDescription: item.label)
            item.target = self
            item.action = #selector(newConnectionFromToolbar(_:))
            item.isBordered = true
            return item
        case Item.sort:
            let item = NSMenuToolbarItem(itemIdentifier: identifier)
            item.label = "Sortierung"
            item.toolTip = "Sortierung"
            item.image = NSImage(systemSymbolName: "arrow.up.arrow.down", accessibilityDescription: item.label)
            item.showsIndicator = true
            let menu = NSMenu()
            for (tag, title) in ["Nach Name", "Zuletzt verwendet zuerst"].enumerated() {
                let entry = menu.addItem(withTitle: title, action: #selector(selectSortOrder(_:)), keyEquivalent: "")
                entry.tag = tag
                entry.target = self
            }
            item.menu = menu
            return item
        case Item.search:
            let item = NSSearchToolbarItem(itemIdentifier: identifier)
            item.searchField.placeholderString = "Suchen"
            item.searchField.sendsSearchStringImmediately = true
            item.searchField.target = self
            item.searchField.action = #selector(searchChanged(_:))
            return item
        default:
            return nil
        }
    }

    @objc private func newConnectionFromToolbar(_ sender: Any?) { newConnection() }

    @objc private func searchChanged(_ sender: NSSearchField) {
        model.searchText = sender.stringValue
    }

    @objc private func selectSortOrder(_ sender: NSMenuItem) {
        model.sortOrder = sender.tag == 1 ? .recent : .name
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(selectSortOrder(_:)) {
            item.state = (item.tag == 1) == (model.sortOrder == .recent) ? .on : .off
        }
        return true
    }

    // MARK: Alerts

    private func presentError(_ title: String, _ error: Error) {
        Self.logger.error("\(title, privacy: .public): \(String(describing: error), privacy: .public)")
        presentAlert(title, Self.describe(error))
    }

    private func presentAlert(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        if let window, window.attachedSheet == nil {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case ConnectionStoreError.invalidConnection: "Ungültige Angaben."
        case ConnectionStoreError.duplicateID: "Die Verbindung gibt es schon."
        case ConnectionStoreError.missingConnection: "Die Verbindung gibt es nicht mehr."
        case ConnectionStoreError.unsupportedSchema, ConnectionStoreError.invalidStore:
            "Die Verbindungsdatei ist unbekannt oder beschädigt; sie bleibt unverändert."
        case RDPFileError.missingAddress, RDPFileError.invalidAddress: "keine gültige Adresse"
        case RDPFileError.invalidEncoding: "unbekannte Zeichenkodierung"
        case RDPFileError.invalidValue(let key): "ungültiger Wert für „\(key)“"
        case let error as CredentialStoreError: "Schlüsselbund-Fehler \(error.status)"
        default: error.localizedDescription
        }
    }
}
