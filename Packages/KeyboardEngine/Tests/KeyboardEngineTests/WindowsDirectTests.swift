@testable import KeyboardEngine
import Testing

/// "Windows 1:1": ⌘ = Win, ⌥ = Alt, ⌃ = Ctrl, no rules.
struct WindowsDirectTests {
    private var direct: KeyboardConfig {
        var config = KeyboardConfig()
        config.mode = .windowsDirect
        return config
    }

    @Test func modifiersAreForwardedImmediatelyWithTheirSide() {
        var h = Harness(config: direct)
        for (modifier, scancode) in [
            (Mod.lCmd, SC.lWin), (.rCmd, SC.rWin), (.lOpt, SC.lAlt), (.rOpt, SC.rAlt),
            (.lCtrl, SC.lCtrl), (.rCtrl, SC.rCtrl), (.lShift, SC.lShift), (.rShift, SC.rShift),
        ] {
            h.press(modifier)
            #expect(h.take() == [down(scancode)])
            h.release(modifier)
            #expect(h.take() == [up(scancode)])
        }
    }

    @Test func commandIsWinWithoutRules() {
        var h = Harness(config: direct)
        h.chord([.lCmd], K.e)
        h.chord([.lCmd], K.left)
        h.chord([.lCmd], K.c)
        #expect(h.take() == sequence(
            [down(SC.lWin)], tap(SC.e), [up(SC.lWin)],
            [down(SC.lWin)], tap(SC.left), [up(SC.lWin)],
            [down(SC.lWin)], tap(SC.c), [up(SC.lWin)]
        ))
    }

    @Test func rightOptionIsAltGr() {
        // AltGr+Q is @ on a German Windows layout.
        var h = Harness(config: direct)
        h.chord([.rOpt], K.q)
        #expect(h.take() == [down(SC.rAlt)] + tap(SC.q) + [up(SC.rAlt)])
    }

    @Test func optionTypesNoCharacters() {
        var h = Harness(config: direct)
        h.chord([.lOpt], K.l)
        #expect(h.take() == [down(SC.lAlt)] + tap(SC.l) + [up(SC.lAlt)])
    }

    @Test func unicodeInputOnlyForUnmodifiedText() {
        var config = direct
        config.unicodeTextInput = true
        var h = Harness(config: config)
        h.type(K.a)
        h.chord([.lOpt], K.a)
        #expect(h.take() == text("a") + [down(SC.lAlt)] + tap(SC.a) + [up(SC.lAlt)])
    }

    @Test func reservedShortcutsStillApply() {
        var h = Harness(config: direct)
        h.press(.lCmd)
        h.down(K.q)
        #expect(h.lastPassedToApp)
        h.up(K.q)
        h.release(.lCmd)
        // The Ctrl tap keeps Windows from opening the Start menu when ⌘ goes up.
        #expect(h.take() == [down(SC.lWin)] + tap(SC.lCtrl) + [up(SC.lWin)])
    }
}
