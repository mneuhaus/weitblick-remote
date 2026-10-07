import ConnectionStore
import SwiftUI

struct EditorDisplayPage: View {
    @Binding var display: DisplaySettings

    private static let scales = [100, 125, 150, 175, 200, 250, 300]

    var body: some View {
        Form {
            Section {
                Picker("Resolution", selection: $display.matchScreenResolution) {
                    Text("Match window size").tag(true)
                    Text("Fixed size").tag(false)
                }
                if display.matchScreenResolution {
                    Toggle("Resize with the window", isOn: $display.dynamicResolution)
                } else {
                    LabeledContent("Size") {
                        HStack(spacing: 6) {
                            TextField("Width", value: $display.fixedWidth, format: .number.grouping(.never))
                                .frame(width: 70)
                            Text(verbatim: "×")
                            TextField("Height", value: $display.fixedHeight, format: .number.grouping(.never))
                                .frame(width: 70)
                            Text("pixels").foregroundStyle(.secondary)
                        }
                        .labelsHidden()
                    }
                }
            }
            Section {
                Toggle(isOn: $display.retina) {
                    Text("Retina (full resolution)")
                    Text("One Windows pixel per screen pixel, pin-sharp. Off: half resolution, scaled up (softer, less data).")
                }
                Picker("Scaling in Windows", selection: $display.desktopScaleFactor) {
                    Text("Automatic").tag(Int?.none)
                    ForEach(scaleChoices, id: \.self) { Text($0, format: .percent).tag(Int?.some($0)) }
                }
                Toggle("Start in full screen", isOn: $display.startFullscreen)
            }
        }
        .formStyle(.grouped)
    }

    /// The usual steps plus an imported value that is not one of them.
    private var scaleChoices: [Int] {
        Array(Set(Self.scales + [display.desktopScaleFactor].compactMap { $0 })).sorted()
    }
}
