import Foundation
import Testing
@testable import ConnectionStore

final class TemporaryDirectory: @unchecked Sendable {
    let url: URL
    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("WeitblickStoreTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }
    var storeURL: URL { url.appendingPathComponent("connections.json") }
    func writeJump(_ object: [String: Any], fileName: String = "test.jump") throws {
        try JSONSerialization.data(withJSONObject: object).write(to: url.appendingPathComponent(fileName))
    }
}

func syntheticJump() throws -> [String: Any] {
    let file = Bundle.module.url(forResource: "Synthetic", withExtension: "jump", subdirectory: "Fixtures")!
    return try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
}

func minimalJump(id: String = "synthetic-1", host: String = "PC0001.example", transport: Int = 0) -> [String: Any] {
    ["UniqueId": id, "DisplayName": "Synthetic workstation", "TcpHostName": host,
     "TcpPort": transport == 0 ? 3389 : 5900, "ProtocolTypeCode": transport, "Username": "testuser"]
}

/// Synthetic NSKeyedArchiver object graph using XML's CF$UID form. No private classes instantiated.
struct ArchiveFixture {
    var objects: [Any] = ["$null"]
    mutating func reference(_ object: Any) -> [String: Int] {
        let index = objects.count
        objects.append(object)
        return ["CF$UID": index]
    }
    mutating func array(_ values: [Any]) -> [String: Int] { reference(["NS.objects": values]) }
    mutating func dictionary(_ values: [String: Any]) -> [String: Int] {
        let pairs = values.sorted { $0.key < $1.key }
        let keys = pairs.map { reference(Int($0.key).map { $0 as Any } ?? $0.key) }
        return reference(["NS.keys": keys, "NS.objects": pairs.map(\.value)])
    }
    mutating func custom(_ name: String, _ fields: [String: Any]) -> [String: Int] {
        let classRef = reference(["$classname": name, "$classes": [name, "NSObject"]])
        return reference(fields.merging(["$class": classRef], uniquingKeysWith: { _, new in new }))
    }
    func data(root: [String: Int], format: PropertyListSerialization.PropertyListFormat = .binary) throws -> Data {
        let archive: [String: Any] = ["$archiver": "NSKeyedArchiver", "$version": 100000,
                                     "$top": ["root": root], "$objects": objects]
        // XML parse promotes CF$UID dictionaries to opaque UID objects, just like a real archive.
        let xml = try PropertyListSerialization.data(fromPropertyList: archive, format: .xml, options: 0)
        let parsed = try PropertyListSerialization.propertyList(from: xml, options: [], format: nil)
        return try PropertyListSerialization.data(fromPropertyList: parsed, format: format, options: 0)
    }
}

func inputArchive(mappings: [[String: Any]], disabled: Bool = false,
                  modifierDeferDisabled: Bool = false, osShortcutsDisabled: Bool = false,
                  format: PropertyListSerialization.PropertyListFormat = .binary) throws -> Data {
    var fixture = ArchiveFixture()
    let mappingRefs = mappings.map { fixture.custom("InputProfileKeyboardMapping", $0) }
    let mappingsArray = fixture.array(mappingRefs)
    let mappingsRef = fixture.custom("InputProfileKeyboardMappings", ["mappings": mappingsArray])
    let shortcutValues = fixture.dictionary(["0": true, "4": false])
    let shortcutsRef = fixture.custom("InputProfileKeyShortcuts", ["shortcuts": shortcutValues])
    let mouseRef = fixture.custom("InputProfileMouse", [:])
    let modifiersRef = fixture.array([])
    let nameRef = fixture.reference("Windows")
    let idRef = fixture.reference("synthetic-windows-profile")
    let profile = fixture.custom("InputProfile", [
        "name": nameRef, "profileid": idRef, "mappings": mappingsRef, "shortcuts": shortcutsRef,
        "mouseOptions": mouseRef, "modifierMappings": modifiersRef, "mappingsDisabled": disabled,
        "modifierDeferDisabled": modifierDeferDisabled, "osShortcutsDisabled": osShortcutsDisabled,
        "modifierForUnmodifiedKeys": 0, "shortcutsDisabled": false,
    ])
    let profiles = fixture.array([profile])
    let root = fixture.custom("InputProfiles", ["version": 1, "profiles": profiles])
    return try fixture.data(root: root, format: format)
}

func mapping(from: Int = 99, fromMods: Int = 192, to: Int = 99, toMods: Int = 12,
             enabled: Bool = true, persistent: Bool = false, exclusive: Bool = false) -> [String: Any] {
    ["fromChar": from, "fromModifiers": fromMods, "fromScanCode": -1,
     "toChar": to, "toModifiers": toMods, "enabled": enabled,
     "persistent": persistent, "exclusive": exclusive]
}
