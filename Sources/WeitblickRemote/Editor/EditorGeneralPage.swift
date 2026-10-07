import ConnectionStore
import SwiftUI

struct EditorGeneralPage: View {
    @Binding var draft: ConnectionDraft

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $draft.connection.name,
                          prompt: draft.connection.host.isEmpty ? Text("e.g. Office PC") : Text(verbatim: draft.connection.host))
                Picker("Type", selection: $draft.connection.protocol) {
                    Text("Remote Desktop (RDP)").tag(ConnectionProtocol.rdp)
                    Text("Screen Sharing (VNC)").tag(ConnectionProtocol.vnc)
                }
                TextField("Host", text: $draft.connection.host, prompt: Text("Computer name or IP address"))
                TextField("Port", value: $draft.connection.port, format: .number.grouping(.never))
            }
            if draft.connection.protocol == .rdp {
                Section("Sign-in") {
                    TextField("User", text: $draft.connection.username)
                    TextField("Domain", text: $draft.connection.domain, prompt: Text("optional"))
                    SecureField("Password", text: $draft.password, prompt: Text(passwordPrompt))
                    if draft.hasStoredPassword {
                        Toggle("Delete saved password", isOn: $draft.removeStoredPassword)
                            .disabled(!draft.password.isEmpty)
                    }
                }
            } else {
                Section {
                    Text("Opens macOS Screen Sharing, which handles sign-in and settings itself.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Section("Notes") {
                TextField("Notes", text: $draft.connection.notes, axis: .vertical)
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

    private var passwordPrompt: LocalizedStringKey {
        if draft.hasStoredPassword && !draft.removeStoredPassword { return "Saved in keychain" }
        return "Ask when connecting"
    }
}
