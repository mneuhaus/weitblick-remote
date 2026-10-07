import KeyboardEngine
import SprungKit

extension RemoteKeyboard {
    /// Sends KeyboardEngine output, in order.
    func send(_ actions: [RDPKeyAction]) {
        for action in actions {
            switch action {
            case .scancode(let code, let extended, let down):
                sendScancode(UInt16(code), extended: extended, down: down)
            case .unicode(let unit, let down):
                sendUnicode(unit, down: down)
            case .sync(let capsLock, let numLock, let scrollLock):
                sendSync(capsLock: capsLock, numLock: numLock, scrollLock: scrollLock)
            case .pause:
                sendPause()
            }
        }
    }
}
