import AppKit
@testable import SprungKit
import XCTest

final class RemoteDataFetcherTests: XCTestCase {
    /// Records requests; the test answers them like the channel thread would.
    final class FakeServer: @unchecked Sendable {
        private let lock = NSLock()
        private var sent: [UInt32] = []
        var requests: [UInt32] { lock.withLock { sent } }
        func send(_ id: UInt32) -> Bool {
            lock.withLock { sent.append(id) }
            return true
        }
    }

    func testFetchesOnceAndServesTheCache() {
        let server = FakeServer()
        let fetcher = RemoteDataFetcher(maxSize: 100) { server.send($0) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { fetcher.deliver(Data("hi".utf8)) }
        XCTAssertEqual(fetcher.fetch(formatID: 13, timeout: 2), Data("hi".utf8))
        XCTAssertEqual(fetcher.fetch(formatID: 13, timeout: 2), Data("hi".utf8))
        XCTAssertEqual(server.requests, [13])
    }

    func testOnlyOneRequestIsInFlight() {
        let server = FakeServer()
        let fetcher = RemoteDataFetcher(maxSize: 100) { server.send($0) }
        let second = expectation(description: "second fetch")
        DispatchQueue.global().async { _ = fetcher.fetch(formatID: 1, timeout: 2) }
        Thread.sleep(forTimeInterval: 0.05)
        DispatchQueue.global().async {
            XCTAssertEqual(fetcher.fetch(formatID: 2, timeout: 2), Data([2]))
            second.fulfill()
        }
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertEqual(server.requests, [1], "the second request waits for the first answer")
        fetcher.deliver(Data([1]))
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertEqual(server.requests, [1, 2])
        fetcher.deliver(Data([2]))
        wait(for: [second], timeout: 2)
    }

    func testALateAnswerIsNotTakenForTheNextRequest() {
        let server = FakeServer()
        let fetcher = RemoteDataFetcher(maxSize: 100) { server.send($0) }
        XCTAssertNil(fetcher.fetch(formatID: 1, timeout: 0.1)) // times out, request stays in flight
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            fetcher.deliver(Data([1])) // late answer to request 1
            Thread.sleep(forTimeInterval: 0.05)
            fetcher.deliver(Data([2]))
        }
        XCTAssertEqual(fetcher.fetch(formatID: 2, timeout: 2), Data([2]))
        XCTAssertEqual(server.requests, [1, 2])
    }

    func testAnswersForAnOldClipboardAndOversizedDataAreDropped() {
        let server = FakeServer()
        let fetcher = RemoteDataFetcher(maxSize: 3) { server.send($0) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            fetcher.reset() // the server's clipboard changed while we waited
            fetcher.deliver(Data([1]))
        }
        XCTAssertNil(fetcher.fetch(formatID: 1, timeout: 2))
        XCTAssertNil(fetcher.cachedData(formatID: 1))
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { fetcher.deliver(Data([1, 2, 3, 4])) }
        XCTAssertNil(fetcher.fetch(formatID: 1, timeout: 2))
    }
}

final class ClipboardOfferTests: XCTestCase {
    @MainActor
    func testTextWinsOverImagesAndPNGOverDIB() {
        let flavors = ClipboardFlavors.all
        let office = [RemoteClipboardFormat(id: 13), RemoteClipboardFormat(id: 8),
                      RemoteClipboardFormat(id: 0xC0A1, name: "html format")]
        let officeOffers = ClipboardSync.offers(for: office, flavors: flavors)
        XCTAssertEqual(Set(officeOffers.keys), [.string, .html])
        XCTAssertEqual(officeOffers[.html]?.formatID, 0xC0A1)

        let picture = [RemoteClipboardFormat(id: 8), RemoteClipboardFormat(id: 17), RemoteClipboardFormat(id: 0xC123, name: "PNG")]
        let pictureOffers = ClipboardSync.offers(for: picture, flavors: flavors)
        XCTAssertEqual(Set(pictureOffers.keys), [.png, .tiff])
        XCTAssertEqual(pictureOffers[.png]?.format, .png)
        XCTAssertEqual(pictureOffers[.png]?.formatID, 0xC123)
    }

    func testFinderIconsAreNotOfferedAsImages() {
        XCTAssertTrue(ImageFlavor().offers([.png]))
        XCTAssertFalse(ImageFlavor().offers([.fileURL, .tiff]))
    }
}

final class SystemShortcutCaptureTests: XCTestCase {
    func testCapturesOnlyForTheKeySessionInTheActiveApp() {
        for setting in SystemShortcutCapture.allCases {
            XCTAssertFalse(setting.applies(sessionIsKey: false, appIsActive: true, isFullScreen: true), "\(setting)")
            XCTAssertFalse(setting.applies(sessionIsKey: true, appIsActive: false, isFullScreen: true), "\(setting)")
        }
        XCTAssertTrue(SystemShortcutCapture.fullScreen.applies(sessionIsKey: true, appIsActive: true, isFullScreen: true))
        XCTAssertFalse(SystemShortcutCapture.fullScreen.applies(sessionIsKey: true, appIsActive: true, isFullScreen: false))
        XCTAssertTrue(SystemShortcutCapture.always.applies(sessionIsKey: true, appIsActive: true, isFullScreen: false))
        XCTAssertFalse(SystemShortcutCapture.never.applies(sessionIsKey: true, appIsActive: true, isFullScreen: true))
    }
}
