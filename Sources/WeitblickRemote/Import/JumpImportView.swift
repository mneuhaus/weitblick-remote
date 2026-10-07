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
                    Text("Import complete").font(.title3.weight(.semibold))
                } else {
                    Text("Import connections from Jump Desktop").font(.title3.weight(.semibold))
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
        if plan.createCount > 0 { parts.append(String(localized: "\(plan.createCount) new")) }
        if plan.updateCount > 0 { parts.append(String(localized: "\(plan.updateCount) changed")) }
        if plan.unchangedCount > 0 { parts.append(String(localized: "\(plan.unchangedCount) unchanged")) }
        if !flow.skipped.isEmpty { parts.append(String(localized: "\(flow.skipped.count) unreadable")) }
        let counts = parts.isEmpty ? String(localized: "No connections found") : parts.joined(separator: ", ")
        return String(localized: "\(counts). Jump’s files are only read, never changed.")
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
                Section("Not imported") {
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
            Section("Notes") {
                ForEach(notes, id: \.self) { Label($0, systemImage: "info.circle").font(.callout) }
                if !flow.commonIgnoredFields.isEmpty {
                    DisclosureGroup("\(flow.commonIgnoredFields.count) Jump settings without an equivalent") {
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
            reportSection(String(localized: "Created"), outcome.created, symbol: "plus.circle.fill", color: .green)
            reportSection(String(localized: "Updated"), outcome.updated, symbol: "arrow.triangle.2.circlepath.circle.fill", color: .blue)
            reportSection(String(localized: "Unchanged"), outcome.unchanged, symbol: "checkmark.circle", color: .secondary)
            reportSection(String(localized: "Not selected"), outcome.notSelected, symbol: "circle.dashed", color: .secondary)
            if !flow.skipped.isEmpty {
                Section("Unreadable") {
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
            let header = "\(title) (\(names.count))" // a String: shown as is, `title` is localized
            Section(header) {
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
                Button("Done", action: onClose).keyboardShortcut(.defaultAction)
            } else {
                if flow.phase == .applying { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel", action: onClose).keyboardShortcut(.cancelAction)
                Button(importTitle) { Task { await flow.apply() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(flow.selectedChangeCount == 0 || flow.phase == .applying)
            }
        }
    }

    private var importTitle: String {
        guard flow.hasChanges else { return String(localized: "All Up to Date") }
        let count = flow.selectedChangeCount
        return count == 1 ? String(localized: "Import 1 Connection") : String(localized: "Import \(count) Connections")
    }
}

private struct PreviewRow: View {
    let row: JumpImportFlow.Row
    @Binding var isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("Import This Connection", isOn: $isSelected).labelsHidden().disabled(row.action == .unchanged)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.name).font(.headline)
                    badge
                }
                Text(row.isVNC ? "\(row.address) · " + String(localized: "Screen Sharing") : row.address)
                    .font(.subheadline).foregroundStyle(.secondary)
                if !row.changes.isEmpty {
                    Text(String(localized: "Changes: \(row.changes.joined(separator: ", "))")).font(.caption).foregroundStyle(.blue)
                }
                ForEach(row.notes, id: \.self) { note in
                    Label(note, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
                if !row.ignoredFields.isEmpty {
                    Text(String(localized: "Not imported: \(row.ignoredFields.map(\.field).joined(separator: ", "))"))
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var badge: some View {
        let (text, color): (String, Color) = switch row.action {
        case .create: (String(localized: "New"), .green)
        case .update: (String(localized: "Update"), .blue)
        case .unchanged: (String(localized: "Unchanged"), .secondary)
        }
        return Text(text).font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }
}
