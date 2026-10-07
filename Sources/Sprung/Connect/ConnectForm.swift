import SwiftUI

/// Values of the M1 connect form (M4 replaces it with the connection manager).
struct ConnectRequest {
    var host = ""
    var username = ""
    var domain = ""
    var password = ""
}

struct ConnectForm: View {
    @State var request: ConnectRequest
    @AppStorage("retina") private var retina = true
    let onConnect: (ConnectRequest, _ retina: Bool) -> Void

    var body: some View {
        Form {
            TextField("Host", text: $request.host)
            TextField("Benutzer", text: $request.username)
            TextField("Domäne", text: $request.domain)
            SecureField("Passwort", text: $request.password)
            Toggle("Retina (volle Auflösung)", isOn: $retina)
            HStack {
                Spacer()
                Button("Verbinden") { onConnect(request, retina) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(request.host.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
