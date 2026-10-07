/// What the remote side currently believes is held down, so every make gets its break.
struct RemoteKeyboard {
    /// Held scancodes in press order.
    private(set) var held: [Scancode] = []

    var modifiers: Set<RemoteModifier> { Set(held.compactMap(RemoteModifier.init(scancode:))) }

    /// Sends a make code. Pressing a held key again is a typematic repeat.
    mutating func press(_ scancode: Scancode, into out: inout [RDPKeyAction]) {
        if !held.contains(scancode) { held.append(scancode) }
        out.append(.key(scancode, down: true))
    }

    /// Sends a break code if the key is held; never a break without a make.
    mutating func release(_ scancode: Scancode, into out: inout [RDPKeyAction]) {
        guard let index = held.firstIndex(of: scancode) else { return }
        held.remove(at: index)
        out.append(.key(scancode, down: false))
    }

    mutating func tap(_ scancode: Scancode, into out: inout [RDPKeyAction]) {
        press(scancode, into: &out)
        release(scancode, into: &out)
    }

    /// Moves the remote modifier keys to exactly `target`: releases first, then presses.
    mutating func setModifiers(_ target: Set<RemoteModifier>, into out: inout [RDPKeyAction]) {
        let current = modifiers
        for modifier in RemoteModifier.allCases.reversed() where current.contains(modifier) && !target.contains(modifier) {
            release(modifier.scancode, into: &out)
        }
        for modifier in RemoteModifier.allCases where target.contains(modifier) && !current.contains(modifier) {
            press(modifier.scancode, into: &out)
        }
    }

    /// Releases everything: ordinary keys first (newest first), then modifiers.
    mutating func releaseAll(into out: inout [RDPKeyAction]) {
        for scancode in held.reversed() where RemoteModifier(scancode: scancode) == nil {
            release(scancode, into: &out)
        }
        for scancode in held.reversed() {
            release(scancode, into: &out)
        }
    }

    mutating func forget() { held = [] }
}
