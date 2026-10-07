import SprungKit
import SwiftUI

/// What the certificate sheet shows (a copy of `ServerCertificate`).
struct CertificateDetails: Equatable {
    var host: String
    var port: UInt16
    var commonName: String
    var subject: String
    var issuer: String
    var fingerprint: String
    var changed: Bool
    var hostnameMismatch: Bool

    init(_ certificate: ServerCertificate) {
        self.init(host: certificate.host, port: certificate.port, commonName: certificate.commonName,
                  subject: certificate.subject, issuer: certificate.issuer, fingerprint: certificate.fingerprint,
                  changed: certificate.changed, hostnameMismatch: certificate.hostnameMismatch)
    }

    init(host: String, port: UInt16, commonName: String, subject: String, issuer: String, fingerprint: String,
         changed: Bool, hostnameMismatch: Bool) {
        self.host = host
        self.port = port
        self.commonName = commonName
        self.subject = subject
        self.issuer = issuer
        self.fingerprint = fingerprint
        self.changed = changed
        self.hostnameMismatch = hostnameMismatch
    }
}

/// Asks whether to trust a server certificate that has no valid chain (trust on first use), or
/// warns that a trusted server now shows a different one.
struct CertificateView: View {
    let certificate: CertificateDetails
    let connectionName: String
    let onDecision: (CertificateDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: certificate.changed ? "exclamationmark.shield.fill" : "lock.shield")
                    .font(.system(size: 32))
                    .foregroundStyle(certificate.changed ? Color.red : Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(certificate.changed ? "Das Zertifikat von „\(connectionName)“ hat sich geändert"
                                             : "Unbekanntes Zertifikat von „\(connectionName)“")
                        .font(.headline)
                    Text(explanation).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
                row("Host", "\(certificate.host):\(certificate.port)")
                row("Ausgestellt für", certificate.commonName.isEmpty ? certificate.subject : certificate.commonName)
                row("Aussteller", certificate.issuer)
                row("SHA-256", Self.grouped(certificate.fingerprint), monospaced: true)
            }
            .font(.callout)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            if certificate.hostnameMismatch {
                Label("Das Zertifikat nennt einen anderen Rechnernamen als „\(certificate.host)“.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
            }
            HStack {
                Button("Abbrechen") { onDecision(.reject) }
                    .keyboardShortcut(certificate.changed ? .defaultAction : .cancelAction)
                Spacer()
                Button("Einmal verbinden") { onDecision(.acceptOnce) }
                Button(certificate.changed ? "Neuem Zertifikat vertrauen" : "Immer vertrauen") {
                    onDecision(.acceptPermanently)
                }
                .keyboardShortcut(certificate.changed ? nil : .defaultAction)
            }
        }
        .padding(20)
        .frame(width: 500)
    }

    private var explanation: String {
        certificate.changed
            ? "Für diese Verbindung ist ein anderes Zertifikat gespeichert. Das passiert nach einer Neuinstallation oder einem neuen Zertifikat, kann aber auch ein Angriff sein. Nur fortfahren, wenn der Grund bekannt ist."
            : "Der Rechner weist sich mit einem selbst ausgestellten Zertifikat aus, bei Remotedesktop üblich. Wer sichergehen will, vergleicht den Fingerabdruck mit dem am Rechner."
    }

    /// Colon-separated bytes in lines of eight, so the fingerprint is easy to compare.
    private static func grouped(_ fingerprint: String) -> String {
        let bytes = fingerprint.split(separator: ":")
        return stride(from: 0, to: bytes.count, by: 8)
            .map { bytes[$0..<min($0 + 8, bytes.count)].joined(separator: ":") }
            .joined(separator: "\n")
    }

    private func row(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value.isEmpty ? "–" : value)
                .font(monospaced ? .callout.monospaced() : .callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
