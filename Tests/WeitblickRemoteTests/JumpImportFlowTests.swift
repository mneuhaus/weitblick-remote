import ConnectionStore
import XCTest

@MainActor
final class JumpImportFlowTests: XCTestCase {
    private func writeJump(_ folder: URL, id: String, name: String, host: String, extra: [String: Any] = [:]) throws {
        let object: [String: Any] = ["UniqueId": id, "DisplayName": name, "TcpHostName": host, "TcpPort": 3389,
                                     "ProtocolTypeCode": 0, "Username": "anna", "AudioPlaybackCode": 2,
                                     "ColorDepthCode": 2].merging(extra) { _, new in new }
        try JSONSerialization.data(withJSONObject: object).write(to: folder.appendingPathComponent("\(id).jump"))
    }

    private func makeFlow(_ jump: URL, _ library: ConnectionLibrary) throws -> JumpImportFlow {
        try JumpImportFlow(importer: JumpImporter(directory: jump),
                           inputProfileURL: jump.appendingPathComponent("missing.plist"), library: library)
    }

    func testPreviewApplyAndIdempotentReimport() async throws {
        let folder = try TemporaryFolder()
        let jump = folder.url.appendingPathComponent("jump")
        try FileManager.default.createDirectory(at: jump, withIntermediateDirectories: true)
        try writeJump(jump, id: "a", name: "Office", host: "pc01.example")
        try writeJump(jump, id: "b", name: "Warehouse", host: "pc02.example", extra: ["FutureField": 1])
        try Data("not json".utf8).write(to: jump.appendingPathComponent("c.jump"))
        let library = ConnectionLibrary(store: ConnectionStore(fileURL: folder.storeURL), credentials: InMemoryCredentialStore())
        await library.load()

        let flow = try makeFlow(jump, library)
        XCTAssertEqual(flow.rows.map(\.name), ["Office", "Warehouse"])
        XCTAssertEqual(flow.rows.map(\.action), [.create, .create])
        XCTAssertEqual(flow.selection, Set(flow.rows.map(\.id)), "new entries are preselected")
        XCTAssertEqual(flow.skipped.map(\.fileName), ["c.jump"])
        // Shown once instead of on every row:
        XCTAssertTrue(flow.commonNotes.contains(JumpImporter.passwordNotice))
        XCTAssertTrue(flow.rows.allSatisfy { !$0.notes.contains(JumpImporter.passwordNotice) })
        XCTAssertEqual(flow.commonIgnoredFields.map(\.field), ["ColorDepthCode"])
        XCTAssertEqual(flow.rows.first { $0.name == "Warehouse" }?.ignoredFields.map(\.field), ["FutureField"])

        let warehouse = try XCTUnwrap(flow.rows.first { $0.name == "Warehouse" }).id
        flow.selection.remove(warehouse)
        XCTAssertEqual(flow.selectedChangeCount, 1)
        await flow.apply()
        XCTAssertEqual(flow.phase, .done(JumpImportFlow.Outcome(created: ["Office"], notSelected: ["Warehouse"])))
        XCTAssertEqual(library.connections.map(\.name), ["Office"])

        let again = try makeFlow(jump, library)
        XCTAssertEqual(Set(again.rows.map(\.action)), [.create, .unchanged])
        XCTAssertEqual(again.selection.count, 1, "unchanged entries are not selected")
    }

    func testStalePlanIsReplannedInsteadOfOverwritingAnEdit() async throws {
        let folder = try TemporaryFolder()
        let jump = folder.url.appendingPathComponent("jump")
        try FileManager.default.createDirectory(at: jump, withIntermediateDirectories: true)
        try writeJump(jump, id: "a", name: "Office", host: "pc01.example")
        let library = ConnectionLibrary(store: ConnectionStore(fileURL: folder.storeURL), credentials: InMemoryCredentialStore())
        await library.load()
        await (try makeFlow(jump, library)).apply()
        try writeJump(jump, id: "a", name: "Office new", host: "pc01.example")
        let flow = try makeFlow(jump, library)
        XCTAssertEqual(flow.rows.first?.changes, ["Name"])
        var edited = try XCTUnwrap(library.connections.first)
        edited.notes = "edited locally"
        try await library.update(edited)
        await flow.apply()
        XCTAssertEqual(flow.phase, .preview)
        XCTAssertNotNil(flow.message)
        XCTAssertEqual(library.connections.first?.notes, "edited locally")
        XCTAssertEqual(flow.rows.first?.changes, ["Name"], "the new preview is based on the edited connection")
    }

    func testChangedAreas() {
        let old = Connection(name: "PC", host: "pc01.example")
        var new = old
        new.port = 3390
        new.redirection.printers = false
        new.keyboard.unicodeTextInput = true
        XCTAssertEqual(JumpImportFlow.changedAreas(from: old, to: new), ["Address", "Redirection", "Keyboard"])
    }
}
