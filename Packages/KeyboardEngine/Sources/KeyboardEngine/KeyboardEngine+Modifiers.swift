// Modifier handling. In Mac-shortcut mode ⇧ and ⌃ are forwarded as soon as they change while no
// ⌘/⌥ is held; ⌘ and ⌥ send nothing until a key (or pointer event, or a lone tap) decides what they
// mean. Each key then moves the remote modifiers to exactly what it needs, and releasing ⌘/⌥ moves
// them back to the physical ⇧/⌃ state ("idle").

extension KeyboardEngine {
    /// Brings the physical modifier state in line with the event's flags. Works for flagsChanged and
    /// for any other event, so a modifier change the app never delivered is still caught.
    mutating func syncPhysicalModifiers(with event: KeyEvent) {
        let capsLock = event.modifiers.contains(.capsLock)
        if let remoteCapsLock, remoteCapsLock != capsLock {
            remote.tap(PCScancode.capsLock, into: &output)
        }
        remoteCapsLock = capsLock

        let target = event.modifiers.intersection(.modifierKeys)
        guard target != physical else { return }
        let changedKey = event.kind == .flagsChanged ? PhysicalModifier(keyCode: event.keyCode) : nil
        for modifier in PhysicalModifier.allCases where physical.contains(modifier.flag) && !target.contains(modifier.flag) {
            physical.remove(modifier.flag)
            modifierReleased(modifier, at: event.timestamp)
        }
        for modifier in PhysicalModifier.allCases where !physical.contains(modifier.flag) && target.contains(modifier.flag) {
            // A tap candidate is a modifier pressed on its own, seen as its own flagsChanged event.
            let alone = physical.isEmpty && modifier == changedKey
            physical.insert(modifier.flag)
            modifierPressed(modifier, alone: alone, at: event.timestamp)
        }
    }

    private mutating func modifierPressed(_ modifier: PhysicalModifier, alone: Bool, at time: Double) {
        guard config.mode == .macShortcuts else {
            remote.setModifiers(idleModifiers(), into: &output)
            return
        }
        interruptModifierTaps()
        let session = ModifierSession(startedBy: modifier, start: time, interrupted: !alone)
        switch MacModifiers(modifier.flag) {
        case .command:
            if command == nil { command = session }
        case .option:
            if option == nil { option = session }
        default:
            if command == nil, option == nil { remote.setModifiers(idleModifiers(), into: &output) }
        }
    }

    private mutating func modifierReleased(_ modifier: PhysicalModifier, at time: Double) {
        guard config.mode == .macShortcuts else {
            remote.setModifiers(idleModifiers(), into: &output)
            return
        }
        switch MacModifiers(modifier.flag) {
        case .command:
            guard physical.isDisjoint(with: .command), let session = command else { return interruptModifierTaps() }
            command = nil
            endSession(session, owner: .command, at: time, tap: .windows)
        case .option:
            guard physical.isDisjoint(with: .option), let session = option else { return interruptModifierTaps() }
            option = nil
            endSession(session, owner: .option, at: time, tap: optionTapsAlt(session.startedBy) ? .alt : [])
        default:
            interruptModifierTaps()
            if command == nil, option == nil { remote.setModifiers(idleModifiers(), into: &output) }
        }
    }

    private mutating func endSession(_ session: ModifierSession, owner: MacModifiers, at time: Double, tap: WindowsModifiers) {
        if hold?.owner == owner { hold = nil }
        let idle = idleModifiers()
        remote.setModifiers(idle, into: &output)
        let timeout = config.modifierTapTimeout
        let isTap = !session.interrupted && (timeout <= 0 || time - session.start <= timeout)
        if isTap, !tap.isEmpty {
            remote.setModifiers(idle.union(sides(for: tap)), into: &output)
            remote.setModifiers(idle, into: &output)
        }
    }

    /// Something else happened while ⌘/⌥ is held: releasing them is no longer a tap.
    mutating func interruptModifierTaps() {
        command?.interrupted = true
        option?.interrupted = true
    }

    /// Remote modifiers when no key needs anything special.
    func idleModifiers() -> Set<RemoteModifier> {
        var idle = physicallyMirroredModifiers()
        if let hold { idle.formUnion(sides(for: hold.modifiers)) }
        return idle
    }

    /// Modifiers whose physical keys are forwarded one to one: all of them in Windows-direct mode,
    /// only ⇧ and ⌃ in Mac-shortcut mode.
    private func physicallyMirroredModifiers() -> Set<RemoteModifier> {
        let mirrored = config.mode == .windowsDirect ? ModifierFlags.modifierKeys : [.shift, .control]
        return Set(PhysicalModifier.allCases.filter { physical.intersection(mirrored).contains($0.flag) }.map(\.windowsKey))
    }

    /// Concrete remote keys for side-agnostic modifiers: keep a side that is already down, else
    /// mirror the physical side of ⇧/⌃, else the left key (never right Alt, which is AltGr).
    func sides(for modifiers: WindowsModifiers) -> Set<RemoteModifier> {
        let down = remote.modifiers
        let mirrored = physicallyMirroredModifiers()
        var result = Set<RemoteModifier>()
        for kind in [WindowsModifiers.control, .alt, .shift, .windows] where modifiers.contains(kind) {
            let held = down.filter { $0.kind == kind }
            let physicalSides = mirrored.filter { $0.kind == kind }
            if !held.isEmpty {
                result.formUnion(held)
            } else if !physicalSides.isEmpty {
                result.formUnion(physicalSides)
            } else if let left = RemoteModifier.allCases.first(where: { $0.kind == kind && $0.isLeft }) {
                result.insert(left)
            }
        }
        return result
    }

    /// Whether a pending ⌥ acts as Alt for pointer events.
    var optionMeansAlt: Bool {
        switch config.optionStrategy {
        case .smart, .alwaysAlt: true
        case .jumpStyle: physical.contains(.leftOption)
        case .alwaysCharacters: false
        }
    }

    private func optionTapsAlt(_ startedBy: PhysicalModifier) -> Bool {
        switch config.optionStrategy {
        case .smart, .alwaysAlt: true
        case .jumpStyle: startedBy == .leftOption
        case .alwaysCharacters: false
        }
    }
}
