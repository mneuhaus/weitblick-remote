import ConnectionStore
import SwiftUI

struct EditorAdvancedPage: View {
    @Binding var advanced: AdvancedSettings

    var body: some View {
        Form {
            Section("Program instead of desktop") {
                TextField("Program", text: $advanced.alternateShell.orEmpty, prompt: Text("e.g. C:\\Program Files\\App\\app.exe"))
                TextField("Working directory", text: $advanced.workingDir.orEmpty, prompt: Text("optional"))
            }
            Section {
                TextField("Load balance info", text: $advanced.loadBalanceInfo.orEmpty, prompt: Text("optional"))
                TextField("Wake-on-LAN", text: macAddresses, prompt: Text("MAC addresses, separated by commas"))
                if advanced.gatewayRef != nil || advanced.gatewayHostname != nil {
                    LabeledContent("Gateway", value: String(localized: "\(advanced.gatewayHostname ?? String(localized: "imported from Jump")) (not supported yet)"))
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
