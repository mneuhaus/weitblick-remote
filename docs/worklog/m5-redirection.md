# M5 Redirection, reconnect, callbacks – Worklog

Agent: M5. Owns `Sources/SprungBridge/**`, `Sources/SprungKit/**`, `Sources/SprungE2E/**`, `scripts/e2e.sh`,
`scripts/smoke.sh`, `scripts/build-freerdp.sh`, `vendor/`. M4b (app UI) owns `Sources/Sprung/**` and
`Packages/ConnectionStore`. Test VM only (10.211.55.9), private pasteboards, test folders under `build/`. No commits.

## Stand

- [x] 1 Certificate decision + disconnect reasons for the app
- [ ] 2 Drive redirection
- [ ] 3 Audio playback (local/remote/off), microphone setting
- [ ] 4 Printer redirection (CUPS) – build check
- [ ] 5 Files over the clipboard, both directions
- [ ] 6 Auto-reconnect
- [ ] 7 Wake-on-LAN helper
- [ ] 8 smoke + e2e green, 3 e2e runs

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
  `.securityNegotiationFailed`, `.serverEnded`, `.takenOver`, `.loggedOff`, `.timeout`, `.connectionLost`,
  `.other`. `reason.needsCredentials` → ask for the password and connect again; `reason.isDeliberate` →
  close quietly (Jump closes the tab when the user logs off in Windows).
- **Reconnect:** `SessionConfiguration.autoReconnect` (default true). Events `.reconnecting(attempt:)` (state
  `.reconnecting`; release local keys, show "Wiederverbinden … (Versuch n)") and `.reconnected` (state
  `.connected`; send `focusGained()`/sync if the window is key). Same `RDPSession`, framebuffer and
  `ClipboardSync`; no new objects needed. After 10 failed attempts `.disconnected` with `.connectionLost`.
  `disconnect()` stops a reconnect at once.
- **Redirection:** `SessionConfiguration.audio: AudioPlayback` (`.local`, `.remote`, `.off`), `microphone`
  (default false; needs `NSMicrophoneUsageDescription` + entitlement `com.apple.security.device.audio-input`
  in the app before it may be switched on), `printers` (default false; Jump: on), `drives: [SharedDrive]`
  (`SharedDrive(name:localPath:)`, read-only not supported by FreeRDP's drive channel; missing folders are
  skipped by FreeRDP with a warning).
- **Files over the clipboard:** nothing to do in the app; `ClipboardSync` handles them.
  `ClipboardSync(remote:pasteboard:maxDataSize:maxFileTransferSize:)` (default 2 GiB per copy). Pasting
  files from Windows into Finder downloads them while Finder waits for the file URL (Sprung's main thread is
  busy for that time; see Risks).
- **Wake-on-LAN:** `try WakeOnLAN.wake(connection.advanced.wakeOnLANMACAddresses)` (limited broadcast
  255.255.255.255, port 9); pass `broadcastAddresses:` (e.g. "192.168.1.255") for other subnets.
  `WakeOnLAN.macAddress(_:)` validates input for the editor.

## Not verified live (Marc should try)

## Risks / open

## Spec proposals
