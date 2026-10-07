@testable import KeyboardEngine
import Testing

/// Focus, toggles, repeats and lost events: nothing may get stuck on the remote side.
struct StateTests {
    @Test func focusLossMidChordReleasesKeyThenCtrl() {
        var h = Harness()
        h.press(.lCmd)
        h.down(K.c)
        _ = h.take()
        h.focusLost()
        #expect(h.take() == [up(SC.c), up(SC.lCtrl)])
        // The late events of the abandoned chord must not send anything (no Win tap either).
        h.up(K.c)
        h.release(.lCmd)
        #expect(h.take() == [])
    }

    @Test func focusLossInTheAppSwitcherReleasesAlt() {
        var h = Harness()
        h.press(.lCmd)
        h.type(K.tab)
        _ = h.take()
        h.focusLost()
        #expect(h.take() == [up(SC.lAlt)])
        h.release(.lCmd)
        #expect(h.take() == [])
    }

    @Test func focusLossReleasesForwardedModifiersAndHeldKeys() {
        var h = Harness()
        h.press(.rShift)
        h.press(.lCtrl)
        h.down(K.a)
        _ = h.take()
        h.focusLost()
        #expect(h.take() == [up(SC.a), up(SC.lCtrl), up(SC.rShift)])
    }

    @Test func focusLossWithPendingCommandSendsNothing() {
        var h = Harness()
        h.press(.lCmd)
        h.focusLost()
        h.release(.lCmd)
        #expect(h.take() == [])
    }

    @Test func focusGainedSyncsTogglesWithNumLockOn() {
        var h = Harness()
        h.flags.insert(.capsLock)
        h.focusGained()
        #expect(h.take() == [.sync(capsLock: true, numLock: true, scrollLock: false)])
        h.type(K.f14)
        h.focusLost()
        h.focusGained()
        #expect(h.take() == tap(SC.scrollLock) + [.sync(capsLock: true, numLock: true, scrollLock: true)])
    }

    @Test func commandHeldWhileSwitchingBackIsNoWinTapButStillAShortcut() {
        var h = Harness()
        h.flags = [.leftCommand]
        h.focusGained()
        _ = h.take()
        h.release(.lCmd)
        #expect(h.take() == [])

        h.flags = [.leftCommand]
        h.focusGained()
        _ = h.take()
        h.type(K.v)
        h.release(.lCmd)
        #expect(h.take() == [down(SC.lCtrl)] + tap(SC.v) + [up(SC.lCtrl)])
    }

    @Test func capsLockTogglesAreMirroredOnce() {
        var h = Harness()
        h.toggleCapsLock()
        #expect(h.take() == tap(SC.capsLock))
        h.type(K.a)
        #expect(h.take() == tap(SC.a))
        h.toggleCapsLock()
        #expect(h.take() == tap(SC.capsLock))
    }

    @Test func capsLockChangeSeenOnlyInAKeyEventIsStillMirrored() {
        var h = Harness()
        h.flags.insert(.capsLock)
        h.type(K.a)
        #expect(h.take() == tap(SC.capsLock) + tap(SC.a))
    }

    @Test func missedCommandReleaseIsRepairedByTheNextKey() {
        var h = Harness()
        h.press(.lCmd)
        h.type(K.c)
        _ = h.take()
        h.flags = [] // ⌘ went up while the app did not get the event
        h.type(K.c)
        #expect(h.take() == [up(SC.lCtrl)] + tap(SC.c))
    }

    @Test func modifierSeenOnlyInAKeyEventIsApplied() {
        var h = Harness()
        h.flags = [.leftCommand]
        h.type(K.c)
        h.flags = []
        h.send(KeyEvent(kind: .flagsChanged, keyCode: 0x37, modifiers: [], timestamp: h.time + 0.01))
        #expect(h.take() == [down(SC.lCtrl)] + tap(SC.c) + [up(SC.lCtrl)])
    }

    @Test func keyUpWithoutDownSendsNothing() {
        var h = Harness()
        h.up(K.a)
        h.up(K.left)
        #expect(h.take() == [])
    }

    @Test func repeatsAreReevaluatedWhenModifiersChange() {
        // Hold ⌥⌫ (Ctrl+Backspace), let go of ⌥ while ⌫ keeps repeating: plain Backspace.
        var h = Harness()
        h.press(.lOpt)
        h.down(K.backspace)
        h.release(.lOpt)
        h.down(K.backspace, isRepeat: true)
        h.up(K.backspace)
        #expect(h.take() == [down(SC.lCtrl), down(SC.backspace), up(SC.lCtrl), down(SC.backspace), up(SC.backspace)])
    }

    @Test func translatedChordRepeats() {
        var h = Harness()
        h.press(.lCmd)
        h.down(K.left)
        h.down(K.left, isRepeat: true)
        h.down(K.left, isRepeat: true)
        h.up(K.left)
        h.release(.lCmd)
        #expect(h.take() == [down(SC.home), down(SC.home), down(SC.home), up(SC.home)])
    }

    @Test func repeatChangingTheTargetReleasesTheOldKey() {
        // ⌘← held (Home), ⌘ released: the repeat becomes ←.
        var h = Harness()
        h.press(.lCmd)
        h.down(K.left)
        h.release(.lCmd)
        h.down(K.left, isRepeat: true)
        h.up(K.left)
        #expect(h.take() == [down(SC.home), up(SC.home), down(SC.left), up(SC.left)])
    }

    @Test func reservedShortcutsStayInTheApp() {
        var h = Harness()
        h.press(.lCmd)
        h.down(K.q)
        #expect(h.lastPassedToApp)
        h.up(K.q)
        #expect(h.lastPassedToApp)
        h.release(.lCmd)
        #expect(h.take() == [])

        h.chord([.lCtrl, .lOpt, .lCmd], K.a)
        #expect(h.take() == [down(SC.lCtrl), up(SC.lCtrl)])
        for (modifiers, key, reserved) in [
            ([Mod.lCtrl, .lCmd], K.f, true), ([.lCtrl, .lOpt, .lShift, .lCmd], K.x, true),
            ([.lCmd], K.ansiY, false), ([.lCmd, .lShift], K.q, false),
        ] {
            modifiers.forEach { h.press($0) }
            h.down(key)
            #expect(h.lastPassedToApp == reserved, "\(modifiers) \(key)")
            h.up(key)
            modifiers.reversed().forEach { h.release($0) }
        }
    }

    @Test func reservedShortcutReleasesChordModifiers() {
        var h = Harness()
        h.press(.lCmd)
        h.type(K.c)
        _ = h.take()
        h.down(K.q)
        #expect(h.lastPassedToApp)
        #expect(h.take() == [up(SC.lCtrl)])
    }

    @Test func reservedMatchingUsesTheLayout() {
        // Reserved patterns match by character, like rules.
        let engine = KeyboardEngine(layout: Layouts.german)
        #expect(engine.isReserved(KeyEvent(kind: .down, keyCode: K.f, modifiers: [.leftControl, .leftCommand])))
        #expect(!engine.isReserved(KeyEvent(kind: .down, keyCode: K.f, modifiers: [.leftCommand])))
        #expect(!engine.isReserved(KeyEvent(kind: .flagsChanged, keyCode: 0x37, modifiers: [.leftCommand])))
    }

    @Test func resetForgetsWithoutSending() {
        var h = Harness()
        h.press(.lShift)
        h.down(K.a)
        _ = h.take()
        h.engine.reset()
        h.up(K.a)
        // No break for the forgotten A; the still-held ⇧ is simply adopted again (new session).
        #expect(h.take() == [down(SC.lShift)])
    }

    @Test func applyingANewConfigReleasesEverythingFirst() {
        var h = Harness()
        h.press(.lCmd)
        h.down(K.c)
        _ = h.take()
        var config = KeyboardConfig()
        config.mode = .windowsDirect
        #expect(h.engine.apply(config) == [up(SC.c), up(SC.lCtrl)])
    }
}
