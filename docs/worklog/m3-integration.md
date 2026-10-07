Working name until 2026-10-07: Sprung

# M3 Integration (Tastatur + Zwischenablage) – Worklog

Agent: M3. Owns everything except `Packages/ConnectionStore` (parallel M4a agent). No commits.
Test VM only (10.211.55.9). Tests use a private named pasteboard, never `.general`.

## Status

- [x] A1 Engine: ⌘Q → Alt+F4 (not reserved), ⌘[ / ⌘] → Alt+← / Alt+→ (M2 added the rules; M3 made
  the bracket rules character-based on the orchestrator's decision). New public `engine.tap(WindowsChord)`
  for the session menu. Dead-key state fix in `UCKeyTranslateLayoutProvider` (see Log). `swift test`: 111 green.
- [x] A2 KeyboardEngine in the app (`Sources/Sprung/Input/SessionKeyboard.swift`), M1 raw pass-through
  (`KeyInputHandling`, `RawKeyInputHandler`, `MacScancodeTable`) deleted.
- [x] A3 Session KLID = `KeyboardConfig.layoutOverride ?? WindowsKeyboardLayoutID.current` (AppDelegate).
- [x] A4 Quit: ⌘Q in a connected session = Alt+F4; menu / ⌘Q elsewhere quits, confirmation if sessions are open.
- [x] A5 System shortcut tap (code + policy unit test; not exercised with real keys, see "Not verified").
- [x] A6 Session menu.
- [x] B Clipboard (cliprdr) both directions: text, HTML, RTF, images (PNG/DIBV5/DIB). App unit tests: 24 green
  (`xcodebuild … -scheme Sprung test`).
- [x] C E2E `scripts/e2e.sh` against the VM: **3 runs × 20 checks, all green** (2026-10-07 13:36–13:41),
  evidence `build/evidence/m3-e2e-20261007-133608/`. Smoke regression after the bridge changes: OK
  (`build/evidence/m3-smoke-regression.log`).

Next step for a fresh agent: nothing open in M3 except the live checks under "Not verified live".

## Where things are

- Bridge: `Sources/SprungBridge/sprung_clipboard.c` (cliprdr callbacks + `sprung_session_clipboard_*`),
  config flag `clipboard`, `sprung_session_send_pause` (Pause has its own call now; (0x46, E0) is a
  normal scancode = Break, which the engine sends for ⌃+Pause).
- SprungKit: `RemoteClipboard` (thread-safe C wrapper + delegate, detached in `RDPSession.close`/deinit),
  `Clipboard/`: `WindowsClipboardFormat`, `WindowsText` (CF_UNICODETEXT), `ClipboardHTML` (CF_HTML),
  `DeviceIndependentBitmap` (CF_DIB 24 bpp over white, CF_DIBV5 32 bpp straight alpha; decoder for
  24/32 bpp, ImageIO for the rest), `ClipboardImage`, `ClipboardFlavor` (format layer), `RemoteDataFetcher`,
  `RemotePasteboardPromise`, `ClipboardSync`.
- App: `Input/SessionKeyboard`, `Input/KeyEvent+AppKit`, `Input/RemoteKeyboard+Actions`,
  `Input/SystemShortcutTap` (+ `SystemShortcutCapture` setting), `Session/SessionWindowController`,
  `App/MainMenu` (`SessionMenu`), `App/AppDelegate`.
- E2E: `Sources/SprungE2E` (`main`, `Scenario`, `KeyboardDriver`, `TestVM`, `SessionScript`, `Pixels`),
  `scripts/e2e.sh`, shared VM console helper `scripts/testvm.sh` (smoke.sh uses it too).
- Unit tests: `Tests/SprungTests/ClipboardFormatTests.swift`, `ClipboardSyncTests.swift` (fetcher,
  offers, capture policy).

## Design decisions

### Keyboard
- One `SessionKeyboard` per session window: engine + `RemoteKeyboard` (the RDPSession). Input comes from a
  local NSEvent monitor (keyDown/keyUp/flagsChanged; sees key-ups under ⌘ and runs before menu key
  equivalents). `passToApp` (⌃⌘F, ⌃⌥⌘…) returns the event to AppKit. Window key/resign → `focusGained`/
  `focusLost` (+ bridge `releaseAllKeys`). Mouse down/wheel → `prepareForPointerEvent` via
  `SessionView.willSendPointerPress`. Layout provider created on the main thread, refreshed on
  `kTISNotifySelectedKeyboardInputSourceChanged` and on focus gain. Keyboard type per event from the CGEvent.
- ⌘Q: no longer reserved, so the monitor sends it to the engine (Alt+F4) while connected. When not
  connected (connecting, connect form) it reaches the menu → `applicationShouldTerminate` asks if session
  windows are open.
- System shortcut tap: CGEventTap at **HID level** (before WindowServer/Dock handle ⌘⇥, ⌘Space, ⌃←/→),
  created only while capturing and destroyed (invalidated) otherwise: capture = connected AND window key
  AND app active AND (setting always, or fullscreen + setting fullScreen). Re-evaluated on key/resign,
  app (de)activation, fullscreen enter/exit, setting change, connect/disconnect, and inside every tap
  callback (passes through and schedules a stop if the condition no longer holds). It runs on the main
  run loop on purpose: if the app hangs, macOS times the tap out (kCGEventTapDisabledByTimeout) instead
  of a background thread swallowing keys system-wide. Reserved shortcuts pass through to the app.
  No permission → `tapCreate` is not even tried, no prompt; the session menu shows one item
  "Allow Accessibility Access for System Shortcuts…" (hidden when trusted or "Never").
- Session menu (no key equivalents): Send Ctrl+Alt+Del, Windows Key, Alt+Tab, Print Screen (engine.tap),
  Keyboard: Mac Shortcuts / Windows 1:1, ⌥ Key (4 strategies), Sync Clipboard (toggle),
  System Shortcuts to Windows (In Full Screen / Always / Never, app-wide UserDefaults `systemShortcutCapture`).
  (Menu names as in the English UI since R3; the German translation keeps the original German names.)
  Mode/strategy apply via `engine.apply` (releases keys first) for this session only.

### Several sessions / window tabs (M4b)
- Everything is per `SessionWindowController` (one NSWindow per session, also as a native tab): its own
  engine, local monitor (only events with `event.window === window`), shortcut tap (consumes only while
  its own window is key; a second controller's tap passes through), and `ClipboardSync`. No app-global
  "the session window" anywhere. Every session announces Mac clipboard changes to its own server while
  the app is active (copy on PC A, paste on PC B works through the Mac pasteboard). ⌃⌥⌘ shortcuts
  (tab switching) are reserved and reach AppKit.

### Clipboard
- Mac → Windows: `checkPasteboard` compares `changeCount` (polled every 0.5 s while the app is active,
  plus on activation and on window key). Announce = each flavor that `offers` the pasteboard types, with
  all its Windows formats (registered ones numbered from 0xC000). Server data request → read the
  pasteboard on main, convert + respond on a serial queue (keeps answer order), > max size → failure.
- Windows → Mac: server format list → `fetcher.reset()` immediately on the channel thread, then on main
  one `NSPasteboardItem` with a lazy `RemotePasteboardPromise` for every Mac type we can produce. Text
  is prefetched in the background (pastes instantly, survives the session: `sessionWillEnd` writes it
  out as plain text if our promise is still on the pasteboard).
- **Text wins over images** when the server offers both (Office copies cells/text with a rendered picture;
  Mac apps would paste the picture). Images from Finder copies (file URL present) are not announced.
- No deadlock: the main thread only ever waits on `RemoteDataFetcher` (NSCondition, bounded 10 s for a
  reading app), which the channel thread signals; the channel thread never waits for main (all delegate
  calls hop with `DispatchQueue.main.async`). One request in flight at a time (answers carry no id);
  an unanswered one blocks the next for at most 15 s; answers after a clipboard change are dropped.
- No echo: our own pasteboard write is remembered (`ownChangeCount`) and never announced back.
- Size limit 128 MB both ways; per-session on/off: `SessionConfiguration.clipboard` (channel loaded or
  not) + runtime toggle `ClipboardSync.isEnabled` in the session menu.
- FreeRDP drops non-initial empty format lists, so when the Mac copies something unsupported the server
  keeps the old announcement; its requests then fail cleanly.
- Files (M5): add a `ClipboardFlavor` for "FileGroupDescriptorW" ↔ file URLs, announce
  `CB_STREAM_FILECLIP_ENABLED` (+ `CB_FILECLIP_NO_FILE_PATHS`, huge files) in
  `sprung_clipboard.c:send_client_capabilities`, and add FileContents request/response to
  `RemoteClipboard` (the bridge answers FileContents requests with FAIL today).

### E2E
- One command: `scripts/e2e.sh [--takeover] [--runs N]` (default 3). Builds, connects as the test user,
  KLID 0x0407, private pasteboard `nrw.neuhaus.sprung.e2e.<pid>`. Keys: `KeyboardDriver` plays a German ISO
  Mac keyboard into the real `KeyboardEngine` with `UCKeyTranslateLayoutProvider(German, type 41)`;
  characters → key presses are derived from the layout itself (incl. dead keys). Win+R via `engine.tap`.
- VM side via `prlctl exec` (SYSTEM): prepare (kill the test user's Notepad/PowerShell, clear Notepad
  TabState/WindowState, write `C:\sprung-e2e\clip.ps1`), read result files. Everything under test goes
  through RDP: `clip.ps1` runs **inside the session** (typed into Win+R) and dumps raw clipboard bytes
  (Win32 GetClipboardData) or sets test content.
- prlctl pitfall: `prlctl exec` hangs on command lines above ~2 KB (1.4 KB fine, 4 KB hangs forever).
  `TestVM.write` sends files in 900-byte chunks; every prlctl call has a 90 s watchdog.
- Evidence: `build/evidence/m3-e2e-<time>/` (e2e.log, run-N/*.png screenshots + transferred files,
  oslog.txt with the `nrw.neuhaus.sprung` log).

## Log

### 2026-10-07 – Engine: bracket rules by typed character

Orchestrator decision: zoom must keep working on German (⌘+ → Ctrl++, ⌘- → Ctrl+-). M2's ⌘[ / ⌘]
rules resolved to the US key positions (Ü and + on German ISO). New rule flag `typedCharacter`
(JSON `"typedCharacter": true`): the trigger matches when the key, with the held ⌥/⇧ (⌘/⌃ must match
exactly), types the rule's character in the current Mac layout. So ⌘[ on US, ⌘⌥5 / ⌘⌥6 on German.
Rules are checked before the ⌘/⌥ paths, so ⌘⌥5 no longer becomes Ctrl+Alt+5. Decoding rejects the
flag on named keys and together with `keepShift`. Tests: `commandBracketsAreOptionDigitsOnGerman`,
`germanKeysAtUSBracketPositionsStayCtrlShortcuts` (⌘Ü, ⌘+, ⌘-), US ⌘[ / ⌘], JSON round trip + rejects.
Mutation check: dropping the flag from the default makes both German tests fail.

### 2026-10-07 – Integration + clipboard implemented

App, bridge, SprungKit clipboard and E2E tool written as described above; app and tools build, 23 unit
tests green. First E2E attempt hung in VM preparation: prlctl command-line limit (see E2E).

### 2026-10-07 – First live E2E runs: four real findings

1. **Typing speed:** at 4 ms per key event (250/s) the WinUI Notepad lost or misplaced Shift around
   letters and dead keys ("Mac" → "ac", "+" → "*"); the engine output was correct (it reads modifier
   state asynchronously). At 25 ms per event (fast human) all Shift cases pass. The driver uses 25 ms.
2. **Windows' synthesized CF_DIBV5 repeats the three BI_BITFIELDS masks after the 124-byte header**
   (GDI treats them as a color table). Our decoder read 12 bytes early, every pixel shifted by 3. Fix:
   skip 12 bytes when the bytes after a V4/V5 header equal the header's masks. Unit test added.
3. **Engine bug (dead keys):** after composing (⌥N space → "~"), UCKeyTranslate leaves the finished
   dead key in the upper 16 bits of the state (0x50000), low bits 0. The engine took that for a pending
   accent: a following ⌫ was swallowed, arrows typed an extra space, and the next character went out as
   Unicode. Fix in `UCKeyTranslateLayoutProvider.translate`: low 16 bits 0 → report state 0 (a real
   pending accent, e.g. ⌥N then ⌥U, keeps non-zero low bits). Tests `composedAccentLeavesNothingPending`,
   `secondDeadKeyStaysPending` (red before the fix). Engine: 111 tests green.
4. E2E driver bug: its character table typed a bare accent as "accent + ^ key" (which leaves ^
   pending) instead of "accent + space". Second keys of dead-key sequences must not be dead keys.

Also: `prlctl exec` hangs on long command lines (see E2E design); the VM helper treats only
terminating PowerShell errors as failures. The server sends no format list at connect (no clobbering
of the Mac clipboard when a session starts) and does not echo our announcements.

### 2026-10-07 – E2E green, 3 runs

20 checks per run: German stress text typed through the engine (⇧/⌥ characters, Windows- and
engine-composed dead keys, capitals, line break) arrives exactly; ⌘← ⌘→ ⌥← ⌥⌫ ⌘⌫ ⌘Z ⌘⇧Z by their effect
in Notepad; Mac→Windows text with emoji and CRLF/LF/CR; Mac→Windows PNG (exact pixels after
Clipboard.GetImage in the session); Windows→Mac bitmap via CF_DIBV5 as PNG and TIFF (exact pixels);
no echo; Windows→Mac "PNG" with alpha (exact incl. alpha); Mac→Windows CF_HTML (offsets checked
independently on the raw bytes) and RTF (byte-exact); Windows→Mac RTF (byte-exact, bold "Grüße") and
HTML (UTF-8 fragment + charset, plus plain text). One run takes about 1:40 min.

Observed: .NET `SetDataObject(…, copy: true)` makes the server send each format list twice; we
publish twice (harmless, lazy data). Session start sends no server format list.

## Not verified live (Marc should try)

- System shortcut capture with real keys (no OS-level events allowed here): ⌘⇥, ⌘Space, ⌃←/→ in
  fullscreen with Accessibility granted; that the tap stops when switching apps.
- App session menu and ⌘Q confirmation (UI not driven here; the general pasteboard must stay untouched,
  so the app was not connected with clipboard on during development).

## Risks / open

- A Mac app pasting a large image from Windows blocks Sprung's main thread until the data arrives
  (lazy promise, bounded 10 s). Text is prefetched and instant.
- At quit AppKit may ask the promise for still-promised data; fetches end quickly once sessions close.
- Only text survives a closed session on the Mac pasteboard; images/HTML/RTF promised by that session
  are gone with it.
- Windows apps that put text and a picture on the clipboard (Word with an image selected) arrive as
  text only (deliberate, see design).
- CF_DIB 32 bpp alpha: all-zero alpha = opaque, otherwise straight alpha; premultiplied writers would
  look slightly too bright at semi-transparent pixels.
- Very fast synthetic input (250 events/s) loses modifiers in WinUI apps on the server side; human
  typing is far slower, but paste-as-keystrokes features (M5+?) should pace.

## For M4 / M5

- M4: `SessionWindowController(configuration:keyboardConfig:retina:)` takes the per-connection
  `KeyboardConfig` (Jump `KeyboardLocaleId` → `layoutOverride`, `RdpUseUnicodeKeyboard` →
  `unicodeTextInput`, imported input-profile rules → `rules`); AppDelegate still passes defaults.
  `SessionConfiguration.clipboard` ← Jump `ClipboardRedirection`. Create `ClipboardSync` before
  `connect()` (it becomes the channel delegate; the initial format list goes out on channel ready).
  Window tabs: see "Several sessions"; tab switch = resign key = all keys released.
  Quit confirmation counts session windows (`AppDelegate.applicationShouldTerminate`).
- M5 files: see the Files bullet under Clipboard design. Reconnect: a new `RDPSession` needs a new
  `ClipboardSync` (it is bound to one `RemoteClipboard`); call `sessionWillEnd()` on the old one.

## Spec proposals

- Keyboard: "⌘[ / ⌘] by typed character (as in Jump): US ⌘[, German ⌘⌥5 / ⌘⌥6; ⌘Ü and ⌘+ stay
  Ctrl+Ü / Ctrl++ (zoom)."
- Clipboard: "If Windows offers text and an image at the same time (Office), the text wins." and
  "File icons from Finder copies are not transferred as an image."
