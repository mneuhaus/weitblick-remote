import Foundation
import SprungKit

/// Sessions that are meant to fail, each checked for the reason the app gets: certificate
/// rejected / trusted / changed, wrong password, closed port. Only ever the test VM.
@MainActor
func runEndReasonChecks(_ vm: TestVMEnvironment) async throws {
    var configuration = makeConfiguration(vm, size: PixelSize(width: 1024, height: 768))

    let rejected = try await endedSession(configuration, decision: .reject)
    try expect(rejected, .certificateRejected, "rejected certificate")
    guard let certificate = rejected.askedCertificates.first, rejected.askedCertificates.count == 1, !certificate.changed else {
        throw SmokeFailure("rejected certificate: expected one question about an unchanged certificate, got \(rejected.askedCertificates)")
    }
    log("certificate \(certificate.fingerprint) rejected -> \(rejected.session.disconnectReason!)")

    configuration.trustedCertificateFingerprints = [certificate.fingerprint.lowercased()]
    let trusted = try await connect(configuration)
    guard trusted.askedCertificates.isEmpty else { throw SmokeFailure("trusted certificate was asked about") }
    try await disconnect(trusted)
    log("trusted fingerprint: connected without a question")

    configuration.trustedCertificateFingerprints = [String(repeating: "AB:", count: 31) + "AB"]
    let changed = try await endedSession(configuration, decision: .reject)
    guard changed.askedCertificates.first?.changed == true else {
        throw SmokeFailure("certificate not reported as changed against another trusted fingerprint")
    }
    try expect(changed, .certificateRejected, "changed certificate")
    log("other trusted fingerprint: asked with changed = true")

    configuration.trustedCertificateFingerprints = []
    var wrongPassword = configuration
    wrongPassword.password += "-falsch"
    let logon = try await endedSession(wrongPassword, decision: .acceptOnce)
    try expect(logon, .logonFailed, "wrong password")
    guard logon.reconnectAttempts.isEmpty, logon.session.disconnectReason?.needsCredentials == true else {
        throw SmokeFailure("wrong password: reconnected or not marked as needing credentials")
    }
    log("wrong password -> \(logon.ending!.message)")

    var closedPort = configuration
    closedPort.port = 3390
    let unreachable = try await endedSession(closedPort, decision: .acceptOnce)
    try expect(unreachable, .hostUnreachable, "closed port")
    log("closed port -> \(unreachable.ending!.message)")

    // The test VM requires NLA (UserAuthentication = 1).
    var withoutNLA = configuration
    withoutNLA.nla = false
    let refused = try await endedSession(withoutNLA, decision: .acceptOnce)
    try expect(refused, .nlaRequired, "NLA off against a server that requires it")
    log("NLA off against an NLA-only server -> \(refused.ending!.message)")
}

@MainActor
private func endedSession(_ configuration: SessionConfiguration, decision: CertificateDecision) async throws -> SmokeProbe {
    guard let probe = SmokeProbe(configuration: configuration) else { throw SmokeFailure("could not create session") }
    probe.certificateDecision = decision
    probe.session.connect()
    try await probe.wait("disconnect", timeout: 45) { probe.ending != nil }
    await probe.session.closeAndWait()
    return probe
}

@MainActor
private func expect(_ probe: SmokeProbe, _ reason: DisconnectReason, _ what: String) throws {
    guard probe.session.disconnectReason == reason, let ending = probe.ending, ending.code != 0 else {
        throw SmokeFailure("\(what): expected \(reason), got \(String(describing: probe.session.disconnectReason)) \(String(describing: probe.ending))")
    }
}
