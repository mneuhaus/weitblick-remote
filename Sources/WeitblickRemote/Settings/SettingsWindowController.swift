import AppKit
import SwiftUI

/// "Settings…": the app-wide switches.
@MainActor
final class SettingsWindowController: NSWindowController {
    init(storeURL: URL) {
        let hosting = NSHostingController(rootView: SettingsView(storeURL: storeURL))
        hosting.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "Settings")
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
            Section("Sessions") {
                Toggle("Open sessions in separate windows", isOn: $ownWindows)
                Toggle("Ask before closing a session", isOn: $confirmClose)
            }
            Section {
                Picker("Send system shortcuts to Windows", selection: $capture) {
                    Text("In full screen").tag(SystemShortcutCapture.fullScreen.rawValue)
                    Text("Always").tag(SystemShortcutCapture.always.rawValue)
                    Text("Never").tag(SystemShortcutCapture.never.rawValue)
                }
                .onChange(of: capture) {
                    NotificationCenter.default.post(name: .systemShortcutCaptureChanged, object: nil)
                }
            } footer: {
                Text("⌘⇥, ⌘Space and ⌃←/→ then go to Windows instead of macOS (needs Accessibility access).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Data") {
                LabeledContent("Connections") {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([storeURL]) }
                }
                Text(storeURL.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
