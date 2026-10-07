import SwiftUI

/// The in-window sign-in sheet: shown when no password is saved or the server rejected it.
struct SignInView: View {
    let connectionName: String
    let message: String?
    @State var username: String
    @State var domain: String
    @State private var password = ""
    @State private var saveInKeychain = true
    let onConnect: (_ credentials: Credentials, _ save: Bool) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "person.badge.key.fill").font(.system(size: 30)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sign in to “\(connectionName)”").font(.headline)
                    if let message {
                        Text(message).font(.callout).foregroundStyle(.red)
                    }
                }
            }
            Form {
                TextField("User", text: $username)
                TextField("Domain", text: $domain, prompt: Text("optional"))
                SecureField("Password", text: $password)
                Toggle("Save in keychain", isOn: $saveInKeychain)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Connect") {
                    onConnect(Credentials(username: username.trimmingCharacters(in: .whitespaces),
                                          domain: domain.trimmingCharacters(in: .whitespaces), password: password),
                              saveInKeychain)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
