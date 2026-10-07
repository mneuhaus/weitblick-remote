Working name until 2026-10-07: Sprung

# M4b App UI (windows/tabs, connection list, editor, Jump migration, sign-in, TOFU) – Worklog

Agent: M4b. Owns `Sources/Sprung/**` and `Packages/ConnectionStore`. M5 owns SprungBridge/SprungKit/SprungE2E/e2e.sh.
No commits. Test VM only (10.211.55.9) or dummy 10.211.55.250 for failures. Never connect imported customer hosts.
Builds via `scripts/build.sh`; app tests via `lockf -t 1800 /tmp/sprung-build.lock xcodebuild … test`.
VM logons under `lockf -t 3600 /tmp/sprung-testvm.lock`.

## Status

- [x] 0 Plan + worklog
- [x] 1 project.yml: ConnectionStore package, `Sources/Sprung/Support/Info.plist` (.rdp document type, merged
  with the generated keys), SprungTests compiles `Sources/Sprung/Model` (pure, AppKit-free app logic)
- [x] 2 ConnectionStore review + fixes (with tests): see findings below; `swift test` 33 green
- [x] 3 App core in `Sources/Sprung/Model`: LaunchOptions, AppSettings, ConnectionLibrary, mapping, SessionStatus,
  ConnectionDraft, JumpImportFlow, OverviewModel (+ 19 unit tests in 4 suites)
- [x] 4 Windows/tabs: WindowCoordinator, OverviewWindowController, session windows as tabs, tab switching menu
- [x] 5 Overview list (search, sort, context menu, keys), editor sheet (6 pages), settings window
- [x] 6 Session window restructure: per-attempt LiveSession, status/tab indicator, overlay, sign-in sheet, certificate sheet
- [x] 7 Jump import (first start + menu), .rdp import/open/export (code done; live check in 8)
- [x] 8 Visual checks (screenshots), VM runs A+B, real import dry run into build/, .rdp open from Finder
- [x] 9 e2e.sh once (3 runs x 36 checks green, M5's extended suite, evidence `build/evidence/m5-e2e-20261007-144047`)
- [x] 10 Rename prep (coordinator: app becomes "Weitblick Remote"): no user-visible app name in texts except via
  `App/AppInfo.name` (CFBundleDisplayName; menus "About …/Hide …/Quit …", quit alert); Application Support
  folder = `ConnectionStore.applicationSupportFolderName` (store file + FreeRDP state dir via the mapping);
  Keychain service = `KeychainCredentialStore.defaultService`. Modules/targets/bundle id untouched.

Final: `scripts/build.sh` green; `xcodebuild … -scheme Sprung test` 60 green (19 of them M4b); `swift test` in
ConnectionStore 32 green. Nothing open in M4b except the items under "Not verified live".

## Design (planned)

- Native window tabs: overview window and session windows share `tabbingIdentifier`
  `nrw.neuhaus.sprung.main`; sessions are added with `addTabbedWindow` to the overview's tab group (own windows
  when the setting is on). Window menu: Overview ⌃⌥⌘1, sessions ⌃⌥⌘2…9 (by current tab order), previous/next
  ⌃⌥⌘←/→. The keyboard engine reserves `ctrl+opt+cmd+*` → passToApp → menu key equivalents fire.
- `SessionWindowController` keeps window, view, tab status, key monitor and shortcut tap for its lifetime; each
  connection attempt is a `LiveSession` (RDPSession + SessionKeyboard + ClipboardSync + CertificateGate), so a
  retry after sign-in or "Reconnect" happens in the same tab.
- Certificates (M5 API, 2026-10-07): `SessionConfiguration.trustedCertificateFingerprints` pass silently; others
  reach `RDPSessionDelegate.session(_:decideAbout:) async -> CertificateDecision` on main (FreeRDP thread waits,
  120 s timeout). The app shows the sheet and resumes the continuation; closing the window resumes it with
  `.reject`. `.acceptPermanently` → `ConnectionLibrary.trust(fingerprint:for:replacing:)` (replacing when
  `certificate.changed`). My own CertificateGate/SessionEnd drafts were dropped in favour of M5's
  `CertificateGate` + `DisconnectReason` (`needsCredentials`, `isDeliberate`, German `message`).
- Credentials: Keychain (`KeychainCredentialStore`) via `CredentialStore`; a new password is saved only after
  the server accepted it (`.connected`).

## Log

### 2026-10-07 – ConnectionStore review + fixes, project setup, model layer started
- Package fixes (tests added, see findings). project.yml: ConnectionStore package for app + tests, INFOPLIST_FILE.
- M5 announced its SprungKit API (certificate delegate, disconnect reasons, reconnect events, audio/drives/printers/
  microphone/trusted fingerprints). Adapted; patched the old SessionWindowController switch so the tree compiles
  (`scripts/build.sh` green) until the rewrite lands.

### 2026-10-07 – App UI implemented, unit tests green
- Files: `App/` (AppDelegate, MainMenu, DebugHooks), `Model/` (pure, compiled into SprungTests), `Windows/WindowCoordinator`,
  `Overview/` (window+toolbar, SwiftUI list, row), `Editor/` (6 pages), `Import/JumpImportView`, `Session/` (LiveSession,
  overlay, sign-in, certificate, tab status indicator; SessionWindowController rewritten), `Settings/`. M1's ConnectForm deleted.
- `scripts/build.sh` green. Tests: 43 app tests green (19 new) via a temp project spec that excludes M5's WIP
  `WakeOnLANTests.swift` (it did not compile at the time: `bind` ambiguity) – `/tmp/m4b-scripts/apptest.sh`; package 32 green.
- project.yml: `developmentLanguage: de` (German system texts: tab bar, alerts), INFOPLIST_FILE, mic usage string,
  CODE_SIGN_ENTITLEMENTS (`com.apple.security.device.audio-input`, M5: FreeRDP's audin needs it before microphone=true).
- Screenshots (synthetic store `build/m4b/demo/connections.json`, launched with `open -g`, captured per window id):
  `build/m4b/shots/` overview, editor pages, certificate (new/changed), sign-in, delete, settings. Fixed after looking:
  overview started at minimum size (hosting controller), certificate box width + fingerprint in lines of 8,
  `\\tsclient` rendered as markdown (Text(verbatim:)), neutral wording instead of "du".
- How to look: `/tmp/m4b-scripts/launch.sh x --store <file> --jump-dir <dir> --debug-testvm-credentials --debug-show …`
  then `/tmp/m4b-scripts/shoot.sh <pid> <name>` (helpers are throwaway, under /tmp; DebugHooks documents the flags).

### 2026-10-07 – Live checks
- Real Jump first-start dry run: `--store build/m4b/real-dryrun/connections.json`, real Jump folder. Preview: 12 new
  (11 RDP + 1 VNC); `--debug-import-confirm` applied it; report 12 created. Re-import of the same store: 12
  unchanged, nothing preselected, button "All Up to Date". Jump files: SHA-256 and mtimes identical before/after
  (`build/m4b/real-dryrun/jump-{before,after}.txt`). `~/Library/Application Support/Sprung/connections.json` was
  NOT created (only the old `FreeRDP/` folder is there). Shots: `build/m4b/shots/real-import-{preview,report}-*.png`,
  `real-reimport-*.png`, `real-overview-*.png` (contain customer host names: local only, build/ is ignored).
- VM run A (VM lock held; store `build/m4b/vm/connections.json`, Test-VM clipboard OFF so the general pasteboard
  stays untouched, passwords in memory only): tabs Overview | Nicht erreichbar (unreachable dummy) | Test-VM with status marks.
  First Test-VM attempt failed with ERRCONNECT_CONNECT_FAILED (≈20 s after an M5 e2e run had used the VM; the
  RDP listener was briefly not accepting) → overlay "Disconnected / Host unreachable." + "Reconnect".
  "Nicht erreichbar" (no password) → sign-in sheet. Around 30 s someone clicked into the visible test window
  ("Reconnect", then "Always Trust" in the real certificate sheet): the app became active only then
  (my hooks never activate it, see below), the session connected, the VM's SHA-256 fingerprint landed in the store
  and lastConnected was set. So retry-in-tab and TOFU "Always Trust" were exercised by a real click.
- VM run B: saved password deliberately wrong → server rejects → sign-in sheet in the tab with
  "Sign-in failed: wrong user name or password." → `--debug-signin` submits the right one (save on)
  → connected in the same tab. No certificate sheet: the fingerprint trusted in run A is passed to SprungKit.
- Focus: frontmost app checked every 1–3 s with `lsappinfo` during run B, tab switching (`--debug-select-tab`),
  sheets and Finder-open: never Sprung. AppKit logs "ordered front from a non-active application and may order
  beneath the active application's windows".
- `.rdp` via LaunchServices (`open -g -a build/Sprung.app Werkbank.rdp --args --store …`): imported, selected,
  German note about the ignored stored password, nothing connected.
- Fixes from looking: relative date "in 0 Sekunden" (in 0 seconds) → "gerade eben" (just now); sheets' SwiftUI closures captured the sheet
  window strongly (retain cycle per sheet) → `weak var sheet`.

### 2026-10-07 – Final
- Review fix: Delete/Return in the list acted on the raw selection, including rows hidden by the search; now only
  visible selected rows. Import report wording for keyboard profiles. Rename prep (see Status 10).
- M5 fixed WakeOnLANTests (`Darwin.bind`); the shared test command works again (no temp spec needed).
- SprungKit's own default `SessionConfiguration.stateDirectory` still names "Sprung/FreeRDP" (M5 file, used by
  smoke/e2e); the app overrides it from `ConnectionStore.applicationSupportDirectory`.

## Requests to M5

- Read-only drive sharing: `DriveMapping.readOnly` (Jump `IsReadOnly`) has no `SharedDrive` counterpart. The app
  does not share read-only mappings at all (never silently writable). A `readOnly` flag would let it map them.
  (Marc's 11 imported mappings are all writable, so nothing is lost today.)

## ConnectionStore review findings

Fixed (with regression tests):
1. Re-import replaced `trustedCertificateFingerprints` with Jump's (or emptied it): certificates trusted in Sprung
   after the migration would be dropped by "Aus Jump importieren…". Now Jump's fingerprint is added, Sprung's stay.
2. Re-import overwrote `lastConnected` with Jump's (older, or nil for 0): the "last used" order would roll back.
   Now the later of both wins.
3. No backup when an import changes an existing file (updates overwrite local edits once confirmed). `apply` now
   writes `connections.before-import.json` (one rolling copy) before replacing the file.
4. No atomic read-modify-write: small updates (last connected, trusted certificate) had to send a full copy and
   could revert a concurrent edit. New `ConnectionStore.modify(id:_:)` runs inside the actor.
5. UI-facing report texts were English (German app): importer warnings/reasons, `.rdp` warnings and
   `ImportReport.humanReadable` are German now; `JumpImporter.passwordNotice` is a constant so the UI can show it
   once. `duplicate` default name "Kopie" (copy). (R3, later the same day: English UI with these texts as the
   German translation; `humanReadable` is English again, it only feeds the dry-run evidence file.)
6. Search logic only on the actor: `ConnectionStore.filter(_:matching:sortedBy:)` is the same logic, synchronous,
   for the list UI (`search` uses it).

Checked, fine: atomic writes (`.atomic` temp+rename); every mutation lazy-loads first, so a fresh actor never
replaces existing records; an unreadable/future-schema file makes load and every mutation throw (never
overwritten; app shows an error and offers no first-start import); migration backs up the original bytes;
Jump files only read (`Data(contentsOf:)`, directory listing), M4a verified hashes; Keychain errors carry only
OSStatus; items are `WhenUnlockedThisDeviceOnly`, not synchronizable.

Open (not changed):
- `Connection` uses synthesized `Codable`: a field added later without a schema bump makes old files undecodable
  (load fails safely, no data loss). Future fields need defaults in a custom `init(from:)` (as `KeyboardConfig`
  does) or a migration.
- A failing migration hook writes a new UUID-named backup on every launch attempt.
- Keychain items are labelled only by connection UUID (Keychain Access shows no name).

- `SessionConfiguration` has no fields yet for: NLA on/off (`SecuritySettings.disableNLA`, needed for old
  Windows 7/IoT targets per SPEC), console session, alternate shell + working directory, load-balance info. The
  editor shows and stores them; the mapping (`Model/SessionConfiguration+Connection.swift`) maps them once they exist.
- Done by M5 meanwhile (mapped): trusted fingerprints, audio mode, microphone, printers, drives, reconnect events,
  certificate delegate, disconnect reasons.

## Spec proposals

- Windows and tabs: "The overview can be closed while no session runs; Sprung then stays running
  (the Dock icon or ⌃⌥⌘1 brings it back)." (SPEC says ⌘W must not quit; this is how it is implemented.)
- Migration: "Jump's keyboard profiles are summarized in the import report. Marc's "Windows" profile matches
  Sprung's default rules; the 4 custom mappings of the "Mac" profile (Jump's mode without shortcut translation,
  ⌥⇥ → Win+⇥ and others) have no rule equivalent in "Windows 1:1" and are not imported." (SPEC says custom
  mappings are imported as rules; none of Marc's RDP-relevant ones are custom.)
- Drives: "Shares that are read-only in Jump are not shared by Sprung (FreeRDP can only share with write access)."
- Certificates: "For a changed certificate, "Trust New Certificate" replaces the fingerprints trusted so far."

## Not verified live (Marc should try)

- Real key input in a session tab (no OS events allowed here): ⌃⌥⌘←/→ and ⌃⌥⌘1–9 switch tabs from inside a
  connected session (engine reserves `ctrl+opt+cmd+*` → passToApp → Window menu key equivalents); keys are
  released on tab switch (`windowDidResignKey` → `focusLost` + `releaseAllKeys`, M3 code path, unchanged).
- Return / double-click / Delete in the list, context menu, ⌘N, search field typing (UI driven only by hooks here).
- Closing a connected tab: confirmation sheet with "Don’t ask again"; re-enable in Settings.
- Fullscreen (session tab group, start-in-fullscreen): not tried (would switch Spaces).
- Keychain: saving a password from the sign-in sheet into the real login keychain (tests used the in-memory store;
  the package's real-Keychain round trip is unit-tested with a throwaway service).
- "Open sessions in separate windows" (setting) and dragging tabs out/merging windows.
- First start with the real data: quit Sprung, start it, the Jump preview appears (12 connections), "Import 12
  Connections", then connect to one PC: sign-in sheet → certificate sheet ("Always Trust").

## Risks / open

- Imported Jump connections have `UseHIDPIResolution` false → non-Retina sessions (half resolution, scaled). That is
  what Jump did; toggle "Retina" per connection in the editor if text looks soft.
- A blocked certificate question times out after 120 s in SprungKit; the sheet then closes with the session's
  failure overlay.
- Keychain items are named by connection UUID only; deleting a connection deletes its item.
- DebugHooks (`--debug-*`) exist only in DEBUG builds; `--debug-connect` refuses hosts outside 10.211.55.x.
