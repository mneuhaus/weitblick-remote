import Foundation

public struct ImportFieldIssue: Codable, Hashable, Sendable {
    public var field: String
    public var reason: String
    public init(_ field: String, _ reason: String) { self.field = field; self.reason = reason }
}

public struct ConnectionImportReport: Codable, Hashable, Sendable {
    public var fileName: String
    public var connectionName: String?
    public var uniqueID: String?
    public var action: JumpImportAction?
    public var importedFields: [String] = []
    public var ignoredFields: [ImportFieldIssue] = []
    public var warnings: [String] = []
    public init(fileName: String) { self.fileName = fileName }
}

public struct ImportReport: Codable, Hashable, Sendable {
    public var connections: [ConnectionImportReport]
    public init(connections: [ConnectionImportReport] = []) { self.connections = connections }
    public var warningCount: Int { connections.reduce(0) { $0 + $1.warnings.count } }
    /// For the dry-run tool's evidence file (English, not localized).
    public var humanReadable: String {
        var lines = ["Jump import (Jump files only read)",
                     "Files: \(connections.count); notes: \(warningCount)"]
        for item in connections {
            lines.append("\n\(item.fileName): \(item.connectionName ?? "unreadable") [\(item.action?.rawValue ?? "not imported")]")
            lines.append("  Imported: " + item.importedFields.sorted().joined(separator: ", "))
            for field in item.ignoredFields.sorted(by: { $0.field < $1.field }) {
                lines.append("  Not imported \(field.field): \(field.reason)")
            }
            for warning in item.warnings { lines.append("  Note: \(warning)") }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

public enum JumpImportAction: String, Codable, Hashable, Sendable { case create, update, unchanged }

public struct JumpImportEntry: Sendable, Identifiable {
    public var id: UUID { connection.id }
    public let action: JumpImportAction
    public let connection: Connection
    public let previous: Connection?
    public init(action: JumpImportAction, connection: Connection, previous: Connection?) {
        self.action = action; self.connection = connection; self.previous = previous
    }
}

public struct JumpImportPlan: Sendable {
    public let entries: [JumpImportEntry]
    public let report: ImportReport
    public init(entries: [JumpImportEntry], report: ImportReport) { self.entries = entries; self.report = report }
    public var createCount: Int { entries.filter { $0.action == .create }.count }
    public var updateCount: Int { entries.filter { $0.action == .update }.count }
    public var unchangedCount: Int { entries.filter { $0.action == .unchanged }.count }
}
