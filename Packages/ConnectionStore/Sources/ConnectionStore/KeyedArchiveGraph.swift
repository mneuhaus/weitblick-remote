import Foundation

public enum JumpInputProfileError: Error, Equatable, Sendable {
    case invalidArchive
    case invalidReference(Int)
    case cyclicReference(Int)
    case archiveTooLarge
}

/// No NSKeyedUnarchiver and no custom-class instantiation: only plist values and reference resolution.
struct KeyedArchiveGraph {
    let objects: [Any]
    let uidKey: String
    var remainingVisits = 200_000

    static func decode(_ data: Data) throws -> [String: Any] {
        guard data.count <= 16 * 1024 * 1024 else { throw JumpInputProfileError.archiveTooLarge }
        let raw = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        // CFKeyedArchiverUID is private. Its documented XML plist representation is {CF$UID: index}.
        // Rename that key before parsing XML back, otherwise Foundation recreates the opaque UID.
        let xmlData = try PropertyListSerialization.data(fromPropertyList: raw, format: .xml, options: 0)
        guard var xml = String(data: xmlData, encoding: .utf8) else { throw JumpInputProfileError.invalidArchive }
        let marker = "SprungArchiveUID_" + UUID().uuidString
        xml = xml.replacingOccurrences(of: "<key>CF$UID</key>", with: "<key>\(marker)</key>")
        guard let normalized = try PropertyListSerialization.propertyList(from: Data(xml.utf8), options: [], format: nil)
                as? [String: Any],
              normalized["$archiver"] as? String == "NSKeyedArchiver",
              let objects = normalized["$objects"] as? [Any], !objects.isEmpty, objects.count <= 50_000,
              let top = normalized["$top"] as? [String: Any], let root = top["root"] else {
            throw JumpInputProfileError.invalidArchive
        }
        var graph = Self(objects: objects, uidKey: marker)
        guard let resolved = try graph.resolve(root, path: [], depth: 0) as? [String: Any] else {
            throw JumpInputProfileError.invalidArchive
        }
        return resolved
    }

    private mutating func resolve(_ value: Any, path: Set<Int>, depth: Int) throws -> Any {
        remainingVisits -= 1
        guard depth <= 64, remainingVisits >= 0 else { throw JumpInputProfileError.archiveTooLarge }
        if let dictionary = value as? [String: Any] {
            if dictionary.count == 1, let index = dictionary[uidKey] as? Int {
                guard objects.indices.contains(index) else { throw JumpInputProfileError.invalidReference(index) }
                if index == 0 { return NSNull() }
                guard !path.contains(index) else { throw JumpInputProfileError.cyclicReference(index) }
                return try resolve(objects[index], path: path.union([index]), depth: depth + 1)
            }
            if let values = dictionary["NS.objects"] as? [Any] {
                if let keys = dictionary["NS.keys"] as? [Any] {
                    guard keys.count == values.count else { throw JumpInputProfileError.invalidArchive }
                    var result: [String: Any] = [:]
                    for (key, value) in zip(keys, values) {
                        let resolvedKey = try resolve(key, path: path, depth: depth + 1)
                        let key: String
                        if let string = resolvedKey as? String {
                            key = string
                        } else if let number = resolvedKey as? NSNumber,
                                  String(cString: number.objCType) != "c", let integer = Int(exactly: number.doubleValue) {
                            // InputProfileKeyShortcuts stores integer NS.keys, not NSStrings.
                            key = String(integer)
                        } else {
                            throw JumpInputProfileError.invalidArchive
                        }
                        guard result[key] == nil else { throw JumpInputProfileError.invalidArchive }
                        result[key] = try resolve(value, path: path, depth: depth + 1)
                    }
                    return result
                }
                return try values.map { try resolve($0, path: path, depth: depth + 1) }
            }
            if let string = dictionary["NS.string"] as? String { return string }
            var result: [String: Any] = [:]
            for (key, value) in dictionary {
                if key == "$class" {
                    let classInfo = try resolve(value, path: path, depth: depth + 1) as? [String: Any]
                    result["_class"] = classInfo?["$classname"]
                } else {
                    result[key] = try resolve(value, path: path, depth: depth + 1)
                }
            }
            return result
        }
        if let values = value as? [Any] { return try values.map { try resolve($0, path: path, depth: depth + 1) } }
        return value
    }
}
