RENAME DONE

# R1 Release 1.0: rename, icon, versioning, packaging – Worklog

Agent: R1. Owns everything except `site/**`, `.github/workflows/pages.yml` and `README.md` (R2).
No commits, no pushes. Test VM only (10.211.55.9). No focus stealing, no OS input events, no general pasteboard.
Language: English for everything new (Marc, 2026-10-07); UI strings, SPEC.md and old worklogs are translated by R3.

## Status

- [x] 1 Rename Sprung → Weitblick Remote (targets, modules, C symbols, constants, docs). Debug build green,
  `swift test` 111 + 32 green, app tests 61 green (`build/unit-tests.log`).
- [x] 2 App icon: asset catalog AppIcon (all sizes, pixel-grid variants for 16/32 px), exports in design/icon/export
- [x] 3 Version 1.0.0 (build 1), utilities category, copyright, LICENSE, THIRD_PARTY_NOTICES.md, About credits
- [x] 4 Signing: ad-hoc default + optional Local.xcconfig; release.sh, install-local.sh, docs/RELEASING.md
- [x] 5 Verification: swift test 111 + 32, app tests 62, smoke OK, e2e 3 runs green (attempt 4), release DMG check,
  install-local

## Plan

Rename map (mechanical):
- Folders: `Sources/Sprung` → `Sources/WeitblickRemote`, `SprungKit` → `WeitblickKit`, `SprungBridge` →
  `WeitblickBridge`, `SprungSmoke` → `WeitblickSmoke`, `SprungE2E` → `WeitblickE2E`, `Tests/SprungTests` →
  `Tests/WeitblickRemoteTests`.
- Targets: `WeitblickRemote` (product "Weitblick Remote", module `WeitblickRemote`), `WeitblickKit`,
  `WeitblickBridge`, `weitblick-smoke`, `weitblick-e2e`, `WeitblickRemoteTests`; project `WeitblickRemote.xcodeproj`.
- C: `sprung_*` → `wb_*`, `Sprung*` types/enums → `WB*`, `SPRUNG_*` macros → `WB_*`, files `sprung_*.c` → `wb_*.c`,
  header `WeitblickBridge.h`, WLog tag `weitblick.bridge`.
- Constants: bundle id / Keychain service / logger subsystem `nrw.neuhaus.weitblick-remote`, Application Support
  "Weitblick Remote", locks `/tmp/weitblick-{build,testvm}.lock`, env `WEITBLICK_*`, E2E share/VM folder
  `weitblick-e2e`.

## Log

### 2026-10-07 16:00 – Rename
- `git mv` of all folders/files, then one scripted pass (perl) with the map above; remaining words by hand.
- Not purely mechanical (needed for `git grep -i sprung`): the German word "übersprungen" (skipped) in five
  importer warnings and the import report became "nicht übernommen" (not imported) / "ignoriert" (ignored); R3 then
  made them English with German translations;
  the E2E's `TestVM.sessionUser` was the hard-coded VM account name, now it comes from `WEITBLICK_TEST_USER`.
- `.testvm.env` keys renamed to `WEITBLICK_TEST_*` (values untouched).
- `vendor/build/freerdp` had a CMake cache from the old folder path: removed, FreeRDP rebuilt (≈ 20 s).
  `build/DerivedData` and the packages' `.build` removed for the same reason.
- Old leftovers checked and removed (all ours, from test runs): `~/Library/Application Support/Sprung` (only
  empty FreeRDP printer folders), `~/Library/Preferences/nrw.neuhaus.sprung.plist` (window frame, retina flag),
  `$TMPDIR/Sprung-Clipboard`, `$TMPDIR/SprungStoreTests-*`. Keychain: no items under `nrw.neuhaus.sprung` or the
  new service. Nothing exists under "Weitblick Remote" in Application Support.
- `git grep -i sprung`: only the worklogs (historic) and README.md (R2) hit.
- Signing moved to `Config/Signing.xcconfig` (ad-hoc, `#include? "../Local.xcconfig"`); project.yml has no signing
  settings any more (they would override the xcconfig). Verified with `-showBuildSettings`: identity `-` without
  Local.xcconfig, "Apple Development" + team with it.

### 2026-10-07 16:30 – App icon
- Sources: `design/icon/app-icon.svg` (Marc's weitblick-titlebar-color design on Apple's grid: 824 body, radius 185,
  drop shadow, thin light rim; window scaled 0.86 about the center), `app-icon-32.svg` and `app-icon-16.svg`
  (drawn on the pixel grid: 4 px title bar with 2 px lights and two ridges at 32 px; bar, sun and one ridge at 16 px).
  `scripts/render-icon.sh` renders the asset catalog (16@1x from the 16 px variant, 16@2x and 32@1x from the 32 px
  variant, the rest from app-icon.svg) and the website exports (`design/icon/export`: icon-1024/512/256/128,
  favicon-16/32/48, favicon.ico, favicon.svg, apple-touch-icon.png from the full-bleed original).
- Tahoe check (IconServices render via NSWorkspace, `build/evidence/r1-icon-tahoe-*.png`): the legacy icon is
  re-masked to the Tahoe squircle at full size, same footprint as Calculator, no gray box.
- Tried an Icon Composer `AppIcon.icon` (two SVG layers + automatic gradient fill). actool then derives every
  rendition, including the macOS 14/15 fallback and the icns, from the .icon and ignores the appiconset (no
  setting to keep it; `--enable-icon-stack-fallback-generation` has no effect). Its 16/32 pt renders were mushy
  and the glass window looked smaller; not worth it, since the legacy icon is not boxed. Dropped.
- `qlmanage -t` hangs for every app bundle on this Mac (also /System/Applications/Calculator.app; the thumbnail
  agent never answers), works for PNGs. The Finder-icon evidence therefore comes from NSWorkspace.icon(forFile:)
  (`/tmp/r1/wsicon.swift`, the same IconServices image Finder and the Dock use).

### 2026-10-07 16:30 – Version, About, licenses, packaging
- project.yml: MARKETING_VERSION 1.0.0, CURRENT_PROJECT_VERSION 1, `public.app-category.utilities`,
  copyright "© 2026 Marc Neuhaus", `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`, LICENSE and
  THIRD_PARTY_NOTICES.md copied into Resources.
- LICENSE: canonical Apache-2.0 text (sha256 of FreeRDP's copy), appendix line "Copyright 2026 Marc Neuhaus".
- THIRD_PARTY_NOTICES.md: FreeRDP 3.32.1 incl. WinPR (Apache-2.0), OpenSSL 3.6.3 (Apache-2.0, the Homebrew
  libssl.a/libcrypto.a copied into vendor/install), plus the two non-Apache pieces found by checking every file
  in FreeRDP's compile_commands.json for license headers: MD4 by Alexander Peslyak (public domain / cut-down BSD,
  built because of WITH_INTERNAL_MD4) and the CLDR windowsZones table (Unicode License V3, text from
  unicode.org). Link line otherwise: system libcups and Apple frameworks only; Swift packages are ours.
- About: "About Weitblick Remote" ("Über Weitblick Remote" in German) → `WindowCoordinator.showAbout` →
  `AboutPanel` (standard panel, credits = bundled THIRD_PARTY_NOTICES.md + LICENSE as plain text).
- `scripts/release.sh <version>`: guard version == project.yml, build lock, Release build with
  `CODE_SIGNING_ALLOWED=NO`, copy to build/release, sign inside-out ad-hoc with hardened runtime + entitlements
  (no nested code today; the loop covers frameworks/bundles/dylibs/executables), `codesign --verify --strict`,
  DMG (HFS+, UDZO, app + Applications link; mounted with -nobrowse and verified), ZIP (ditto --keepParent),
  SHA256SUMS.txt. No Finder AppleScript for a window layout (it would open Finder windows on Marc's screen).
- `scripts/install-local.sh`: needs Local.xcconfig, refuses while the app runs, Release build signed by Xcode
  with the local identity, checks there is an Authority (not ad-hoc), replaces /Applications/Weitblick Remote.app.
  Never launches it.
- First release run: 34 s; app `flags=0x10002(adhoc,runtime)`, entitlement audio-input only, `spctl` rejected,
  minos 14.0, no non-system dylibs. Homebrew's OpenSSL objects are built for macOS 26 (linker warnings, known since
  M1); every libSystem symbol the binary imports exists on macOS 14 (checked with `nm -u -m`), not run on 14/15.
- Smoke (`build/evidence/r1-smoke.log`): SMOKE OK, 10 cycles. It created an empty
  `~/Library/Application Support/Weitblick Remote/FreeRDP` (WeitblickKit's default state dir, as in M5); removed
  again at the end so Marc's first start sees nothing.

### 2026-10-07 16:45 – Verification
- E2E attempt 1 (`build/evidence/m5-e2e-20261007-163249`, log `build/evidence/r1-e2e.log`): run 1 "Notepad did not
  start" (R2's screenshot script had just restarted Explorer in the test session and released the VM lock in the
  same second; R2 now waits for Explorer), run 2 "timed out after 20 s waiting for server file list" after 31/31
  checks, run 3 35/35. Host load average 20–28 from other projects' ffmpeg jobs (Windows → Mac drive copy only
  2.7 MB/s). Rerun started 16:44.
- Release DMG check: mounted with -nobrowse, app copied to a temp folder, `codesign --verify --strict --deep` OK,
  `spctl -a -vv` "rejected" (ad-hoc, not notarized, as expected). Launched with `open -g -n … --args --store <tmp>
  --jump-dir <empty tmp>`: windows "Übersicht" (Overview) plus the first-start Jump sheet ("Keine Verbindungen
  gefunden", no connections found; the UI was still German then);
  NSRunningApplication: name "Weitblick Remote", bundle id nrw.neuhaus.weitblick-remote, not active (frontmost
  stayed Chrome), icon = the new AppIcon. Evidence `build/evidence/r1-release-overview-window.png`,
  `r1-release-running-icon.png`. Quit with SIGTERM. Nothing new in Application Support from the launch; the
  temp store stayed empty.
- DebugHooks: `--debug-show about` opens the About panel (for screenshots; DEBUG only).
- E2E attempt 2 (`build/evidence/m5-e2e-20261007-164320`, log `r1-e2e-2.log`): runs 1 and 2 green (36/36, 35/35),
  run 3 34/35: "Windows → Mac HTML with plain text" (the HTML fragment check right before it passed; the plain
  text read raced a later server announcement, the race M5 described; load average 27). Same check green in the
  other five runs since the rename. Attempt 3 started 16:57.
- About panel (Debug build, `--debug-show about`): name, "Version 1.0.0 (1)", icon, scrollable notices,
  "© 2026 Marc Neuhaus" (`build/evidence/r1-about-panel.png`). THIRD_PARTY_NOTICES.md paragraphs unwrapped to one
  line each, so they wrap to the panel width.
- E2E attempt 3 (`build/evidence/m5-e2e-20261007-165650`, `r1-e2e-3.log`, load average 27–34): 36/36, 34/35, 35/35;
  again only "Windows → Mac HTML with plain text". os_log shows the two announcements of .NET's
  SetDataObject(copy: true) 1 ms apart, the HTML read succeeds 0.5 s later, the text read fails. Diagnosis:
  ClipboardSync prefetches the text right after the second announcement; when Windows answers that request with
  CB_RESPONSE_FAIL (its clipboard still busy), `RemoteDataFetcher` cached `.failed` for the whole clipboard
  generation, so every later paste of that copy got no text. A real (rare) product bug, more likely under load.
  (Not observed directly for the text format; attempt 4 logged exactly such a refusal for the file list right
  after an announcement, see below.)
- Fix (WeitblickKit `RemoteDataFetcher`): a refused answer (nil data) goes to the waiting fetch only and is not
  cached, the next fetch asks again; oversized data stays a cached failure (`.tooLarge`). Logged as "server
  refused format N" (category clipboard). Unit test `testARefusedFormatIsAskedForAgain`, oversized test extended
  (no second request). E2E failure message now shows the text it got. App tests: the fetcher tests pass; 2
  failures in `ConnectionDraftTests` come from R3's translation in progress (English strings, German asserts).
- E2E attempt 4 started 17:14 (build includes R3's current tree).

### 2026-10-07 17:30 – Final verification
- E2E attempt 4 (`build/evidence/m5-e2e-20261007-171345`, `r1-e2e-4.log`, load average ≈ 25): 36/36, 35/35, 35/35,
  E2E OK. os_log has one "server refused format 49307" (FileGroupDescriptorW) at 17:21:11.840, right after the
  first of two announcements; the second announcement's fetch succeeded, so the step passed. With a refusal on
  the second (final) announcement `ClipboardFiles.receive` does not ask again ("server file list unreadable"),
  which matches attempt 1's "timed out after 20 s waiting for server file list". Open: retry the file list a few
  times while the generation is current (not done here, scope).
- R3's edits to `Sources/WeitblickE2E/Scenario.swift` (shortcut texts) landed during attempt 4 and are not covered
  by it (the binary was built at 17:13).
- After R3's part 1: `swift test` 111 + 32 green, app tests 62 green (incl. the new fetcher test).
- Final `scripts/release.sh 1.0.0` (17:28): the tree now has a ConnectionStore resource bundle (R3's String
  Catalog); the inside-out loop signed it as a nested bundle, `codesign --verify --strict --deep` OK. DMG mounted,
  app copied out, verify OK, `spctl` rejected, launched in the background (`open -g -n`, temp store, empty Jump
  folder): "Übersicht" (the German translation: this Mac runs in German) + Jump sheet, name/icon right, not
  frontmost; quit with SIGTERM; no connections.json.
- Cleanup: VM folder `C:\sprung-e2e` (32 entries, old E2E scratch) removed under the VM lock;
  `~/Library/Application Support/Weitblick Remote` (only empty FreeRDP printer folders from smoke/e2e) removed;
  preferences domain `nrw.neuhaus.weitblick-remote` (window frames from my launches) deleted;
  `~/Library/Developer/Xcode/DerivedData/WeitblickRemote-*` (from my -showBuildSettings) removed.
  Not touched: `nrw.neuhaus.weitblick-remote.r2shots.plist` (R2).
- The VM account itself is still called "sprung" (value of WEITBLICK_TEST_USER in .testvm.env); renaming a
  Windows account was out of scope and nothing tracked names it any more.
- `scripts/install-local.sh` (17:31): installed `/Applications/Weitblick Remote.app` 1.0.0, signed with the
  Local.xcconfig identity (`flags=0x10000(runtime)`, team from Local.xcconfig; Xcode adds get-task-allow for
  development signing). Not launched; no Application Support folder exists afterwards.
- Release artifacts (17:28, tree incl. R3's part 1): Weitblick-Remote.dmg 4,674,801 bytes
  (sha256 e7032bbbc29f25cce911a917f05e1b163f221a7d11e3cd99cd88af162b09df43), Weitblick-Remote.zip 4,347,795 bytes
  (sha256 2be333b51136673f7576566cf706ee457948db3c8ea735b17427f73bd6f0fecd). Rebuild with
  `scripts/release.sh 1.0.0` once R3 is done, before uploading.
