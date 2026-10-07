import AppKit
import SwiftUI

/// "Einstellungen…": the app-wide switches.
@MainActor
final class SettingsWindowController: NSWindowController {
    init(storeURL: URL) {
        let hosting = NSHostingController(rootView: SettingsView(storeURL: storeURL))
        hosting.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: hosting)
        window.title = "Einstellungen"
        window.styleMask = [.titled, .closable]
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

private struct SettingsView: View {
    let storeURL: URL
    @AppStorage(AppSettings.sessionsInOwnWindowsKey) private var ownWindows = false
    @AppStorage(AppSettings.confirmCloseSessionKey) private var confirmClose = true
    @AppStorage(SystemShortcutCapture.defaultsKey) private var capture = SystemShortcutCapture.fullScreen.rawValue

    var body: some View {
        Form {
            Section("Fenster") {
                Toggle("Sitzungen in eigenen Fenstern öffnen", isOn: $ownWindows)
                Toggle("Vor dem Schließen einer Sitzung nachfragen", isOn: $confirmClose)
            }
            Section {
                Picker("Systemkürzel an Windows", selection: $capture) {
                    Text("Im Vollbild").tag(SystemShortcutCapture.fullScreen.rawValue)
                    Text("Immer").tag(SystemShortcutCapture.always.rawValue)
                    Text("Nie").tag(SystemShortcutCapture.never.rawValue)
                }
                .onChange(of: capture) {
                    NotificationCenter.default.post(name: .systemShortcutCaptureChanged, object: nil)
                }
            } footer: {
                Text("⌘⇥, ⌘Leertaste, ⌃←/→ gehen dann an Windows statt an macOS (braucht das Bedienungshilfen-Recht).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Daten") {
                LabeledContent("Verbindungen") {
                    Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([storeURL]) }
                }
                Text(storeURL.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
