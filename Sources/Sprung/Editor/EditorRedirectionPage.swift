import AppKit
import ConnectionStore
import SwiftUI

struct EditorRedirectionPage: View {
    @Binding var redirection: RedirectionSettings

    var body: some View {
        Form {
            Section {
                Toggle("Zwischenablage", isOn: $redirection.clipboard)
                Picker("Ton", selection: $redirection.audioPlayback) {
                    Text("Auf diesem Mac abspielen").tag(AudioPlaybackMode.local)
                    Text("Auf dem entfernten PC lassen").tag(AudioPlaybackMode.remote)
                    Text("Aus").tag(AudioPlaybackMode.off)
                }
                Toggle("Mikrofon", isOn: $redirection.microphone)
                Toggle("Drucker", isOn: $redirection.printers)
            }
            Section {
                Toggle("Ordner als Laufwerke freigeben", isOn: $redirection.driveRedirection)
                // By position: the name is edited in place, so the value cannot be the identity.
                ForEach(redirection.drives.indices, id: \.self) { index in
                    DriveRow(drive: $redirection.drives[index]) { redirection.drives.remove(at: index) }
                        .disabled(!redirection.driveRedirection)
                }
                Button("Ordner hinzufügen…", action: addFolder)
            } header: {
                Text("Laufwerke")
            } footer: {
                Text(verbatim: "Erscheinen unter Windows als \\\\tsclient\\<Name>.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Freigeben"
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
            Toggle("Aktiv", isOn: $drive.enabled).labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                TextField("Name", text: $drive.name).labelsHidden()
                Text(drive.localPath).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                if drive.readOnly {
                    Text("In Jump schreibgeschützt: wird nicht freigegeben (geht nur mit Schreibzugriff).")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Button(action: remove) { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .help("Entfernen")
        }
    }
}
