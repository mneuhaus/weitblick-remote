@testable import KeyboardEngine
import Testing

/// ⌥ handling. Expected characters come from the real Apple layouts, not from this file.
struct OptionStrategyTests {
    private func config(_ strategy: KeyboardConfig.OptionStrategy) -> KeyboardConfig {
        var config = KeyboardConfig()
        config.optionStrategy = strategy
        return config
    }

    private func optionText(_ keyCode: UInt16, shift: Bool = false, layout: any KeyboardLayoutProvider = Layouts.german) -> String {
        var state: UInt32 = 0
        return layout.translate(keyCode: keyCode, modifiers: shift ? [.option, .shift] : [.option], deadKeyState: &state)
    }

    /// The German Mac characters a programmer types with ⌥: @ € [ ] | { } and ⌥⇧7 = \.
    @Test(arguments: [K.l, K.e, K.five, 0x16, K.seven, K.eight, K.nine])
    func smartTypesUsefulGermanCharactersAsUnicode(keyCode: UInt16) {
        let expected = optionText(keyCode)
        #expect("@€[]|{}".contains(expected))
        var h = Harness(config: config(.smart))
        h.chord([.lOpt], keyCode)
        #expect(h.take() == text(expected))
    }

    @Test func smartTypesBackslashWithOptionShiftSeven() {
        #expect(optionText(K.seven, shift: true) == "\\")
        var h = Harness(config: config(.smart))
        h.chord([.lShift, .lOpt], K.seven)
        // ⇧ was forwarded before ⌥ and may stay down for Unicode input.
        #expect(h.take() == [down(SC.lShift)] + text("\\") + [up(SC.lShift)])
    }

    /// ⌥F ƒ, ⌥D ∂, ⌥A å, ⌥O ø, ⌥X ≈: no useful character, so Windows gets the Alt accelerator.
    @Test(arguments: [(K.f, SC.f), (K.d, SC.d), (K.a, SC.a), (K.o, SC.o), (K.x, SC.x)])
    func smartSendsAltForUnusualCharactersOnLetterKeys(keyCode: UInt16, scancode: Scancode) {
        #expect(optionText(keyCode).unicodeScalars.allSatisfy { !$0.isASCII })
        var h = Harness(config: config(.smart))
        h.chord([.lOpt], keyCode)
        #expect(h.take() == [down(SC.lAlt)] + tap(scancode) + [up(SC.lAlt)])
    }

    @Test func smartKeepsDigitAndPunctuationCharacters() {
        // ⌥, is ∞ on German: no accelerator to lose on a punctuation key.
        let infinity = optionText(K.comma)
        #expect(infinity == "∞")
        var h = Harness(config: config(.smart))
        h.chord([.lOpt], K.comma)
        #expect(h.take() == text(infinity))
    }

    @Test(arguments: [(K.f4, SC.f4), (K.tab, SC.tab), (K.returnKey, SC.enter), (K.escape, SC.escape), (K.keypad1, SC.keypad1)])
    func optionWithNonCharacterKeysIsAlt(keyCode: UInt16, scancode: Scancode) {
        for strategy in [KeyboardConfig.OptionStrategy.smart, .jumpStyle, .alwaysAlt, .alwaysCharacters] {
            var h = Harness(config: config(strategy))
            h.chord([.rOpt], keyCode)
            #expect(h.take() == [down(SC.lAlt)] + tap(scancode) + [up(SC.lAlt)], "\(strategy)")
        }
    }

    @Test func altCodesOnTheKeypadKeepAltDown() {
        var h = Harness(config: config(.smart))
        h.press(.lOpt)
        h.type(K.keypad1)
        h.type(K.keypad1)
        h.release(.lOpt)
        #expect(h.take() == [down(SC.lAlt)] + tap(SC.keypad1) + tap(SC.keypad1) + [up(SC.lAlt)])
    }

    @Test func smartOptionSpaceIsAPlainSpace() {
        // German ⌥Space is a no-break space; when typing `|| ` with ⌥ still down it must stay a space.
        var h = Harness(config: config(.smart))
        h.press(.lOpt)
        h.type(K.seven)
        h.type(K.space)
        h.release(.lOpt)
        #expect(h.take() == text("|") + tap(SC.space))
    }

    @Test func altAcceleratorThenCharacterReleasesAltBeforeTheCharacter() {
        var h = Harness(config: config(.smart))
        h.press(.lOpt)
        h.type(K.f)
        h.type(K.l)
        h.release(.lOpt)
        #expect(h.take() == [down(SC.lAlt)] + tap(SC.f) + [up(SC.lAlt)] + text("@"))
    }

    @Test func optionAloneTapsAltWhereOptionCanMeanAlt() {
        for (strategy, side, expected) in [
            (KeyboardConfig.OptionStrategy.smart, Mod.lOpt, tap(SC.lAlt)),
            (.alwaysAlt, .rOpt, tap(SC.lAlt)),
            (.jumpStyle, .lOpt, tap(SC.lAlt)),
            (.jumpStyle, .rOpt, []),
            (.alwaysCharacters, .lOpt, []),
        ] {
            var h = Harness(config: config(strategy))
            h.press(side)
            h.release(side)
            #expect(h.take() == expected, "\(strategy) \(side)")
        }
    }

    @Test func pointerWithOptionIsAltClickUnlessOptionOnlyTypesCharacters() {
        var smart = Harness(config: config(.smart))
        smart.press(.lOpt)
        smart.pointer()
        smart.release(.lOpt)
        #expect(smart.take() == [down(SC.lAlt), up(SC.lAlt)])

        var characters = Harness(config: config(.alwaysCharacters))
        characters.press(.lOpt)
        characters.pointer()
        characters.release(.lOpt)
        #expect(characters.take() == [])
    }

    @Test func jumpStyleRightOptionTypesLeftOptionIsAlt() {
        var h = Harness(config: config(.jumpStyle))
        h.chord([.rOpt], K.l)
        #expect(h.take() == text("@"))
        h.chord([.lOpt], K.l)
        #expect(h.take() == [down(SC.lAlt)] + tap(SC.l) + [up(SC.lAlt)])
        // Right ⌥ types whatever the layout gives, also ƒ.
        h.chord([.rOpt], K.f)
        #expect(h.take() == text(optionText(K.f)))
    }

    @Test func alwaysAltNeverTypesCharacters() {
        var h = Harness(config: config(.alwaysAlt))
        h.chord([.rOpt], K.l)
        #expect(h.take() == [down(SC.lAlt)] + tap(SC.l) + [up(SC.lAlt)])
    }

    @Test func alwaysCharactersTypesEverythingPrintable() {
        var h = Harness(config: config(.alwaysCharacters))
        h.chord([.lOpt], K.f)
        #expect(h.take() == text("ƒ"))
        // ⌥⇧+ on German is the Apple logo (private use): Windows can't show it, so Alt+Shift+key.
        #expect(optionText(0x1E, shift: true) == "\u{F8FF}")
        h.chord([.lShift, .lOpt], 0x1E)
        #expect(h.take() == [down(SC.lShift), down(SC.lAlt)] + tap(Scancode(0x1B)) + [up(SC.lAlt), up(SC.lShift)])
    }

    @Test(arguments: [KeyboardConfig.OptionStrategy.smart, .jumpStyle, .alwaysAlt, .alwaysCharacters])
    func rulesComeBeforeTheStrategy(strategy: KeyboardConfig.OptionStrategy) {
        var h = Harness(config: config(strategy))
        h.chord([.lOpt], K.left)
        #expect(h.take() == [down(SC.lCtrl)] + tap(SC.left) + [up(SC.lCtrl)])
        h.chord([.lOpt, .lShift], K.right)
        #expect(h.take() == [down(SC.lCtrl), down(SC.lShift)] + tap(SC.right) + [up(SC.lShift), up(SC.lCtrl)])
    }

    @Test func optionBackspaceRepeatsWithoutResendingCtrl() {
        var h = Harness()
        h.press(.lOpt)
        h.down(K.backspace)
        h.down(K.backspace, isRepeat: true)
        h.down(K.backspace, isRepeat: true)
        h.up(K.backspace)
        h.release(.lOpt)
        #expect(h.take() == [down(SC.lCtrl), down(SC.backspace), down(SC.backspace), down(SC.backspace), up(SC.backspace), up(SC.lCtrl)])
    }

    @Test func optionForwardDeleteIsCtrlDelete() {
        var h = Harness()
        h.chord([.lOpt], K.forwardDelete)
        #expect(h.take() == [down(SC.lCtrl)] + tap(SC.delete) + [up(SC.lCtrl)])
    }

    @Test func usLayoutSmartTypesEszettAndAccentsForGermansOnUS() {
        #expect(optionText(K.s, layout: Layouts.us) == "ß")
        var h = Harness(Layouts.us, config: config(.smart))
        h.chord([.lOpt], K.s)
        #expect(h.take() == text("ß"))
        // ⌥U is the dead diaeresis on US: ⌥U, A -> ä
        h.chord([.lOpt], K.u)
        h.type(K.a)
        #expect(h.take() == text("ä"))
    }

    @Test func controlOptionKeyIsCtrlAlt() {
        var h = Harness()
        h.chord([.lCtrl, .lOpt], K.q)
        #expect(h.take() == [down(SC.lCtrl), down(SC.lAlt)] + tap(SC.q) + [up(SC.lAlt), up(SC.lCtrl)])
    }
}
