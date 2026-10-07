import Foundation
import os

/// A server certificate without a valid chain (self-signed, the usual case for RDP).
public struct ServerCertificate: Sendable {
    public let host: String
    public let port: UInt16
    public let commonName: String
    public let subject: String
    public let issuer: String
    /// SHA-256, colon-separated uppercase hex.
    public let fingerprint: String
    /// The certificate does not name the host we connected to.
    public let hostnameMismatch: Bool
    /// The connection trusts other fingerprints (`SessionConfiguration.trustedCertificateFingerprints`),
    /// so the server's certificate changed since it was trusted.
    public let changed: Bool
}

public enum CertificateDecision: Sendable {
    case acceptOnce
    /// Accept, and the app remembers the fingerprint for this connection (SprungKit stores nothing).
    case acceptPermanently
    case reject

    var accepts: Bool { self != .reject }
}

/// Decides about certificates on the FreeRDP thread: trusted fingerprints and those accepted
/// earlier in this session (reconnects) pass at once, anything else waits for the app's answer on
/// the main actor, bounded by `timeout`. Thread safe.
final class CertificateGate: Sendable {
    private final class Pending: @unchecked Sendable {
        let semaphore = DispatchSemaphore(value: 0)
        var decision = CertificateDecision.reject // written before the signal
    }

    private struct State {
        var acceptedThisSession: Set<String> = []
        var pending: [ObjectIdentifier: Pending] = [:]
        var isClosed = false
    }

    private let trusted: Set<String>
    private let timeout: TimeInterval
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(trustedFingerprints: [String], timeout: TimeInterval) {
        self.trusted = Set(trustedFingerprints.map(Self.normalize))
        self.timeout = timeout
    }

    static func normalize(_ fingerprint: String) -> String {
        fingerprint.uppercased().filter { $0.isHexDigit }
    }

    func isTrusted(_ fingerprint: String) -> Bool {
        let key = Self.normalize(fingerprint)
        return trusted.contains(key) || state.withLock { $0.acceptedThisSession.contains(key) }
    }

    var trustsOtherCertificates: Bool { !trusted.isEmpty }

    /// Blocks the calling (FreeRDP) thread until `ask` answers, the timeout passes or `close` runs.
    func decide(_ certificate: ServerCertificate,
                ask: @escaping @Sendable (ServerCertificate, @escaping @Sendable (CertificateDecision) -> Void) -> Void) -> Bool {
        if isTrusted(certificate.fingerprint) { return true }
        let pending = Pending()
        let id = ObjectIdentifier(pending)
        guard state.withLock({ state -> Bool in
            guard !state.isClosed else { return false }
            state.pending[id] = pending
            return true
        }) else { return false }

        ask(certificate) { [weak self] decision in self?.resolve(id, with: decision) }
        let answered = pending.semaphore.wait(timeout: .now() + timeout) == .success
        state.withLock { _ = $0.pending.removeValue(forKey: id) }
        guard answered else {
            Logger.session.error("No answer about the certificate of \(certificate.host, privacy: .public) within \(Int(self.timeout)) s, rejecting")
            return false
        }
        if pending.decision.accepts {
            state.withLock { _ = $0.acceptedThisSession.insert(Self.normalize(certificate.fingerprint)) }
        }
        return pending.decision.accepts
    }

    /// Rejects every open question and all later ones; the session is going away.
    func close() {
        let open = state.withLock { state in
            state.isClosed = true
            defer { state.pending = [:] }
            return Array(state.pending.values)
        }
        open.forEach { $0.semaphore.signal() }
    }

    private func resolve(_ id: ObjectIdentifier, with decision: CertificateDecision) {
        guard let pending = state.withLock({ $0.pending.removeValue(forKey: id) }) else { return }
        pending.decision = decision
        pending.semaphore.signal()
    }
}
