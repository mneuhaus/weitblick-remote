import AppKit
@testable import WeitblickKit
import XCTest

@MainActor
final class RemoteCursorsTests: XCTestCase {
    private let arrow = RemotePointerImage(id: 7, width: 64, height: 48, hotspotX: 10, hotspotY: 20,
                                           bgra: Data(repeating: 0xFF, count: 64 * 48 * 4))

    func testCursorIsScaledToTheDesktopWithItsHotspot() {
        let cursors = RemoteCursors()
        cursors.pointsPerPixel = 0.5
        XCTAssertFalse(cursors.apply(.new(arrow)))
        XCTAssertTrue(cursors.apply(.set(id: 7)))
        XCTAssertEqual(cursors.current.image.size, NSSize(width: 32, height: 24))
        XCTAssertEqual(cursors.current.hotSpot, NSPoint(x: 5, y: 10))

        cursors.pointsPerPixel = 1 // e.g. Retina switched off
        XCTAssertEqual(cursors.current.image.size, NSSize(width: 64, height: 48))
    }

    func testHiddenAndDefaultShapes() {
        let cursors = RemoteCursors()
        _ = cursors.apply(.new(arrow))
        _ = cursors.apply(.set(id: 7))
        XCTAssertTrue(cursors.apply(.hidden))
        XCTAssertEqual(cursors.current.image.size, NSSize(width: 1, height: 1))
        XCTAssertTrue(cursors.apply(.systemDefault))
        XCTAssertTrue(cursors.current === NSCursor.arrow)
    }
}
