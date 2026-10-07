import ConnectionStore
import XCTest

/// A temporary folder for a store file and Jump files, removed afterwards.
final class TemporaryFolder {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("WeitblickAppTests-\(UUID().uuidString)")
    init() throws { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
    deinit { try? FileManager.default.removeItem(at: url) }
    var storeURL: URL { url.appendingPathComponent("connections.json") }
}

@MainActor
final class ConnectionLibraryTests: XCTestCase {
    private func makeLibrary(_ folder: TemporaryFolder, credentials: InMemoryCredentialStore = InMemoryCredentialStore()) -> ConnectionLibrary {
        ConnectionLibrary(store: ConnectionStore(fileURL: folder.storeURL), credentials: credentials)
    }

    func testFirstStartUntilSomethingIsSaved() async throws {
        let folder = try TemporaryFolder()
        let library = makeLibrary(folder)
        await library.load()
        XCTAssertTrue(library.isFirstStart)
        try await library.add(Connection(name: "PC", host: "pc01.example"))
        XCTAssertFalse(library.isFirstStart)
        XCTAssertEqual(library.connections.map(\.name), ["PC"])
    }

    func testUnreadableFileIsReportedAndNeverOverwritten() async throws {
        let folder = try TemporaryFolder()
        let garbage = Data("{ kaputt".utf8)
        try garbage.write(to: folder.storeURL)
        let library = makeLibrary(folder)
        await library.load()
        XCTAssertNotNil(library.loadError)
        XCTAssertFalse(library.isFirstStart, "no Jump migration over an existing file")
        do {
            try await library.add(Connection(name: "PC", host: "pc01.example"))
            XCTFail("adding must fail while the file is unreadable")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: folder.storeURL), garbage)
    }

    func testDeleteAlsoRemovesThePasswordAndDuplicateCopiesIt() async throws {
        let folder = try TemporaryFolder()
        let credentials = InMemoryCredentialStore()
        let library = makeLibrary(folder, credentials: credentials)
        await library.load()
        let original = Connection(name: "PC", host: "pc01.example")
        try await library.add(original)
        try library.setPassword("secret", for: original.id)
        let copy = try await library.duplicate(original.id)
        XCTAssertEqual(copy.name, "PC copy")
        XCTAssertEqual(library.password(for: copy.id), "secret")
        try await library.delete([original.id])
        XCTAssertNil(library.password(for: original.id))
        XCTAssertEqual(library.connections.map(\.id), [copy.id])
    }

    func testMarkConnectedKeepsConcurrentEdits() async throws {
        let folder = try TemporaryFolder()
        let library = makeLibrary(folder)
        await library.load()
        var connection = Connection(name: "PC", host: "pc01.example")
        try await library.add(connection)
        connection.notes = "edited"
        try await library.update(connection)
        let when = Date(timeIntervalSinceReferenceDate: 1000)
        await library.markConnected(connection.id, at: when)
        XCTAssertEqual(library.connection(with: connection.id)?.notes, "edited")
        XCTAssertEqual(library.connection(with: connection.id)?.lastConnected, when)
    }

    func testTrustAddsOrReplacesFingerprints() async throws {
        let folder = try TemporaryFolder()
        let library = makeLibrary(folder)
        await library.load()
        let connection = Connection(name: "PC", host: "pc01.example")
        try await library.add(connection)
        try await library.trust(fingerprint: "AA:BB", for: connection.id, replacing: false)
        try await library.trust(fingerprint: "aabb", for: connection.id, replacing: false)
        XCTAssertEqual(library.connection(with: connection.id)?.security.trustedCertificateFingerprints, ["AA:BB"])
        try await library.trust(fingerprint: "CC:DD", for: connection.id, replacing: true)
        XCTAssertEqual(library.connection(with: connection.id)?.security.trustedCertificateFingerprints, ["CC:DD"])
    }

    func testOverviewFiltersSortsAndIgnoresHiddenSelection() async throws {
        let folder = try TemporaryFolder()
        let library = makeLibrary(folder)
        await library.load()
        var alpha = Connection(name: "Alpha", host: "pc01.example")
        alpha.lastConnected = Date(timeIntervalSinceReferenceDate: 10)
        var beta = Connection(name: "Beta", host: "pc02.example")
        beta.lastConnected = Date(timeIntervalSinceReferenceDate: 20)
        try await library.add(alpha)
        try await library.add(beta)
        let model = OverviewModel(library: library, activity: SessionActivity())
        model.sortOrder = .name
        XCTAssertEqual(model.visibleConnections.map(\.name), ["Alpha", "Beta"])
        model.sortOrder = .recent
        XCTAssertEqual(model.visibleConnections.map(\.name), ["Beta", "Alpha"])
        model.selection = [alpha.id, beta.id]
        model.searchText = "pc02"
        XCTAssertEqual(model.selectedConnections.map(\.id), [beta.id])
    }
}
