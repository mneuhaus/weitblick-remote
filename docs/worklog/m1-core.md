# M1 Kern – Worklog

Agent: M1 core (FreeRDP-Build, Bridge, Sitzungsfenster, Smoke-Test). M2 (Packages/KeyboardEngine) läuft parallel, `Packages/` wird hier nicht angefasst.

## Stand

- [x] `vendor/FreeRDP` als Submodul auf Tag 3.32.1 (Commit bf217a504)
- [x] `scripts/build-freerdp.sh` (statisch, arm64, 14.0, nur Client)
- [x] `Sources/SprungBridge` (C) – kompiliert, Smoke grün
- [x] `Sources/SprungKit` (Swift-Wrapper `RDPSession`, von App und Smoke geteilt)
- [x] App `Sources/Sprung` + `project.yml` – baut, Retina/Non-Retina/Resize/Reconnect visuell geprüft
- [x] Smoke-Test `sprung-smoke` + `scripts/smoke.sh` – grün inkl. 10 Zyklen, Cursor-Dump, Soak, `leaks`: 0
- [x] `scripts/build.sh`, README.md
- [x] Unit-Tests `SprungTests` (Geometrie, Scroll-Vorzeichen, Cursor-Skalierung), 8/8 grün
- [ ] Vollbild (⌃⌘F) nur im Code geprüft, nicht visuell (Marc war aktiv am Rechner, Vollbild hätte seinen Space übernommen)
- [ ] Lokaler Mauszeiger über dem Fenster (NSCursor-Wechsel live) nicht geprüft, aus demselben Grund; Pointer-Daten
  per Smoke-Dump und NSCursor-Skalierung per Unit-Test abgedeckt
- Submodul-Pointer ist gestaged (`git add vendor/FreeRDP`, bf217a504), nichts committet.

Nächster Schritt: Vollbild + Live-Cursor prüfen, wenn Marc nicht am Rechner ist (`build/Sprung.app --autoconnect`,
⌃⌘F, Maus über Suchfeld → I-Beam). Danach M3: `RawKeyInputHandler` durch einen KeyboardEngine-Adapter ersetzen (gleiches
`KeyInputHandling`-Protokoll, Ausgabe über `RemoteKeyboard`), Zwischenablage über cliprdr.

## Log

### 2026-10-07 – FreeRDP-Build

- Submodul hinzugefügt, Tag 3.32.1 ausgecheckt.
- Homebrew hat viele optionale Libs installiert (ffmpeg, cjson, json-c, krb5, uriparser, opus, soxr, libusb, cairo, jpeg …).
  FreeRDPs Feature-Erkennung würde die finden und Homebrew-Dylibs in die App ziehen. Deshalb schaltet das Skript
  **jedes** optionale Feature und jeden nicht benötigten Kanal explizit ab.
- OpenSSL 3 bringt MD4/RC4 nur im Legacy-Provider (`ossl-modules/legacy.dylib`, per dlopen). Statisch nicht
  mitlieferbar, NTLM braucht aber MD4 (und RC4 für Legacy-RDP-Security). Lösung: `WITH_INTERNAL_RC4=ON`,
  `WITH_INTERNAL_MD4=ON` (FreeRDP-eigene Implementierungen).
- Homebrew-`libcrypto.a`/`libssl.a` sind mit `minos 26.0` gebaut. Linken gegen Deployment Target 14.0 erzeugt
  Linker-Warnungen; auf macOS < 26 könnte es Probleme geben. Für Marcs Rechner (macOS 26) unkritisch.
  Vorschlag: später OpenSSL selbst aus Quellen mit 14.0 bauen (siehe „Spec-Vorschläge“).
- Kanal-Tabelle geprüft (`vendor/build/freerdp/channels/client/tables.c`): VirtualChannelEntryEx = drdynvc, rdpsnd,
  rdpdr, cliprdr; DVCPluginEntry = rdpsnd, rdpgfx, disp; DeviceServiceEntry = drive; rdpsnd-Subsysteme = mac, fake.
  Das Skript bricht ab, falls einer davon fehlt. Symbole in `libfreerdp-client3.a` per `nm` bestätigt.
- Ergebnis: `vendor/install/lib/{libfreerdp-client3,libfreerdp3,libwinpr3}.a`, Header unter
  `vendor/install/include/{freerdp3,winpr3}`. Build dauert ~20 s (18 Kerne).

#### Finale CMake-Flags

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

Ohne H.264-Decoder ist `WITH_GFX_H264` aus; rdpgfx setzt dann in allen CAPVERSION_10x-Capsets
`RDPGFX_CAPS_FLAG_AVC_DISABLED` (channels/rdpgfx/client/rdpgfx_main.c) – der Server versucht kein AVC.

### 2026-10-07 – Bridge, SprungKit, Smoke

Architektur:
- `Sources/SprungBridge` (C, statische Lib, Modul `SprungBridge` per `include/module.modulemap`):
  `sprung_session.c` (Settings, Thread mit `freerdp_connect` + Eventloop, Auth/Zertifikat-Hooks, Teardown),
  `sprung_display.c` (GDI BGRA32, Dirty-Region, Framebuffer-Lock, DesktopResize), `sprung_pointer.c`
  (Cursor), `sprung_resolution.c` (disp-Kanal), `sprung_input.c` (Tastatur/Maus unter `inputLock`). Öffentliche API nur in `include/SprungBridge.h`
  (keine FreeRDP-Header), damit Swift ohne FreeRDP-Includes importieren kann.
- `Sources/SprungKit` (Swift, statische Lib): `RDPSession` (@MainActor), `EventRelay` (C-Callbacks →
  Main-Queue, FIFO), `SessionConfiguration`, `TestVMEnvironment`, `RemoteKeyboard`-Protokoll.
- `Sources/Sprung` (App), `Sources/SprungSmoke` (CLI).

Entscheidungen:
- **Framebuffer:** FreeRDP-GDI besitzt den Puffer. Dirty-Rects sammelt die Bridge in `EndPaint` (unter dem
  FreeRDP-Update-Lock) in einer `REGION16`; `frameReady` feuert koalesziert einmal bis zum nächsten
  `framebuffer_acquire`. Die App kopiert pro Display-Refresh nur die Dirty-Rects in eins von drei
  IOSurfaces (eins, das der WindowServer gerade nicht liest, `IOSurface.isInUse`) und tauscht es als
  `CALayer.contents` ein → kein Tearing, keine Vollbildkopien. sRGB-Farbraum am IOSurface.
- **Lock-Reihenfolge:** gfx-mux → Update-Lock (FreeRDP) ist die einzige Reihenfolge; die App nimmt nur den
  Update-Lock. `gdi_free` in PostDisconnect läuft unter dem Update-Lock, damit ein gleichzeitiges
  `framebuffer_acquire` nie freigegebenen Speicher liest.
- **Input:** direkt aus dem Main-Thread (FreeRDP-Transport schreibt mit eigenem Mutex), aber unter
  `inputLock` + `inputReady`, das der Eventloop-Thread vor `freerdp_disconnect` auf false setzt.
  Die Bridge führt eine Bitmap gedrückter Scancodes: wiederholtes Down → Repeat-Flag, Up ohne Down wird
  verworfen, `release_all_keys` löst alles. Pause = (0x46, extended) → `freerdp_input_send_keyboard_pause_event`.
- **disp-Kanal:** `set_resolution` legt nur ein Pending-Layout ab und weckt den Eventloop (`wakeEvent`). Gesendet
  wird auf dem Eventloop-Thread, frühestens 1 s nach `DisplayControlCaps` und nur, wenn kein Resize mehr
  „in flight“ ist. Als Antwort zählt nur ein DesktopResize auf genau die angefragte Größe; ohne Antwort nach
  1,5 s wird bis zu 3× neu gesendet. Neueste Anfrage gewinnt; ein Layout gleich dem aktuellen wird verworfen.
  (Gemessen: Windows verwirft ein Layout, das direkt mit den Caps kommt, jedes Mal; nach 500 ms klappte es bei
  100 %, in der App mit 200 % aber nicht immer, nach 1 s in allen Läufen (App 2×, Smoke 10 Zyklen, 0 Retries).
  Der initiale Graphics-Reset kann *nach* einer frühen Anfrage kommen und darf sie nicht „beantworten“.)
- **Zertifikat:** Callback in Swift (synchron, auf FreeRDP-Thread), M1 akzeptiert + loggt SHA-256.
  Rückgabe 2 = nur diese Sitzung, FreeRDP speichert nie etwas. `FreeRDP_ConfigPath` zeigt auf
  `~/Library/Application Support/Sprung/FreeRDP`, damit `~/.config/freerdp` (dort lag ein alter Eintrag
  für die VM) nicht mitspielt.
- **Auth:** Credentials kommen aus der Config. `AuthenticateEx` wird nur bei fehlenden Daten gerufen und
  bricht dann mit `FREERDP_ERROR_CONNECT_NO_OR_MISSING_CREDENTIALS` ab (Dialog kommt in M4).
- **SIGPIPE** wird einmalig ignoriert (sonst killt ein Write auf einen geschlossenen Socket die App).
- Teardown: `sprung_session_destroy` → `freerdp_abort_connect_context` → `pthread_join` →
  `freerdp_client_context_free`. Swift ruft das auf einer Background-Queue (TLS-Shutdown kann dauern):
  `RDPSession.close()` startet es (idempotent, danach liefert `rawSession` nil → Bridge-Funktionen No-ops),
  `closeAndWait()` wartet darauf.
- **Prozessende:** `exit()` zerstört FreeRDPs globalen Zustand (WLog-Mutexe) per `__cxa_finalize`. Läuft dann noch
  ein Sitzungs-Thread in `freerdp_disconnect`, gibt es SIGSEGV (passiert: Crashreport
  `sprung-smoke-2026-10-07-113145.ips`, Smoke-Fehlerpfad beendete sich mit offener Sitzung). Fix: jede Sitzung
  hängt in einer globalen `DispatchGroup`; `RDPSession.waitForAllSessionsToClose(timeout:)` wird vor `exit` im
  Smoke-Tool und in `applicationWillTerminate` (schließt vorher alle Sitzungsfenster) aufgerufen. App 3× mit
  aktiver Sitzung beendet: sauberes Trennen, kein Crashreport.

Probleme + Fixes:
- XcodeGen kopiert `include/` der statischen C-Lib nach `Products/include/SprungBridge/` (inkl. modulemap).
  Zusätzliches `SWIFT_INCLUDE_PATHS` → „redefinition of module“. Lösung: nur die kopierte modulemap nutzen.
- XcodeGen fügt Swift-Static-Libs eine „Copy ObjC Header“-Phase hinzu, die mit Script-Sandboxing scheitert →
  `SWIFT_INSTALL_OBJC_HEADER: NO` für SprungKit.
- **Test-VM: Windows 11 Pro erlaubt eine aktive Sitzung.** `mneuhaus` war seit 29.12.2025 an der Konsole aktiv,
  die RDP-Anmeldung als `sprung` blieb deshalb auf „Ein anderer Benutzer ist angemeldet … trotzdem anmelden?“
  stehen (kein Desktop, kein disp-Resize). Ich habe die Konsolensitzung einmalig per `tsdiscon 1` getrennt
  (nicht abgemeldet, Programme laufen weiter). `scripts/smoke.sh` prüft das jetzt vorab und bricht mit
  klarer Meldung ab; `--takeover` trennt die Konsolensitzung automatisch.
- Smoke wartet auf „Frame settled“ (1,5 s ohne neue Pixel); animierende Desktops sind kein Fehler (nach 10 s
  zählt der aktuelle Frame).

Ergebnisse (Smoke gegen 10.211.55.9):
- Verbindung inkl. NLA ~0,15 s, erster Desktop ~3 s nach Logon, `display control ready (max 16 monitors)`.
- Resize auf 1600x1000: DesktopResize nach ~50 ms. Alpha-Bytes im Framebuffer sind 255 (opak).
- 10 Connect/Disconnect-Zyklen ohne Fehler, Footprint 195 MB → 157 MB (kein Wachstum).
- `leaks --atExit` mit Scenario + 3 Zyklen: **0 leaks**.
- Evidenz: `build/smoke.png`, `build/smoke-resized.png`.

Bekannte Log-Rauschen von FreeRDP (harmlos): „OpenSSL LEGACY provider failed to load“ (wir nutzen interne
MD4/RC4), „x509_utils_from_pem: BIO_new failed“, „host key has changed“ (FreeRDPs Text für *neues* Zertifikat).

### 2026-10-07 – App, visuelle Prüfung, Soak

App:
- `SessionView` (Layer-backed, flipped): `FramePresenter` (IOSurface-Pool) als Sublayer mit
  `contentsGravity = .resizeAspect`; `CADisplayLink` (macOS 14 `NSView.displayLink`) holt bei `frameReady`
  pro Refresh einmal die Dirty-Rects und pausiert nach 30 Ticks ohne neue Pixel.
- Maus: `DesktopGeometry` (Aspect-Fit, Letterbox, Punkt → Remote-Pixel, Clamp), alle Buttons (other 2/3/4 →
  Mitte/X1/X2), `ScrollAccumulator` (30 pt pro Notch bei Trackpad, Zeile = Notch beim Mausrad, Rest wird
  übertragen, Reset bei Gestenbeginn). Vorzeichen: macOS-Deltas enthalten schon „Natürliches Scrollen“,
  also deltaY → WHEEL direkt, deltaX → HWHEEL negiert.
- Cursor: `RemoteCursors` baut NSCursor aus den BGRA-Daten, skaliert mit Punkten pro Remote-Pixel (Retina:
  0,5), versteckt = transparenter 1×1-Cursor, Default = Pfeil. Server-Warp (`pointerPosition`) wird bewusst
  ignoriert (würde gegen die Maus des Nutzers arbeiten).
- Tastatur M1: `KeyInputHandling`-Protokoll, `RawKeyInputHandler` + `MacScancodeTable` (physische Position,
  ISO-Tausch 0x0A/0x32 per `KBGetLayoutType`, ⌘ = Win, Help = Einfg, F13/14/15 = Druck/Rollen/Pause,
  Clear = Num). Eingang über einen lokalen Event-Monitor (sieht auch keyUp bei gehaltenem ⌘); ⌃⌘F und ⌘Q
  bleiben lokal. Fokusverlust → `releaseAllKeys`, Fokusgewinn → `sync(caps, num: an, scroll: aus)`.
- Auflösung: Fenster-Resize/Backing-Änderung → 300 ms Debounce → `setResolution(Punkte × Backing, 200 %)`.
  Retina-Schalter im Formular (`UserDefaults` „retina“, Standard an).

Visuell geprüft (Screenshots in `build/evidence/`):
- `m1-window-retina.png`: 1440×900 pt → Remote 2880×1800 @ 200 %, Text gestochen scharf
  (`crop-taskbar.png` in nativer Auflösung).
- `m1-window-resized-1000x700.png`: Fenster per AX auf 1000×700 → genau eine Anfrage
  `requesting desktop 2000x1336 at 200%`, Windows hat Desktop-Icons und Taskleiste neu gelayoutet.
- `m1-window-nonretina.png` / `crop-taskbar-nonretina.png`: Retina aus → 1440×900 @ 100 %, 2× hochskaliert.
- `m1-connect-form.png`: Formular (Debug vorbefüllt).
- `m1-window-resized-during-connect.png`: Fenster schon während des Verbindens auf 1200×760 → Remote
  2400×1456 @ 200 %, füllt das Fenster ohne Ränder.
- Fenster schließen → Sitzung sauber getrennt, Formular erscheint wieder; erneut verbinden funktioniert.
- `m1-cursors.png`: Server-Cursor (Pfeil, Pfeil+Busy, Busy, I-Beam) mit korrektem Alpha. Der I-Beam ist ein
  XOR-Cursor; FreeRDP macht aus invertierenden Pixeln ein Schachbrett. Für später: als Schwarz mit weißem
  Rand rendern.
- Lokalen Mauszeiger nicht bewegt (Marc arbeitete parallel, HIDIdleTime 0 s). Die NSCursor-Skalierung ist
  stattdessen per Unit-Test abgedeckt; die Pointer-Daten selbst per Smoke-Dump.

Soak (`--soak`): eine Sitzung, Maus-Sweep mit 50 Hz, alle ~4 s Rechtsklick + Esc (Tastaturpfad), Mausrad,
alle ~12 s Resize 1280×800 ↔ 1440×900 mit Prüfung, dass DesktopResize ankommt.
- 180 s Soak + 10 Zyklen (`build/evidence/soak-180s.log`): 15 Resizes, alle beantwortet; Footprint
  während des Soaks 131–148 MB ohne Trend, nach den Zyklen 80 MB. Exit 0.
- Zyklen fordern jetzt direkt nach dem Verbinden 1152×864 an (Resize während der Anmeldung) → deckte das
  „Layout direkt nach Caps wird verworfen“-Problem auf (s. disp-Kanal). Final: 10/10 ohne Retry.
- `leaks --atExit` (Scenario + 3 Zyklen, final): 0 leaks. App nach 4 Sitzungen ohne aktive Sitzung: 0 leaks.
  Mit aktiver Sitzung meldet `leaks` einen NTLM-Kontext (4,5 KB) – Fehlalarm: WinPR speichert SSPI-Handles
  bitweise invertiert (`sspi_SecureHandleSetLowerPointer`), `leaks` sieht die Referenz nicht.
- GFX-Verhandlung (`WLOG_FILTER=com.freerdp.channels.rdpgfx.client:TRACE`, `build/evidence/gfx-trace.log`):
  `RDPGFX_CAPVERSION_107`, Flags `0xA2` = SMALL_CACHE | AVC_DISABLED | SCALEDMAP_DISABLE. Benutzte Codecs:
  CAPROGRESSIVE (27) und CLEARCODEC (11), kein AVC.

## Hinweise für M3 (KeyboardEngine-Integration)

- Ausgabe-Schnittstelle ist `RemoteKeyboard` (SprungKit, `RDPSession` implementiert es):
  `sendScancode(code, extended:, down:)`, `sendUnicode(codeUnit, down:)`, `sendSync(capsLock:numLock:scrollLock:)`,
  `releaseAllKeys()`. Das passt 1:1 auf die Engine-Aktionen `scancode/unicode/sync`.
- Scancodes: Set-1-Make-Codes 0x01…0x7F + E0-Flag. **Pause = (0x46, extended)** (FreeRDP-Konvention), Bridge
  sendet beim Down die E1-Sequenz, das Up wird ignoriert. NumLock = (0x45, nicht extended).
- Die Bridge merkt sich gedrückte Scancodes: erneutes Down = Repeat (KBD_FLAGS_DOWN), Up ohne vorheriges Down
  wird verworfen, `releaseAllKeys` schickt Ups für alles Gedrückte. Unicode-Events werden nicht getrackt.
- Unicode: UTF-16-Codeunits; Zeichen außerhalb der BMP als zwei Units (Surrogatpaar) jeweils down+up.
- Eingang: `KeyInputHandling` (App) mit `handle(NSEvent)` für keyDown/keyUp/flagsChanged, `focusGained()`,
  `focusLost()`. Der lokale Event-Monitor in `SessionWindowController` filtert vorher ⌃⌘F und ⌘Q heraus –
  M3 sollte diese Entscheidung in die Engine verlagern (Spec: ⌃⌥⌘ reserviert) und `isLocalShortcut` ersetzen.
- `RemoteKeyboard` ist @MainActor; die C-Funktionen selbst sind threadsicher und vor `connected` bzw. nach dem
  Trennen No-ops.
- Tastaturlayout der Sitzung: `SessionConfiguration.keyboardLayout` (KLID, Standard 0x0407). M3/M2 setzt es aus
  der TIS-Input-Source.

## Spec-Vorschläge

- OpenSSL 3 aus Quellen mit Deployment Target 14.0 bauen statt Homebrew-`.a` (minos 26.0).
- Kerberos (`WITH_KRB5`) ist aus. Für Domänen-Logins reicht NTLM; falls Marcs Ziele Kerberos erzwingen, später
  gegen Heimdal/GSS.framework bauen.
- Test-VM: Windows 11 Pro erlaubt eine aktive Sitzung. Die Spec sollte festhalten, dass E2E-Tests die
  Konsolensitzung von `mneuhaus` trennen (`smoke.sh --takeover`), oder die VM ohne Auto-Login betreiben.
- `GfxSmallCache` ist FreeRDP-Standard (an). Für langsame Verbindungen zu Kunden-PCs später den großen
  Cache testen (weniger Neuübertragung, mehr RAM).
- `WITH_VERBOSE_WINPR_ASSERT` ist an (FreeRDP-Default, warnt „might slow down“); für Release-Builds abwägen.
- XOR-Cursor (z. B. Text-I-Beam) kommen von FreeRDP als Schachbrett; eigener Konverter (schwarz mit weißem
  Rand) wäre hübscher.
- ⌘Q mit offenen Sitzungen trennt in M1 ohne Rückfrage (Spec: Rückfrage, M4).
