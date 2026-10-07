import ConnectionStore
import SwiftUI

struct EditorAdvancedPage: View {
    @Binding var advanced: AdvancedSettings

    var body: some View {
        Form {
            Section("Programm statt Desktop") {
                TextField("Programm", text: $advanced.alternateShell.orEmpty, prompt: Text("z. B. C:\\Programme\\App\\app.exe"))
                TextField("Arbeitsverzeichnis", text: $advanced.workingDir.orEmpty, prompt: Text("optional"))
            }
            Section {
                TextField("Load-Balance-Info", text: $advanced.loadBalanceInfo.orEmpty, prompt: Text("optional"))
                TextField("Wake-on-LAN", text: macAddresses, prompt: Text("MAC-Adressen, durch Komma getrennt"))
                if advanced.gatewayRef != nil || advanced.gatewayHostname != nil {
                    LabeledContent("Gateway", value: "\(advanced.gatewayHostname ?? "aus Jump übernommen") (noch nicht unterstützt)")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var macAddresses: Binding<String> {
        Binding(
            get: { advanced.wakeOnLANMACAddresses.joined(separator: ", ") },
            // Empty entries stay while typing ("AA:…, "); saving drops them.
            set: { advanced.wakeOnLANMACAddresses = $0.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) } })
    }
}
