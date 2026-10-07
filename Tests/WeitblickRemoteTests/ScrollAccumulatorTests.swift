import XCTest

final class ScrollAccumulatorTests: XCTestCase {
    func testDirectionsMatchLocalScrolling() {
        var scroll = ScrollAccumulator()
        // Content toward its top (positive deltaY) is a positive RDP wheel value; content
        // moving right (positive deltaX) means scrolling left, a negative HWHEEL value.
        let result = scroll.add(deltaX: 1, deltaY: 1, precise: false, gestureBegan: false)
        XCTAssertEqual(result.vertical, 120)
        XCTAssertEqual(result.horizontal, -120)
    }

    func testTrackpadPointsAccumulateIntoWholeNotches() {
        var scroll = ScrollAccumulator()
        let steps = [12.0, 12.0, 12.0, 12.0, 12.0].map {
            scroll.add(deltaX: 0, deltaY: -$0, precise: true, gestureBegan: false).vertical
        }
        // 30 points per notch: the remainder carries over instead of being dropped.
        XCTAssertEqual(steps, [0, 0, -120, 0, -120])
    }

    func testNewGestureDropsTheLeftover() {
        var scroll = ScrollAccumulator()
        _ = scroll.add(deltaX: 0, deltaY: 25, precise: true, gestureBegan: false)
        let afterReset = scroll.add(deltaX: 0, deltaY: 25, precise: true, gestureBegan: true)
        XCTAssertEqual(afterReset.vertical, 0)
    }
}
