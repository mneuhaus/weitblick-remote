import Foundation

/// Fetches remote clipboard data one request at a time (answers carry no id, so they pair up in
/// order) and caches it until the remote clipboard changes. Thread safe. `fetch` blocks for at most
/// its timeout and never needs the main thread, so the main thread may call it.
final class RemoteDataFetcher: @unchecked Sendable {
    private enum Outcome {
        case data(Data)
        case failed
    }

    /// An unanswered request blocks the next ones (its late answer must not be taken for theirs)
    /// until this long after it was sent.
    static let abandonAfter: TimeInterval = 15

    private let condition = NSCondition()
    private let maxSize: Int
    private let send: @Sendable (UInt32) -> Bool
    // Guarded by `condition`.
    private var currentGeneration = 0
    private var outcomes: [UInt32: Outcome] = [:]
    private var inFlight: (formatID: UInt32, generation: Int, sentAt: Date)?

    /// `send` asks the server for a format; data larger than `maxSize` counts as a failure.
    init(maxSize: Int, send: @escaping @Sendable (UInt32) -> Bool) {
        self.maxSize = maxSize
        self.send = send
    }

    /// Identifies the current remote clipboard for `discard(generation:)`.
    var generation: Int {
        condition.lock()
        defer { condition.unlock() }
        return currentGeneration
    }

    /// The remote clipboard changed: cached and pending data belong to the old one.
    func reset() {
        condition.lock()
        currentGeneration += 1
        outcomes = [:]
        condition.broadcast()
        condition.unlock()
    }

    /// Frees the cache if it still belongs to `generation` (nobody needs that clipboard any more).
    func discard(generation: Int) {
        condition.lock()
        if generation == currentGeneration { outcomes = [:] }
        condition.unlock()
    }

    /// Already fetched data, without asking the server.
    func cachedData(formatID: UInt32) -> Data? {
        condition.lock()
        defer { condition.unlock() }
        if case .data(let data) = outcomes[formatID] { return data }
        return nil
    }

    /// Data of the current remote clipboard in `formatID`, nil on failure, timeout or a clipboard
    /// change while waiting.
    func fetch(formatID: UInt32, timeout: TimeInterval) -> Data? {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        let wanted = currentGeneration
        while currentGeneration == wanted {
            switch outcomes[formatID] {
            case .data(let data): return data
            case .failed: return nil
            case nil: break
            }
            if let flight = inFlight, Date().timeIntervalSince(flight.sentAt) > Self.abandonAfter {
                inFlight = nil
            }
            if inFlight == nil {
                let sentAt = Date()
                inFlight = (formatID, currentGeneration, sentAt)
                condition.unlock()
                let sent = send(formatID)
                condition.lock()
                if !sent {
                    if inFlight?.sentAt == sentAt { inFlight = nil }
                    condition.broadcast()
                    return nil
                }
                continue
            }
            if !condition.wait(until: deadline) { return nil }
        }
        return nil
    }

    /// The server's answer to the request in flight (channel thread).
    func deliver(_ data: Data?) {
        condition.lock()
        if let flight = inFlight {
            inFlight = nil
            if flight.generation == currentGeneration {
                if let data, data.count <= maxSize {
                    outcomes[flight.formatID] = .data(data)
                } else {
                    outcomes[flight.formatID] = .failed
                }
            }
        }
        condition.broadcast()
        condition.unlock()
    }
}
