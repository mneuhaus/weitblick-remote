@testable import KeyboardEngine
import Testing

/// Physical key placement: macOS key code -> set-1 scancode.
struct PhysicalKeyTests {
    @Test(arguments: [PhysicalKeyboardType.ansi, .iso, .jis])
    func everyMappedKeyHasAUniqueValidScancode(keyboardType: PhysicalKeyboardType) {
        var seen: [KeyTarget: UInt16] = [:]
        for keyCode in PhysicalKeyMap.mappedKeyCodes {
            let target = PhysicalKeyMap.target(for: keyCode, keyboardType: keyboardType)
            #expect(target != nil, "key code \(keyCode) has no target")
            guard let target else { continue }
            if let other = seen[target] {
                Issue.record("key codes \(other) and \(keyCode) both send \(target)")
            }
            seen[target] = keyCode
            if case .scancode(let scancode) = target {
                let isIMEKey = scancode.extended && (scancode.code == 0xF1 || scancode.code == 0xF2)
                #expect(scancode.code != 0 && (scancode.code < 0x80 || isIMEKey), "\(scancode) is no make code")
            }
            #expect(PhysicalKeyMap.keyClass(of: keyCode) != nil)
        }
        // Modifier keys, Caps Lock and fn are handled as modifiers, never as plain keys.
        for keyCode: UInt16 in 0x36...0x3F {
            #expect(PhysicalKeyMap.target(for: keyCode, keyboardType: keyboardType) == nil)
        }
    }

    @Test func isoKeyboardSendsTheTwoExtraKeysAtTheirPCPositions() {
        // German MacBook: ^° left of 1 is kVK_ISO_Section, <> left of Y is kVK_ANSI_Grave.
        #expect(Layouts.german.baseCharacter(of: K.grave) == "<")
        var h = Harness(Layouts.german)
        h.type(K.isoSection)
        h.type(K.grave)
        #expect(h.take() == tap(SC.grave) + tap(SC.oem102))
    }

    @Test func ansiKeyboardSendsGraveLeftOfOne() {
        var h = Harness(Layouts.us)
        h.type(K.grave)
        #expect(h.take() == tap(SC.grave))
    }

    @Test func eventKeyboardTypeBeatsLayoutAndOverrideBeatsBoth() {
        var h = Harness(Layouts.usOnISO)
        h.keyboardType = .ansi
        h.type(K.grave)
        #expect(h.take() == tap(SC.grave))

        var config = KeyboardConfig()
        config.keyboardTypeOverride = .iso
        var overridden = Harness(Layouts.us, config: config)
        overridden.keyboardType = .ansi
        overridden.type(K.grave)
        #expect(overridden.take() == tap(SC.oem102))
    }

    @Test(arguments: [
        (K.home, SC.home), (K.end, SC.end), (K.pageUp, Scancode(0x49, extended: true)),
        (K.pageDown, Scancode(0x51, extended: true)), (K.forwardDelete, SC.delete),
        (K.left, SC.left), (K.right, SC.right), (K.up, SC.up), (K.down, SC.down),
        (K.keypadEnter, SC.keypadEnter), (K.keypadDivide, SC.keypadDivide),
        (K.help, SC.insert), (K.f13, SC.printScreen), (K.f14, SC.scrollLock), (K.keypadClear, SC.numLock),
        (K.f16, SC.f16), (K.f17, SC.f17), (K.f18, SC.f18), (K.f19, SC.f19),
        (K.returnKey, SC.enter), (K.keypad1, SC.keypad1), (K.f12, SC.f12),
        (K.jisYen, Scancode(0x7D)), (K.jisUnderscore, Scancode(0x73)),
        (K.jisKana, Scancode(0xF2, extended: true)), (K.jisEisu, Scancode(0xF1, extended: true)),
    ])
    func specialKeysFromTheSpec(keyCode: UInt16, scancode: Scancode) {
        var h = Harness()
        h.type(keyCode)
        #expect(h.take() == tap(scancode))
    }

    @Test func f15IsPauseAndBreakWithCtrl() {
        var h = Harness()
        h.type(K.f15)
        #expect(h.take() == [.pause])
        h.chord([.lCtrl], K.f15)
        #expect(h.take() == [down(SC.lCtrl)] + tap(SC.breakKey) + [up(SC.lCtrl)])
        // ⌘F15 -> Ctrl+Pause -> Break as well.
        h.chord([.lCmd], K.f15)
        #expect(h.take() == [down(SC.lCtrl)] + tap(SC.breakKey) + [up(SC.lCtrl)])
    }

    @Test func lockKeysAndPauseDoNotRepeat() {
        var h = Harness()
        for key in [K.f14, K.keypadClear, K.f15] {
            h.down(key)
            _ = h.take()
            h.down(key, isRepeat: true)
            h.down(key, isRepeat: true)
            #expect(h.take() == [])
            h.up(key)
        }
    }

    @Test func keypadEqualsIsTypedAsText() {
        var h = Harness()
        h.type(K.keypadEquals)
        #expect(h.take() == text("="))
    }

    @Test func unknownKeyCodesAreSwallowed() {
        var h = Harness()
        h.type(0x34)
        h.type(0x7F)
        #expect(h.take() == [])
    }
}
