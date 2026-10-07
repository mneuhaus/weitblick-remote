import KeyboardEngine
import SwiftUI

struct EditorKeyboardPage: View {
    @Binding var keyboard: KeyboardConfig

    /// Windows layouts offered by name; any other imported KLID is listed by its number.
    private static let layouts: [(String, WindowsKeyboardLayoutID)] = [
        ("Deutsch", .german), ("Deutsch (Schweiz)", WindowsKeyboardLayoutID(0x0807)),
        ("Englisch (USA)", .usEnglish), ("Englisch (Großbritannien)", WindowsKeyboardLayoutID(0x0809)),
        ("Englisch (USA, international)", WindowsKeyboardLayoutID(0x0002_0409)),
        ("Französisch", WindowsKeyboardLayoutID(0x040C)), ("Französisch (Schweiz)", WindowsKeyboardLayoutID(0x100C)),
        ("Italienisch", WindowsKeyboardLayoutID(0x0410)), ("Spanisch", WindowsKeyboardLayoutID(0x040A)),
        ("Niederländisch", WindowsKeyboardLayoutID(0x0413)), ("Polnisch (Programmierer)", WindowsKeyboardLayoutID(0x0415)),
    ]

    var body: some View {
        Form {
            Section {
                Picker("Modus", selection: $keyboard.mode) {
                    Text("Mac-Kurzbefehle (⌘C wird Strg+C)").tag(KeyboardConfig.Mode.macShortcuts)
                    Text("Windows 1:1 (⌘ = Windows-Taste, ⌥ = Alt)").tag(KeyboardConfig.Mode.windowsDirect)
                }
                .pickerStyle(.radioGroup)
                Picker("⌥-Taste", selection: $keyboard.optionStrategy) {
                    Text("Smart: Sonderzeichen tippen, sonst Alt").tag(KeyboardConfig.OptionStrategy.smart)
                    Text("Wie Jump: rechte ⌥ tippt Zeichen, linke ist Alt").tag(KeyboardConfig.OptionStrategy.jumpStyle)
                    Text("Immer Alt").tag(KeyboardConfig.OptionStrategy.alwaysAlt)
                    Text("Immer Zeichen").tag(KeyboardConfig.OptionStrategy.alwaysCharacters)
                }
                .disabled(keyboard.mode == .windowsDirect)
            }
            Section {
                Picker("Tastaturlayout unter Windows", selection: $keyboard.layoutOverride) {
                    Text("Automatisch (wie am Mac)").tag(WindowsKeyboardLayoutID?.none)
                    ForEach(layoutChoices, id: \.1) { name, id in
                        Text(name).tag(WindowsKeyboardLayoutID?.some(id))
                    }
                }
                Toggle(isOn: $keyboard.unicodeTextInput) {
                    Text("Unicode-Eingabe")
                    Text("Tippt Zeichen als Unicode statt als Tasten. Hilft, wenn das Windows-Layout nicht zum Mac passt; Spiele und manche Kürzel gehen dann nicht.")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var layoutChoices: [(String, WindowsKeyboardLayoutID)] {
        guard let current = keyboard.layoutOverride, !Self.layouts.contains(where: { $0.1 == current }) else {
            return Self.layouts
        }
        return Self.layouts + [("Layout \(current.description)", current)]
    }
}
