import Foundation
import Testing
import Security
@testable import ConnectionStore

@Suite("Credential stores")
struct CredentialStoreTests {
    @Test func fakeGetSetDeleteAndIsolation() throws {
        let store = InMemoryCredentialStore()
        let id = UUID(), other = UUID()
        #expect(try store.get(for: id) == nil)
        try store.set("synthetic-password", for: id)
        #expect(try store.get(for: id) == "synthetic-password")
        #expect(try store.get(for: other) == nil)
        try store.set("replacement-synthetic-password", for: id)
        #expect(try store.get(for: id) == "replacement-synthetic-password")
        try store.delete(for: id)
        try store.delete(for: id)
        #expect(try store.get(for: id) == nil)
    }

    @Test func realKeychainThrowawayServiceAlwaysCleansUp() throws {
        let service = "nrw.neuhaus.sprung.tests." + UUID().uuidString
        let store = KeychainCredentialStore(service: service)
        let id = UUID()
        defer {
            // Delete the entire unique service, even if an assertion or get/update step fails.
            let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                                       kSecAttrService as String: service] as CFDictionary)
            #expect(status == errSecSuccess || status == errSecItemNotFound)
        }
        #expect(try store.get(for: id) == nil)
        try store.set("synthetic-keychain-password", for: id)
        #expect(try store.get(for: id) == "synthetic-keychain-password")
        try store.set("synthetic-replacement", for: id)
        #expect(try store.get(for: id) == "synthetic-replacement")
        try store.delete(for: id)
        #expect(try store.get(for: id) == nil)
        try store.delete(for: id)
    }
}
