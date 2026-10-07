import Foundation
import Security

public protocol CredentialStore: Sendable {
    func get(for connectionID: UUID) throws -> String?
    func set(_ password: String, for connectionID: UUID) throws
    func delete(for connectionID: UUID) throws
}

/// Status-only error: never contains accounts, passwords or Keychain item data.
public struct CredentialStoreError: Error, Equatable, Sendable {
    public let status: OSStatus
    public init(status: OSStatus) { self.status = status }
}

public struct KeychainCredentialStore: CredentialStore {
    public static let defaultService = "nrw.neuhaus.weitblick-remote"
    public let service: String
    public init(service: String = Self.defaultService) { self.service = service }

    public func get(for connectionID: UUID) throws -> String? {
        var query = query(for: connectionID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CredentialStoreError(status: status) }
        guard let data = result as? Data, let password = String(data: data, encoding: .utf8) else {
            throw CredentialStoreError(status: errSecDecode)
        }
        return password
    }

    public func set(_ password: String, for connectionID: UUID) throws {
        let query = query(for: connectionID)
        let value = [kSecValueData as String: Data(password.utf8)]
        var status = SecItemUpdate(query as CFDictionary, value as CFDictionary)
        if status == errSecItemNotFound {
            var item = query.merging(value, uniquingKeysWith: { _, new in new })
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
            // A concurrent writer can create the item between Update and Add.
            if status == errSecDuplicateItem { status = SecItemUpdate(query as CFDictionary, value as CFDictionary) }
        }
        guard status == errSecSuccess else { throw CredentialStoreError(status: status) }
    }

    public func delete(for connectionID: UUID) throws {
        let status = SecItemDelete(query(for: connectionID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError(status: status)
        }
    }

    private func query(for id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString, kSecAttrSynchronizable as String: false]
    }
}

/// Lock protected so the same test fake can be shared across connection/session actors.
public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var passwords: [UUID: String] = [:]
    public init() {}
    public func get(for connectionID: UUID) throws -> String? {
        lock.withLock { passwords[connectionID] }
    }
    public func set(_ password: String, for connectionID: UUID) throws {
        lock.withLock { passwords[connectionID] = password }
    }
    public func delete(for connectionID: UUID) throws {
        _ = lock.withLock { passwords.removeValue(forKey: connectionID) }
    }
}
