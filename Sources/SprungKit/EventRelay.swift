import Foundation
import SprungBridge

/// Receives the bridge's C callbacks on FreeRDP threads and forwards them, in order, to the
/// session on the main actor.
final class EventRelay: Sendable {
    @MainActor weak var session: RDPSession?
    private let certificatePolicy: @Sendable (ServerCertificate) -> Bool

    init(certificatePolicy: @escaping @Sendable (ServerCertificate) -> Bool) {
        self.certificatePolicy = certificatePolicy
    }

    func post(_ event: RDPSessionEvent) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.session?.handle(event) }
        }
    }

    func verify(_ certificate: ServerCertificate) -> Bool {
        certificatePolicy(certificate)
    }

    /// C callback table pointing back at this relay. The relay must outlive the bridge session.
    func makeCallbacks() -> SprungCallbacks {
        var callbacks = SprungCallbacks()
        callbacks.userData = Unmanaged.passUnretained(self).toOpaque()
        callbacks.connected = { userData in
            EventRelay.from(userData).post(.connected)
        }
        callbacks.disconnected = { userData, code, message in
            let text = message.map { String(cString: $0) } ?? ""
            EventRelay.from(userData).post(.disconnected(code: code, message: text))
        }
        callbacks.frameReady = { userData in
            EventRelay.from(userData).post(.frameReady)
        }
        callbacks.desktopResized = { userData, width, height in
            EventRelay.from(userData).post(.desktopResized(PixelSize(width: Int(width), height: Int(height))))
        }
        callbacks.pointerNew = { userData, id, bgra, width, height, hotspotX, hotspotY in
            guard let bgra else { return }
            let image = RemotePointerImage(
                id: id, width: Int(width), height: Int(height),
                hotspotX: Int(hotspotX), hotspotY: Int(hotspotY),
                bgra: Data(bytes: bgra, count: Int(width) * Int(height) * 4))
            EventRelay.from(userData).post(.pointer(.new(image)))
        }
        callbacks.pointerFree = { userData, id in
            EventRelay.from(userData).post(.pointer(.free(id: id)))
        }
        callbacks.pointerSet = { userData, id in
            EventRelay.from(userData).post(.pointer(.set(id: id)))
        }
        callbacks.pointerSetNull = { userData in
            EventRelay.from(userData).post(.pointer(.hidden))
        }
        callbacks.pointerSetDefault = { userData in
            EventRelay.from(userData).post(.pointer(.systemDefault))
        }
        callbacks.pointerPosition = { userData, x, y in
            EventRelay.from(userData).post(.pointer(.moved(x: Int(x), y: Int(y))))
        }
        callbacks.verifyCertificate = { userData, info in
            guard let info = info?.pointee else { return false }
            func string(_ pointer: UnsafePointer<CChar>?) -> String { pointer.map { String(cString: $0) } ?? "" }
            let certificate = ServerCertificate(
                host: string(info.host), port: info.port, commonName: string(info.commonName),
                subject: string(info.subject), issuer: string(info.issuer),
                fingerprint: string(info.fingerprint), changed: info.changed)
            return EventRelay.from(userData).verify(certificate)
        }
        return callbacks
    }

    private static func from(_ userData: UnsafeMutableRawPointer?) -> EventRelay {
        Unmanaged<EventRelay>.fromOpaque(userData!).takeUnretainedValue()
    }
}
