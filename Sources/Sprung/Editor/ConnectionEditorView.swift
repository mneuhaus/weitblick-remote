import ConnectionStore
import SwiftUI

/// The connection editor sheet: general settings plus, for RDP, display, redirection, keyboard,
/// security and advanced tabs. Nothing is stored before "Sichern".
struct ConnectionEditorView: View {
    enum Page: String, CaseIterable, Identifiable {
        case general = "Allgemein", display = "Anzeige", redirection = "Umleitung"
        case keyboard = "Tastatur", security = "Sicherheit", advanced = "Erweitert"
        var id: Self { self }
    }

    @State var draft: ConnectionDraft
    @State var page = Page.general
    let onSave: (ConnectionDraft) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Text(title).font(.headline)
                if draft.connection.protocol == .rdp {
                    Picker("Bereich", selection: $page) {
                        ForEach(Page.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            .padding([.top, .horizontal], 16)
            .padding(.bottom, 4)
            pageContent.frame(height: 420)
            Divider()
            HStack {
                if let problem = draft.problem {
                    Label(problem, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Abbrechen", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Sichern") { onSave(draft) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.problem != nil)
            }
            .padding(16)
        }
        .frame(width: 620)
    }

    private var title: String {
        if draft.isNew { return "Neue Verbindung" }
        return draft.connection.name.isEmpty ? draft.connection.host : draft.connection.name
    }

    @ViewBuilder private var pageContent: some View {
        switch draft.connection.protocol == .vnc ? .general : page {
        case .general: EditorGeneralPage(draft: $draft)
        case .display: EditorDisplayPage(display: $draft.connection.display)
        case .redirection: EditorRedirectionPage(redirection: $draft.connection.redirection)
        case .keyboard: EditorKeyboardPage(keyboard: $draft.connection.keyboard)
        case .security: EditorSecurityPage(security: $draft.connection.security)
        case .advanced: EditorAdvancedPage(advanced: $draft.connection.advanced)
        }
    }
}

extension Binding where Value == String? {
    /// An optional string as a text field: empty means nil.
    var orEmpty: Binding<String> {
        Binding<String>(get: { wrappedValue ?? "" }, set: { wrappedValue = $0.isEmpty ? nil : $0 })
    }
}
