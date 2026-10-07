import ConnectionStore
import SwiftUI

struct EditorGeneralPage: View {
    @Binding var draft: ConnectionDraft

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $draft.connection.name,
                          prompt: Text(draft.connection.host.isEmpty ? "z. B. Büro-PC" : draft.connection.host))
                Picker("Art", selection: $draft.connection.protocol) {
                    Text("Remotedesktop (RDP)").tag(ConnectionProtocol.rdp)
                    Text("Bildschirmfreigabe (VNC)").tag(ConnectionProtocol.vnc)
                }
                TextField("Host", text: $draft.connection.host, prompt: Text("Rechnername oder IP-Adresse"))
                TextField("Port", value: $draft.connection.port, format: .number.grouping(.never))
            }
            if draft.connection.protocol == .rdp {
                Section("Anmeldung") {
                    TextField("Benutzer", text: $draft.connection.username)
                    TextField("Domäne", text: $draft.connection.domain, prompt: Text("optional"))
                    SecureField("Passwort", text: $draft.password, prompt: Text(passwordPrompt))
                    if draft.hasStoredPassword {
                        Toggle("Gesichertes Passwort löschen", isOn: $draft.removeStoredPassword)
                            .disabled(!draft.password.isEmpty)
                    }
                }
            } else {
                Section {
                    Text("Öffnet die Bildschirmfreigabe von macOS; Anmeldung und Einstellungen regelt sie selbst.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Section("Notizen") {
                TextField("Notizen", text: $draft.connection.notes, axis: .vertical)
                    .lineLimit(2...4)
                    .labelsHidden()
            }
        }
        .formStyle(.grouped)
        .onChange(of: draft.connection.protocol) { _, newValue in
            // Follow the protocol's standard port unless a custom one is set.
            switch (newValue, draft.connection.port) {
            case (.vnc, 3389): draft.connection.port = 5900
            case (.rdp, 5900): draft.connection.port = 3389
            default: break
            }
        }
    }

    private var passwordPrompt: String {
        if draft.hasStoredPassword && !draft.removeStoredPassword { return "Im Schlüsselbund gesichert" }
        return "Beim Verbinden fragen"
    }
}
