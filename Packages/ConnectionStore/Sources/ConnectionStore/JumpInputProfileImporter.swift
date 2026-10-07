import Foundation
import KeyboardEngine

public enum JumpMappingClassification: String, Codable, Sendable {
    case builtIn, customConvertible, notConvertible, disabled
}

public struct JumpKeyboardMapping: Codable, Sendable {
    public var fromChar: Int?
    public var fromModifiers: Int?
    public var fromScanCode: Int?
    public var toChar: Int?
    public var toModifiers: Int?
    public var enabled: Bool
    public var persistent: Bool
    public var exclusive: Bool
    public var fromKey: String?
    public var toKey: String?
    public var classification: JumpMappingClassification
    public var rule: ShortcutRule?
    public var explanation: String
}

public struct JumpInputProfile: Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var modifierDeferDisabled: Bool
    public var osShortcutsDisabled: Bool
    public var mappingsDisabled: Bool
    public var shortcutsDisabled: Bool
    public var modifierForUnmodifiedKeys: Int
    /// Jump shortcut IDs are undocumented. Preserve their states in the report, not as Sprung rules.
    public var shortcuts: [String: Bool]
    public var mappings: [JumpKeyboardMapping]
    public var warnings: [String]
    public var customRules: [ShortcutRule] {
        mappings.filter { $0.classification == .customConvertible }.compactMap(\.rule)
    }

    /// Opt-in only; disabled/default/unconvertible mappings never alter the person's config.
    public func applyingCustomRules(to config: KeyboardConfig) -> KeyboardConfig {
        var config = config
        for rule in customRules {
            config.rules.removeAll { $0.mac == rule.mac }
            config.rules.insert(rule, at: 0)
        }
        return config
    }
}

public struct JumpInputProfileReport: Codable, Sendable {
    public var profiles: [JumpInputProfile]
    public var warnings: [String]
    public var humanReadable: String {
        var lines = ["Jump input profile preview (raw plist graph, read-only)"]
        for warning in warnings { lines.append("Warning: \(warning)") }
        for profile in profiles {
            lines.append("\n\(profile.name): \(profile.mappings.count) mappings; modifierDeferDisabled=\(profile.modifierDeferDisabled), osShortcutsDisabled=\(profile.osShortcutsDisabled)")
            for mapping in profile.mappings {
                let source = mapping.fromChar.map(String.init) ?? "?"
                let target = mapping.toChar.map(String.init) ?? "?"
                lines.append("  \(source)/\(mapping.fromModifiers ?? -1) -> \(target)/\(mapping.toModifiers ?? -1): \(mapping.classification.rawValue); \(mapping.explanation)")
                lines.append("    enabled=\(mapping.enabled), persistent=\(mapping.persistent), exclusive=\(mapping.exclusive)")
            }
            for warning in profile.warnings { lines.append("  Warning: \(warning)") }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

public struct JumpInputProfileImporter: Sendable {
    public static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Containers/com.p5sys.jump.mac.viewer/Data/Library/Application Support/Jump Desktop/JDInputProfile.plist")
    }
    public let fileURL: URL
    public init(fileURL: URL = Self.defaultFileURL) { self.fileURL = fileURL }
    public func read() throws -> JumpInputProfileReport { try decode(Data(contentsOf: fileURL)) }

    public func decode(_ data: Data) throws -> JumpInputProfileReport {
        let root = try KeyedArchiveGraph.decode(data)
        guard let objects = root["profiles"] as? [[String: Any]] else { throw JumpInputProfileError.invalidArchive }
        var profiles: [JumpInputProfile] = []
        for (index, object) in objects.enumerated() {
            let disabled = object["mappingsDisabled"] as? Bool ?? false
            let mappingsObject = object["mappings"] as? [String: Any]
            let mappings = mappingsObject?["mappings"] as? [[String: Any]] ?? []
            let shortcutsObject = object["shortcuts"] as? [String: Any]
            var warnings: [String] = []
            let shortcutStates = shortcutsObject?["shortcuts"] as? [String: Bool] ?? [:]
            if !shortcutStates.isEmpty { warnings.append("Shortcut ID switches retained for review; undocumented IDs are not converted.") }
            if (object["modifierMappings"] as? [Any])?.isEmpty == false {
                warnings.append("Modifier-only mappings cannot be represented by KeyboardEngine shortcut rules.")
            }
            if object["mouseOptions"] != nil { warnings.append("Mouse mappings are outside KeyboardEngine; not imported.") }
            if object["modifierDeferDisabled"] as? Bool == true {
                warnings.append("Disabling modifier deferral cannot be represented without changing Sprung's shortcut mode; flag reported only.")
            }
            if object["osShortcutsDisabled"] as? Bool == true {
                warnings.append("OS shortcut capture is an app-level setting; flag reported only.")
            }
            if (object["modifierForUnmodifiedKeys"] as? Int ?? 0) != 0 {
                warnings.append("modifierForUnmodifiedKeys is not expressible as a shortcut rule; reported only.")
            }
            let known: Set<String> = ["_class", "name", "profileid", "modifierDeferDisabled", "osShortcutsDisabled",
                "mappingsDisabled", "shortcutsDisabled", "modifierForUnmodifiedKeys", "shortcuts", "mappings",
                "modifierMappings", "mouseOptions"]
            for key in object.keys.sorted() where !known.contains(key) { warnings.append("Unknown profile field \(key); not imported.") }
            profiles.append(JumpInputProfile(
                id: object["profileid"] as? String ?? "profile-\(index)", name: object["name"] as? String ?? "Unnamed",
                modifierDeferDisabled: object["modifierDeferDisabled"] as? Bool ?? false,
                osShortcutsDisabled: object["osShortcutsDisabled"] as? Bool ?? false, mappingsDisabled: disabled,
                shortcutsDisabled: object["shortcutsDisabled"] as? Bool ?? false,
                modifierForUnmodifiedKeys: object["modifierForUnmodifiedKeys"] as? Int ?? 0,
                shortcuts: shortcutStates, mappings: mappings.map { convert($0, profileDisabled: disabled) }, warnings: warnings))
        }
        return JumpInputProfileReport(profiles: profiles, warnings: [])
    }

    private func convert(_ object: [String: Any], profileDisabled: Bool) -> JumpKeyboardMapping {
        var mapping = JumpKeyboardMapping(
            fromChar: object["fromChar"] as? Int, fromModifiers: object["fromModifiers"] as? Int,
            fromScanCode: object["fromScanCode"] as? Int, toChar: object["toChar"] as? Int,
            toModifiers: object["toModifiers"] as? Int, enabled: object["enabled"] as? Bool ?? false,
            persistent: object["persistent"] as? Bool ?? false, exclusive: object["exclusive"] as? Bool ?? false,
            classification: .notConvertible, explanation: "")
        mapping.fromKey = mapping.fromChar.flatMap(keyName)
        mapping.toKey = mapping.toChar.flatMap(keyName)
        guard mapping.enabled, !profileDisabled else {
            mapping.classification = .disabled
            mapping.explanation = "Disabled mapping/profile; no rule imported."
            return mapping
        }
        guard let from = mapping.fromChar, let to = mapping.toChar,
              let fromMods = mapping.fromModifiers, let toMods = mapping.toModifiers,
              let fromKey = mapping.fromKey, let toKey = mapping.toKey else {
            mapping.explanation = "Unresolved key code or incomplete mapping; no rule imported."
            return mapping
        }
        guard mapping.fromScanCode == nil || mapping.fromScanCode == -1,
              !mapping.persistent, !mapping.exclusive else {
            mapping.explanation = "Scancode/persistent/exclusive semantics have no lossless KeyboardEngine equivalent."
            return mapping
        }
        guard modifiersAreSideAgnostic(fromMods), modifiersAreSideAgnostic(toMods) else {
            mapping.explanation = "Unknown or side-specific modifier bits cannot be represented by chord rules."
            return mapping
        }
        var outputModifiers = toMods
        var assumption = ""
        // This exact default is specified as Alt+Arrow, although Jump encodes Alt+Meta (240).
        if fromMods == 192, toMods == 240,
           (from == 91 && to == 0x0200_FF51 || from == 93 && to == 0x0200_FF53) {
            outputModifiers = 48
            assumption = " Jump's 240 normalized to Alt only for SPEC's default bracket mappings."
        }
        let input = macModifierNames(fromMods) + [fromKey]
        let output = windowsModifierNames(outputModifiers) + [toKey]
        do {
            let mac = try MacChord(input.joined(separator: "+"))
            let windows = try WindowsChord(output.joined(separator: "+"))
            // App-reserved Ctrl+Option+Command combinations cannot run as remote rules.
            if mac.modifiers.isSuperset(of: [.control, .option, .command]) || mac.description == "ctrl+cmd+f" {
                mapping.explanation = "Sprung reserves this trigger locally; remote rule would never execute."
                return mapping
            }
            let rule = ShortcutRule(mac: mac, windows: [windows])
            mapping.rule = rule
            let defaultRule = ShortcutRule.defaults.contains { $0.mac == mac && $0.windows == [windows] }
            let genericCommand = fromMods == 192 && outputModifiers == 12 && from == to
                && from < 0x0200_0000 && !ShortcutRule.defaults.contains(where: { $0.mac == mac })
            mapping.classification = defaultRule || genericCommand ? .builtIn : .customConvertible
            mapping.explanation = "\(mac) -> \(windows). " + (mapping.classification == .builtIn
                ? "Equals Sprung default; nothing to import." : "Custom rule available for explicit import.") + assumption
            if from >= 0x0200_0000 || to >= 0x0200_0000 {
                mapping.explanation += " Special keys interpreted as 0x0200 + X11 keysym (inferred)."
            }
        } catch {
            mapping.explanation = "Recognized key cannot be represented as a KeyboardEngine chord."
        }
        return mapping
    }

    /// Observed FF08/FF09/FF51/FF53/FFC1/FFFF match X11 keysyms exactly. Broader table is inferred,
    /// not an assertion that all Jump versions implement every X11 key. Unknowns stay unresolved.
    private func keyName(_ code: Int) -> String? {
        if code & 0xFFFF_0000 == 0x0200_0000 {
            let symbol = code & 0xFFFF
            let keys: [Int: String] = [0xFF08: "backspace", 0xFF09: "tab", 0xFF0D: "return", 0xFF1B: "escape",
                0xFF50: "home", 0xFF51: "left", 0xFF52: "up", 0xFF53: "right", 0xFF54: "down",
                0xFF55: "pageup", 0xFF56: "pagedown", 0xFF57: "end", 0xFF63: "insert", 0xFFFF: "delete"]
            if let key = keys[symbol] { return key }
            if (0xFFBE...0xFFD1).contains(symbol) { return "f\(symbol - 0xFFBE + 1)" }
            return nil
        }
        if code == 32 { return "space" }
        if code == 43 { return "plus" }
        guard code >= 33, let scalar = UnicodeScalar(code), !CharacterSet.controlCharacters.contains(scalar) else { return nil }
        return String(scalar).lowercased()
    }
    private func modifiersAreSideAgnostic(_ bits: Int) -> Bool {
        bits >= 0 && bits & ~255 == 0 && [3, 12, 48, 192].allSatisfy { bits & $0 == 0 || bits & $0 == $0 }
    }
    private func macModifierNames(_ bits: Int) -> [String] {
        [(12, "ctrl"), (48, "opt"), (3, "shift"), (192, "cmd")].compactMap { bits & $0.0 != 0 ? $0.1 : nil }
    }
    private func windowsModifierNames(_ bits: Int) -> [String] {
        [(12, "ctrl"), (48, "alt"), (3, "shift"), (192, "win")].compactMap { bits & $0.0 != 0 ? $0.1 : nil }
    }
}
