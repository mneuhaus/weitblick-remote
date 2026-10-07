@testable import KeyboardEngine
import Testing

/// Dead keys and the Unicode path.
struct TextInputTests {
    private var unicodeConfig: KeyboardConfig {
        var config = KeyboardConfig()
        config.unicodeTextInput = true
        return config
    }

    @Test func plainDeadKeysPassAsScancodesForWindowsToCompose() {
        // German ´ then e: Windows (German layout) composes é itself.
        var h = Harness()
        h.type(K.equal)
        h.type(K.e)
        #expect(h.take() == tap(Scancode(0x0D)) + tap(SC.e))
    }

    @Test func optionDeadKeyComposesLocally() {
        // German ⌥N is the dead tilde.
        var h = Harness()
        h.chord([.lOpt], K.n)
        #expect(h.take() == [])
        h.type(K.n)
        #expect(h.take() == text("ñ"))
    }

    @Test func deadKeyThenSpaceTypesTheAccent() {
        var h = Harness()
        h.chord([.lOpt], K.n)
        h.type(K.space)
        #expect(h.take() == text("~"))
    }

    /// UCKeyTranslate keeps the finished dead key in the upper state bits; nothing is pending then,
    /// so ⌫, arrows and space after "~" are ordinary keys again.
    @Test func composedAccentLeavesNothingPending() {
        var h = Harness()
        h.chord([.lOpt], K.n)
        h.type(K.space)
        h.type(K.backspace)
        h.type(K.left)
        h.type(K.space)
        #expect(h.take() == text("~") + tap(SC.backspace) + tap(SC.left) + tap(SC.space))
    }

    @Test func secondDeadKeyStaysPending() {
        // ⌥N then ⌥U: "~" is typed and the diaeresis waits for its letter (as on the Mac).
        var h = Harness()
        h.chord([.lOpt], K.n)
        h.chord([.lOpt], K.u)
        h.type(K.a)
        #expect(h.take() == text("~") + text("ä"))
    }

    @Test func deadKeyThenNonComposingLetterTypesBoth() {
        var h = Harness()
        h.chord([.lOpt], K.n)
        h.type(K.x)
        #expect(h.take() == text("~x"))
    }

    @Test func backspaceCancelsAPendingAccent() {
        var h = Harness()
        h.chord([.lOpt], K.n)
        h.type(K.backspace)
        #expect(h.take() == [])
        h.type(K.n)
        #expect(h.take() == tap(SC.n))
    }

    @Test func arrowAfterAPendingAccentTypesTheAccentThenMoves() {
        var h = Harness()
        h.chord([.lOpt], K.n)
        h.type(K.left)
        #expect(h.take() == text("~") + tap(SC.left))
    }

    @Test func commandShortcutDropsAPendingAccent() {
        var h = Harness()
        h.chord([.lOpt], K.n)
        h.chord([.lCmd], K.c)
        h.type(K.n)
        #expect(h.take() == [down(SC.lCtrl)] + tap(SC.c) + [up(SC.lCtrl)] + tap(SC.n))
    }

    @Test func heldDeadKeyDoesNotRepeat() {
        var h = Harness(config: unicodeConfig)
        h.down(K.equal)
        h.down(K.equal, isRepeat: true)
        h.up(K.equal)
        #expect(h.take() == [])
        h.type(K.e)
        #expect(h.take() == text("é"))
    }

    @Test func unicodeInputSendsLettersAsTextAndComposesDeadKeys() {
        var h = Harness(config: unicodeConfig)
        h.type(K.a)
        h.chord([.lShift], K.a)
        #expect(h.take() == text("a") + [down(SC.lShift)] + text("A") + [up(SC.lShift)])
        // German ^ (left of 1) is dead; followed by space it is the circumflex itself.
        h.type(K.isoSection)
        h.type(K.space)
        h.type(K.equal)
        h.type(K.e)
        #expect(h.take() == text("^") + text("é"))
    }

    @Test func unicodeInputKeepsSpaceShortcutsAndControlKeysAsScancodes() {
        var h = Harness(config: unicodeConfig)
        h.type(K.space)
        h.type(K.returnKey)
        h.chord([.lCmd], K.c)
        h.chord([.lCtrl], K.c)
        #expect(h.take() == sequence(
            tap(SC.space), tap(SC.enter),
            [down(SC.lCtrl)], tap(SC.c), [up(SC.lCtrl)],
            [down(SC.lCtrl)], tap(SC.c), [up(SC.lCtrl)]
        ))
    }

    @Test func unicodeInputRespectsCapsLock() {
        var h = Harness(config: unicodeConfig)
        h.toggleCapsLock()
        h.type(K.a)
        #expect(h.take() == tap(SC.capsLock) + text("A"))
    }

    @Test func nonBMPCharactersAreSentAsSurrogatePairs() {
        var state: UInt32 = 0
        let expected = Layouts.osage.translate(keyCode: K.a, modifiers: [], deadKeyState: &state)
        #expect(expected.unicodeScalars.first!.value > 0xFFFF)
        var h = Harness(Layouts.osage, config: unicodeConfig)
        h.type(K.a)
        let units = h.take().compactMap { action -> UInt16? in
            if case .unicode(let unit, true) = action { unit } else { nil }
        }
        #expect(units == Array(expected.utf16))
        #expect(units.count == 2 && UTF16.isLeadSurrogate(units[0]) && UTF16.isTrailSurrogate(units[1]))
    }

    @Test func repeatedCharacterIsTypedAgain() {
        var h = Harness()
        h.press(.lOpt)
        h.down(K.l)
        h.down(K.l, isRepeat: true)
        h.up(K.l)
        h.release(.lOpt)
        #expect(h.take() == text("@") + text("@"))
    }
}
