Working name until 2026-10-07: Sprung

# M4a ConnectionStore

## Scope and state
- Own only `Packages/ConnectionStore` and this worklog. No commits, no network, no changes to Jump's Library files. The explicitly requested dry-run evidence is the sole output outside this scope (`build/evidence/jump-import-report.txt`, ignored by git).
- Read `docs/SPEC.md` first. Package will use Swift 6, macOS 14, Foundation/Security and the sibling KeyboardEngine.
- Read-only schema inspection found 12 local Jump JSON files and two keyed-archive input profiles, Mac (4 mappings) and Windows (14 mappings). No customer values will enter source or synthetic fixtures.
- Dependency coordination sent to KeyboardEngine owner: public chord/config APIs reused, SPEC's cmd+q/brackets expected as built-in defaults.

## Decisions and assumptions
- ConnectionStore will be an actor with explicit load/save and atomic mutations; missing file means an empty store. JSON uses a versioned envelope, lossless NSDate-reference-epoch doubles for dates, injectable URL, migration hook with original-byte backup before migration. ISO-8601/millisecond scaling was rejected because it loses fractional timestamp precision and can turn every re-import into an update. Per-connection schemaVersion also retained.
- Jump preview/apply remains separate; matching by UniqueId, updates retain Sprung UUID and initial import date, caller may select entries. Apply will reject stale previews rather than overwrite concurrent edits.
- Jump `LastConnectedTime` uses Apple's 2001 reference epoch (observed value ~813 million corresponds to 2026), zero means never connected.
- Real DriveMappings keys are DisplayName, LocalPath, Enabled, IsReadOnly, UniqueId. IsReadOnly will be retained as an extra safe flag, not silently made writable.
- AudioPlaybackCode=2 observed for playback-on, tentatively maps local; other codes remain unknown and fall back off, with warnings. Unknown enums/flags are not interpreted and are individually reported: observed ColorDepthCode=2, RdpPerformanceFlags=0/133, ConnectionTypeCode=0, TypeCode=1, OsTypeCode=0/1 (also separate OSTypeCode=0), GestureProfileCode=0. No attempt to infer OS, color depth, transport or performance settings from these. ProtocolTypeCode alone decides RDP/VNC.
- DesktopScaleFactor=0 means automatic (nil); KeyboardLocaleId ignored when automatic detection is true. MatchScreenResolution takes precedence over fixed dimensions, which remain retained for future use.
- Input special key values actually have prefix 0x0200 (not 0x0201 as suggested in the brief) and X11 keysyms in the low 16 bits: observed FF08 Backspace, FF09 Tab, FF51 Left, FF53 Right, FFC1 F4, FFFF Delete. Other standard X11 values can be recognized as inferred, truly unknown values remain unresolved.
- Jump output modifier 240 on cmd+[ / cmd+] is Alt+Meta bits, but SPEC explicitly defines these as Alt+Left/Right. Normalize only those exact compatibility mappings, report this assumption. Do not drop Meta elsewhere.

## Implementation checkpoint
- Implemented model/settings, actor store, backup/migration hook, Keychain service + lock-protected fake, Jump JSON preview/apply/reports, bounded raw keyed-archive graph decoder, input rule classification/conversion, RDP UTF-8/UTF-16LE IO, and a local evidence executable.
- Initial build green. First full test pass found Foundation disallows `.atomic` combined with `.withoutOverwriting`; backup now uses unique UUID name plus atomic write. Real throwaway Keychain round-trip passed and cleanup ran.
- Tests exposed millisecond Date precision loss, fixed by using Foundation's exact reference-epoch Date encoding. They also exposed the brief's special-key-prefix typo, corrected to 0x0200FFxx with decimal witnesses.
- Synthetic suite green: 26 test functions in 5 suites (29 expanded cases), including real throwaway-service Keychain set/update/get/delete with unconditional cleanup.
- Real read-only dry run completed. Current folder has **12 total connections: 11 RDP + 1 VNC**, not 12 RDP as the original SPEC inventory says. Preview creates 12; simulated re-import gives 12 unchanged. No connections attempted, no Jump files/Keychain items modified, preview store not saved.
- Real input archive uses integer NSDictionary keys for shortcut IDs; initial dry run exposed this fixture omission. Decoder now safely normalizes integer keys, and synthetic fixture mirrors them. Two profiles / 18 mappings: Windows 14 all built-in, Mac 4 custom-convertible (reported, not auto-applied).
- Evidence: `build/evidence/jump-import-report.txt` (ignored, local-only). 24 connection warnings = 12 unavailable passwords + 12 tentative AudioPlaybackCode=2 assumptions. Six profile warnings report unsupported mouse/shortcut-switch/app-level flags. Unknown settings listed individually per source file without dumping values.
- Public API handoff sent to main. Full rerun with integer archive-key fixture green (26 functions/29 expanded cases); optimized release build green.
- Verified SHA-256 and modification times of all 13 real source files before/after dry-run execution: unchanged. Verified no preview connections.json was created. Evidence confirmed gitignored. Added package-local .gitignore for .build/.swiftpm so no generated compiler artifacts can enter source control.
- Evidence executable now handles errors without top-level traps or leaking parser details.
- Independent read-only correctness review running. Known data-loss concern fixed: save/CRUD/apply now lazy-load before mutation; replaceAll alone is an explicit replacement. Regression covers fresh actor save/insert/update retaining existing records and refusing to overwrite future-schema files. Suite green at 27 functions/30 expanded cases.
- Added explicit decimal special-key witness regression (33619720/721/793/795/905/967) so a hex-prefix typo cannot hide behind synthetic fixtures again. Stable full gate is green in **both Debug and Release: 28 tests in 5 suites (31 expanded cases)**, including real Keychain cleanup; optimized release build green.
- Final Release-mode dry run also verified all 13 source hashes/mtimes unchanged and no preview store persisted; evidence regenerated with the stable optimized runner.
- Package edits held on reviewer request. Reviewer identity clarified: the second message identity is the forked code-review skill under the named Astra review, not an independent second round.
- Coordinator explicitly ordered the hung review abandoned and current frozen package handed off; review returned no findings. TaskStop was denied by harness ownership, so both review identities were told to stop without edits/spawns. Coordinator will review during M4b integration; no further review rounds.

## Final state
- Implemented all requested package surfaces. Swift 6/macOS 14 package builds in Debug and Release. Debug and Release `swift test`: **28 tests in 5 suites, 31 expanded parameterized cases**, all passing, including isolated real Keychain round-trip and cleanup.
- Read-only real import: **12 total = 11 RDP + 1 VNC**, initial 12 create, simulated second preview 12 unchanged. Two profiles, 18 mappings; Windows 14 match built-ins, Mac 4 custom-convertible, no automatic rule application. 24 connection warnings (12 passwords + 12 audio assumption) and 6 profile warnings.
- Local-only evidence is `/Users/mneuhaus/Workspace/sprung/build/evidence/jump-import-report.txt` (gitignored), no preview store saved. All 13 Jump source hashes and mtimes unchanged. No network calls, no Jump Keychain access, no commits.
- Open: independent review deferred to coordinator/M4b; double-check AudioPlaybackCode=2→local, bracket modifier 240→Alt-only compatibility normalization, X11-keyspace inference for unobserved special keys, and unsupported enum/flag interpretations. Gateway/UI/runtime feature support is intentionally not implemented by this persistence package.


## App-facing integration contract
- `Connection` stores the endpoint plus `display`, `redirection`, `keyboard: KeyboardConfig`, `security`, `advanced`, tags/lastConnected/notes/importSource. No password property. `.vncURL` contains endpoint only.
- `ConnectionStore(fileURL:migration:)` is an actor. Startup: `try await load()`; UI snapshot: `await connections`, `await search(_:sortedBy:)`. CRUD persist atomically before mutating memory. `duplicate` clears import identity/lastConnected, not credentials. One actor per file URL.
- `JumpImporter(directory:).plan(existing:)` returns immutable entries (create/update/unchanged, candidate, previous) plus report. Confirmation: `try await importer.apply(plan,to:store,selectedIDs:)`. nil selects all; empty set selects none; changed baselines cause staleImportPlan.
- `KeychainCredentialStore`/`InMemoryCredentialStore` implement synchronous throwing `get(for:)`, `set(_:for:)`, `delete(for:)`, keyed by Connection UUID.
- `JumpInputProfileImporter(fileURL:).read()` returns profiles with raw mapping flags/keys, classification and optional rule; `customRules` excludes disabled/default/unconvertible entries. `applyingCustomRules(to:)` is explicit opt-in, not automatic profile selection.
- `RDPFile.read(_:)`, `decode(_:name:)`, `encode(_:encoding:)` support requested portable settings. UTF-16LE+BOM is export default; UTF-8 available. Windows drive selectors are retained, never converted into automatic local directory access.






