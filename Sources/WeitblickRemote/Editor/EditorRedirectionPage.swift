import AppKit
import ConnectionStore
import SwiftUI

struct EditorRedirectionPage: View {
    @Binding var redirection: RedirectionSettings

    var body: some View {
        Form {
            Section {
                Toggle("Clipboard", isOn: $redirection.clipboard)
                Picker("Sound", selection: $redirection.audioPlayback) {
                    Text("Play on this Mac").tag(AudioPlaybackMode.local)
                    Text("Leave on the remote PC").tag(AudioPlaybackMode.remote)
                    Text("Off").tag(AudioPlaybackMode.off)
                }
                Toggle("Microphone", isOn: $redirection.microphone)
                Toggle("Printers", isOn: $redirection.printers)
            }
            Section {
                Toggle("Share folders as drives", isOn: $redirection.driveRedirection)
                // By position: the name is edited in place, so the value cannot be the identity.
                ForEach(redirection.drives.indices, id: \.self) { index in
                    DriveRow(drive: $redirection.drives[index]) { redirection.drives.remove(at: index) }
                        .disabled(!redirection.driveRedirection)
                }
                Button("Add Folder…", action: addFolder)
            } header: {
                Text("Drives")
            } footer: {
                // A String, not a key: Text would read the backslashes as Markdown.
                Text(String(localized: "Appear in Windows as \\\\tsclient\\<name>.")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Share")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !redirection.drives.contains(where: { $0.localPath == url.path }) {
            redirection.drives.append(DriveMapping(name: url.lastPathComponent, localPath: url.path))
        }
        redirection.driveRedirection = true
    }
}

private struct DriveRow: View {
    @Binding var drive: DriveMapping
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("Enabled", isOn: $drive.enabled).labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                TextField("Name", text: $drive.name).labelsHidden()
                Text(drive.localPath).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                if drive.readOnly {
                    Text("Read-only in Jump: not shared (sharing needs write access).")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Button(action: remove) { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .help("Remove")
        }
    }
}
