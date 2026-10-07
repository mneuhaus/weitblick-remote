import Foundation
@testable import SprungKit
import XCTest

final class CertificateGateTests: XCTestCase {
    private func certificate(_ fingerprint: String) -> ServerCertificate {
        ServerCertificate(host: "10.211.55.9", port: 3389, commonName: "PC", subject: "CN = PC", issuer: "CN = PC",
                          fingerprint: fingerprint, hostnameMismatch: true, changed: false)
    }

    func testTrustedFingerprintsPassWithoutAsking() {
        let gate = CertificateGate(trustedFingerprints: ["ab:cd:ef"], timeout: 1)
        XCTAssertTrue(gate.decide(certificate("AB:CD:EF")) { _, _ in XCTFail("asked") })
        XCTAssertTrue(gate.trustsOtherCertificates)
    }

    func testAnAcceptedCertificateIsNotAskedAgainInTheSession() {
        let gate = CertificateGate(trustedFingerprints: [], timeout: 1)
        XCTAssertTrue(gate.decide(certificate("11:22")) { _, reply in DispatchQueue.global().async { reply(.acceptOnce) } })
        XCTAssertTrue(gate.decide(certificate("11:22")) { _, _ in XCTFail("asked again") })
    }

    func testRejectAndTimeoutRefuse() {
        let gate = CertificateGate(trustedFingerprints: [], timeout: 0.2)
        XCTAssertFalse(gate.decide(certificate("33")) { _, reply in reply(.reject) })
        let started = Date()
        XCTAssertFalse(gate.decide(certificate("44")) { _, _ in })
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), 0.2)
    }

    func testCloseAnswersAnOpenQuestionAndAllLaterOnes() {
        let gate = CertificateGate(trustedFingerprints: [], timeout: 30)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { gate.close() }
        let started = Date()
        XCTAssertFalse(gate.decide(certificate("55")) { _, _ in })
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        XCTAssertFalse(gate.decide(certificate("66")) { _, reply in reply(.acceptOnce) })
    }
}
