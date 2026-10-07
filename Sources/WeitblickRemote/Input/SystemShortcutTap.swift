import AppKit
import ApplicationServices

/// When macOS's own shortcuts (⌘⇥, ⌘Space, ⌃←/→, ⌘`, Mission Control) go to the session instead.
enum SystemShortcutCapture: String, CaseIterable {
    case fullScreen, always, never

    static let defaultsKey = "systemShortcutCapture"

    static var setting: SystemShortcutCapture {
        get { UserDefaults.standard.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? .fullScreen }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    /// Capture only while a connected session window is key in the active app; anything else
    /// would take the keyboard away from the rest of the Mac.
    func applies(sessionIsKey: Bool, appIsActive: Bool, isFullScreen: Bool) -> Bool {
        guard sessionIsKey, appIsActive else { return false }
        switch self {
        case .fullScreen: return isFullScreen
        case .always: return true
        case .never: return false
        }
    }
}

/// A keyboard event tap at HID level (before macOS handles its own shortcuts). It exists only while
/// capturing: `start` creates it, `stop` removes it. It runs on the main run loop, so a hung app
/// makes macOS time the tap out instead of swallowing keys system wide.
@MainActor
final class SystemShortcutTap {
    /// Returns true if the event was consumed (it then never reaches macOS or the app).
    private let consume: (CGEvent) -> Bool
    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { port != nil }

    static var isPermitted: Bool { AXIsProcessTrusted() }

    init(consume: @escaping (CGEvent) -> Bool) {
        self.consume = consume
    }

    /// Needs the Accessibility permission; returns false without it (no prompt).
    @discardableResult
    func start() -> Bool {
        guard port == nil else { return true }
        guard Self.isPermitted else { return false }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(mask), callback: tapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        self.source = source
        return true
    }

    func stop() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(port)
        self.port = nil
        source = nil
    }

    /// Whether the event is swallowed (consumed for the session).
    fileprivate func swallows(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return false
        case .keyDown, .keyUp, .flagsChanged:
            return isRunning && consume(event)
        default:
            return false
        }
    }
}

private func tapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?)
    -> Unmanaged<CGEvent>? {
    guard let userInfo, Thread.isMainThread else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<SystemShortcutTap>.fromOpaque(userInfo).takeUnretainedValue()
    // The callback runs on the main run loop; the event never leaves this thread.
    nonisolated(unsafe) let mainThreadEvent = event
    let swallowed = MainActor.assumeIsolated { tap.swallows(type, mainThreadEvent) }
    return swallowed ? nil : Unmanaged.passUnretained(event)
}
