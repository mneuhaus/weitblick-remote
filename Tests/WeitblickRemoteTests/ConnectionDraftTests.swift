import ConnectionStore
import XCTest

final class ConnectionDraftTests: XCTestCase {
    func testProblems() {
        var draft = ConnectionDraft.new()
        XCTAssertEqual(draft.problem, "Enter a host.")
        draft.connection.host = "pc 01"
        XCTAssertEqual(draft.problem, "The host can’t contain spaces.")
        draft.connection.host = "  pc01.example "
        XCTAssertNil(draft.problem)
        draft.connection.port = 0
        XCTAssertNotNil(draft.problem)
        draft.connection.port = 3389
        draft.connection.display.matchScreenResolution = false
        draft.connection.display.fixedWidth = 100
        XCTAssertEqual(draft.problem, "The fixed resolution must be between 200 and 8192 pixels.")
    }

    func testSavedTrimsAndNamesAfterTheHost() {
        var draft = ConnectionDraft.new()
        draft.connection.host = " pc01.example "
        draft.connection.username = " anna "
        draft.connection.advanced.alternateShell = "  "
        draft.connection.advanced.wakeOnLANMACAddresses = ["02:00:00:00:00:01", " ", ""]
        let saved = draft.saved()
        XCTAssertEqual(saved.host, "pc01.example")
        XCTAssertEqual(saved.name, "pc01.example")
        XCTAssertEqual(saved.username, "anna")
        XCTAssertNil(saved.advanced.alternateShell)
        XCTAssertEqual(saved.advanced.wakeOnLANMACAddresses, ["02:00:00:00:00:01"])
        XCTAssertNoThrow(try saved.validate())
    }

    func testPasswordChange() {
        var draft = ConnectionDraft(connection: Connection(name: "PC", host: "pc01"), isNew: false, hasStoredPassword: true)
        XCTAssertEqual(draft.passwordChange, .keep)
        draft.removeStoredPassword = true
        XCTAssertEqual(draft.passwordChange, .remove)
        draft.password = "neu"
        XCTAssertEqual(draft.passwordChange, .set("neu"), "a typed password wins over removing")
    }
}
