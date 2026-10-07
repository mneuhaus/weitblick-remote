import ConnectionStore
import SwiftUI

struct EditorSecurityPage: View {
    @Binding var security: SecuritySettings

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { !security.disableNLA }, set: { security.disableNLA = !$0 })) {
                    Text("Netzwerkebenen-Authentifizierung (NLA)")
                    Text("Anmeldung vor dem Verbindungsaufbau. Nur für sehr alte Windows-Versionen ausschalten.")
                }
                Toggle(isOn: $security.ignoreCertificateErrors) {
                    Text("Zertifikat nicht prüfen")
                    Text("Es wird nie nach dem Zertifikat gefragt. Nur in vertrauenswürdigen Netzen.")
                }
            }
            Section {
                if security.trustedCertificateFingerprints.isEmpty {
                    Text("Noch keins. Beim ersten Verbinden wird gefragt.").foregroundStyle(.secondary)
                }
                ForEach(security.trustedCertificateFingerprints, id: \.self) { fingerprint in
                    HStack {
                        Text(fingerprint).font(.caption.monospaced()).textSelection(.enabled).lineLimit(2)
                        Spacer()
                        Button {
                            security.trustedCertificateFingerprints.removeAll { $0 == fingerprint }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Nicht mehr vertrauen")
                    }
                }
            } header: {
                Text("Vertrauenswürdige Zertifikate (SHA-256)")
            }
        }
        .formStyle(.grouped)
    }
}
