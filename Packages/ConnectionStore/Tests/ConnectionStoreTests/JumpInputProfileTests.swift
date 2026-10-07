import Foundation
import Testing
import KeyboardEngine
@testable import ConnectionStore

@Suite("Raw Jump keyed archives")
struct JumpInputProfileTests {
    @Test func allWindowsDefaultsNeedNoImport() throws {
        var mappings = "cxvazspft".unicodeScalars.map { mapping(from: Int($0.value), to: Int($0.value)) }
        mappings += [mapping(from: 122, fromMods: 195, to: 121),
                     mapping(from: 113, to: 0x0200_FFC1, toMods: 48),
                     mapping(from: 91, to: 0x0200_FF51, toMods: 240),
                     mapping(from: 93, to: 0x0200_FF53, toMods: 240),
                     mapping(from: 0x0200_FF08, fromMods: 60, to: 0x0200_FFFF, toMods: 60)]
        let report = try JumpInputProfileImporter().decode(inputArchive(mappings: mappings))
        let profile = try #require(report.profiles.first)
        #expect(profile.name == "Windows")
        #expect(profile.mappings.count == 14)
        #expect(profile.mappings.allSatisfy { $0.classification == .builtIn })
        #expect(profile.customRules.isEmpty)
        #expect(profile.mappings[10].toKey == "f4")
        #expect(profile.mappings[11].rule?.windows.first?.description == "alt+left")
        #expect(profile.mappings[12].rule?.windows.first?.description == "alt+right")
        #expect(profile.mappings[13].fromKey == "backspace")
        #expect(profile.mappings[13].toKey == "delete")
        #expect(profile.shortcuts == ["0": true, "4": false])
    }

    @Test func actualDecimalSpecialKeyWitnesses() throws {
        let witnesses: [(Int, String)] = [(33619720, "backspace"), (33619721, "tab"),
            (33619793, "left"), (33619795, "right"), (33619905, "f4"), (33619967, "delete")]
        #expect(33619905 == 0x0200_FFC1)
        let mappings = witnesses.map { mapping(from: 107, to: $0.0) }
        let profile = try #require(JumpInputProfileImporter().decode(inputArchive(mappings: mappings)).profiles.first)
        #expect(profile.mappings.map(\.toKey) == witnesses.map { Optional($0.1) })
        #expect(profile.mappings.allSatisfy { $0.classification == .customConvertible })
    }

    @Test func customRuleConvertsAndReplacesMatchingRule() throws {
        let report = try JumpInputProfileImporter().decode(inputArchive(mappings: [mapping(from: 107, to: 109)]))
        let profile = try #require(report.profiles.first)
        #expect(profile.mappings[0].classification == .customConvertible)
        #expect(profile.customRules[0].mac.description == "cmd+k")
        #expect(profile.customRules[0].windows[0].description == "ctrl+m")
        let original = KeyboardConfig()
        let applied = profile.applyingCustomRules(to: original)
        #expect(applied.rules.first?.mac.description == "cmd+k")
        #expect(applied.rules.count == original.rules.count + 1)
        #expect(profile.applyingCustomRules(to: applied).rules.count == applied.rules.count)
    }

    @Test func genericCommandDoesNotHideConflictingDefault() throws {
        let mappings = [mapping(from: 113, to: 113), mapping(from: 33619793, to: 33619793)]
        let profile = try #require(JumpInputProfileImporter().decode(inputArchive(mappings: mappings)).profiles.first)
        #expect(profile.mappings.allSatisfy { $0.classification == .customConvertible })
    }

    @Test func unknownKeySideModifiersAndFlagsNotGuessed() throws {
        var scanMapping = mapping(from: 107, to: 109)
        scanMapping["fromScanCode"] = 45
        let mappings = [mapping(to: 0x0200_1234), mapping(fromMods: 64), mapping(toMods: 1024),
                        mapping(persistent: true), mapping(exclusive: true), scanMapping,
                        mapping(fromMods: 252)]
        let profile = try #require(JumpInputProfileImporter().decode(inputArchive(mappings: mappings)).profiles.first)
        #expect(profile.mappings.allSatisfy { $0.classification == .notConvertible })
        #expect(profile.customRules.isEmpty)
        #expect(profile.mappings[0].toKey == nil)
        #expect(profile.mappings[6].explanation.contains("reserves"))
    }

    @Test func disabledMappingsAndProfileSettingsReported() throws {
        let data = try inputArchive(mappings: [mapping(enabled: false), mapping()], disabled: true,
                                    modifierDeferDisabled: true, osShortcutsDisabled: true, format: .xml)
        let report = try JumpInputProfileImporter().decode(data)
        let profile = try #require(report.profiles.first)
        #expect(profile.mappings.allSatisfy { $0.classification == .disabled })
        #expect(profile.modifierDeferDisabled && profile.osShortcutsDisabled && profile.mappingsDisabled)
        #expect(profile.warnings.contains { $0.contains("modifier deferral") })
        #expect(profile.warnings.contains { $0.contains("OS shortcut capture") })
    }

    @Test func cyclesAndInvalidReferencesRejectedWithoutInstantiatingClasses() throws {
        var cycle = ArchiveFixture()
        let reference = cycle.reference(["next": ["CF$UID": 1]])
        #expect(throws: JumpInputProfileError.cyclicReference(1)) {
            try JumpInputProfileImporter().decode(cycle.data(root: reference))
        }
        let invalid = try ArchiveFixture().data(root: ["CF$UID": 999])
        #expect(throws: JumpInputProfileError.invalidReference(999)) { try JumpInputProfileImporter().decode(invalid) }
    }

    @Test func safeFileReadAndNonArchiveRejected() throws {
        let temporary = try TemporaryDirectory()
        let file = temporary.url.appendingPathComponent("JDInputProfile.plist")
        let data = try inputArchive(mappings: [mapping()])
        try data.write(to: file)
        #expect(try JumpInputProfileImporter(fileURL: file).read().profiles.count == 1)
        #expect(try Data(contentsOf: file) == data)
        let invalid = try PropertyListSerialization.data(fromPropertyList: ["name": "synthetic"], format: .binary, options: 0)
        #expect(throws: JumpInputProfileError.invalidArchive) { try JumpInputProfileImporter().decode(invalid) }
    }
}
