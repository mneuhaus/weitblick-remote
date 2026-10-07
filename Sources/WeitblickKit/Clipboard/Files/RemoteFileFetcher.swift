import Foundation
import os

/// Fetches file contents from the server's clipboard (FileContents requests). Answers carry the
/// stream id of their request, so several chunks are in flight at once. Thread safe; waiting never
/// needs the main thread, so the main thread may call it.
final class RemoteFileFetcher: @unchecked Sendable {
    struct Progress: Sendable {
        var bytes: UInt64
        var total: UInt64
    }

    /// Bytes per request and requests in flight per file.
    static let chunkSize = 1 << 20
    static let window = 4
    /// A download fails when no answer arrived for this long.
    static let stallTimeout: TimeInterval = 30
    private static let logger = Logger(subsystem: "nrw.neuhaus.weitblick-remote", category: "clipboard")

    private let condition = NSCondition()
    private let send: @Sendable (RemoteFileRequest) -> Bool
    // Guarded by `condition`.
    private var currentGeneration = 0
    private var nextStreamID: UInt32 = 1
    private var answers: [UInt32: Data?] = [:]
    private var waiting: Set<UInt32> = []

    init(send: @escaping @Sendable (RemoteFileRequest) -> Bool) {
        self.send = send
    }

    /// Identifies the current remote file list.
    var generation: Int {
        condition.lock()
        defer { condition.unlock() }
        return currentGeneration
    }

    /// The remote clipboard changed or the channel closed: every request in flight fails.
    func reset() {
        condition.lock()
        currentGeneration += 1
        answers = [:]
        waiting = []
        condition.broadcast()
        condition.unlock()
    }

    /// An answer from the server (channel thread).
    func deliver(streamID: UInt32, data: Data?) {
        condition.lock()
        if waiting.remove(streamID) != nil {
            answers[streamID] = .some(data)
            condition.broadcast()
        }
        condition.unlock()
    }

    /// The size of file `fileIndex`, asked from the server.
    func size(of fileIndex: Int, generation: Int) -> UInt64? {
        guard let id = start(RemoteFileRequest(streamID: 0, fileIndex: fileIndex, sizeOnly: true, offset: 0, length: 8),
                             generation: generation),
              let data = wait(for: [id], generation: generation)?[id] ?? nil, data.count >= 8
        else { return nil }
        return data.prefix(8).enumerated().reduce(0) { $0 | UInt64($1.element) << (8 * UInt64($1.offset)) }
    }

    /// Streams file `fileIndex` (`size` bytes) to `write`, in order. False on failure, a stall,
    /// a clipboard change, or when `write` throws.
    func download(fileIndex: Int, size: UInt64, generation: Int,
                  write: (Data) throws -> Void, progress: (UInt64) -> Void = { _ in }) -> Bool {
        var chunk = Self.chunkSize // shrinks to the server's cap: the largest answer it gave
        var largestAnswer = 0
        var nextOffset: UInt64 = 0
        var gaps: [(offset: UInt64, length: Int)] = [] // left by short answers, requested first
        var inFlight: [UInt32: (offset: UInt64, length: Int)] = [:]
        var received: [UInt64: Data] = [:]
        var written: UInt64 = 0

        while written < size {
            while inFlight.count < Self.window {
                let range: (offset: UInt64, length: Int)
                if !gaps.isEmpty {
                    range = gaps.removeFirst()
                } else if nextOffset < size {
                    range = (nextOffset, Int(min(UInt64(chunk), size - nextOffset)))
                    nextOffset += UInt64(range.length)
                } else {
                    break
                }
                let request = RemoteFileRequest(streamID: 0, fileIndex: fileIndex, sizeOnly: false,
                                                offset: range.offset, length: range.length)
                guard let id = start(request, generation: generation) else { return false }
                inFlight[id] = range
            }
            guard let answers = wait(for: Set(inFlight.keys), generation: generation) else { return false }
            for (id, data) in answers {
                guard let range = inFlight.removeValue(forKey: id), let data, !data.isEmpty else { return false }
                let piece = data.prefix(range.length)
                received[range.offset] = piece
                largestAnswer = max(largestAnswer, piece.count)
                if piece.count < range.length {
                    gaps.append((range.offset + UInt64(piece.count), range.length - piece.count))
                    if largestAnswer < chunk {
                        Self.logger.notice("server answers at most \(largestAnswer) bytes per file request")
                        chunk = largestAnswer
                    }
                }
            }
            while let next = received.removeValue(forKey: written) {
                do { try write(next) } catch { return false }
                written += UInt64(next.count)
                progress(written)
            }
        }
        return true
    }

    /// Registers a request and sends it; its stream id, or nil.
    private func start(_ request: RemoteFileRequest, generation: Int) -> UInt32? {
        condition.lock()
        guard generation == currentGeneration else {
            condition.unlock()
            return nil
        }
        let id = nextStreamID
        nextStreamID = nextStreamID == UInt32.max ? 1 : nextStreamID + 1
        waiting.insert(id)
        condition.unlock()
        var request = request
        request.streamID = id
        guard send(request) else {
            condition.lock()
            waiting.remove(id)
            condition.unlock()
            return nil
        }
        return id
    }

    /// Waits until at least one of `ids` is answered; returns and removes all answered ones.
    /// nil on a stall, a generation change or a reset.
    private func wait(for ids: Set<UInt32>, generation: Int) -> [UInt32: Data?]? {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(Self.stallTimeout)
        while true {
            guard generation == currentGeneration else { return nil }
            let done = ids.filter { answers[$0] != nil }
            if !done.isEmpty {
                var result: [UInt32: Data?] = [:]
                for id in done { result[id] = answers.removeValue(forKey: id)! }
                return result
            }
            if !condition.wait(until: deadline) {
                waiting.subtract(ids)
                return nil
            }
        }
    }
}
