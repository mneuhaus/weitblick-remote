import ConnectionStore
import SwiftUI

struct EditorDisplayPage: View {
    @Binding var display: DisplaySettings

    private static let scales = [100, 125, 150, 175, 200, 250, 300]

    var body: some View {
        Form {
            Section {
                Picker("Auflösung", selection: $display.matchScreenResolution) {
                    Text("An die Fenstergröße anpassen").tag(true)
                    Text("Feste Größe").tag(false)
                }
                if display.matchScreenResolution {
                    Toggle("Beim Ändern der Fenstergröße mitwachsen", isOn: $display.dynamicResolution)
                } else {
                    LabeledContent("Größe") {
                        HStack(spacing: 6) {
                            TextField("Breite", value: $display.fixedWidth, format: .number.grouping(.never))
                                .frame(width: 70)
                            Text("×")
                            TextField("Höhe", value: $display.fixedHeight, format: .number.grouping(.never))
                                .frame(width: 70)
                            Text("Pixel").foregroundStyle(.secondary)
                        }
                        .labelsHidden()
                    }
                }
            }
            Section {
                Toggle(isOn: $display.retina) {
                    Text("Retina (volle Auflösung)")
                    Text("Ein Windows-Pixel pro Bildschirmpixel, gestochen scharf. Aus: halbe Auflösung, hochskaliert (weicher, weniger Daten).")
                }
                Picker("Skalierung unter Windows", selection: $display.desktopScaleFactor) {
                    Text("Automatisch").tag(Int?.none)
                    ForEach(scaleChoices, id: \.self) { Text("\($0) %").tag(Int?.some($0)) }
                }
                Toggle("Im Vollbild starten", isOn: $display.startFullscreen)
            }
        }
        .formStyle(.grouped)
    }

    /// The usual steps plus an imported value that is not one of them.
    private var scaleChoices: [Int] {
        Array(Set(Self.scales + [display.desktopScaleFactor].compactMap { $0 })).sorted()
    }
}
