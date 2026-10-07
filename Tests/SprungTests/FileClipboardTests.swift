import Foundation
@testable import SprungKit
import XCTest

final class FileGroupDescriptorTests: XCTestCase {
    func testRoundTripKeepsPathsKindsSizesAndTimes() throws {
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            ClipboardFileEntry(path: "Ordner-Ä", isDirectory: true, size: 0, modified: modified),
            ClipboardFileEntry(path: "Ordner-Ä\\Grüße.txt", isDirectory: false, size: 12, modified: modified),
            ClipboardFileEntry(path: "groß.bin", isDirectory: false, size: 5_000_000_000, modified: nil),
        ]
        let data = FileGroupDescriptor.encode(entries)
        XCTAssertEqual(data.count, 4 + 3 * 592)
        XCTAssertEqual(FileGroupDescriptor.decode(data), entries)
    }

    func testRecordLayoutMatchesFILEDESCRIPTORW() {
        let data = [UInt8](FileGroupDescriptor.encode([ClipboardFileEntry(path: "a", isDirectory: false, size: 0x1_0000_0002, modified: nil)]))
        XCTAssertEqual(Array(data[0..<4]), [1, 0, 0, 0]) // cItems
        XCTAssertEqual(data[4 + 36], 0x80) // FILE_ATTRIBUTE_NORMAL
        XCTAssertEqual(Array(data[(4 + 64)..<(4 + 72)]), [1, 0, 0, 0, 2, 0, 0, 0]) // nFileSizeHigh, nFileSizeLow
        XCTAssertEqual(Array(data[(4 + 72)..<(4 + 76)]), [0x61, 0, 0, 0]) // "a", NUL
    }

    func testRejectsPathsOutsideTheCopiedItems() {
        for path in ["..\\evil.txt", "a\\..\\..\\b", "C:\\Windows\\x", "\\\\?\\c:\\x", ""] {
            let data = FileGroupDescriptor.encode([ClipboardFileEntry(path: path, isDirectory: false, size: 1, modified: nil)])
            XCTAssertNil(FileGroupDescriptor.decode(data), path)
        }
        XCTAssertEqual(FileGroupDescriptor.safeRelativePath("\\a/b\\.\\c\\"), "a\\b\\c")
    }

    func testRejectsTruncatedData() {
        let data = FileGroupDescriptor.encode([ClipboardFileEntry(path: "a", isDirectory: false, size: 1, modified: nil)])
        XCTAssertNil(FileGroupDescriptor.decode(data.prefix(100)))
        XCTAssertNil(FileGroupDescriptor.decode(Data([1, 0])))
    }
}

final class LocalFileListTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("sprung-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Ordner-Ä/tief"), withIntermediateDirectories: true)
        try Data("hallo".utf8).write(to: root.appendingPathComponent("Ordner-Ä/tief/Grüße.txt"))
        try Data("x".utf8).write(to: root.appendingPathComponent("Ordner-Ä/.DS_Store"))
        try Data((0..<300).map { UInt8($0 % 256) }).write(to: root.appendingPathComponent("daten.bin"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testListsFoldersRecursivelyBeforeTheirContents() throws {
        let list = try XCTUnwrap(LocalFileList(fileURLs: [root.appendingPathComponent("Ordner-Ä"), root.appendingPathComponent("daten.bin")],
                                               maxTotalSize: 1000))
        XCTAssertEqual(list.entries.map(\.path), ["Ordner-Ä", "Ordner-Ä\\tief", "Ordner-Ä\\tief\\Grüße.txt", "daten.bin"])
        XCTAssertEqual(list.entries.map(\.isDirectory), [true, true, false, false])
        XCTAssertEqual(list.totalSize, 305)
    }

    func testAnswersSizesAndRanges() throws {
        let list = try XCTUnwrap(LocalFileList(fileURLs: [root.appendingPathComponent("daten.bin")], maxTotalSize: 1000))
        let size = list.answer(RemoteFileRequest(streamID: 1, fileIndex: 0, sizeOnly: true, offset: 0, length: 8))
        XCTAssertEqual(size, Data([44, 1, 0, 0, 0, 0, 0, 0]))
        let range = list.answer(RemoteFileRequest(streamID: 2, fileIndex: 0, sizeOnly: false, offset: 290, length: 100))
        XCTAssertEqual(range, Data((290..<300).map { UInt8($0 % 256) }))
        XCTAssertNil(list.answer(RemoteFileRequest(streamID: 3, fileIndex: 5, sizeOnly: true, offset: 0, length: 8)))
    }

    func testRefusesMoreThanTheLimit() {
        XCTAssertNil(LocalFileList(fileURLs: [root.appendingPathComponent("daten.bin")], maxTotalSize: 299))
    }
}

final class RemoteFileFetcherTests: XCTestCase {
    /// Answers requests like a server would, optionally out of order and with short answers.
    final class FakeServer: @unchecked Sendable {
        let content: Data
        let shortAnswers: Bool
        weak var fetcher: RemoteFileFetcher?
        private let lock = NSLock()
        private var queued: [RemoteFileRequest] = []
        private(set) var requests = 0

        init(content: Data, shortAnswers: Bool = false) {
            self.content = content
            self.shortAnswers = shortAnswers
        }

        func send(_ request: RemoteFileRequest) -> Bool {
            lock.withLock {
                requests += 1
                queued.append(request)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.001) { self.answerNewestFirst() }
            return true
        }

        private func answerNewestFirst() {
            guard let request = lock.withLock({ queued.popLast() }) else { return }
            if request.sizeOnly {
                var size = Data()
                size.appendLittleEndian(UInt64(content.count))
                fetcher?.deliver(streamID: request.streamID, data: size)
                return
            }
            let start = Int(request.offset)
            let length = shortAnswers ? max(1, request.length / 3) : request.length
            fetcher?.deliver(streamID: request.streamID, data: content.subdata(in: start..<min(content.count, start + length)))
        }
    }

    func testDownloadsInOrderDespiteShuffledAndShortAnswers() {
        let content = Data((0..<(3 * RemoteFileFetcher.chunkSize + 123)).map { UInt8(truncatingIfNeeded: $0 &* 7) })
        for short in [false, true] {
            let server = FakeServer(content: content, shortAnswers: short)
            let fetcher = RemoteFileFetcher { server.send($0) }
            server.fetcher = fetcher
            var received = Data()
            XCTAssertTrue(fetcher.download(fileIndex: 0, size: UInt64(content.count), generation: fetcher.generation,
                                           write: { received.append($0) }))
            XCTAssertEqual(received, content, "short answers: \(short)")
            XCTAssertEqual(fetcher.size(of: 0, generation: fetcher.generation), UInt64(content.count))
        }
    }

    func testResetFailsADownloadInProgress() {
        final class Silent: @unchecked Sendable { func send(_ request: RemoteFileRequest) -> Bool { true } }
        let silent = Silent()
        let fetcher = RemoteFileFetcher { silent.send($0) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { fetcher.reset() }
        let started = Date()
        XCTAssertFalse(fetcher.download(fileIndex: 0, size: 10, generation: fetcher.generation, write: { _ in }))
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        XCTAssertFalse(fetcher.download(fileIndex: 0, size: 10, generation: fetcher.generation - 1, write: { _ in }))
    }
}
