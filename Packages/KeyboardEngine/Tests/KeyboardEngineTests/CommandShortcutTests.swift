@testable import KeyboardEngine
import Testing

/// ⌘ deferral and the spec's shortcut rules in Mac-shortcut mode (German ISO layout unless noted).
struct CommandShortcutTests {
    @Test func commandAloneSendsNothingUntilReleasedThenTapsWin() {
        var h = Harness()
        h.press(.lCmd)
        #expect(h.take() == [])
        h.release(.lCmd)
        #expect(h.take() == tap(SC.lWin))
    }

    @Test func commandHeldLongerThanTapTimeoutSendsNothing() {
        var h = Harness()
        h.press(.lCmd)
        h.wait(0.8)
        h.release(.lCmd)
        #expect(h.take() == [])
    }

    @Test func commandAfterAnotherModifierIsNoWinTap() {
        var h = Harness()
        h.press(.lShift)
        h.press(.lCmd)
        h.release(.lCmd)
        h.release(.lShift)
        #expect(h.take() == [down(SC.lShift), up(SC.lShift)])
    }

    @Test func commandCopyIsCtrlCInPressOrder() {
        var h = Harness()
        h.chord([.lCmd], K.c)
        #expect(h.take() == [down(SC.lCtrl), down(SC.c), up(SC.c), up(SC.lCtrl)])
    }

    @Test func rightCommandWorksLikeLeft() {
        var h = Harness()
        h.chord([.rCmd], K.v)
        #expect(h.take() == [down(SC.lCtrl), down(SC.v), up(SC.v), up(SC.lCtrl)])
    }

    @Test func copyThenPasteWithoutReleasingCommandKeepsCtrlDown() {
        var h = Harness()
        h.press(.lCmd)
        h.type(K.c)
        h.type(K.v)
        h.release(.lCmd)
        #expect(h.take() == [down(SC.lCtrl), down(SC.c), up(SC.c), down(SC.v), up(SC.v), up(SC.lCtrl)])
    }

    @Test func overlappingKeysUnderCommand() {
        var h = Harness()
        h.press(.lCmd)
        h.down(K.c)
        h.down(K.v)
        h.up(K.c)
        h.up(K.v)
        h.release(.lCmd)
        #expect(h.take() == [down(SC.lCtrl), down(SC.c), down(SC.v), up(SC.c), up(SC.v), up(SC.lCtrl)])
    }

    @Test func shiftIsKeptInTheDefaultCommandRule() {
        var h = Harness()
        // ⇧ first: forwarded at once, Ctrl joins for the key.
        h.chord([.lShift, .lCmd], K.s)
        #expect(h.take() == [
            down(SC.lShift), down(SC.lCtrl), down(Scancode(0x1F)), up(Scancode(0x1F)), up(SC.lCtrl), up(SC.lShift),
        ])
        // ⌘ first: ⇧ waits for the key.
        h.chord([.lCmd, .rShift], K.s)
        #expect(h.take() == [
            down(SC.lCtrl), down(SC.rShift), down(Scancode(0x1F)), up(Scancode(0x1F)), up(SC.rShift), up(SC.lCtrl),
        ])
    }

    @Test func commandOptionKeyAddsAlt() {
        var h = Harness()
        h.chord([.lCmd, .lOpt], K.d)
        #expect(h.take() == [down(SC.lCtrl), down(SC.lAlt), down(SC.d), up(SC.d), up(SC.lAlt), up(SC.lCtrl)])
    }

    @Test func undoAndRedoFollowTheGermanLayout() {
        // QWERTZ: the key labelled Z is kVK_ANSI_Y, the key labelled Y is kVK_ANSI_Z.
        #expect(Layouts.german.baseCharacter(of: K.ansiY) == "z")
        #expect(Layouts.german.baseCharacter(of: K.ansiZ) == "y")
        var h = Harness(Layouts.german)
        h.chord([.lCmd], K.ansiY)
        // Same physical key as on the Mac: German Windows reads scancode 15 as Z.
        #expect(h.take() == [down(SC.lCtrl), down(SC.usY), up(SC.usY), up(SC.lCtrl)])
        h.chord([.lCmd, .lShift], K.ansiY)
        // ⌘⇧Z -> Ctrl+Y without Shift; Y is at scancode 2C on a German PC keyboard.
        #expect(h.take() == [down(SC.lCtrl), down(SC.usZ), up(SC.usZ), up(SC.lCtrl)])
    }

    @Test func redoFollowsTheUSLayout() {
        var h = Harness(Layouts.us)
        h.chord([.lCmd, .lShift], K.ansiZ)
        #expect(h.take() == [down(SC.lCtrl), down(SC.usY), up(SC.usY), up(SC.lCtrl)])
    }

    @Test func redoWithShiftHeldBeforeCommandReleasesShiftForTheKey() {
        var h = Harness()
        h.press(.lShift)
        h.press(.lCmd)
        h.down(K.ansiY)
        #expect(h.take() == [down(SC.lShift), up(SC.lShift), down(SC.lCtrl), down(SC.usZ)])
        h.up(K.ansiY)
        h.release(.lCmd)
        // Back to the physical state: ⇧ is still held.
        #expect(h.take() == [up(SC.usZ), up(SC.lCtrl), down(SC.lShift)])
        h.release(.lShift)
        #expect(h.take() == [up(SC.lShift)])
    }

    @Test func redoFallsBackToUSPositionsOnCyrillicLayouts() {
        // Russian has no Latin letters; Windows uses the US positions for shortcuts there.
        var h = Harness(Layouts.russian)
        h.chord([.lCmd, .lShift], K.ansiZ)
        #expect(h.take() == [down(SC.lCtrl), down(SC.usY), up(SC.usY), up(SC.lCtrl)])
    }

    @Test(arguments: [
        (K.left, [SC.home]), (K.right, [SC.end]), (K.up, [SC.lCtrl, SC.home]), (K.down, [SC.lCtrl, SC.end]),
    ])
    func commandArrowsJumpToLineAndDocumentEdges(arrow: UInt16, output: [Scancode]) {
        var h = Harness()
        h.chord([.lCmd], arrow)
        let modifiers = output.dropLast()
        let key = output.last!
        #expect(h.take() == modifiers.map(down) + tap(key) + modifiers.reversed().map(up))
    }

    @Test func commandShiftArrowsSelect() {
        var h = Harness()
        h.chord([.lShift, .lCmd], K.left)
        #expect(h.take() == [down(SC.lShift)] + tap(SC.home) + [up(SC.lShift)])
        h.chord([.lCmd, .lShift], K.down)
        #expect(h.take() == [down(SC.lCtrl), down(SC.lShift)] + tap(SC.end) + [up(SC.lShift), up(SC.lCtrl)])
    }

    @Test func commandArrowAfterCopyReleasesCtrlFirst() {
        var h = Harness()
        h.press(.lCmd)
        h.type(K.c)
        h.type(K.left)
        h.type(K.v)
        h.release(.lCmd)
        #expect(h.take() == [
            down(SC.lCtrl), down(SC.c), up(SC.c),
            up(SC.lCtrl), down(SC.home), up(SC.home),
            down(SC.lCtrl), down(SC.v), up(SC.v),
            up(SC.lCtrl),
        ])
    }

    @Test func commandBackspaceDeletesToLineStart() {
        var h = Harness()
        h.press(.lCmd)
        h.down(K.backspace)
        let expected = [down(SC.lShift)] + tap(SC.home) + [up(SC.lShift)] + tap(SC.backspace)
        #expect(h.take() == expected)
        h.down(K.backspace, isRepeat: true)
        #expect(h.take() == expected)
        h.up(K.backspace)
        h.release(.lCmd)
        #expect(h.take() == [])
    }

    @Test func commandForwardDeleteDeletesToLineEnd() {
        var h = Harness()
        h.chord([.lCmd], K.forwardDelete)
        #expect(h.take() == [down(SC.lShift)] + tap(SC.end) + [up(SC.lShift)] + tap(SC.delete))
    }

    @Test func commandSpaceTapsWinOnce() {
        var h = Harness()
        h.press(.lCmd)
        h.down(K.space)
        h.down(K.space, isRepeat: true)
        h.up(K.space)
        h.release(.lCmd)
        #expect(h.take() == tap(SC.lWin))
    }

    /// From Jump's default input profile; ⌘Q reaches the session instead of quitting Weitblick Remote.
    @Test func commandQClosesTheRemoteWindow() {
        var h = Harness()
        h.press(.lCmd)
        h.down(K.q)
        #expect(!h.lastPassedToApp)
        #expect(h.take() == [down(SC.lAlt), down(SC.f4)])
        h.up(K.q)
        h.release(.lCmd)
        #expect(h.take() == [up(SC.f4), up(SC.lAlt)])
    }

    @Test func commandBracketsAreBrowserBackAndForward() {
        var h = Harness(Layouts.us)
        h.chord([.lCmd], K.leftBracket)
        h.chord([.lCmd], K.rightBracket)
        #expect(h.take() == sequence(
            [down(SC.lAlt)], tap(SC.left), [up(SC.lAlt)],
            [down(SC.lAlt)], tap(SC.right), [up(SC.lAlt)]
        ))
    }

    /// The bracket rules match by typed character like Jump: German types [ and ] with ⌥5 / ⌥6, and
    /// ⌘⌥ must not take the default ⌘ path (Ctrl+Alt+5) there.
    @Test func commandBracketsAreOptionDigitsOnGerman() {
        var h = Harness(Layouts.german)
        h.chord([.lCmd, .lOpt], K.five)
        h.chord([.lOpt, .lCmd], K.six)
        #expect(h.take() == sequence(
            [down(SC.lAlt)], tap(SC.left), [up(SC.lAlt)],
            [down(SC.lAlt)], tap(SC.right), [up(SC.lAlt)]
        ))
    }

    /// The keys at the US bracket positions keep the default rule on German: ⌘Ü = Ctrl+Ü and
    /// ⌘+ / ⌘- stay zoom (Ctrl++ / Ctrl+-).
    @Test(arguments: [(K.leftBracket, Scancode(0x1A)), (K.rightBracket, Scancode(0x1B)), (K.slash, Scancode(0x35))])
    func germanKeysAtUSBracketPositionsStayCtrlShortcuts(key: UInt16, scancode: Scancode) {
        #expect(Layouts.german.baseCharacter(of: K.leftBracket) == "ü")
        #expect(Layouts.german.baseCharacter(of: K.rightBracket) == "+")
        var h = Harness(Layouts.german)
        h.chord([.lCmd], key)
        #expect(h.take() == [down(SC.lCtrl)] + tap(scancode) + [up(SC.lCtrl)])
    }

    @Test func customRuleWithoutModifiersReleasesItsModifiersWithTheKey() {
        var config = KeyboardConfig()
        config.rules.append(ShortcutRule("f13", ["win+shift+s"]))
        var h = Harness(config: config)
        h.type(K.f13)
        // The key that types s on German is at scancode 1F.
        #expect(h.take() == [down(SC.lShift), down(SC.lWin)] + tap(Scancode(0x1F)) + [up(SC.lWin), up(SC.lShift)])
    }

    @Test func optionCommandEscapeOpensTaskManager() {
        var h = Harness()
        h.chord([.lOpt, .lCmd], K.escape)
        #expect(h.take() == [down(SC.lCtrl), down(SC.lShift)] + tap(SC.escape) + [up(SC.lShift), up(SC.lCtrl)])
    }

    @Test(arguments: [K.backspace, K.forwardDelete])
    func controlOptionDeleteIsCtrlAltDel(key: UInt16) {
        var h = Harness()
        h.chord([.lCtrl, .lOpt], key)
        #expect(h.take() == [down(SC.lCtrl), down(SC.lAlt)] + tap(SC.delete) + [up(SC.lAlt), up(SC.lCtrl)])
    }

    @Test func commandTabHoldsAltUntilCommandIsReleased() {
        var h = Harness()
        h.press(.lCmd)
        h.type(K.tab)
        #expect(h.take() == [down(SC.lAlt)] + tap(SC.tab))
        h.type(K.tab)
        #expect(h.take() == tap(SC.tab))
        h.press(.lShift)
        h.type(K.tab)
        #expect(h.take() == [down(SC.lShift)] + tap(SC.tab))
        h.release(.lShift)
        h.type(K.tab)
        #expect(h.take() == [up(SC.lShift)] + tap(SC.tab))
        // Arrows move in the switcher (no ⌘← rule while it is open).
        h.type(K.left)
        #expect(h.take() == tap(SC.left))
        h.release(.lCmd)
        #expect(h.take() == [up(SC.lAlt)])
    }

    @Test func commandShiftTabStartsTheSwitcherBackwards() {
        var h = Harness()
        h.press(.lCmd)
        h.press(.lShift)
        h.type(K.tab)
        #expect(h.take() == [down(SC.lAlt), down(SC.lShift)] + tap(SC.tab))
        h.release(.lShift)
        h.release(.lCmd)
        #expect(h.take() == [up(SC.lShift), up(SC.lAlt)])
    }

    @Test func controlIsForwardedImmediately() {
        var h = Harness()
        h.press(.rCtrl)
        #expect(h.take() == [down(SC.rCtrl)])
        h.type(K.c)
        h.release(.rCtrl)
        #expect(h.take() == tap(SC.c) + [up(SC.rCtrl)])
    }

    @Test func pointerTurnsCommandIntoCtrlAndCancelsTheWinTap() {
        var h = Harness()
        h.press(.lCmd)
        h.pointer()
        #expect(h.take() == [down(SC.lCtrl)])
        h.release(.lCmd)
        #expect(h.take() == [up(SC.lCtrl)])
    }

    @Test func pointerWithShiftAndCommandIsCtrlShiftClick() {
        var h = Harness()
        h.press(.lCmd)
        h.press(.lShift)
        h.pointer()
        #expect(h.take() == [down(SC.lCtrl), down(SC.lShift)])
        h.release(.lShift)
        h.release(.lCmd)
        #expect(h.take() == [up(SC.lShift), up(SC.lCtrl)])
    }
}
