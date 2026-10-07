ENGLISH UI DONE

# R3 English: UI in English (German as translation), repo in English – Worklog

Agent: R3. Edits UI strings, catalogs, docs, comments, scripts. Does not touch `site/**`, `README.md`,
`.github/workflows/pages.yml` (R2). No commits, no pushes. Builds only via `scripts/build.sh` and never while
R1's e2e runs (check with `pgrep -f 'T//weitblick-e2e'`: a plain `pgrep -f weitblick-e2e` also matches the
waiting shell itself). Temp stores only; never `~/Library/Application Support/Weitblick Remote/connections.json`.
Test VM not needed. No focus stealing, no OS input events, no general pasteboard.

## Status

- [x] 1 English UI base (developmentLanguage en), String Catalogs (app incl. WeitblickKit, InfoPlist, ConnectionStore), German as "de"
- [x] 2 Build + tests green (app 62, ConnectionStore 32, KeyboardEngine 111), screenshots EN/DE, German-leftover grep
- [x] 3 SPEC.md translated
- [x] 4 Worklogs translated (German parts)
- [x] 5 Comments, script/log messages, test names, design/ in English
- [x] 6 Final umlaut grep reviewed (list below)

## Log

### 2026-10-07 – Start
- Read r1-rename.md, SPEC.md, m4b-ui.md. Screenshot helpers from M4b (`/tmp/m4b-scripts/windows`, `shoot.sh`)
  reused under `/tmp/r3`.

### 2026-10-07 17:10 – English UI strings
- Approach: English text in code; AppKit strings via `String(localized:)`, SwiftUI literals as `LocalizedStringKey`
  (ternaries and `String` parameters turned into `Text`/`LocalizedStringKey` so they are looked up, Markdown-sensitive
  `\\tsclient` text stays a `String`). Catalogs: `Sources/WeitblickRemote/Support/Localizable.xcstrings` (app +
  WeitblickKit's `DisconnectReason`, which is a static library and looks up in the main bundle),
  `Support/InfoPlist.xcstrings` (microphone usage, .rdp document type name),
  `Packages/ConnectionStore/Sources/ConnectionStore/Localizable.xcstrings` (`bundle: .module`, `defaultLocalization: "en"`).
- German values are the old German texts verbatim (translation table `/tmp/r3/de.tsv`, `/tmp/r3/de-store.tsv`;
  `/tmp/r3/make_catalogs.py` writes the catalogs).
- `swift test` (SwiftPM CLI) copies an .xcstrings into the resource bundle without compiling it (checked with a
  scratch package): package tests always see English, even on this German Mac.
- Not localized on purpose: `ImportReport.humanReadable` (dry-run evidence file, English), log messages.
- Editor pages: `Page` raw values are now `general`, `display`, … (`--debug-show editor:<name>:keyboard`).
- project.yml: `developmentLanguage: en`, `SWIFT_EMIT_LOC_STRINGS`, `LOCALIZATION_PREFERS_STRING_CATALOGS`;
  Info.plist `CFBundleLocalizations` en + de, document type "Remote Desktop Connection".
- First build failed in `RemoteDataFetcher.swift` (another agent's edit in progress at 17:12, not mine); retrying.
- R1's unit-test run at 17:13 compiled everything with my changes; 2 failures were German assertions I had missed in
  `ConnectionDraftTests` (fixed). Other test updates: `ConnectionDraftTests`, `ConnectionLibraryTests` ("PC copy"),
  `JumpImportFlowTests` (changed areas; test names "Office"/"Warehouse"), `ConnectionMappingTests`, package tests
  (`Beta copy`, warning substrings).
- Key check against the compiler: `xcrun xcstringstool sync` on copies of both catalogs with the `.stringsdata` of
  that build (`/tmp/r3/synccheck.sh`): 291 app keys and 32 package keys, none missing a German value, none stale,
  and the synced file is byte-identical to the generated one (same formatting as Xcode writes).

### 2026-10-07 17:20 – Part 2 started while R1's e2e runs (no builds meanwhile)
- SPEC.md translated in full (same structure; notes the String Catalogs under Architecture).
- Worklogs: m1-core.md translated in full; German spec proposals/decisions in m2, m3, m4b, m5 translated; quoted
  German UI strings replaced by the English UI names (the German UI still shows the old texts); Windows' German
  messages ("Bitte warten", "Ein anderer Benutzer ist angemeldet") kept as quotes with an English gloss.
- Code: e2e shortcut case names and their ASCII text ("one two three"), `⌘Z = Ctrl+Z` check names, two comments.

### 2026-10-07 17:40 – Part 1 verified, marker set
- Build (`scripts/build.sh`, after R1's e2e ended at 17:25) green. Bundle: `en.lproj` (plural stringsdict) and
  `de.lproj` with `Localizable.strings` + `InfoPlist.strings`, `ConnectionStore_ConnectionStore.bundle/…/de.lproj`;
  Info.plist `CFBundleDevelopmentRegion` en, `CFBundleLocalizations` en, de.
- Plurals: "%lld Jump settings without an equivalent" showed "1 Jump settings" in the first screenshots; it and
  "%lld custom mappings not imported …" now have one/other variations (en + de; the German "1 Jump-Einstellung"
  was wrong before too). Other counts are only shown for 2 or more, or are bare numbers ("3 new").
  Not done: "Keyboard profile “%@”: all %lld mappings …" with exactly 1 mapping (two arguments would need
  substitutions; Jump profiles have many mappings).
- German consistency: "Speichern fehlgeschlagen" → "Sichern fehlgeschlagen" (the app says "sichern" everywhere
  else for saving). The row toggle in the Jump preview got its own key ("Import This Connection" → "Übernehmen")
  so the German stays "Übernehmen" rather than the .rdp panel's "Importieren".
- Tests: app `xcodebuild … test` 62 green (on this German Mac: the test bundle has no catalog, so app strings
  are English there), `swift test` ConnectionStore 32 and KeyboardEngine 111 green.
- Screenshots (`/tmp/r3/shots.sh en|de`: `open -g -n` with `-AppleLanguages (en|de)`, a temp copy of a demo store,
  the synthetic Jump folder `/tmp/r3/jump`, `--jump-profile /nonexistent`, captured per window with
  `screencapture -l`, then SIGTERM): overview, all six editor pages, new connection, certificate (new/changed),
  sign-in, delete alert, settings, Jump preview and report, empty first start; English and German each. Copies in
  `build/evidence/r3-{en,de}-*.png`. Frontmost app checked before/after: never Weitblick Remote.
- Grep: no umlauts and no German words in string literals under Sources/WeitblickRemote, Sources/WeitblickKit,
  Packages/ConnectionStore/Sources outside the catalogs.

### 2026-10-07 17:50 – Part 2 finished
- Worklogs: remaining German UI quotes in m5 ("Auf dem entfernten PC" / "Aus", "Mikrofon", the reconnect
  status) and r1 (German UI it saw, now glossed; long lines reflowed) translated. r2-site.md left to R2.
- Sweeps over Sources, Packages, Tests, scripts, design, project.yml, docs with umlauts, German stop words and
  German UI terms: nothing German left except the hits below. Scripts, the decode script and design/ SVG comments
  were already English.
- My screenshot launches at 17:37 re-created the preferences domain `nrw.neuhaus.weitblick-remote` (only
  "NSWindow Frame Overview") after R1's cleanup; deleted again with `defaults delete`. Application Support has no
  "Weitblick Remote" folder (my launches never connected, temp stores only).
- Not rerun: the VM e2e after renaming its shortcut cases (ASCII texts "one two three" etc. instead of
  "eins zwei drei"; compiled in the 17:37 build). R2 held the VM; the next e2e run covers it.

Remaining `git grep --untracked -nIP '[äöüÄÖÜß]'` hits (outside site/ and README.md), all intentional:
- The two `Localizable.xcstrings` (German translations; InfoPlist.xcstrings has no umlauts).
- KeyboardEngine: the Smart ⌥ character set (`OptionCharacterPolicy.swift`), the ⌘Ü key name in a
  `ShortcutRule.swift` comment, tests for German layout characters (ü, ß, ä via dead keys).
- E2E (`Sources/WeitblickE2E`): the German stress text typed through the engine, umlaut file and folder names for
  drive redirection and file clipboard, umlaut clipboard texts (HTML, RTF, plain, after reconnect).
- App tests: `ClipboardFormatTests` (UTF-16/UTF-8/HTML encoding of "Grüße"/"Größe"), `FileClipboardTests`
  (umlaut paths in file descriptors).
- Worklogs: m2/m3 key and character names (⌘Ü, Ü and +, the ⌥ character set, bold "Grüße" from the e2e RTF),
  r1 (German UI it saw then, glossed), r3 (this log).
