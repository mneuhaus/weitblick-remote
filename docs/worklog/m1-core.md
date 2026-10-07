Working name until 2026-10-07: Sprung

# M1 Core – Worklog

Agent: M1 core (FreeRDP build, bridge, session window, smoke test). M2 (Packages/KeyboardEngine) runs in parallel; `Packages/` is not touched here.

## Status

- [x] `vendor/FreeRDP` as a submodule at tag 3.32.1 (commit bf217a504)
- [x] `scripts/build-freerdp.sh` (static, arm64, 14.0, client only)
- [x] `Sources/SprungBridge` (C) – compiles, smoke green
- [x] `Sources/SprungKit` (Swift wrapper `RDPSession`, shared by the app and the smoke test)
- [x] App `Sources/Sprung` + `project.yml` – builds, Retina/non-Retina/resize/reconnect checked visually
- [x] Smoke test `sprung-smoke` + `scripts/smoke.sh` – green incl. 10 cycles, cursor dump, soak, `leaks`: 0
- [x] `scripts/build.sh`, README.md
- [x] Unit tests `SprungTests` (geometry, scroll sign, cursor scaling), 8/8 green
- [ ] Full screen (⌃⌘F) checked in code only, not visually (Marc was actively using the Mac; full screen would have taken over his Space)
- [ ] Local mouse pointer over the window (NSCursor switching live) not checked, for the same reason; pointer data
  covered by the smoke dump and NSCursor scaling by a unit test
- The submodule pointer is staged (`git add vendor/FreeRDP`, bf217a504), nothing committed.

Next step: check full screen + live cursor when Marc is not at the Mac (`build/Sprung.app --autoconnect`,
⌃⌘F, mouse over a search field → I-beam). Then M3: replace `RawKeyInputHandler` with a KeyboardEngine adapter (same
`KeyInputHandling` protocol, output through `RemoteKeyboard`), clipboard over cliprdr.

## Log

### 2026-10-07 – FreeRDP build

- Submodule added, tag 3.32.1 checked out.
- Homebrew has many optional libraries installed (ffmpeg, cjson, json-c, krb5, uriparser, opus, soxr, libusb, cairo, jpeg …).
  FreeRDP's feature detection would find them and pull Homebrew dylibs into the app. So the script turns
  **every** optional feature and every channel we don't need off explicitly.
- OpenSSL 3 ships MD4/RC4 only in the legacy provider (`ossl-modules/legacy.dylib`, loaded with dlopen). It cannot be
  shipped statically, but NTLM needs MD4 (and RC4 for legacy RDP security). Solution: `WITH_INTERNAL_RC4=ON`,
  `WITH_INTERNAL_MD4=ON` (FreeRDP's own implementations).
- Homebrew's `libcrypto.a`/`libssl.a` are built with `minos 26.0`. Linking against deployment target 14.0 produces
  linker warnings; macOS < 26 could have problems. Not critical for Marc's Mac (macOS 26).
  Proposal: later build OpenSSL from source with 14.0 (see "Spec proposals").
- Channel table checked (`vendor/build/freerdp/channels/client/tables.c`): VirtualChannelEntryEx = drdynvc, rdpsnd,
  rdpdr, cliprdr; DVCPluginEntry = rdpsnd, rdpgfx, disp; DeviceServiceEntry = drive; rdpsnd subsystems = mac, fake.
  The script aborts if one of them is missing. Symbols in `libfreerdp-client3.a` confirmed with `nm`.
- Result: `vendor/install/lib/{libfreerdp-client3,libfreerdp3,libwinpr3}.a`, headers under
  `vendor/install/include/{freerdp3,winpr3}`. The build takes ~20 s (18 cores).

#### Final CMake flags

```
-G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
-DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF
-DWITH_CCACHE=OFF -DWITH_CLANG_FORMAT=OFF -DWITH_MANPAGES=OFF -DWITH_SAMPLE=OFF
-DWITH_CLIENT_COMMON=ON -DWITH_CLIENT=OFF -DWITH_CLIENT_SDL=OFF -DWITH_CLIENT_MAC=OFF
-DWITH_CLIENT_CHANNELS=ON -DWITH_CHANNELS=ON
-DWITH_SERVER=OFF -DWITH_SERVER_CHANNELS=OFF -DWITH_SHADOW=OFF -DWITH_PROXY=OFF -DWITH_PLATFORM_SERVER=OFF
-DWITH_WINPR_TOOLS=OFF -DWITH_X11=OFF -DWITH_WAYLAND=OFF
-DWITH_FFMPEG=OFF -DWITH_DSP_FFMPEG=OFF -DWITH_VIDEO_FFMPEG=OFF -DWITH_SWSCALE=OFF -DWITH_CAIRO=OFF
-DWITH_OPENH264=OFF -DWITH_JPEG=OFF -DWITH_OPUS=OFF -DWITH_SOXR=OFF -DWITH_LAME=OFF -DWITH_FAAD2=OFF
-DWITH_FAAC=OFF -DWITH_GSM=OFF -DWITH_AOM=OFF -DWITH_DAV1D=OFF -DWITH_YUV=OFF
-DWITH_PCSC=OFF -DWITH_SMARTCARD_EMULATE=OFF -DWITH_PKCS11=OFF -DWITH_FUSE=OFF -DWITH_CUPS=OFF
-DWITH_KRB5=OFF -DWITH_URIPARSER=OFF -DWITH_JSON_DISABLED=ON -DWITH_AAD=OFF -DWITH_MBEDTLS=OFF -DWITH_LIBRESSL=OFF
-DWITH_MACAUDIO=ON -DWITH_SIMD=ON -DWITH_INTERNAL_RC4=ON -DWITH_INTERNAL_MD4=ON
-DOPENSSL_ROOT_DIR=$(brew --prefix openssl@3) -DOPENSSL_USE_STATIC_LIBS=ON
-DCHANNEL_{DRDYNVC,RDPGFX,DISP,CLIPRDR,RDPSND,RDPDR,DRIVE}=ON (+ _CLIENT=ON)
-DCHANNEL_{AINPUT,AUDIN,ECHO,ENCOMSP,GEOMETRY,GFXREDIR,LOCATION,PARALLEL,PRINTER,RAIL,RDP2TCP,RDPEAR,
  RDPECAM,RDPEI,RDPEMSC,RDPEWA,REMDESK,SERIAL,SMARTCARD,SSHAGENT,TELEMETRY,TSMF,URBDRC,VIDEO}=OFF
```

Without an H.264 decoder `WITH_GFX_H264` is off; rdpgfx then sets `RDPGFX_CAPS_FLAG_AVC_DISABLED` in every
CAPVERSION_10x capset (channels/rdpgfx/client/rdpgfx_main.c) – the server does not try AVC.

### 2026-10-07 – Bridge, SprungKit, smoke

Architecture:
- `Sources/SprungBridge` (C, static library, module `SprungBridge` via `include/module.modulemap`):
  `sprung_session.c` (settings, thread with `freerdp_connect` + event loop, auth/certificate hooks, teardown),
  `sprung_display.c` (GDI BGRA32, dirty region, framebuffer lock, DesktopResize), `sprung_pointer.c`
  (cursor), `sprung_resolution.c` (disp channel), `sprung_input.c` (keyboard/mouse under `inputLock`). Public API only in `include/SprungBridge.h`
  (no FreeRDP headers), so Swift can import it without FreeRDP includes.
- `Sources/SprungKit` (Swift, static library): `RDPSession` (@MainActor), `EventRelay` (C callbacks →
  main queue, FIFO), `SessionConfiguration`, `TestVMEnvironment`, `RemoteKeyboard` protocol.
- `Sources/Sprung` (app), `Sources/SprungSmoke` (CLI).

Decisions:
- **Framebuffer:** FreeRDP's GDI owns the buffer. The bridge collects dirty rects in `EndPaint` (under the
  FreeRDP update lock) in a `REGION16`; `frameReady` fires coalesced once until the next
  `framebuffer_acquire`. Per display refresh the app copies only the dirty rects into one of three
  IOSurfaces (one the WindowServer is not reading right now, `IOSurface.isInUse`) and swaps it in as
  `CALayer.contents` → no tearing, no full-frame copies. sRGB color space on the IOSurface.
- **Lock order:** gfx mux → update lock (FreeRDP) is the only order; the app takes only the
  update lock. `gdi_free` in PostDisconnect runs under the update lock, so a concurrent
  `framebuffer_acquire` never reads freed memory.
- **Input:** directly from the main thread (FreeRDP's transport writes with its own mutex), but under
  `inputLock` + `inputReady`, which the event loop thread sets to false before `freerdp_disconnect`.
  The bridge keeps a bitmap of pressed scancodes: a repeated down → repeat flag, an up without a down is
  dropped, `release_all_keys` releases everything. Pause = (0x46, extended) → `freerdp_input_send_keyboard_pause_event`.
- **disp channel:** `set_resolution` only stores a pending layout and wakes the event loop (`wakeEvent`). It is sent
  on the event loop thread, at the earliest 1 s after `DisplayControlCaps` and only when no resize is
  "in flight". Only a DesktopResize to exactly the requested size counts as the answer; without an answer after
  1.5 s it is resent up to 3×. The newest request wins; a layout equal to the current one is dropped.
  (Measured: Windows drops a layout that comes right with the caps every time; after 500 ms it worked at
  100 %, in the app at 200 % not always, after 1 s in every run (app 2×, smoke 10 cycles, 0 retries).
  The initial graphics reset can come *after* an early request and must not "answer" it.)
- **Certificate:** callback into Swift (synchronous, on the FreeRDP thread); M1 accepts and logs the SHA-256.
  Return value 2 = this session only, FreeRDP never stores anything. `FreeRDP_ConfigPath` points to
  `~/Library/Application Support/Sprung/FreeRDP`, so `~/.config/freerdp` (which had an old entry
  for the VM) plays no part.
- **Auth:** credentials come from the configuration. `AuthenticateEx` is called only when data is missing and
  then aborts with `FREERDP_ERROR_CONNECT_NO_OR_MISSING_CREDENTIALS` (the dialog comes in M4).
- **SIGPIPE** is ignored once (otherwise a write to a closed socket kills the app).
- Teardown: `sprung_session_destroy` → `freerdp_abort_connect_context` → `pthread_join` →
  `freerdp_client_context_free`. Swift calls this on a background queue (TLS shutdown can take a while):
  `RDPSession.close()` starts it (idempotent; afterwards `rawSession` returns nil → bridge functions are no-ops),
  `closeAndWait()` waits for it.
- **Process exit:** `exit()` destroys FreeRDP's global state (WLog mutexes) through `__cxa_finalize`. If a
  session thread is still in `freerdp_disconnect` then, there is a SIGSEGV (it happened: crash report
  `sprung-smoke-2026-10-07-113145.ips`, the smoke failure path exited with an open session). Fix: every session
  is in a global `DispatchGroup`; `RDPSession.waitForAllSessionsToClose(timeout:)` is called before `exit` in the
  smoke tool and in `applicationWillTerminate` (which closes all session windows first). Quit the app 3× with an
  active session: clean disconnect, no crash report.

Problems + fixes:
- XcodeGen copies the static C library's `include/` to `Products/include/SprungBridge/` (incl. the modulemap).
  An additional `SWIFT_INCLUDE_PATHS` → "redefinition of module". Solution: use only the copied modulemap.
- XcodeGen adds a "Copy ObjC Header" phase to Swift static libraries, which fails with script sandboxing →
  `SWIFT_INSTALL_OBJC_HEADER: NO` for SprungKit.
- **Test VM: Windows 11 Pro allows one active session.** `mneuhaus` had been active on the console since 2025-12-29,
  so the RDP logon as `sprung` stopped at "Ein anderer Benutzer ist angemeldet … trotzdem anmelden?" (another user
  is signed in … sign in anyway?) (no desktop, no disp resize). I disconnected the console session once with
  `tsdiscon 1` (not logged off, programs keep running). `scripts/smoke.sh` now checks this beforehand and aborts with
  a clear message; `--takeover` disconnects the console session automatically.
- Smoke waits for "frame settled" (1.5 s without new pixels); animating desktops are not an error (after 10 s
  the current frame counts).

Results (smoke against 10.211.55.9):
- Connection incl. NLA ~0.15 s, first desktop ~3 s after logon, `display control ready (max 16 monitors)`.
- Resize to 1600x1000: DesktopResize after ~50 ms. Alpha bytes in the framebuffer are 255 (opaque).
- 10 connect/disconnect cycles without errors, footprint 195 MB → 157 MB (no growth).
- `leaks --atExit` with scenario + 3 cycles: **0 leaks**.
- Evidence: `build/smoke.png`, `build/smoke-resized.png`.

Known log noise from FreeRDP (harmless): "OpenSSL LEGACY provider failed to load" (we use the internal
MD4/RC4), "x509_utils_from_pem: BIO_new failed", "host key has changed" (FreeRDP's text for a *new* certificate).

### 2026-10-07 – App, visual check, soak

App:
- `SessionView` (layer-backed, flipped): `FramePresenter` (IOSurface pool) as a sublayer with
  `contentsGravity = .resizeAspect`; `CADisplayLink` (macOS 14 `NSView.displayLink`) fetches the dirty rects once
  per refresh after `frameReady` and pauses after 30 ticks without new pixels.
- Mouse: `DesktopGeometry` (aspect fit, letterbox, point → remote pixel, clamp), all buttons (other 2/3/4 →
  middle/X1/X2), `ScrollAccumulator` (30 pt per notch on a trackpad, line = notch for a mouse wheel, the remainder is
  carried over, reset at gesture start). Sign: macOS deltas already include "natural scrolling",
  so deltaY → WHEEL directly, deltaX → HWHEEL negated.
- Cursor: `RemoteCursors` builds NSCursors from the BGRA data, scaled by points per remote pixel (Retina:
  0.5); hidden = transparent 1×1 cursor, default = arrow. Server warps (`pointerPosition`) are ignored on purpose
  (they would fight the user's mouse).
- Keyboard M1: `KeyInputHandling` protocol, `RawKeyInputHandler` + `MacScancodeTable` (physical position,
  ISO swap 0x0A/0x32 via `KBGetLayoutType`, ⌘ = Win, Help = Insert, F13/14/15 = Print Screen/Scroll Lock/Pause,
  Clear = Num Lock). Input through a local event monitor (also sees keyUp while ⌘ is held); ⌃⌘F and ⌘Q
  stay local. Focus loss → `releaseAllKeys`, focus gain → `sync(caps, num: on, scroll: off)`.
- Resolution: window resize/backing change → 300 ms debounce → `setResolution(points × backing, 200 %)`.
  Retina switch in the form (`UserDefaults` "retina", default on).

Checked visually (screenshots in `build/evidence/`):
- `m1-window-retina.png`: 1440×900 pt → remote 2880×1800 @ 200 %, text pin-sharp
  (`crop-taskbar.png` at native resolution).
- `m1-window-resized-1000x700.png`: window resized via AX to 1000×700 → exactly one request
  `requesting desktop 2000x1336 at 200%`, Windows laid out the desktop icons and taskbar again.
- `m1-window-nonretina.png` / `crop-taskbar-nonretina.png`: Retina off → 1440×900 @ 100 %, scaled up 2×.
- `m1-connect-form.png`: form (pre-filled in Debug).
- `m1-window-resized-during-connect.png`: window resized to 1200×760 while connecting → remote
  2400×1456 @ 200 %, fills the window without borders.
- Closing the window → session disconnected cleanly, the form appears again; connecting again works.
- `m1-cursors.png`: server cursors (arrow, arrow+busy, busy, I-beam) with correct alpha. The I-beam is an
  XOR cursor; FreeRDP turns inverting pixels into a checkerboard. For later: render it black with a white
  outline.
- Did not move the local mouse pointer (Marc was working in parallel, HIDIdleTime 0 s). NSCursor scaling is
  covered by a unit test instead; the pointer data itself by the smoke dump.

Soak (`--soak`): one session, mouse sweep at 50 Hz, a right-click + Esc every ~4 s (keyboard path), mouse wheel,
a resize 1280×800 ↔ 1440×900 every ~12 s with a check that the DesktopResize arrives.
- 180 s soak + 10 cycles (`build/evidence/soak-180s.log`): 15 resizes, all answered; footprint
  131–148 MB during the soak without a trend, 80 MB after the cycles. Exit 0.
- Cycles now request 1152×864 right after connecting (resize during the logon) → this uncovered the
  "a layout right after the caps is dropped" problem (see disp channel). Final: 10/10 without a retry.
- `leaks --atExit` (scenario + 3 cycles, final): 0 leaks. App after 4 sessions without an active session: 0 leaks.
  With an active session `leaks` reports an NTLM context (4.5 KB) – a false alarm: WinPR stores SSPI handles
  bitwise inverted (`sspi_SecureHandleSetLowerPointer`), `leaks` does not see the reference.
- GFX negotiation (`WLOG_FILTER=com.freerdp.channels.rdpgfx.client:TRACE`, `build/evidence/gfx-trace.log`):
  `RDPGFX_CAPVERSION_107`, flags `0xA2` = SMALL_CACHE | AVC_DISABLED | SCALEDMAP_DISABLE. Codecs used:
  CAPROGRESSIVE (27) and CLEARCODEC (11), no AVC.

## Notes for M3 (KeyboardEngine integration)

- The output interface is `RemoteKeyboard` (SprungKit, implemented by `RDPSession`):
  `sendScancode(code, extended:, down:)`, `sendUnicode(codeUnit, down:)`, `sendSync(capsLock:numLock:scrollLock:)`,
  `releaseAllKeys()`. That maps 1:1 to the engine actions `scancode/unicode/sync`.
- Scancodes: set 1 make codes 0x01…0x7F + E0 flag. **Pause = (0x46, extended)** (FreeRDP convention); the bridge
  sends the E1 sequence on down, the up is ignored. Num Lock = (0x45, not extended).
- The bridge remembers pressed scancodes: another down = repeat (KBD_FLAGS_DOWN), an up without a previous down
  is dropped, `releaseAllKeys` sends ups for everything pressed. Unicode events are not tracked.
- Unicode: UTF-16 code units; characters outside the BMP as two units (surrogate pair), each down+up.
- Input: `KeyInputHandling` (app) with `handle(NSEvent)` for keyDown/keyUp/flagsChanged, `focusGained()`,
  `focusLost()`. The local event monitor in `SessionWindowController` filters out ⌃⌘F and ⌘Q first –
  M3 should move this decision into the engine (spec: ⌃⌥⌘ reserved) and replace `isLocalShortcut`.
- `RemoteKeyboard` is @MainActor; the C functions themselves are thread-safe and no-ops before `connected` and after
  disconnecting.
- Keyboard layout of the session: `SessionConfiguration.keyboardLayout` (KLID, default 0x0407). M3/M2 sets it from
  the TIS input source.

## Spec proposals

- Build OpenSSL 3 from source with deployment target 14.0 instead of Homebrew's `.a` (minos 26.0).
- Kerberos (`WITH_KRB5`) is off. NTLM is enough for domain logons; if Marc's targets enforce Kerberos, build
  against Heimdal/GSS.framework later.
- Test VM: Windows 11 Pro allows one active session. The spec should state that E2E tests disconnect
  `mneuhaus`'s console session (`smoke.sh --takeover`), or the VM runs without auto-login.
- `GfxSmallCache` is FreeRDP's default (on). For slow connections to customer PCs test the large
  cache later (less retransmission, more RAM).
- `WITH_VERBOSE_WINPR_ASSERT` is on (FreeRDP default, warns "might slow down"); weigh it for release builds.
- XOR cursors (e.g. the text I-beam) arrive from FreeRDP as a checkerboard; an own converter (black with a white
  outline) would look nicer.
- ⌘Q with open sessions disconnects without asking in M1 (spec: confirmation, M4).
