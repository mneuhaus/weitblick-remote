import Foundation
import Observation

/// What a session tab shows about its connection.
enum SessionStatus: Equatable, Sendable {
    case connecting
    case connected
    /// The network dropped; attempt `attempt` to get the same Windows session back runs.
    case reconnecting(attempt: Int)
    case disconnected

    var label: String {
        switch self {
        case .connecting: "Verbindet…"
        case .connected: "Verbunden"
        case .reconnecting(let attempt): "Wiederverbinden (Versuch \(attempt))…"
        case .disconnected: "Getrennt"
        }
    }
}

/// Status of every open session by connection, for the overview list.
@MainActor @Observable
final class SessionActivity {
    private(set) var statuses: [UUID: SessionStatus] = [:]

    func set(_ status: SessionStatus?, for connectionID: UUID) {
        statuses[connectionID] = status
    }
}
