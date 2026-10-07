import Foundation
import Testing
@testable import ConnectionStore

@Suite("Jump JSON import")
struct JumpImporterTests {
    @Test func mapsEverySpecField() throws {
        let temporary = try TemporaryDirectory()
        try temporary.writeJump(syntheticJump())
        let plan = try JumpImporter(directory: temporary.url).plan(existing: [])
        let entry = try #require(plan.entries.first)
        let c = entry.connection
        #expect(entry.action == .create)
        #expect(c.name == "Synthetic workstation")
        #expect(c.host == "PC0001.example")
        #expect(c.port == 13389)
        #expect(c.username == "testuser")
        #expect(c.domain == "EXAMPLE")
        #expect(c.protocol == .rdp)
        #expect(c.redirection.driveRedirection)
        #expect(c.redirection.drives == [
            DriveMapping(name: "Test files", localPath: "/Users/testuser/Downloads", readOnly: true, sourceID: "synthetic-drive-1"),
            DriveMapping(name: "Work", localPath: "/Users/testuser/Workspace", enabled: false, sourceID: "synthetic-drive-2"),
        ])
        #expect(!c.redirection.clipboard)
        #expect(c.redirection.audioPlayback == .local)
        #expect(c.redirection.microphone)
        #expect(c.redirection.audioInputDevice == "Synthetic microphone")
        #expect(c.redirection.printers)
        #expect(c.redirection.defaultPrinter == "Synthetic printer")
        #expect(!c.display.dynamicResolution)
        #expect(!c.display.matchScreenResolution)
        #expect(c.display.fixedWidth == 1600 && c.display.fixedHeight == 900)
        #expect(c.display.retina)
        #expect(c.display.desktopScaleFactor == 150)
        #expect(c.display.startFullscreen)
        #expect(c.display.useAllMonitors && c.display.monitorCount == 2)
        #expect(c.keyboard.layoutOverride?.rawValue == 1031)
        #expect(c.keyboard.unicodeTextInput)
        #expect(c.security.disableNLA)
        #expect(c.security.consoleSession)
        #expect(c.security.ignoreCertificateErrors)
        #expect(c.security.trustedCertificateFingerprints == ["SYNTHETIC:AA:BB:CC"])
        #expect(c.advanced.alternateShell == "C:\\Windows\\notepad.exe")
        #expect(c.advanced.workingDir == "C:\\Test")
        #expect(c.advanced.loadBalanceInfo == "synthetic-routing-token")
        #expect(c.advanced.gatewayRef == "synthetic-gateway")
        #expect(c.advanced.wakeOnLANMACAddresses == ["02:00:00:00:00:01"])
        #expect(c.tags == ["synthetic", "test"])
        #expect(c.lastConnected == Date(timeIntervalSinceReferenceDate: 600000000.125))
        #expect(c.importSource?.uniqueID == "synthetic-jump-0001")
        #expect(c.importSource?.fileName == "test.jump")
        let report = try #require(plan.report.connections.first)
        #expect(report.ignoredFields.contains { $0.field == "FutureJumpField" })
        for field in ["ColorDepthCode", "RdpPerformanceFlags", "ConnectionTypeCode", "TypeCode", "OsTypeCode", "GestureProfileCode"] {
            #expect(report.ignoredFields.contains { $0.field == field && $0.reason.contains("Undocumented") })
        }
        #expect(report.warnings.contains { $0.contains("Password unavailable") })
        let source = try syntheticJump()
        let reported = Set(report.importedFields + report.ignoredFields.map(\.field))
        #expect(Set(source.keys).isSubset(of: reported))
    }

    @Test func idempotentPlanApplyAndPersistence() async throws {
        let temporary = try TemporaryDirectory()
        var source = try syntheticJump()
        source["LastConnectedTime"] = 600000000.123456
        try temporary.writeJump(source)
        let importer = JumpImporter(directory: temporary.url)
        let store = ConnectionStore(fileURL: temporary.storeURL)
        let first = try importer.plan(existing: [])
        try await importer.apply(first, to: store)
        let reloaded = ConnectionStore(fileURL: temporary.storeURL)
        let existing = try await reloaded.load()
        let again = try importer.plan(existing: existing, importedAt: .distantFuture)
        #expect(again.createCount == 0 && again.updateCount == 0 && again.unchangedCount == 1)
        #expect(again.entries[0].connection.id == first.entries[0].connection.id)
        #expect(again.entries[0].connection.importSource?.importedAt == existing[0].importSource?.importedAt)
        source["DisplayName"] = "Updated synthetic workstation"
        try temporary.writeJump(source)
        let update = try importer.plan(existing: existing)
        #expect(update.updateCount == 1)
        try await importer.apply(update, to: reloaded)
        #expect(await reloaded.connections[0].name == "Updated synthetic workstation")
    }

    @Test func stalePlanRejectedAndCallerCanSelectNone() async throws {
        let temporary = try TemporaryDirectory()
        try temporary.writeJump(minimalJump())
        let importer = JumpImporter(directory: temporary.url)
        let plan = try importer.plan(existing: [])
        let store = ConnectionStore(fileURL: temporary.storeURL)
        try await importer.apply(plan, to: store, selectedIDs: [])
        #expect(await store.connections.isEmpty)
        try await importer.apply(plan, to: store)
        await #expect(throws: ConnectionStoreError.staleImportPlan) { try await importer.apply(plan, to: store) }
        var changed = await store.connections[0]
        var source = minimalJump()
        source["DisplayName"] = "Source change"
        try temporary.writeJump(source)
        let update = try importer.plan(existing: await store.connections)
        changed.notes = "Concurrent local edit"
        try await store.update(changed)
        await #expect(throws: ConnectionStoreError.staleImportPlan) { try await importer.apply(update, to: store) }
        #expect(await store.connections[0].notes == "Concurrent local edit")
    }

    @Test func vncAndConservativeUnknowns() throws {
        let temporary = try TemporaryDirectory()
        var source = minimalJump(transport: 1)
        source["AudioPlaybackCode"] = 777
        source["KeyboardAutomaticLocaleDetection"] = true
        source["KeyboardLocaleId"] = 1033
        source["DesktopScaleFactor"] = 0
        source["LastConnectedTime"] = 0
        source["AudioInputDevice"] = NSNull()
        source["Tags"] = NSNull()
        try temporary.writeJump(source)
        let plan = try JumpImporter(directory: temporary.url).plan(existing: [])
        let c = try #require(plan.entries.first).connection
        #expect(c.protocol == .vnc)
        #expect(c.vncURL?.absoluteString == "vnc://PC0001.example:5900")
        #expect(c.redirection.audioPlayback == .off)
        #expect(!c.redirection.microphone)
        #expect(c.keyboard.layoutOverride == nil)
        #expect(c.display.desktopScaleFactor == nil)
        #expect(c.lastConnected == nil)
        #expect(plan.report.connections[0].ignoredFields.contains { $0.field == "AudioPlaybackCode" })
        source["ProtocolTypeCode"] = 7
        try temporary.writeJump(source)
        #expect(try JumpImporter(directory: temporary.url).plan(existing: []).entries.isEmpty)
    }

    @Test func duplicateIDsMalformedTypesAndUnreadableFilesReported() throws {
        let temporary = try TemporaryDirectory()
        try temporary.writeJump(minimalJump(), fileName: "a.jump")
        try temporary.writeJump(minimalJump(), fileName: "b.jump")
        var malformed = minimalJump(id: "synthetic-other")
        malformed["TcpPort"] = "3389"
        malformed["ClipboardRedirection"] = 1
        malformed["DriveMappings"] = [["DisplayName": "Synthetic", "LocalPath": "/tmp/synthetic", "Enabled": true, "UnknownDriveField": 5]]
        try temporary.writeJump(malformed, fileName: "c.jump")
        try Data("not JSON".utf8).write(to: temporary.url.appendingPathComponent("d.jump"))
        try temporary.writeJump(["TcpHostName": "PC0003.example"], fileName: "e.jump")
        let plan = try JumpImporter(directory: temporary.url).plan(existing: [])
        #expect(plan.entries.count == 2)
        #expect(plan.report.connections.count == 5)
        #expect(plan.report.connections[1].warnings.contains { $0.contains("Duplicate UniqueId") })
        let issues = plan.report.connections[2].ignoredFields.map(\.field)
        #expect(issues.contains("TcpPort") && issues.contains("ClipboardRedirection"))
        #expect(issues.contains("DriveMappings[0].UnknownDriveField"))
        #expect(plan.report.connections[3].action == nil)
        #expect(plan.report.connections[4].warnings.contains { $0.contains("Missing UniqueId") })
    }

    @Test func sourceRemainsByteForByteUnchanged() throws {
        let temporary = try TemporaryDirectory()
        try temporary.writeJump(syntheticJump())
        let url = temporary.url.appendingPathComponent("test.jump")
        let before = try Data(contentsOf: url)
        _ = try JumpImporter(directory: temporary.url).plan(existing: [])
        #expect(try Data(contentsOf: url) == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: temporary.url.path) == ["test.jump"])
    }
}
