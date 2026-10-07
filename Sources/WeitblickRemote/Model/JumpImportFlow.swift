import ConnectionStore
import Foundation
import Observation

/// The Jump migration as the import sheet shows it: preview with checkboxes, then the report.
/// Jump's files are only read (`JumpImporter`); nothing is stored before `apply()`.
@MainActor @Observable
final class JumpImportFlow {
    struct Row: Identifiable {
        let id: UUID
        let name: String
        let address: String
        let isVNC: Bool
        let action: JumpImportAction
        /// For updates: which areas change ("Name", "Display", …).
        let changes: [String]
        let notes: [String]
        let ignoredFields: [ImportFieldIssue]
    }

    struct SkippedFile: Identifiable {
        var id: String { fileName }
        let fileName: String
        let reason: String
    }

    struct Outcome: Equatable {
        var created: [String] = []
        var updated: [String] = []
        var unchanged: [String] = []
        var notSelected: [String] = []
    }

    enum Phase: Equatable {
        case preview
        case applying
        case done(Outcome)
    }

    private let importer: JumpImporter
    private let library: ConnectionLibrary
    private(set) var plan: JumpImportPlan
    private(set) var rows: [Row] = []
    /// Notes that apply to every entry (shown once).
    private(set) var commonNotes: [String] = []
    /// Jump fields that no entry takes over.
    private(set) var commonIgnoredFields: [ImportFieldIssue] = []
    private(set) var skipped: [SkippedFile] = []
    private(set) var keyboardProfileNotes: [String] = []
    var selection: Set<UUID> = []
    private(set) var phase = Phase.preview
    /// A problem to show above the list (e.g. the store changed meanwhile, or saving failed).
    private(set) var message: String?

    /// Fails when Jump's folder cannot be read.
    init(importer: JumpImporter, inputProfileURL: URL, library: ConnectionLibrary) throws {
        self.importer = importer
        self.library = library
        plan = try importer.plan(existing: library.connections)
        keyboardProfileNotes = Self.keyboardProfileNotes(inputProfileURL)
        rebuild()
    }

    var hasChanges: Bool { plan.createCount + plan.updateCount > 0 }
    var selectedChangeCount: Int { rows.filter { $0.action != .unchanged && selection.contains($0.id) }.count }

    func apply() async {
        phase = .applying
        message = nil
        do {
            try await importer.apply(plan, to: library.store, selectedIDs: selection)
            await library.refresh()
            phase = .done(outcome())
        } catch ConnectionStoreError.staleImportPlan {
            await library.refresh()
            replan(message: String(localized: "The connections changed in the meantime. The preview is updated; please check it again."))
        } catch {
            phase = .preview
            message = String(localized: "Saving failed: \(error.localizedDescription)")
        }
    }

    private func replan(message: String) {
        do {
            plan = try importer.plan(existing: library.connections)
            rebuild()
            self.message = message
        } catch {
            self.message = String(localized: "Jump’s folder can no longer be read.")
        }
        phase = .preview
    }

    private func outcome() -> Outcome {
        var outcome = Outcome()
        for row in rows {
            switch (row.action, selection.contains(row.id)) {
            case (.unchanged, _): outcome.unchanged.append(row.name)
            case (_, false): outcome.notSelected.append(row.name)
            case (.create, true): outcome.created.append(row.name)
            case (.update, true): outcome.updated.append(row.name)
            }
        }
        return outcome
    }

    private func rebuild() {
        let reports = plan.report.connections
        let imported = reports.filter { $0.action != nil }
        commonNotes = Self.common(imported.map(\.warnings))
        commonIgnoredFields = Self.common(imported.map(\.ignoredFields))
        let reportsByFile = Dictionary(reports.map { ($0.fileName, $0) }, uniquingKeysWith: { first, _ in first })
        rows = plan.entries.map { entry in
            let connection = entry.connection
            let report = connection.importSource.flatMap { reportsByFile[$0.fileName] }
            return Row(
                id: connection.id, name: connection.name, address: "\(connection.host):\(connection.port)",
                isVNC: connection.protocol == .vnc, action: entry.action,
                changes: entry.previous.map { Self.changedAreas(from: $0, to: connection) } ?? [],
                notes: (report?.warnings ?? []).filter { !commonNotes.contains($0) },
                ignoredFields: (report?.ignoredFields ?? []).filter { !commonIgnoredFields.contains($0) })
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        selection = Set(rows.filter { $0.action != .unchanged }.map(\.id))
        skipped = reports.filter { $0.action == nil }.map {
            SkippedFile(fileName: $0.fileName, reason: $0.warnings.first ?? String(localized: "Unreadable."))
        }
    }

    /// Items present in every list, in the order of the first.
    private nonisolated static func common<Item: Hashable>(_ lists: [[Item]]) -> [Item] {
        guard let first = lists.first else { return [] }
        let rest = lists.dropFirst().map { Set($0) }
        var seen: Set<Item> = []
        var result: [Item] = []
        for item in first where rest.allSatisfy({ $0.contains(item) }) && seen.insert(item).inserted {
            result.append(item)
        }
        return result
    }

    /// Localized names of the setting groups that differ (the editor's page names).
    static func changedAreas(from old: Connection, to new: Connection) -> [String] {
        var areas: [String] = []
        if old.name != new.name { areas.append(String(localized: "Name")) }
        if old.host != new.host || old.port != new.port || old.protocol != new.protocol { areas.append(String(localized: "Address")) }
        if old.username != new.username || old.domain != new.domain { areas.append(String(localized: "Sign-in")) }
        if old.display != new.display { areas.append(String(localized: "Display")) }
        if old.redirection != new.redirection { areas.append(String(localized: "Redirection")) }
        if old.keyboard != new.keyboard { areas.append(String(localized: "Keyboard")) }
        if old.security != new.security { areas.append(String(localized: "Security")) }
        if old.advanced != new.advanced || old.tags != new.tags { areas.append(String(localized: "Advanced")) }
        if old.lastConnected != new.lastConnected { areas.append(String(localized: "Last connected")) }
        return areas
    }

    /// One line per Jump keyboard profile. The default rules already cover Jump's standard
    /// shortcuts; mappings beyond that are listed, not applied.
    private static func keyboardProfileNotes(_ url: URL) -> [String] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        guard let report = try? JumpInputProfileImporter(fileURL: url).read() else {
            return [String(localized: "Jump’s keyboard profiles couldn’t be read; the default rules apply.")]
        }
        return report.profiles.map { profile in
            let standard = profile.mappings.filter { $0.classification == .builtIn }.count
            let own = profile.mappings.count - standard
            let ownPart = String(localized: "\(own) custom mappings not imported (the keyboard settings cover them)")
            switch (standard, own) {
            case (_, 0): return String(localized: "Keyboard profile “\(profile.name)”: all \(standard) mappings match the default rules.")
            case (0, _): return String(localized: "Keyboard profile “\(profile.name)”: \(ownPart).")
            default: return String(localized: "Keyboard profile “\(profile.name)”: \(standard) mappings match the default rules, \(ownPart).")
            }
        }
    }
}
