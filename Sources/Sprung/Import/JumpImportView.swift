import ConnectionStore
import SwiftUI

/// The Jump migration sheet: preview with checkboxes, then what was imported.
struct JumpImportView: View {
    @Bindable var flow: JumpImportFlow
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(20)
            Divider()
            switch flow.phase {
            case .preview, .applying: preview
            case .done(let outcome): report(outcome)
            }
            Divider()
            footer.padding(16)
        }
        .frame(width: 640, height: 560)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "square.and.arrow.down.on.square").font(.system(size: 30)).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                if case .done = flow.phase {
                    Text("Import abgeschlossen").font(.title3.weight(.semibold))
                } else {
                    Text("Verbindungen aus Jump Desktop übernehmen").font(.title3.weight(.semibold))
                    Text(summary).foregroundStyle(.secondary)
                }
                if let message = flow.message {
                    Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout)
                }
            }
        }
    }

    private var summary: String {
        let plan = flow.plan
        var parts: [String] = []
        if plan.createCount > 0 { parts.append("\(plan.createCount) neu") }
        if plan.updateCount > 0 { parts.append("\(plan.updateCount) geändert") }
        if plan.unchangedCount > 0 { parts.append("\(plan.unchangedCount) unverändert") }
        if !flow.skipped.isEmpty { parts.append("\(flow.skipped.count) nicht lesbar") }
        let counts = parts.isEmpty ? "Keine Verbindungen gefunden" : parts.joined(separator: ", ")
        return "\(counts). Jumps Dateien werden nur gelesen, nicht verändert."
    }

    // MARK: Preview

    private var preview: some View {
        List {
            Section {
                ForEach(flow.rows) { row in
                    PreviewRow(row: row, isSelected: Binding(
                        get: { flow.selection.contains(row.id) },
                        set: { if $0 { flow.selection.insert(row.id) } else { flow.selection.remove(row.id) } }))
                }
            }
            if !flow.skipped.isEmpty {
                Section("Nicht übernommen") {
                    ForEach(flow.skipped) { file in
                        LabeledContent(file.fileName) { Text(file.reason).foregroundStyle(.secondary) }
                    }
                }
            }
            notesSection
        }
        .disabled(flow.phase == .applying)
    }

    @ViewBuilder private var notesSection: some View {
        let notes = flow.commonNotes + flow.keyboardProfileNotes
        if !notes.isEmpty || !flow.commonIgnoredFields.isEmpty {
            Section("Hinweise") {
                ForEach(notes, id: \.self) { Label($0, systemImage: "info.circle").font(.callout) }
                if !flow.commonIgnoredFields.isEmpty {
                    DisclosureGroup("\(flow.commonIgnoredFields.count) Jump-Einstellungen ohne Entsprechung") {
                        ForEach(flow.commonIgnoredFields, id: \.self) { issue in
                            LabeledContent(issue.field) { Text(issue.reason).foregroundStyle(.secondary) }.font(.caption)
                        }
                    }
                    .font(.callout)
                }
            }
        }
    }

    // MARK: Report

    private func report(_ outcome: JumpImportFlow.Outcome) -> some View {
        List {
            reportSection("Neu angelegt", outcome.created, symbol: "plus.circle.fill", color: .green)
            reportSection("Aktualisiert", outcome.updated, symbol: "arrow.triangle.2.circlepath.circle.fill", color: .blue)
            reportSection("Unverändert", outcome.unchanged, symbol: "checkmark.circle", color: .secondary)
            reportSection("Nicht ausgewählt", outcome.notSelected, symbol: "circle.dashed", color: .secondary)
            if !flow.skipped.isEmpty {
                Section("Nicht lesbar") {
                    ForEach(flow.skipped) { file in
                        LabeledContent(file.fileName) { Text(file.reason).foregroundStyle(.secondary) }
                    }
                }
            }
            notesSection
        }
    }

    @ViewBuilder
    private func reportSection(_ title: String, _ names: [String], symbol: String, color: Color) -> some View {
        if !names.isEmpty {
            Section("\(title) (\(names.count))") {
                ForEach(names, id: \.self) { name in
                    Label { Text(name) } icon: { Image(systemName: symbol).foregroundStyle(color) }
                }
            }
        }
    }

    // MARK: Buttons

    @ViewBuilder private var footer: some View {
        HStack {
            if case .done = flow.phase {
                Spacer()
                Button("Fertig", action: onClose).keyboardShortcut(.defaultAction)
            } else {
                if flow.phase == .applying { ProgressView().controlSize(.small) }
                Spacer()
                Button("Abbrechen", action: onClose).keyboardShortcut(.cancelAction)
                Button(importTitle) { Task { await flow.apply() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(flow.selectedChangeCount == 0 || flow.phase == .applying)
            }
        }
    }

    private var importTitle: String {
        guard flow.hasChanges else { return "Alles aktuell" }
        let count = flow.selectedChangeCount
        return count == 1 ? "1 Verbindung übernehmen" : "\(count) Verbindungen übernehmen"
    }
}

private struct PreviewRow: View {
    let row: JumpImportFlow.Row
    @Binding var isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("Übernehmen", isOn: $isSelected).labelsHidden().disabled(row.action == .unchanged)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.name).font(.headline)
                    badge
                }
                Text(row.isVNC ? "\(row.address) · Bildschirmfreigabe" : row.address)
                    .font(.subheadline).foregroundStyle(.secondary)
                if !row.changes.isEmpty {
                    Text("Ändert: " + row.changes.joined(separator: ", ")).font(.caption).foregroundStyle(.blue)
                }
                ForEach(row.notes, id: \.self) { note in
                    Label(note, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
                if !row.ignoredFields.isEmpty {
                    Text("Nicht übernommen: " + row.ignoredFields.map(\.field).joined(separator: ", "))
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var badge: some View {
        let (text, color): (String, Color) = switch row.action {
        case .create: ("Neu", .green)
        case .update: ("Ändern", .blue)
        case .unchanged: ("Unverändert", .secondary)
        }
        return Text(text).font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }
}
