import SprungKit
import XCTest

final class DesktopGeometryTests: XCTestCase {
    func testRetinaDesktopMapsOnePointToTwoPixels() {
        let geometry = DesktopGeometry(bounds: CGRect(x: 0, y: 0, width: 800, height: 500),
                                       desktop: PixelSize(width: 1600, height: 1000))
        XCTAssertEqual(geometry.pointsPerPixel, 0.5)
        XCTAssertEqual(geometry.remotePoint(for: CGPoint(x: 100.25, y: 40.75)), RemotePoint(x: 200, y: 81))
    }

    func testLetterboxedDesktopAccountsForTheBars() {
        // 1000x500 points showing a 1000x1000 desktop: 0.5 pt/px, 250 pt bars left and right.
        let geometry = DesktopGeometry(bounds: CGRect(x: 0, y: 0, width: 1000, height: 500),
                                       desktop: PixelSize(width: 1000, height: 1000))
        XCTAssertEqual(geometry.contentRect, CGRect(x: 250, y: 0, width: 500, height: 500))
        XCTAssertEqual(geometry.remotePoint(for: CGPoint(x: 500, y: 250)), RemotePoint(x: 500, y: 500))
    }

    func testPointsOutsideTheDesktopAreClamped() {
        let geometry = DesktopGeometry(bounds: CGRect(x: 0, y: 0, width: 1000, height: 500),
                                       desktop: PixelSize(width: 1000, height: 1000))
        XCTAssertEqual(geometry.remotePoint(for: CGPoint(x: 10, y: -5)), RemotePoint(x: 0, y: 0))
        XCTAssertEqual(geometry.remotePoint(for: CGPoint(x: 990, y: 600)), RemotePoint(x: 999, y: 999))
    }
}
