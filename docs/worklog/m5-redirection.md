# M5 Redirection, reconnect, callbacks – Worklog

Agent: M5. Owns `Sources/SprungBridge/**`, `Sources/SprungKit/**`, `Sources/SprungE2E/**`, `scripts/e2e.sh`,
`scripts/smoke.sh`, `scripts/build-freerdp.sh`, `vendor/`. M4b (app UI) owns `Sources/Sprung/**` and
`Packages/ConnectionStore`. Test VM only (10.211.55.9), private pasteboards, test folders under `build/`. No commits.
After M4b finished (checkpoint c28388c) M5 also edited `Sources/Sprung/Model/SessionConfiguration+Connection.swift`
(security options) and `Sources/Sprung/Overview/*` (Wake-on-LAN menu item).

## Stand

- [x] 1 Certificate decision + disconnect reasons for the app (VM-verified, smoke end-reason checks)
- [x] 2 Drive redirection (E2E: umlauts, create/rename/delete both ways, 100 MB both ways byte-exact)
- [x] 3 Audio playback local/remote/off (E2E rotates the mode per run); microphone setting wired, never
  switched on in tests (permission dialog)
- [x] 4 Printer redirection: CUPS builds statically, Mac printers reach Windows; the VM lacks the driver
  FreeRDP names, so they are not installed there (event 1111); nothing printed
- [x] 5 Files over the clipboard, both directions, folders recursive, 50 MB, umlauts (E2E); real Finder untested
- [x] 6 Auto-reconnect (E2E: VM adapter unplugged, same Windows session, keyboard + clipboard after)
- [x] 7 Wake-on-LAN helper (unit tests; packet received inside the VM); wired in the overview menu
- [x] 8 smoke green, unit tests 61 green, e2e 3 runs green (`build/evidence/m5-e2e-20261007-154133/`)
- [x] M4b request: NLA on/off, console session, alternate shell, working dir, load-balance info (TLS and
  RDP security without NLA verified against the VM)

Next step for a fresh agent: nothing open in M5; see "Not verified live" and "Risks / open".

## Plan

1. Item 1 first (M4b waits for it), API announced to M4b right away.
2. FreeRDP build: printer (CUPS) + audin channels; SessionConfiguration fields for drives, audio, printers,
   microphone; verify in the VM.
3. WoL, then auto-reconnect (in-place `freerdp_reconnect` on the same context, ARC cookie by FreeRDP).
4. Files over the clipboard (Swift: descriptor codec, local file list, remote file fetcher), E2E round trips.

## Log

### 2026-10-07 14:10 – Item 1: certificate decision + end reasons (done, VM-verified)

- Bridge: `SprungCertificateInfo.hostnameMismatch` (from `VERIFY_CERT_FLAG_MISMATCH`), FreeRDP's `changed`
  dropped (its store is never written, so it meant nothing). A rejected certificate sets a session flag, so the
  end reason is "certificate rejected" instead of FreeRDP's generic TLS error.
- `sprung_disconnect.c` maps FreeRDP's last error (ERRCONNECT_* and the server's ERRINFO_*) to
  `SprungDisconnectReason`; `sprung_session_disconnect` records the user's request (FreeRDP's abort flag is
  reset by reconnects, so it is not enough). `disconnected(reason, code, detail)`.
- SprungKit: `RDPSessionDelegate.session(_:decideAbout:) async -> CertificateDecision` with a default
  (accept once + log); `CertificateGate` blocks the FreeRDP thread on a semaphore (≤ 120 s), trusted
  fingerprints (`SessionConfiguration.trustedCertificateFingerprints`, normalized hex) and fingerprints accepted
  earlier in the session pass at once; `close()`/`disconnect()` answer open questions with reject (no deadlock
  at quit). `ServerCertificate.changed` = the connection trusts other fingerprints.
  `RDPSession.disconnectReason` + German `DisconnectReason.message`, `.needsCredentials`, `.isDeliberate`.
  `RDPSession(configuration:certificatePolicy:)` lost the policy parameter (M4b informed, codes against it).
- Smoke: `EndReasonChecks.swift` (runs after the scenario): delegate rejects → `.certificateRejected` (one
  question, not changed); trusted fingerprint (lower-case) → connects without a question; other trusted
  fingerprint → asked with `changed`; wrong password → `.logonFailed`, no reconnect; port 3390 → `.hostUnreachable`
  (15 s TCP timeout). Disconnects must end with `.requested`, code 0.
  Evidence: `build/evidence/m5/smoke-reasons.log` (SMOKE OK, 2 cycles).
- VM lockout policy: threshold 10 in 10 min; the smoke makes one wrong-password attempt and successful logons
  reset the counter.
- FreeRDP rebuilt with `audin` (mac) and `printer` (CUPS from the SDK, pinned include/lib paths): builds
  cleanly; the app links `-lcups` (project.yml freerdpLink). build-freerdp.sh now checks the rdpsnd/audin mac
  and printer cups subsystem entries in the static table.


### 2026-10-07 14:35 – Items 2–7 implemented, E2E extended (first runs)

- Bridge: `sprung_redirection.c` (audio local/remote/off via AudioPlayback + RemoteConsoleAudio; drives via
  `freerdp_client_add_device_channel("drive", name, path)`, never RedirectDrives (that would add "media *" =
  every drive); printers via RedirectPrinters (CUPS enumerates all Mac printers); microphone via AudioCapture).
- `sprung_session_thread.c`: connect, event loop (also wakes on a stop event), reconnect loop, end report.
  Reconnect only when FreeRDP's own rule says network loss (no server error info, or graphics failure) and
  the session was not stopped: `freerdp_reconnect` on the same context (framebuffer, settings and the ARC
  cookie survive), attempts 1…10 with 1, 2, 4, 8, then 15 s waits (each attempt can take the 15 s TCP connect
  timeout), stopped at once by `sprung_session_disconnect` (stop event + flag, because FreeRDP resets its abort
  flag inside every reconnect). Credential/security failures on an attempt end the loop with that reason;
  giving up on network errors reports `.connectionLost`. Keys are released (bridge bitmap cleared) on loss.
- Clipboard files (MS-RDPECLIP file streams): caps add CB_STREAM_FILECLIP_ENABLED | CB_FILECLIP_NO_FILE_PATHS |
  CB_HUGE_FILE_SUPPORT_ENABLED; FileContents requests/responses both ways with stream ids; `clipboardClosed`
  callback when the channel goes down (reconnect). Swift: `Clipboard/Files/` – `FileGroupDescriptor` (592-byte
  FILEDESCRIPTORW codec, rejects "..", drive and device paths), `LocalFileList` (Finder file URLs, folders
  recursive, .DS_Store skipped, data read from disk per request on the responder queue), `RemoteFileFetcher`
  (1 MB chunks, 4 in flight, short answers re-requested, 30 s stall timeout, reset on clipboard change),
  `RemoteFileTransfer` (one pasteboard item per copied top-level file/folder with a lazy `public.file-url`;
  reading it downloads that subtree into $TMPDIR/Sprung-Clipboard/<uuid>/, removed 10 min after the pasteboard
  moved on, stale folders purged after a day), `ClipboardFiles` (glue for ClipboardSync). Limit
  `ClipboardSync(maxFileTransferSize:)`, default 2 GiB per copy. ClipboardSync resets on channel close and
  re-announces when the channel is ready again (reconnect).
- `WakeOnLAN.wake(_:broadcastAddresses:port:)` (+ MAC parser, magic packet), unit tests over loopback.
- E2E (`Sources/SprungE2E`): `FileScript` (files.ps1 in the session: drive, paste via Shell
  `InvokeVerb('paste')`, copy-files via CF_HDROP, play-sound with an inaudible WAV, printers), `TestFiles`
  (manifests with SHA-256), steps in `RedirectionSteps`, `FileClipboardSteps`, `ReconnectSteps`. FreeRDP logs to
  `<evidence>/freerdp.log` (WLog file appender, rdpsnd at DEBUG) so the audio check can count wave PDUs.
  e2e.sh: evidence `build/evidence/m5-e2e-<time>/`, trap that plugs the VM adapter back in, `--no-build`.
- Found: a parallel `scripts/build.sh` copies `build/sprung-e2e` over the running binary → macOS SIGKILLs the
  test ("Code Signature Invalid", crash report sprung-e2e-2026-10-07-142841.ips). smoke.sh and e2e.sh now run a
  private copy from a temp dir.
- Unit tests written (FileGroupDescriptor, LocalFileList, RemoteFileFetcher incl. shuffled/short answers,
  CertificateGate, WakeOnLAN); not run yet because the app target (M4b, mid-edit) does not compile and the
  test scheme builds it.


### 2026-10-07 14:45 – First green full E2E run (36/36), fixes

- Run `build/evidence/m5-e2e-20261007-143744/`: drives (umlauts, create/rename/delete both ways, 100 MB both
  ways byte-exact; Mac → Windows 59.9 MB/s, Windows → Mac 13.6 MB/s), printers, audio (11 wave PDUs to the mac
  backend), files Mac → Windows (8 entries incl. 50 MB, folders, empty file/folder, umlauts; 1.7 s) and
  Windows → Mac (3 items, 50 MB, 3.5 s ≈ 14.6 MB/s), reconnect (loss noticed after 10.7 s, back 0.5 s after the
  adapter returned, same Notepad PID, typing + clipboard work).
- Fixes from the runs: the reconnect typing text had "✓" (not typeable on German); the printer check accepts
  Windows' event 1111 "driver unknown" (see Item 4); `RemoteFileFetcher` shrank its chunk to the size of a
  file's last short piece (a 1 MB+1 file made every following request tiny) → now the largest answer seen;
  "server file list unreadable" was logged when Windows announced twice (fetch cancelled) → only logged when
  the clipboard did not change meanwhile.
- Earlier run (`m5-e2e-20261007-142931`) measured Windows → Mac drive copy at 1.4 MB/s once (69.9 s for 100 MB),
  13.6 MB/s in the next run; not reproduced since (see Risks).

### 2026-10-07 15:25 – Resumed after the T3 restart (checkpoint c28388c)

- Unit tests: `xcodebuild … -scheme Sprung test` 61 green (incl. FileGroupDescriptor, LocalFileList,
  RemoteFileFetcher with shuffled and short answers, CertificateGate, WakeOnLAN, new mapping test).
- App name: no user-visible "Sprung" in SprungKit; the on-disk folder names come from
  `AppIdentity.supportFolderName` (SprungKit: default FreeRDP state dir, clipboard temp folder) and
  `ConnectionStore.applicationSupportFolderName` (the app's store; the app maps its FreeRDP dir from it). Windows
  sees the Mac's computer name as client name (FreeRDP default), never the app name.
- M4b request: `SessionConfiguration.nla` (default true), `consoleSession`, `alternateShell`,
  `workingDirectory`, `loadBalanceInfo`; bridge `sprung_settings.c` (moved out of sprung_session.c):
  NLA off = no HYBRID and no HYBRID_EX (FreeRDP's ExtSecurity, which alone kept NLA on in the first try),
  TLS and standard RDP security always offered; TLS ≥ 1.0 with OpenSSL security level 0 for old Windows
  (FreeRDP default would be TLS 1.2 / level 2). Mapped in `SessionConfiguration+Connection.swift`.
  New end reason `.nlaRequired` ("Der Server verlangt … NLA …") for HYBRID_REQUIRED_BY_SERVER.
- NLA off, VM-verified (`build/evidence/m5/nla-off/`): against the VM as configured (NLA required) the session
  ends with `.nlaRequired` (now part of the smoke end-reason checks). With UserAuthentication = 0 set
  temporarily (restored to 1 / SecurityLayer 2 by a trap, checked): TLS negotiated (`[SSL]`), autologon
  ("Willkommen", `smoke-fresh-logon.png`, then desktop + resize, SMOKE OK); with SecurityLayer 0 standard RDP
  security negotiated (`[RDP]`), desktop + resize (`smoke-rdp-security.png`, SMOKE OK). Not verified: TLS 1.0
  (the VM speaks TLS 1.2/1.3; changing Schannel would risk the VM's RDP).
- Found on the way: reconnecting without NLA to a Windows session that was created by an NLA logon hung at
  "Bitte warten" for > 90 s (session active on the server, no logon notification); a fresh logon and a session
  created without NLA work. Logged as risk, not a Sprung bug as far as visible.
- `smoke.sh --no-nla` (for a VM that allows it); the smoke now waits up to 90 s for a non-black desktop
  (Windows logs on inside the session without NLA).
- E2E rotates the audio mode per run: run 1 local (mac backend + wave PDUs), run 2 remote, run 3 off (no mac
  backend, no wave PDUs).


### 2026-10-07 15:55 – Final runs

- WoL inside the VM: 5 packets for the fake MAC 02:00:00:5E:00:01 to 10.211.55.255:9; a listener in the VM
  (temporary firewall rule, removed, checked) received 102 bytes from 10.211.55.2 with the right content; the
  Mac's own broadcast copy on bridge109 too (`build/evidence/m5/wol/wol-evidence.txt`).
- Smoke: `build/evidence/m5/smoke-final.log` (scenario, end reasons incl. `.nlaRequired`, 3 cycles) OK.
- E2E 3 runs: first attempt (`m5-e2e-20261007-152727`) run 1 had 2 failures, runs 2–3 green. Causes: I ran
  `scripts/build.sh` while run 1 typed (the VM shares the Mac's CPU; WinUI Notepad lost "dre" of "drei"),
  and the Mac's load average was ≈ 40 from other projects' ffmpeg jobs; plus a test race: .NET's
  `SetDataObject(copy: true)` announces twice 2 ms apart and the second publication replaced the first while
  the test read `.string`. The E2E now waits until the server clipboard is quiet for 0.5 s. Second attempt
  `build/evidence/m5-e2e-20261007-154133/`: 36/36, 35/35, 35/35 – E2E OK (≈ 3.7 min per run).
- Windows → Mac throughput follows the host load: drive 3.7 / 5.2 / 12.3 MB/s, files 6.1 / 2.9 / 11.8 MB/s
  (load average 20–30 → 11); Mac → Windows drive 39–66 MB/s. Do not build while the E2E runs.
- Unit tests 61 green (`build/evidence/m5/unit-tests.log`).

## For M4b

SprungKit API (all main actor unless noted):

- **Certificates:** implement `RDPSessionDelegate.session(_:decideAbout:) async -> CertificateDecision`
  (`.acceptOnce`, `.acceptPermanently`, `.reject`). Asked only for certificates without a valid chain that
  are not in `SessionConfiguration.trustedCertificateFingerprints` and were not accepted earlier in this
  session (reconnects). The connection waits at most `RDPSession.certificateDecisionTimeout` (120 s);
  `disconnect()`/`close()` answer an open question with reject. `ServerCertificate`: host, port, commonName,
  subject, issuer, `fingerprint` (SHA-256, uppercase colon hex), `hostnameMismatch`, `changed` (the connection
  trusts other fingerprints). `.acceptPermanently` = store the fingerprint yourself; nothing is stored by
  SprungKit/FreeRDP. Default implementation (delegate without the method): accept once + log.
- **End reasons:** `.disconnected(code:message:)` – `message` is German; `session.disconnectReason` tells why:
  `.requested`, `.hostUnreachable`, `.logonFailed`, `.missingCredentials`, `.accountLocked`,
  `.accountRestricted`, `.passwordExpired`, `.accessDenied`, `.certificateRejected`,
  `.securityNegotiationFailed`, `.nlaRequired`, `.serverEnded`, `.takenOver`, `.loggedOff`, `.timeout`, `.connectionLost`,
  `.other`. `reason.needsCredentials` → ask for the password and connect again; `reason.isDeliberate` →
  close quietly (Jump closes the tab when the user logs off in Windows).
- **Reconnect:** `SessionConfiguration.autoReconnect` (default true). Events `.reconnecting(attempt:)` (state
  `.reconnecting`; release local keys, show "Wiederverbinden … (Versuch n)") and `.reconnected` (state
  `.connected`; send `focusGained()`/sync if the window is key). Same `RDPSession`, framebuffer and
  `ClipboardSync`; no new objects needed. After 10 failed attempts `.disconnected` with `.connectionLost`.
  `disconnect()` stops a reconnect at once.
- **Redirection:** `SessionConfiguration.audio: AudioPlayback` (`.local`, `.remote`, `.off`), `microphone`
  (default false; the app has `NSMicrophoneUsageDescription` and the audio-input entitlement), `printers`
  (default false; Jump: on), `drives: [SharedDrive]` (`SharedDrive(name:localPath:)`, read-only
  not supported by FreeRDP's drive channel; missing folders are skipped by FreeRDP with a warning).
- **Files over the clipboard:** nothing to do in the app; `ClipboardSync` handles them.
  `ClipboardSync(remote:pasteboard:maxDataSize:maxFileTransferSize:)` (default 2 GiB per copy). Pasting
  files from Windows into Finder downloads them while Finder waits for the file URL (Sprung's main thread is
  busy for that time; see Risks).
- **Wake-on-LAN:** `try WakeOnLAN.wake(connection.advanced.wakeOnLANMACAddresses)` (limited broadcast
  255.255.255.255, port 9); pass `broadcastAddresses:` (e.g. "192.168.1.255") for other subnets.
  `WakeOnLAN.macAddress(_:)` validates input for the editor.
- **Security options (M4b request):** `SessionConfiguration.nla` (default true; `Connection.security.disableNLA`),
  `consoleSession`, `alternateShell`, `workingDirectory`, `loadBalanceInfo` – mapped in
  `SessionConfiguration+Connection.swift` (test `testLegacyAndSessionOptions`). NLA off against a server that
  requires it ends with `.nlaRequired`. Without NLA a wrong password is not reported as `.logonFailed`: the
  session connects and Windows shows its own logon screen.
- **Wake-on-LAN** is wired as "Aufwecken (Wake-on-LAN)" in the overview's context menu (only for connections
  with MAC addresses), German error texts in `OverviewWindowController.describe`.

## Not verified live (Marc should try)

- Pasting files from Windows into the real Finder (⌘V in a Finder window; drag and drop between the
  session and Finder is not implemented): the E2E reads the lazy `public.file-url` from a private
  pasteboard the way Finder does, but the general pasteboard and Finder were off-limits here. Same
  for copying files in Finder and pasting in Explorer.
- Hearing audio on the Mac (E2E only proves wave PDUs reach the macOS backend) and that "Auf dem
  entfernten PC" / "Aus" behave as expected on a real PC (E2E: no audio data reaches the Mac).
- Microphone: never switched on in tests (it would show the macOS permission dialog). FreeRDP's audin asks
  for microphone access when the channel loads, i.e. at connect time of a connection with "Mikrofon" on.
- Printing a page (never done: the printers are Marc's real ones). On the VM the printers reach Windows but
  are not installed (driver "Microsoft Print to PDF" missing on this ARM VM, event 1111).
- Reconnect after the Mac slept, after a Wi-Fi change and with a VPN; E2E only unplugs the VM's adapter.
- NLA off against a real Windows 7 / IoT target (TLS 1.0); the VM speaks TLS 1.2/1.3 only.
- "Aufwecken (Wake-on-LAN)" against a real sleeping PC (VM test: packet received inside the VM).
- Console session, alternate shell and load-balance info (wired, not exercised: the VM has no broker and
  Marc's connections do not use them).

## Risks / open

- **Main thread waits while a Windows file is pasted into Finder.** Finder asks Sprung for the file URL and
  Sprung downloads the file before answering (no deadlock: the channel thread feeds the download directly).
  Measured ≈ 15 MB/s on the VM, so 1 GB freezes the session window for about a minute and there is no
  progress UI. Options: prefetch small copies when they are announced, or an `NSFilePromiseProvider`-based
  drag source with progress (M6).
- Clipboard locking (CB_CAN_LOCK_CLIPDATA) is not used: if Windows' clipboard changes while the Mac is still
  pasting a copy, that paste fails (the download is cancelled cleanly).
- Drive copy Windows → Mac was once 1.4 MB/s (69.9 s for 100 MB) instead of the usual 13–14 MB/s; not
  reproduced. Mac → Windows 35–60 MB/s.
- Reconnect notices a dead connection after ≈ 11 s (FreeRDP's TCP keepalive 5 s + 3 × 2 s); 10 attempts with
  1, 2, 4, 8, 15… s waits plus up to 15 s connect timeout each, so it gives up after roughly 3–4 minutes.
- Without NLA, reconnecting to a Windows session that an NLA logon created hung at "Bitte warten" (> 90 s)
  on the VM; fresh logons without NLA and sessions created without NLA work.
- TLS 1.0 and OpenSSL security level 0 are allowed for every connection (needed by old Windows); the client
  still negotiates the best version and pins certificates. Standard RDP security (last fallback) has no server
  certificate, so there is no certificate question at all for such targets (like mstsc).
- Printers: FreeRDP names "Microsoft Print to PDF" as the driver on macOS 14+. Windows without that driver
  (Windows 7, some IoT images, this ARM VM) refuses the printers (event 1111); Easy Print is not supported by
  FreeRDP.
- Ad-hoc signing (1.0): macOS keys the microphone permission (and Accessibility) to the code signature's hash,
  so it is asked again after every update.
- Read-only drive mappings cannot be honoured by FreeRDP's drive channel; the app skips them.

## Spec proposals

- Zwischenablage: „Dateien (auch Ordner, rekursiv) in beide Richtungen; Grenze 2 GB je Kopiervorgang
  (getrennt von den 128 MB für andere Formate). Von Windows eingefügte Dateien werden beim Einfügen in den
  Finder geladen.“
- Sicherheit: „NLA aus = Kompatibilitätsmodus für alte Ziele: TLS (ab 1.0), sonst RDP-Sicherheit; Windows
  fragt dann selbst nach dem Passwort. TLS 1.0 ist für alle Verbindungen erlaubt.“
- Audio: „Wiedergabe lokal / auf dem entfernten PC / aus; Mikrofon standardmäßig aus.“
- Drucker (M6): Druckertreiber pro Verbindung wählbar (z. B. „MS Publisher Imagesetter“ für Windows 7), weil
  Windows ohne „Microsoft Print to PDF“ die Mac-Drucker ablehnt.
- Laufwerke: „schreibgeschützt“ aus Jump wird nicht unterstützt (FreeRDP kann es nicht); solche Freigaben
  entfallen und stehen im Importbericht.
- Wiederverbinden: „automatisch nach Netzabbruch, bis zu 10 Versuche (≈ 3–4 min), danach Fehlermeldung mit
  ‚Erneut verbinden‘.“
