/// Turns macOS key events into RDP keyboard input. One engine per session; call it on one thread.
///
/// The app feeds every key event of the session view (`handle`), calls `prepareForPointerEvent()`
/// before mouse button presses and wheel events, `focusLost()` when the session stops receiving keys
/// and `focusGained(modifiers:)` when it starts again (also right after connecting).
public struct KeyboardEngine: Sendable {
    public private(set) var config: KeyboardConfig
    /// The Mac layout used for ⌥ characters, dead keys, Unicode input and layout-aware rules.
    public var layout: any KeyboardLayoutProvider {
        didSet { deadKeyState = 0 }
    }

    // Mac side
    var physical: ModifierFlags = []
    var command: ModifierSession?
    var option: ModifierSession?
    var hold: ModifierHold?
    var heldKeys: [UInt16: HeldKey] = [:]
    var deadKeyState: UInt32 = 0

    // Remote side
    var remote = RemoteKeyboard()
    var remoteCapsLock: Bool?
    var remoteScrollLock = false
    var output: [RDPKeyAction] = []

    public init(config: KeyboardConfig = KeyboardConfig(), layout: any KeyboardLayoutProvider) {
        self.config = config
        self.layout = layout
    }

    public mutating func handle(_ event: KeyEvent) -> KeyboardOutput {
        syncPhysicalModifiers(with: event)
        var passToApp = false
        if !Self.isModifierKey(event.keyCode) {
            switch event.kind {
            case .down:
                if isReserved(event) {
                    reservedKeyDown()
                    passToApp = true
                } else {
                    keyDown(event)
                }
            case .up:
                passToApp = !keyUp(event) && isReserved(event)
            case .flagsChanged:
                break
            }
        }
        return KeyboardOutput(actions: takeOutput(), passToApp: passToApp)
    }

    /// Whether the event belongs to an app shortcut (`config.reservedShortcuts`). `handle` already
    /// reports this as `passToApp`; this is for deciding early, e.g. in an event tap.
    public func isReserved(_ event: KeyEvent) -> Bool {
        guard event.kind != .flagsChanged, !Self.isModifierKey(event.keyCode) else { return false }
        let modifiers = MacModifiers(event.modifiers)
        return config.reservedShortcuts.contains {
            $0.matches(keyCode: event.keyCode, modifiers: modifiers, layout: layout)
        }
    }

    /// Call before forwarding a mouse button press or wheel event: a held ⌘ becomes Ctrl
    /// (⌘-click = Ctrl-click) and ⌥ becomes Alt where the ⌥ strategy allows it. Cancels ⌘/⌥ taps.
    public mutating func prepareForPointerEvent() -> [RDPKeyAction] {
        interruptModifierTaps()
        var chordModifiers: WindowsModifiers = []
        if config.mode == .macShortcuts {
            if command != nil { chordModifiers.insert(.control) }
            if option != nil, optionMeansAlt { chordModifiers.insert(.alt) }
        }
        remote.setModifiers(idleModifiers().union(sides(for: chordModifiers)), into: &output)
        return takeOutput()
    }

    /// Releases every key the remote side holds and forgets the local state.
    public mutating func focusLost() -> [RDPKeyAction] {
        remote.releaseAll(into: &output)
        forgetLocalState()
        return takeOutput()
    }

    /// Synchronizes the toggle keys (NumLock always on) and adopts the currently held modifiers
    /// without sending them; a ⌘ or ⌥ still held from another app never becomes a tap.
    public mutating func focusGained(modifiers: ModifierFlags) -> [RDPKeyAction] {
        remote.releaseAll(into: &output)
        forgetLocalState()
        physical = modifiers.intersection(.modifierKeys)
        if !physical.isDisjoint(with: .command) {
            command = ModifierSession(startedBy: .leftCommand, start: 0, interrupted: true)
        }
        if !physical.isDisjoint(with: .option) {
            option = ModifierSession(startedBy: .leftOption, start: 0, interrupted: true)
        }
        let capsLock = modifiers.contains(.capsLock)
        remoteCapsLock = capsLock
        output.append(.sync(capsLock: capsLock, numLock: true, scrollLock: remoteScrollLock))
        return takeOutput()
    }

    /// Forgets everything without sending anything (new or reconnected session).
    public mutating func reset() {
        forgetLocalState()
        remote.forget()
        remoteCapsLock = nil
        remoteScrollLock = false
        output = []
    }

    /// Switches the configuration; releases all remote keys first.
    public mutating func apply(_ config: KeyboardConfig) -> [RDPKeyAction] {
        let released = focusLost()
        self.config = config
        return released
    }

    // MARK: - Internals shared by the extensions

    static func isModifierKey(_ keyCode: UInt16) -> Bool {
        PhysicalModifier(keyCode: keyCode) != nil || keyCode == MacKeyCode.capsLock || keyCode == MacKeyCode.function
    }

    mutating func takeOutput() -> [RDPKeyAction] {
        defer { output = [] }
        return output
    }

    private mutating func forgetLocalState() {
        physical = []
        command = nil
        option = nil
        hold = nil
        heldKeys = [:]
        deadKeyState = 0
    }
}

/// Result of `KeyboardEngine.handle`.
public struct KeyboardOutput: Equatable, Sendable {
    public var actions: [RDPKeyAction]
    /// The event is a reserved app shortcut: hand it to AppKit (menus) instead of the session.
    public var passToApp: Bool

    public init(actions: [RDPKeyAction], passToApp: Bool = false) {
        self.actions = actions
        self.passToApp = passToApp
    }
}

/// A held ⌘ or ⌥ that has not been resolved yet.
struct ModifierSession {
    let startedBy: PhysicalModifier
    let start: Double
    /// Another key, modifier or pointer event was involved: releasing it is no tap.
    var interrupted: Bool
}

/// Output modifiers kept down until the owning ⌘/⌥ is released (⌘⇥ app switcher).
struct ModifierHold {
    let owner: MacModifiers
    let modifiers: WindowsModifiers
}

/// What a held Mac key has to release on key up.
enum HeldKey {
    case scancode(Scancode)
    /// Already complete (taps, text, Pause) or swallowed.
    case consumed
    /// Started a dead key; its repeats are ignored.
    case composing
}
