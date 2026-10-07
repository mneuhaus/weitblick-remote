// Non-modifier keys: decide what a key press means, then send it.

/// One output chord with its key resolved for the current layout and keyboard.
struct OutputChord {
    var modifiers: WindowsModifiers
    /// nil: tap the modifiers alone (⌘Space -> Win).
    var target: KeyTarget?
}

/// What a key press turns into.
enum KeyOutput {
    /// Pressed now, released with the Mac key, repeats with it.
    case hold(OutputChord)
    /// Sent completely on press (multi-step rules, modifier taps).
    case taps([OutputChord])
    case text(String)
    /// A dead key started composing; nothing to send yet.
    case composing
    case swallow
}

extension KeyboardEngine {
    mutating func keyDown(_ event: KeyEvent) {
        interruptModifierTaps()
        if event.isRepeat, case .composing? = heldKeys[event.keyCode] { return }
        let keyboardType = config.keyboardTypeOverride ?? event.keyboardType ?? layout.keyboardType
        guard let target = PhysicalKeyMap.target(for: event.keyCode, keyboardType: keyboardType),
              let keyClass = PhysicalKeyMap.keyClass(of: event.keyCode)
        else { return }
        let key = PressedKey(keyCode: event.keyCode, target: target, keyClass: keyClass, keyboardType: keyboardType)
        let result = switch config.mode {
        case .macShortcuts: resolveMacShortcut(key)
        case .windowsDirect: resolveWindowsDirect(key)
        }
        perform(result, for: key, isRepeat: event.isRepeat)
    }

    /// Returns whether the key had been pressed through the engine.
    mutating func keyUp(_ event: KeyEvent) -> Bool {
        interruptModifierTaps()
        guard let held = heldKeys.removeValue(forKey: event.keyCode) else { return false }
        if case .scancode(let scancode) = held { remote.release(scancode, into: &output) }
        // Chord modifiers only outlive their key while a ⌘/⌥ that owns them is held.
        if command == nil, option == nil { remote.setModifiers(idleModifiers(), into: &output) }
        return true
    }

    mutating func reservedKeyDown() {
        interruptModifierTaps()
        remote.setModifiers(idleModifiers(), into: &output)
        // Windows-direct: Win or Alt is already down and the key never reaches Windows, so releasing
        // it later would look like a lone tap (Start menu, menu bar). A Ctrl tap masks that.
        let held = remote.modifiers.map(\.kind)
        if held.contains(.windows) || held.contains(.alt), !held.contains(.control) {
            remote.tap(RemoteModifier.leftControl.scancode, into: &output)
        }
    }

    // MARK: - Resolution

    private mutating func resolveMacShortcut(_ key: PressedKey) -> KeyOutput {
        let modifiers = MacModifiers(physical)
        let shift: WindowsModifiers = modifiers.contains(.shift) ? .shift : []
        if let hold {
            deadKeyState = 0
            return .hold(OutputChord(modifiers: hold.modifiers.union(shift), target: key.target))
        }
        if let rule = config.rules.match(keyCode: key.keyCode, modifiers: modifiers, layout: layout) {
            deadKeyState = 0
            return output(for: rule, shiftHeld: modifiers.contains(.shift), keyboardType: key.keyboardType)
        }
        if modifiers.contains(.command) {
            // Default rule: ⌘ + key -> Ctrl + the same physical key; ⌥ and ⇧ come along.
            deadKeyState = 0
            var windows: WindowsModifiers = [.control]
            if modifiers.contains(.option) { windows.insert(.alt) }
            return .hold(OutputChord(modifiers: windows.union(shift), target: key.target))
        }
        if modifiers.contains(.option) {
            if modifiers.contains(.control) {
                deadKeyState = 0
                return .hold(OutputChord(modifiers: [.control, .alt, shift], target: key.target))
            }
            return resolveOption(key, shift: shift)
        }
        if modifiers.contains(.control) {
            deadKeyState = 0
            return .hold(OutputChord(modifiers: [.control, shift], target: key.target))
        }
        return resolvePlain(key, shift: shift)
    }

    private mutating func resolveWindowsDirect(_ key: PressedKey) -> KeyOutput {
        let modifiers = MacModifiers(physical)
        if modifiers.isDisjoint(with: [.command, .option, .control]) {
            return resolvePlain(key, shift: modifiers.contains(.shift) ? .shift : [])
        }
        deadKeyState = 0
        var windows: WindowsModifiers = []
        if modifiers.contains(.command) { windows.insert(.windows) }
        if modifiers.contains(.option) { windows.insert(.alt) }
        if modifiers.contains(.control) { windows.insert(.control) }
        if modifiers.contains(.shift) { windows.insert(.shift) }
        return .hold(OutputChord(modifiers: windows, target: key.target))
    }

    private mutating func output(for rule: ShortcutRule, shiftHeld: Bool, keyboardType: PhysicalKeyboardType) -> KeyOutput {
        let addShift: WindowsModifiers = rule.keepShift && shiftHeld && !rule.mac.modifiers.contains(.shift) ? .shift : []
        var chords: [OutputChord] = []
        for chord in rule.windows {
            var target: KeyTarget?
            if let key = chord.key {
                guard let resolved = windowsTarget(for: key, keyboardType: keyboardType) else { return .swallow }
                target = resolved
            }
            chords.append(OutputChord(modifiers: chord.modifiers.union(addShift), target: target))
        }
        if rule.holdUntilRelease, let first = rule.windows.first {
            let owner: MacModifiers = rule.mac.modifiers.contains(.command) ? .command : .option
            let ownerHeld = owner == .command ? command != nil : option != nil
            if ownerHeld { hold = ModifierHold(owner: owner, modifiers: first.modifiers) }
        }
        if chords.count == 1, chords[0].target != nil { return .hold(chords[0]) }
        return .taps(chords)
    }

    private func windowsTarget(for key: KeyRef, keyboardType: PhysicalKeyboardType) -> KeyTarget? {
        switch key {
        case .named(let named): named.windowsTarget
        case .character(let character):
            layout.keyCode(typing: character).flatMap { PhysicalKeyMap.target(for: $0, keyboardType: keyboardType) }
        case .any: nil
        }
    }

    /// ⌥ + key without ⌘/⌃ and without a rule.
    private mutating func resolveOption(_ key: PressedKey, shift: WindowsModifiers) -> KeyOutput {
        let alt = KeyOutput.hold(OutputChord(modifiers: [.alt, shift], target: key.target))
        guard key.keyClass == .character else {
            // F-keys, arrows, Tab, Return, keypad (Alt+numpad codes): always Alt.
            deadKeyState = 0
            return alt
        }
        switch config.optionStrategy {
        case .alwaysAlt:
            deadKeyState = 0
            return alt
        case .alwaysCharacters:
            return optionCharacter(key, otherwise: alt, accept: isPrintable)
        case .jumpStyle:
            guard physical.contains(.rightOption), !physical.contains(.leftOption) else {
                deadKeyState = 0
                return alt
            }
            return optionCharacter(key, otherwise: alt, accept: isPrintable)
        case .smart:
            if key.keyCode == MacKeyCode.space, deadKeyState == 0 {
                // Not Alt+Space (window menu) when ⌥ is still down after typing `|` or `}`.
                return .hold(OutputChord(modifiers: shift, target: key.target))
            }
            let base = layout.baseCharacter(of: key.keyCode)
            return optionCharacter(key, otherwise: alt) { OptionCharacterPolicy.smartAccepts($0, baseCharacter: base) }
        }
    }

    private mutating func optionCharacter(
        _ key: PressedKey, otherwise fallback: KeyOutput, accept: (String) -> Bool
    ) -> KeyOutput {
        var state = deadKeyState
        let text = layout.translate(keyCode: key.keyCode, modifiers: layoutModifiers(option: true), deadKeyState: &state)
        if text.isEmpty, state != 0 {
            deadKeyState = state
            return .composing
        }
        guard accept(text) else {
            deadKeyState = 0
            return fallback
        }
        deadKeyState = state
        return .text(text)
    }

    /// No ⌘ ⌥ ⌃ (⇧ allowed): scancodes, unless a dead key is composing or Unicode input is on.
    private mutating func resolvePlain(_ key: PressedKey, shift: WindowsModifiers) -> KeyOutput {
        let scancodes = KeyOutput.hold(OutputChord(modifiers: shift, target: key.target))
        if deadKeyState != 0 {
            if key.keyClass != .function {
                var state = deadKeyState
                let text = layout.translate(keyCode: key.keyCode, modifiers: layoutModifiers(option: false), deadKeyState: &state)
                deadKeyState = state
                if text.isEmpty, state != 0 { return .composing }
                if isPrintable(text) { return .text(text) }
                return scancodes
            }
            if key.keyCode == MacKeyCode.backspace || key.keyCode == MacKeyCode.escape {
                // Like on the Mac: ⌫/Esc cancel the pending accent.
                deadKeyState = 0
                return .swallow
            }
            emitPendingAccent()
        }
        guard config.unicodeTextInput, key.keyClass != .function else { return scancodes }
        var state: UInt32 = 0
        let text = layout.translate(keyCode: key.keyCode, modifiers: layoutModifiers(option: false), deadKeyState: &state)
        if text.isEmpty, state != 0 {
            deadKeyState = state
            return .composing
        }
        // Space stays a scancode: identical in every layout and games want it.
        guard isPrintable(text), text != " " else { return scancodes }
        return .text(text)
    }

    /// A dead key followed by a non-character key: type the accent on its own first.
    private mutating func emitPendingAccent() {
        var state = deadKeyState
        deadKeyState = 0
        let accent = layout.translate(keyCode: MacKeyCode.space, modifiers: [], deadKeyState: &state)
        if isPrintable(accent) { emitText(accent) }
    }

    private func layoutModifiers(option: Bool) -> LayoutModifiers {
        var modifiers: LayoutModifiers = []
        if option { modifiers.insert(.option) }
        if !physical.isDisjoint(with: .shift) { modifiers.insert(.shift) }
        if remoteCapsLock == true { modifiers.insert(.capsLock) }
        return modifiers
    }

    // MARK: - Sending

    private mutating func perform(_ result: KeyOutput, for key: PressedKey, isRepeat: Bool) {
        switch result {
        case .hold(let chord):
            press(chord, for: key, isRepeat: isRepeat)
        case .taps(let chords):
            releaseHeldKey(key.keyCode)
            heldKeys[key.keyCode] = .consumed
            // Never repeat a pure modifier tap (a held ⌘Space would toggle the Start menu).
            if isRepeat, chords.allSatisfy({ $0.target == nil }) { return }
            for chord in chords { tap(chord) }
        case .text(let text):
            releaseHeldKey(key.keyCode)
            heldKeys[key.keyCode] = .consumed
            emitText(text)
        case .composing:
            releaseHeldKey(key.keyCode)
            heldKeys[key.keyCode] = .composing
        case .swallow:
            releaseHeldKey(key.keyCode)
            heldKeys[key.keyCode] = .consumed
        }
    }

    private mutating func press(_ chord: OutputChord, for key: PressedKey, isRepeat: Bool) {
        guard let target = chord.target else { return }
        switch target {
        case .text(let text):
            releaseHeldKey(key.keyCode)
            heldKeys[key.keyCode] = .consumed
            emitText(text)
        case .pause:
            releaseHeldKey(key.keyCode)
            heldKeys[key.keyCode] = .consumed
            if isRepeat { return }
            remote.setModifiers(sides(for: chord.modifiers), into: &output)
            if remote.modifiers.contains(where: { $0.kind == .control }) {
                remote.press(PCScancode.breakKey, into: &output)
                heldKeys[key.keyCode] = .scancode(PCScancode.breakKey)
            } else {
                output.append(.pause)
            }
        case .scancode(let scancode):
            let isLockKey = scancode == PCScancode.numLock || scancode == PCScancode.scrollLock
            if isRepeat, isLockKey { return }
            if case .scancode(let previous)? = heldKeys[key.keyCode], previous != scancode {
                remote.release(previous, into: &output)
            }
            remote.setModifiers(sides(for: chord.modifiers), into: &output)
            remote.press(scancode, into: &output)
            heldKeys[key.keyCode] = .scancode(scancode)
            if scancode == PCScancode.scrollLock { remoteScrollLock.toggle() }
        }
    }

    private mutating func tap(_ chord: OutputChord) {
        remote.setModifiers(sides(for: chord.modifiers), into: &output)
        switch chord.target {
        case nil:
            remote.setModifiers([], into: &output)
        case .scancode(let scancode):
            remote.tap(scancode, into: &output)
        case .pause:
            output.append(.pause)
        case .text(let text):
            emitText(text)
        }
    }

    /// Unicode input, one down/up pair per UTF-16 unit. Ctrl/Alt/Win go up first; Shift may stay
    /// (it does not change Unicode input, and tapping it per character could trigger Sticky Keys).
    private mutating func emitText(_ text: String) {
        remote.setModifiers(remote.modifiers.filter { $0.kind == .shift }, into: &output)
        for unit in text.utf16 {
            output.append(.unicode(unit, down: true))
            output.append(.unicode(unit, down: false))
        }
    }

    private mutating func releaseHeldKey(_ keyCode: UInt16) {
        if case .scancode(let scancode)? = heldKeys.removeValue(forKey: keyCode) {
            remote.release(scancode, into: &output)
        }
    }
}

/// A key press with its physical mapping.
struct PressedKey {
    let keyCode: UInt16
    let target: KeyTarget
    let keyClass: KeyClass
    let keyboardType: PhysicalKeyboardType
}
