# R2 Website, README, screenshots – Worklog

Agent: R2. Owns only `site/**`, `.github/workflows/pages.yml`, `README.md` and this worklog. R1 (parallel) renames
Sprung → Weitblick Remote, builds the icon and the release packaging. No commits, no push, Pages not enabled here.
Test VM only (10.211.55.9, VM lock for logons), temp stores only, never the general pasteboard, never focus.

## Status

- [x] 1 Read spec + worklogs (m1–m5), KeyboardEngine defaults (ShortcutRule.defaults, PhysicalKeyMap, OptionCharacterPolicy)
- [x] 2 Site (English only, Marc 2026-10-07): site/index.html, assets/css/site.css, assets/js/site.js (lightbox, copy)
- [x] 3 .github/workflows/pages.yml (checkout v7, configure-pages v6, upload-pages-artifact v5, deploy-pages v5)
- [x] 4 README.md (English)
- [x] 5 Local preview + headless screenshots (desktop/mobile, light/dark), iterate
- [x] 6 Wait for `ENGLISH UI DONE` (first line of docs/worklog/r3-english.md), build, app screenshots
- [x] 7 Final screenshots into site + README, icon exports from R1, re-check

Assets: site/assets/screenshots/* are the final English-UI captures (raw captures in build/r2/final, gitignored);
site/assets/img/* are R1's exports from design/icon/export plus og.png (1200x630, rendered by /tmp/r2-tools/og.mjs).

Tools (throwaway, outside the repo): /tmp/r2-tools/shot.sh (PNG → webp 800/1600 + png), /tmp/r2-tools/snap.mjs
(headless_shell from the Playwright cache, desktop 1440 + mobile 390, light + dark). Local server:
`/usr/bin/python3 -m http.server 8765 --bind 127.0.0.1` in site/.

## Log

### 2026-10-07 – Start
- Read SPEC.md and worklogs m1, m2, m3, m4a, m4b, m5. Background watcher waits for `RENAME DONE`.

### 2026-10-07 – Plan change from Marc (via coordinator)
- English only: no site/de/, no language switch, README English. Say "English and German UI".
- Screenshots in the English UI: wait for `ENGLISH UI DONE` in docs/worklog/r3-english.md (not `RENAME DONE`).
  Background watcher started.
- Demo connection names in English (Office PC, Workshop, Accounting, Server (RDP), Mac mini (VNC)).

### 2026-10-07 – Site, workflow, README written; first visual pass
- First headless pass: fixed tagline orphan (text-wrap balance), notice pill spacing, hero shadow cut by
  overflow hidden (now overflow-x clip), install column squeezed by the long xattr line (min-width 0), nested
  quotes in step 3, chips instead of kbd for non-keys, compact feature cards on mobile.

### 2026-10-07 16:45 – Screenshot pipeline rehearsed (German UI build, results not used)
- Demo data: /tmp/r2-tools/make-demo.mjs → build/r2/demo/{overview,session}/connections.json + build/r2/demo/jump
  (synthetic .jump files, *.example / 192.0.2.x; the session store maps "Office PC" to the test VM and "Workshop"
  to the unreachable dummy 10.211.55.250). Always pass `--jump-profile build/r2/demo/no-profile.plist`: without it
  the import preview reads Marc's real Jump input profile (first rehearsal did; only counts shown, not kept).
- App copy: /tmp/r2-tools/make-app-copy.sh → build/r2/app (bundle id nrw.neuhaus.weitblick-remote.r2shots, ad hoc,
  no hardened runtime: an ad-hoc main binary with hardened runtime cannot load the ad-hoc debug.dylib). Window
  frames go to the r2shots defaults domain, never the real one. A first re-sign attempt crashed the copy and
  opened a "Problem Reporter" window on Marc's screen; closed it (killed that Problem Reporter process).
- Launched directly (exec, not `open`): not activated (frontmost app checked), and network access is attributed
  to the calling tool. Via LaunchServices the renamed app fails at once with hostUnreachable
  (ERRCONNECT_CONNECT_FAILED): it has no Local Network permission yet (new bundle id). Marc will get the macOS
  Local Network prompt on his first real connection; that is expected.
- VM (under the VM lock): /tmp/r2-tools/vm-shot.sh. Desktop icons via Explorer's own toggle (WM_COMMAND 0x7402,
  run as scheduled task in the user's session); registry HideIcons + Explorer restart does NOT work (Explorer
  writes its own state back). Explorer only answers while the session is connected, so restore runs before the
  app disconnects. Widgets button (local weather) hidden via HKLM\SOFTWARE\Policies\Microsoft\Dsh
  AllowNewsAndInterests=0, removed again. Notepad note in German (Windows is German), file without .txt extension
  (spell check squiggles on .txt). The "Windows aktivieren" watermark is always on top: Notepad is placed so it
  sits on Notepad's plain white text area, then it is painted over in the final image.
- Incident: one restore restarted Explorer right before R1's e2e took the lock → R1 run 1 "Notepad did not
  start". Told R1. Restore now waits 8 s before releasing the lock.
- R1's e2e (printers on) creates ~/Library/Application Support/Weitblick Remote/FreeRDP/printers (16:33); my
  runs only remove that folder when empty.
- Site icons switched to R1's exports (design/icon/export).

### 2026-10-07 17:30 – VM pipeline final, desktop restored
- Icon toggle fixed: PowerShell passes `$null` to a string P/Invoke parameter as "" → FindWindowEx found no
  Progman; title parameter is IntPtr now. Restore verified: icons visible again, HideIcons 0, Dsh policy gone,
  C:\weitblick-shot removed, no scheduled tasks left. (The test user's icons were hidden from 16:33 to 17:27
  because of the earlier broken restore; R1's e2e runs in that window were not affected by icons.)
- Notepad note: no file extension and key names with spaces ("Strg + C") → no spell-check squiggles.
- /tmp/r2-tools/retouch.sh paints the "Windows aktivieren" watermark out (bounding box of non-background pixels
  in the lower right of Notepad's plain text area, filled with the sampled text-area color).
- /tmp/r2-tools/shoot-local.sh (overview / editor / import, no VM) and og.mjs (1200x630 social image) ready.
- An App Data TCC prompt for "T3 Code (Marc).app" (16:58, frontmost on Marc's screen) is not from my scripts
  (nothing of mine ran at 16:58); left for Marc.
- Waiting for `ENGLISH UI DONE` (R3 is in progress: editor page raw values are now `general`, `keyboard`, …).

### 2026-10-07 17:58 – English screenshots
- R3 marked ENGLISH UI DONE (build 17:35). App copy re-made from it; launched with `-AppleLanguages "(en)"`
  (this Mac is German). Overview autosave name is now "Overview", editor page `keyboard`.
- Captured (build/r2/final): overview, editor keyboard page, Jump import preview (synthetic folder, no profile) in
  light and dark; session light (tabs Overview | Workshop | Office PC, Notepad note, taskbar). Session dark had
  no taskbar (Explorer restart not finished): re-run with 15 s wait queued behind an e2e holding the VM lock.
- Session menu (item 5): skipped. Opening an NSMenu needs a real click or a debug hook the app does not have.
- All images checked: only *.example / 192.0.2.x / test-VM data, no Mac desktop files, no watermark (painted
  out), no weather widget, no customer names.
- Site uses the real screenshots; gallery dims 1600x1367, hero 1600x1122; og.png added.

### 2026-10-07 18:05 – Done
- Session dark re-captured with taskbar (15 s Explorer wait); both session shots retouched (watermark).
- Final site check (headless, build/evidence/r2-site-{desktop,mobile}-{light,dark}.png full page, r2-site-top-* first
  viewport, r2-site-lightbox-dark.png): all local asset references resolve, no console errors, lightbox opens the
  dark/light variant and closes on Esc, copy buttons present. site/ is 1.9 MB.
- VM restored after every run (icons visible, HideIcons 0, no Dsh policy, no C:\weitblick-shot, no tasks).
  Mac cleanup: app copy deleted and unregistered from LaunchServices, r2shots defaults domain deleted, local
  server stopped. ~/Library/Application Support/Weitblick Remote/FreeRDP/printers comes from R1's e2e.
- For the orchestrator (not done here): enable Pages with build_type workflow
  (`gh api -X POST repos/mneuhaus/weitblick-remote/pages -f build_type=workflow`, or Settings → Pages → Source:
  GitHub Actions), push; the Pages workflow then deploys site/. Release assets must keep the names
  Weitblick-Remote.dmg / Weitblick-Remote.zip (links use releases/latest/download/…). Optionally set the repo
  homepage to https://mneuhaus.github.io/weitblick-remote/.
- Re-shooting later: /tmp/r2-tools (make-app-copy.sh, make-demo.mjs, shoot-local.sh, vm-shot.sh + vm-lib.sh,
  vm-open.ps1, vm-icons.ps1, retouch.sh, shot.sh, og.mjs, snap.mjs). /tmp is not durable; the steps are described
  in the entries above.

### 2026-10-07 18:10 – Session shots re-shot with English Notepad text (coordinator request)
- Notepad note now English ("Mac shortcuts in Windows", ⌘ → Ctrl lines, "German layout: ⌥L = @ …"), file
  "Mac shortcuts.log": Notepad's spell check is off for .log, so the German spell checker draws no squiggles on
  the English words (the .log file also hides the formatting toolbar). Windows stays German.
- Light and dark captured under the VM lock (build/r2/final2), watermark painted out, taskbar present in both,
  desktop restored (icons visible, HideIcons 0, no Dsh policy, no files/tasks). session-{light,dark}{.png,-1100.webp,
  -2200.webp} and og.png regenerated (same 1600x1122 size, HTML unchanged). README still points at
  site/assets/screenshots/session-light.png (exists). App copy, r2shots defaults and LaunchServices entry removed.
