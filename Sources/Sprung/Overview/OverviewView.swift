import ConnectionStore
import SwiftUI

/// What the overview's list, menus and buttons can do (implemented by the overview window).
struct OverviewActions {
    var connect: (Set<UUID>) -> Void
    var edit: (UUID) -> Void
    var duplicate: (UUID) -> Void
    var export: (UUID) -> Void
    var wake: (UUID) -> Void
    var delete: (Set<UUID>) -> Void
    var newConnection: () -> Void
    var importFromJump: () -> Void
    var jumpAvailable: Bool
}

/// The "Übersicht" tab: all saved connections.
struct OverviewView: View {
    @Bindable var model: OverviewModel
    let actions: OverviewActions

    var body: some View {
        content.frame(minWidth: 480, minHeight: 320)
    }

    @ViewBuilder private var content: some View {
        if let error = model.library.loadError {
            ContentUnavailableView {
                Label("Verbindungen nicht lesbar", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            }
        } else if model.library.connections.isEmpty {
            ContentUnavailableView {
                Label("Noch keine Verbindungen", systemImage: "pc")
            } description: {
                Text("Lege eine Verbindung an oder übernimm deine Verbindungen aus Jump Desktop.")
            } actions: {
                HStack {
                    Button("Neue Verbindung…", action: actions.newConnection)
                    if actions.jumpAvailable { Button("Aus Jump importieren…", action: actions.importFromJump) }
                }
            }
        } else if model.visibleConnections.isEmpty {
            ContentUnavailableView.search(text: model.searchText)
        } else {
            list
        }
    }

    private var list: some View {
        List(selection: $model.selection) {
            ForEach(model.visibleConnections) { connection in
                ConnectionRow(connection: connection, status: model.activity.statuses[connection.id])
                    .tag(connection.id)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: false))
        .contextMenu(forSelectionType: UUID.self) { ids in
            menu(for: ids)
        } primaryAction: { ids in
            actions.connect(ids)
        }
        // Only rows the search shows: a hidden selected row must not be deleted or opened.
        .onDeleteCommand { actions.delete(visibleSelection) }
        .onKeyPress(.return) {
            guard !visibleSelection.isEmpty else { return .ignored }
            actions.connect(visibleSelection)
            return .handled
        }
    }

    private var visibleSelection: Set<UUID> { Set(model.selectedConnections.map(\.id)) }

    @ViewBuilder private func menu(for ids: Set<UUID>) -> some View {
        if !ids.isEmpty {
            Button(ids.count == 1 ? "Verbinden" : "\(ids.count) Verbindungen öffnen") { actions.connect(ids) }
            if ids.count == 1, let id = ids.first {
                Divider()
                Button("Bearbeiten…") { actions.edit(id) }
                Button("Duplizieren") { actions.duplicate(id) }
                if model.library.connection(with: id)?.protocol == .rdp {
                    Button("Als .rdp exportieren…") { actions.export(id) }
                }
                if model.library.connection(with: id)?.advanced.wakeOnLANMACAddresses.isEmpty == false {
                    Button("Aufwecken (Wake-on-LAN)") { actions.wake(id) }
                }
            }
            Divider()
            Button(ids.count == 1 ? "Löschen…" : "\(ids.count) Verbindungen löschen…", role: .destructive) { actions.delete(ids) }
        } else {
            Button("Neue Verbindung…", action: actions.newConnection)
        }
    }
}
