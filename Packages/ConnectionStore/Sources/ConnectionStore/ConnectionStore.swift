import Foundation

public enum ConnectionStoreError: Error, Equatable, Sendable {
    case unsupportedSchema(Int)
    case invalidConnection(UUID)
    case duplicateID(UUID)
    case missingConnection(UUID)
    case staleImportPlan
    case invalidStore
}

public struct ConnectionStoreDocument: Codable, Sendable {
    public static let currentSchemaVersion = 1
    public var schemaVersion: Int
    public var connections: [Connection]
    public init(schemaVersion: Int = currentSchemaVersion, connections: [Connection]) {
        self.schemaVersion = schemaVersion
        self.connections = connections
    }
}

public enum ConnectionSortOrder: Sendable { case name, recent }

/// All mutations persist before changing the in-memory snapshot. One actor per file URL.
public actor ConnectionStore {
    public typealias Migration = @Sendable (_ oldData: Data, _ oldSchemaVersion: Int) throws -> Data
    /// The app's folder in Application Support (the one place that names it).
    public static let applicationSupportFolderName = "Sprung"
    public static var applicationSupportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(applicationSupportFolderName)", isDirectory: true)
    }
    public static var defaultFileURL: URL {
        applicationSupportDirectory.appendingPathComponent("connections.json")
    }

    public nonisolated let fileURL: URL
    public private(set) var connections: [Connection] = []
    public private(set) var lastMigrationBackupURL: URL?
    /// The file as it was before the last import changed it (one rolling copy).
    public nonisolated var importBackupURL: URL {
        fileURL.deletingPathExtension().appendingPathExtension("before-import.json")
    }
    private let migration: Migration?
    private var isLoaded = false

    public init(fileURL: URL = ConnectionStore.defaultFileURL, migration: Migration? = nil) {
        self.fileURL = fileURL
        self.migration = migration
    }

    @discardableResult
    public func load() throws -> [Connection] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            connections = []
            isLoaded = true
            return connections
        }
        let original = try Data(contentsOf: fileURL)
        let object = try JSONSerialization.jsonObject(with: original)
        let version = (object as? [String: Any])?["schemaVersion"] as? Int ?? 0
        guard version <= ConnectionStoreDocument.currentSchemaVersion else {
            throw ConnectionStoreError.unsupportedSchema(version)
        }
        let data: Data
        if version < ConnectionStoreDocument.currentSchemaVersion {
            // Preserve exact original bytes even if a user migration hook subsequently fails.
            let backup = fileURL.appendingPathExtension("v\(version).\(UUID().uuidString).bak")
            try original.write(to: backup, options: .atomic)
            lastMigrationBackupURL = backup
            data = try migration?(original, version) ?? Self.migrateLegacy(original, version: version)
        } else {
            data = original
        }
        let document = try Self.decoder().decode(ConnectionStoreDocument.self, from: data)
        guard document.schemaVersion == ConnectionStoreDocument.currentSchemaVersion else {
            throw ConnectionStoreError.unsupportedSchema(document.schemaVersion)
        }
        try Self.validate(document.connections)
        if data != original { try write(document.connections) }
        connections = document.connections
        isLoaded = true
        return connections
    }

    public func save() throws {
        try ensureLoaded()
        try write(connections)
    }

    /// Explicit replacement is the only operation that does not load an existing file first.
    public func replaceAll(_ connections: [Connection]) throws {
        try write(connections)
        self.connections = connections
        isLoaded = true
    }

    private func ensureLoaded() throws {
        if !isLoaded { try load() }
    }

    public func insert(_ connection: Connection) throws {
        try ensureLoaded()
        guard !connections.contains(where: { $0.id == connection.id }) else {
            throw ConnectionStoreError.duplicateID(connection.id)
        }
        try replaceAll(connections + [connection])
    }

    public func update(_ connection: Connection) throws {
        try ensureLoaded()
        guard let index = connections.firstIndex(where: { $0.id == connection.id }) else {
            throw ConnectionStoreError.missingConnection(connection.id)
        }
        var updated = connections
        updated[index] = connection
        try replaceAll(updated)
    }

    /// Changes one stored connection in place (read, change, write inside the actor), so small
    /// updates such as the last-connected date never overwrite other changes with a stale copy.
    @discardableResult
    public func modify(id: UUID, _ change: @Sendable (inout Connection) -> Void) throws -> Connection {
        try ensureLoaded()
        guard var connection = connections.first(where: { $0.id == id }) else {
            throw ConnectionStoreError.missingConnection(id)
        }
        change(&connection)
        connection.id = id
        try update(connection)
        return connection
    }

    public func delete(id: UUID) throws {
        try ensureLoaded()
        guard connections.contains(where: { $0.id == id }) else { throw ConnectionStoreError.missingConnection(id) }
        try replaceAll(connections.filter { $0.id != id })
    }

    @discardableResult
    public func duplicate(id: UUID, name: String? = nil) throws -> Connection {
        try ensureLoaded()
        guard var copy = connections.first(where: { $0.id == id }) else { throw ConnectionStoreError.missingConnection(id) }
        copy.id = UUID()
        copy.name = name ?? "\(copy.name) Kopie"
        copy.lastConnected = nil
        copy.importSource = nil
        try insert(copy)
        return copy
    }

    public func search(_ query: String = "", sortedBy order: ConnectionSortOrder = .name) -> [Connection] {
        Self.filter(connections, matching: query, sortedBy: order)
    }

    /// Search over name, host, user, domain, notes and tags; `.recent` puts the last used first.
    public static func filter(_ connections: [Connection], matching query: String,
                              sortedBy order: ConnectionSortOrder) -> [Connection] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = connections.filter { connection in
            needle.isEmpty || ([connection.name, connection.host, connection.username, connection.domain,
                               connection.notes] + connection.tags).contains { $0.localizedCaseInsensitiveContains(needle) }
        }
        return result.sorted {
            if order == .recent, $0.lastConnected != $1.lastConnected {
                return ($0.lastConnected ?? .distantPast) > ($1.lastConnected ?? .distantPast)
            }
            let comparison = $0.name.localizedStandardCompare($1.name)
            return comparison == .orderedSame ? $0.id.uuidString < $1.id.uuidString : comparison == .orderedAscending
        }
    }

    /// Call only after the person confirms the preview. nil selects all; an empty set selects none.
    public func apply(_ plan: JumpImportPlan, selectedIDs: Set<UUID>? = nil) throws {
        try ensureLoaded()
        var updated = connections
        for entry in plan.entries where selectedIDs?.contains(entry.connection.id) ?? true {
            guard entry.action != .unchanged else { continue }
            let index = updated.firstIndex { $0.id == entry.connection.id }
            if let previous = entry.previous {
                guard let index, updated[index] == previous else { throw ConnectionStoreError.staleImportPlan }
                updated[index] = entry.connection
            } else {
                guard index == nil, !updated.contains(where: {
                    $0.importSource?.kind == "jump" && $0.importSource?.uniqueID == entry.connection.importSource?.uniqueID
                }) else { throw ConnectionStoreError.staleImportPlan }
                updated.append(entry.connection)
            }
        }
        guard updated != connections else { return }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try Data(contentsOf: fileURL).write(to: importBackupURL, options: .atomic)
        }
        try replaceAll(updated)
    }

    private func write(_ connections: [Connection]) throws {
        try Self.validate(connections)
        let data = try Self.encoder().encode(ConnectionStoreDocument(connections: connections))
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func validate(_ connections: [Connection]) throws {
        var ids: Set<UUID> = []
        for connection in connections {
            guard ids.insert(connection.id).inserted else { throw ConnectionStoreError.duplicateID(connection.id) }
            try connection.validate()
        }
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        // Reference-epoch doubles round-trip Date exactly; scaling to milliseconds loses low bits.
        encoder.dateEncodingStrategy = .deferredToDate
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return decoder
    }

    private static func migrateLegacy(_ data: Data, version: Int) throws -> Data {
        guard version == 0 else { throw ConnectionStoreError.unsupportedSchema(version) }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let array = object as? [[String: Any]] ?? (object as? [String: Any])?["connections"] as? [[String: Any]] else {
            throw ConnectionStoreError.invalidStore
        }
        let defaults = try JSONSerialization.jsonObject(with: encoder().encode(
            Connection(name: "", host: "placeholder.example"))) as! [String: Any]
        let migrated = array.map { old in
            defaults.merging(old, uniquingKeysWith: { _, new in new })
                .merging(["schemaVersion": Connection.currentSchemaVersion], uniquingKeysWith: { _, new in new })
        }
        return try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "connections": migrated])
    }
}
