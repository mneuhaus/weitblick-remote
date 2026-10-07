import ConnectionStore
import Foundation
import Observation
import os

/// The saved connections as the app sees them: a main-actor snapshot of the `ConnectionStore`
/// actor, plus the passwords in the credential store (Keychain). Every change goes through the
/// store first; the snapshot follows.
@MainActor @Observable
final class ConnectionLibrary {
    let store: ConnectionStore
    @ObservationIgnored private let credentials: any CredentialStore
    private(set) var connections: [Connection] = []
    /// Set when the connections file exists but cannot be read. The store then refuses every
    /// change, so the file is never overwritten.
    private(set) var loadError: String?

    private static let logger = Logger(subsystem: "nrw.neuhaus.sprung", category: "library")

    init(store: ConnectionStore, credentials: any CredentialStore) {
        self.store = store
        self.credentials = credentials
    }

    /// No connections file yet: the first start (Jump migration is offered).
    var isFirstStart: Bool { !FileManager.default.fileExists(atPath: store.fileURL.path) }

    func load() async {
        do {
            connections = try await store.load()
            loadError = nil
        } catch {
            Self.logger.error("loading connections failed: \(String(describing: error), privacy: .public)")
            loadError = "Die Verbindungen in „\(store.fileURL.path)“ ließen sich nicht lesen. Die Datei bleibt unverändert."
        }
    }

    func connection(with id: UUID) -> Connection? {
        connections.first { $0.id == id }
    }

    func add(_ connection: Connection) async throws {
        try await store.insert(connection)
        await refresh()
    }

    func update(_ connection: Connection) async throws {
        try await store.update(connection)
        await refresh()
    }

    @discardableResult
    func modify(_ id: UUID, _ change: @escaping @Sendable (inout Connection) -> Void) async throws -> Connection {
        let result = try await store.modify(id: id, change)
        await refresh()
        return result
    }

    /// Deletes the connections and their saved passwords.
    func delete(_ ids: some Sequence<UUID>) async throws {
        for id in ids {
            try await store.delete(id: id)
            do {
                try deletePassword(for: id)
            } catch {
                Self.logger.error("deleting password failed: \(String(describing: error), privacy: .public)")
            }
        }
        await refresh()
    }

    /// A copy named "… Kopie" with the same saved password.
    func duplicate(_ id: UUID) async throws -> Connection {
        guard let original = connection(with: id) else { throw ConnectionStoreError.missingConnection(id) }
        let copy = try await store.duplicate(id: id, name: "\(original.name) Kopie")
        if let password = password(for: id) { try? setPassword(password, for: copy.id) }
        await refresh()
        return copy
    }

    /// Records a successful connection for the "last used" order. Failure is only logged.
    func markConnected(_ id: UUID, at date: Date = Date()) async {
        do {
            try await modify(id) { $0.lastConnected = date }
        } catch {
            Self.logger.error("recording last connection failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// "Immer vertrauen": adds the fingerprint; `replacing` drops the previously trusted ones (the
    /// server has a new certificate).
    func trust(fingerprint: String, for id: UUID, replacing: Bool) async throws {
        try await modify(id) { connection in
            if replacing { connection.security.trustedCertificateFingerprints = [] }
            if !connection.security.trusts(fingerprint: fingerprint) {
                connection.security.trustedCertificateFingerprints.append(fingerprint)
            }
        }
    }

    func refresh() async {
        connections = await store.connections
    }

    // MARK: Passwords

    /// The saved password; nil if there is none or the Keychain refused (only its status is logged).
    func password(for id: UUID) -> String? {
        do {
            return try credentials.get(for: id)
        } catch {
            Self.logger.error("reading password failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    func setPassword(_ password: String, for id: UUID) throws {
        try credentials.set(password, for: id)
    }

    func deletePassword(for id: UUID) throws {
        try credentials.delete(for: id)
    }
}
