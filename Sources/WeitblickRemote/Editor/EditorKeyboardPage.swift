import KeyboardEngine
import SwiftUI

struct EditorKeyboardPage: View {
    @Binding var keyboard: KeyboardConfig

    /// Windows layouts offered by name; any other imported KLID is listed by its number.
    private static let layouts: [(String, WindowsKeyboardLayoutID)] = [
        (String(localized: "German"), .german), (String(localized: "German (Switzerland)"), WindowsKeyboardLayoutID(0x0807)),
        (String(localized: "English (US)"), .usEnglish), (String(localized: "English (UK)"), WindowsKeyboardLayoutID(0x0809)),
        (String(localized: "English (US, International)"), WindowsKeyboardLayoutID(0x0002_0409)),
        (String(localized: "French"), WindowsKeyboardLayoutID(0x040C)), (String(localized: "French (Switzerland)"), WindowsKeyboardLayoutID(0x100C)),
        (String(localized: "Italian"), WindowsKeyboardLayoutID(0x0410)), (String(localized: "Spanish"), WindowsKeyboardLayoutID(0x040A)),
        (String(localized: "Dutch"), WindowsKeyboardLayoutID(0x0413)), (String(localized: "Polish (Programmers)"), WindowsKeyboardLayoutID(0x0415)),
    ]

    var body: some View {
        Form {
            Section {
                Picker("Mode", selection: $keyboard.mode) {
                    Text("Mac shortcuts (⌘C becomes Ctrl+C)").tag(KeyboardConfig.Mode.macShortcuts)
                    Text("Windows 1:1 (⌘ = Windows key, ⌥ = Alt)").tag(KeyboardConfig.Mode.windowsDirect)
                }
                .pickerStyle(.radioGroup)
                Picker("⌥ key", selection: $keyboard.optionStrategy) {
                    Text("Smart: type special characters, otherwise Alt").tag(KeyboardConfig.OptionStrategy.smart)
                    Text("Like Jump: right ⌥ types characters, left is Alt").tag(KeyboardConfig.OptionStrategy.jumpStyle)
                    Text("Always Alt").tag(KeyboardConfig.OptionStrategy.alwaysAlt)
                    Text("Always characters").tag(KeyboardConfig.OptionStrategy.alwaysCharacters)
                }
                .disabled(keyboard.mode == .windowsDirect)
            }
            Section {
                Picker("Keyboard layout in Windows", selection: $keyboard.layoutOverride) {
                    Text("Automatic (same as the Mac)").tag(WindowsKeyboardLayoutID?.none)
                    ForEach(layoutChoices, id: \.1) { name, id in
                        Text(name).tag(WindowsKeyboardLayoutID?.some(id))
                    }
                }
                Toggle(isOn: $keyboard.unicodeTextInput) {
                    Text("Unicode input")
                    Text("Types characters as Unicode instead of keys. Helps when the Windows layout doesn’t match the Mac; games and some shortcuts then don’t work.")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var layoutChoices: [(String, WindowsKeyboardLayoutID)] {
        guard let current = keyboard.layoutOverride, !Self.layouts.contains(where: { $0.1 == current }) else {
            return Self.layouts
        }
        return Self.layouts + [(String(localized: "Layout \(current.description)"), current)]
    }
}
