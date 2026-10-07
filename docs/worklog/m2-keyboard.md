# M2 KeyboardEngine: Worklog

Owner: M2 agent. Scope: only `Packages/KeyboardEngine`. No git commits (orchestrator commits).
Source of truth: `docs/SPEC.md`, section "Tastatur".

## Current state (2026-10-07)

- Done: package, engine, all spec rules, 4 ⌥ strategies, dead keys, Unicode input, Windows-direct
  mode, JSON config, KLID map, UCKeyTranslate provider.
- `swift test` in `Packages/KeyboardEngine`: 103 tests (8 suites) pass, ~4 s, incl. a seeded fuzz test
  (7 configurations x 1500 random sessions) that checks: nothing held after all keys are up, no break
  without make, no modifier pressed twice, Caps Lock in sync, nothing held after focus loss.
- Mutation-checked: removing the idle modifier sync, the Caps mirroring, the repeat-target release or
  the key-up modifier sync each makes tests fail.

## Layout of the package

- `Sources/KeyboardEngine` (no Foundation/AppKit/Carbon):
  `KeyEvent` (+ `ModifierFlags(eventFlags:)`), `RDPKeyAction`, `PhysicalKeyMap` (keyCode -> scancode),
  `Modifiers`, `KeyboardLayoutProvider` (protocol + reverse lookup), `ChordNotation` (`cmd+shift+z`),
  `ShortcutRule` (+ defaults), `KeyboardConfig`, `WindowsKeyboardLayoutID`, `OptionCharacterPolicy`,
  `RemoteKeyboard` (remote key state), `KeyboardEngine` (+ `+Modifiers`, `+Keys`).
- `Sources/KeyboardEngineCarbon`: `UCKeyTranslateLayoutProvider`, `PhysicalKeyboardType(macKeyboardType:)`,
  `WindowsKeyboardLayoutID.current`.
- `Tests/KeyboardEngineTests`: swift-testing, real Apple layouts (German ISO, US ANSI, Swiss German,
  Russian, Osage for surrogate pairs).

## API for M3 (app integration)

```swift
var engine = KeyboardEngine(config: KeyboardConfig, layout: UCKeyTranslateLayoutProvider.current()!)
engine.handle(KeyEvent) -> KeyboardOutput            // .actions, .passToApp (reserved -> AppKit)
engine.isReserved(KeyEvent) -> Bool                  // early check, e.g. in a CGEventTap
engine.prepareForPointerEvent() -> [RDPKeyAction]    // before mouse button down / wheel
engine.focusLost() -> [RDPKeyAction]                 // window resigns key, session switch
engine.focusGained(modifiers: ModifierFlags) -> [RDPKeyAction]  // window becomes key, after connect
engine.reset()                                       // new/reconnected session, sends nothing
engine.apply(KeyboardConfig) -> [RDPKeyAction]       // config change mid-session
engine.layout = newProvider                          // Mac input source changed
KeyEvent(kind: .down/.up/.flagsChanged, keyCode:, modifiers: ModifierFlags(eventFlags: UInt64(nsEvent.modifierFlags.rawValue)),
         isRepeat:, timestamp: nsEvent.timestamp, keyboardType: PhysicalKeyboardType(macKeyboardType: cgEvent kbd type))
WindowsKeyboardLayoutID.current / provider.windowsLayoutID / config.layoutOverride -> FreeRDP_KeyboardLayout
```

Sending the actions with FreeRDP 3.32.1:
- `.scancode(code, extended, down)` -> `freerdp_input_send_keyboard_event_ex(input, down, repeat, MAKE_RDP_SCANCODE(code, extended))`.
  `repeat` = make for a scancode the bridge already has down (typematic; sets KBD_FLAGS_DOWN like mstsc).
- `.unicode(unit, down)` -> `freerdp_input_send_unicode_keyboard_event(input, down ? 0 : KBD_FLAGS_RELEASE, unit)`.
- `.sync(caps, num, scroll)` -> `freerdp_input_send_focus_in_event(input, flags)` (CAPS 0x04, NUM 0x02, SCROLL 0x01).
- `.pause` -> `freerdp_input_send_keyboard_pause_event(input)`.

M3 pitfalls to watch:
- AppKit does not deliver `keyUp:` for keys pressed with ⌘ held to the view; the engine needs every
  key up (else the remote key stays down). Use a local event monitor / `sendEvent` override.
- `UCKeyTranslateLayoutProvider` loading, `.current()` and the dynamic `keyboardType` call TIS/TSM:
  main thread only (TSM aborts on concurrent calls; the parallel test run hit this). Pass the event's
  keyboard type in `KeyEvent.keyboardType` so the engine never asks.
- ⌘⇥, ⌘Space, ⌥⌘Esc and ⌃←/→ need the CGEventTap from the spec to reach the app at all.

## Findings from probing real layout data (this Mac: LMGetKbdType() = 92 = ISO)

- The ISO key swap is NOT in the layout data: German gives `0x0A` = dead `^`/`°` and `0x32` = `<`/`>` for
  ANSI (40), ISO (41) and JIS (42) alike. So the physical mapping depends on the keyboard type: ISO
  `0x0A -> 0x29`, `0x32 -> 0x56`; ANSI/JIS `0x32 -> 0x29`, `0x0A -> 0x56` (as SPEC says).
- German `⌥` layer: `⌥L=@ ⌥E=€ ⌥5=[ ⌥6=] ⌥7=| ⌥8={ ⌥9=} ⌥⇧7=\ ⌥N=dead ~ ⌥U=dead ¨ ⌥S=‚ ⌥Q=« ⌥-=–
  ⌥.=… ⌥^=„ ⌥2=“ ⌥,=∞`, unusual: `⌥F=ƒ ⌥D=∂ ⌥A=å ⌥O=ø ⌥X=≈`. `⌥⇧+` = U+F8FF (Apple logo).
- Non-character keys translate to control characters (arrows U+001C.., Home U+0001, F1 U+0010, keypad
  Clear U+001B), so keys are classified by keyCode, not by translated output.
- Dead keys: `´`+`e` -> `é`; `⌥N`+`n` -> `ñ`; `^`+space -> `^`; `⌥N`+`x` -> `~x`.
- Osage-QWERTY / Adlam produce non-BMP characters (used for the surrogate pair test).

## Decisions (and why)

- **Two targets.** Core without Foundation/AppKit/Carbon, Carbon glue separate: enforces the
  "no AppKit in core" rule at compile time and keeps the core testable with any provider.
- **Pause:** `RDPKeyAction.pause` instead of raw scancodes. FreeRDP has
  `freerdp_input_send_keyboard_pause_event()` = what mstsc sends (Ctrl with E1 flag + NumLock make,
  then both breaks); the E1 prefix can't be expressed with `extended: Bool`. With remote Ctrl held,
  Pause becomes Break (`E0 46`) like on a PC keyboard (so ⌘F15 = Ctrl+Break).
  Pause, NumLock (keypad Clear) and ScrollLock (F14) ignore key repeats (they toggle on every make).
- **Keypad `=`** (Mac only) is sent as Unicode `=`; PC scancode `0x59` is VK_CLEAR on Windows.
- **JIS:** Yen `0x7D`, Ro `0x73`, keypad comma `0x7E`, Kana `E0 F2` (VK_IME_ON), Eisu `E0 F1`
  (VK_IME_OFF), per kbdlayout.info for the Windows JP layouts. Unverified on a JIS target.
- **ContextualMenu** keyCode `0x6E` -> Apps key `E0 5D`. Volume keys -> media scancodes.
- **Modifier model (Mac mode):** ⇧ and ⌃ are forwarded at once while no ⌘/⌥ is held (shift-click,
  ctrl-click). ⌘ and ⌥ send nothing; each key moves the remote modifiers to exactly what it needs
  (releases first, then presses), and releasing ⌘/⌥ (or a key up with no ⌘/⌥ held) moves them back to
  the physical ⇧/⌃ state. Gives: ⌘C⌘V keeps Ctrl down, ⌘C then ⌘← releases Ctrl before Home,
  ⌘⇧Z drops Shift for Ctrl+Y, repeats don't re-send Ctrl, clean release on focus loss.
- **Modifier state is reconciled from every event's flags**, so a lost flagsChanged (focus switch) is
  repaired by the next event. Modifiers detected that way never count as taps.
- **Lone taps:** ⌘ alone -> Win tap, ⌥ alone -> Alt tap (where ⌥ can mean Alt), only if nothing else
  happened and the press was shorter than `modifierTapTimeout` (0.5 s; <= 0 = no limit). An abandoned
  ⌘ chord must not pop the Start menu.
- **Pointer:** `prepareForPointerEvent()` resolves held ⌘ to Ctrl and ⌥ to Alt (if the strategy allows
  Alt) and cancels the tap: ⌘-click = Ctrl-click, ⌥-drag = Alt-drag.
- **Rules first, then ⌥ strategy**, in every strategy (⌥← is Ctrl+← even in "always Alt").
- **Rule keys are layout-aware:** `shift+cmd+z` matches the key that types `z` in the current Mac
  layout (German keyCode 0x10); output `ctrl+y` resolves `y` the same way (German keyCode 0x06 ->
  scancode 2C = VK_Y on German Windows). Letters missing from the layout (Cyrillic) fall back to US
  positions, as Windows does for shortcuts. Same for reserved shortcuts.
- **Rule notation / JSON:** `{"mac": "cmd+left", "windows": ["home"], "keepShift": true}`.
  `keepShift`: also matches with ⇧ and adds Shift to the output. `holdUntilRelease`: output modifiers
  stay down until the trigger's ⌘/⌥ is released, other keys pass through with them (⌘⇥ switcher is
  just a default rule). Single chord with key = held with the Mac key (repeats); sequences and
  modifier-only chords (`win`) are taps; modifier taps never repeat.
- **Smart ⌥:** non-character keys (F-keys, arrows, Tab, Esc, Return, ⌫, nav, keypad) -> Alt chord
  (keypad keeps Alt+numpad codes working). Space -> plain space (no Alt+Space window menu when typing
  `|| ` fast). Dead keys -> local compose. On letter keys the output must be in a curated set (printable
  ASCII, € £ ¥ ¢ ° § ¶ © ® ™ „ “ ” ‚ ‘ ’ « » ‹ › – — … • · ± × ÷ ≠ ≤ ≥ ¬ ¡ ¿ µ ‰ ß), else Alt+letter:
  keeps Alt+A/D/F/H/X/B/O/C/V/W/Z/T/I/P accelerators. On other keys any printable character counts.
- **Jump-Stil:** right ⌥ alone held -> character (any printable), otherwise Alt.
- **Dead keys** (Unicode path): ⌫/Esc cancel a pending accent (as on the Mac); other non-character keys
  type the accent first; ⌘/⌃ chords drop it; dead-key repeats are ignored.
- **Unicode emission** releases Ctrl/Alt/Win first but keeps Shift: Shift doesn't change Unicode input,
  and tapping Shift per character could trigger Windows Sticky Keys. Space stays a scancode.
- **Repeats are re-evaluated** with the current modifiers (mirrors macOS). Same scancode -> one more
  make; changed target (⌘← held, ⌘ released) -> old key released first.
- **Reserved shortcuts** (`cmd+q`, `ctrl+cmd+f`, `ctrl+opt+cmd+*`, `ctrl+opt+shift+cmd+*`) apply in
  both modes; exact modifiers, `*` = any key. Pending taps are cancelled, chord modifiers released.
  In Windows-direct mode a Ctrl tap masks the already-pressed Win/Alt so its release is no Start-menu tap.
- **Caps Lock:** compared on every event with the remote state; a change sends Caps make+break.
  `focusGained` sends `.sync` (NumLock always on, ScrollLock as toggled through F14).

## Proposed SPEC changes (not applied; SPEC is read-only for M2)

- Tastatur/Physische Zuordnung: add "F15 -> Pause über FreeRDPs Pause-Sequenz (wie mstsc), mit Strg ->
  Untbr", "Ziffernblock-= als Unicode", JIS keys as above, "Kontextmenü-Taste -> Apps".
- Mac-Kurzbefehle: "⌘ allein antippen" = kürzer als 0,5 s und ohne andere Taste; ⌥ allein antippen = Alt.
  Regeln gelten vor der ⌥-Strategie. Regel-JSON-Format (above).
- Option-Taste Smart: precise definition above (letter keys curated set, other keys any printable,
  ⌥Leertaste = Leertaste, Ziffernblock = Alt).
- Lokal bleiben: also in "Windows 1:1".

## Open questions for Marc

- Smart ⌥ on letter keys: å ø æ œ ç count as "not useful", so ⌥A = Alt+A. Polish Pro users (ą ę on ⌥)
  would need "Immer Zeichen" or Jump-Stil. OK?
- Lone ⌥ tap -> Alt tap (menu bar / ribbon key tips): wanted, or rather nothing?
- Tap timeout 0.5 s for ⌘ -> Win: Jump has none, I think; keep?

## Next step

M3 integration (other agent). For M2: nothing open except answers to the questions above.

## Entscheidungen Orchestrator (2026-10-07)
- Smart: ⌥A/⌥O usw. → Alt+Buchstabe bleibt so (å/ø braucht Marc nicht; wer es braucht, nimmt "Immer Zeichen" oder Jump-Stil).
- ⌥ allein antippen → Alt-Tipp bleibt (Windows-Standardverhalten für Menüleiste/Ribbon).
- 0,5 s Grenze für ⌘ → Win-Tipp bleibt.
