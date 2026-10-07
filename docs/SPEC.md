# Sprung: RDP-Client für macOS

Ziel: Jump Desktop als RDP-Client für Marc ersetzen. Eine native Mac-App (Apple Silicon, macOS 14+),
Open Source (Apache-2.0), die per RDP sauber, stabil und schnell auf Windows-Rechner verbindet.
Kernfeatures sind **Tastatur** (inkl. Übersetzung der Mac-Kurzbefehle wie in Jump) und **Zwischenablage**.

## Reale Zielsysteme (aus Marcs Jump-Konfiguration)

- 12 RDP-Ziele: Kunden-PCs per NetBIOS-Hostname, Port 3389,
  NLA aktiv, teils mit Domäne, kein Gateway. Ältere Industrie-PCs (evtl. Windows 7/10 IoT) möglich:
  Legacy-TLS und RDP-Security als Fallback müssen gehen.
- Laufwerksumleitung `~/Downloads` und einem Projektordner bei fast allen Verbindungen.
- Zwischenablage an, Audio-Wiedergabe an, Druckerumleitung an, dynamische Auflösung an.
- Jump-Dateien: `~/Library/Containers/com.p5sys.jump.mac.viewer/Data/Documents/JumpDesktop/Viewer/Servers/*.jump`
  (JSON). Import soll diese Einstellungen übernehmen (Passwörter nicht; die liegen nicht in den Dateien).
- VNC-Ziel m4-mini: nicht unser Thema, dafür gibt es macOS-Bildschirmfreigabe.

**Regel für die Entwicklung:** Verbunden wird ausschließlich mit der Test-VM. Die Kunden-PCs sind
Produktivsysteme; die testet Marc selbst.

## Testumgebung

- Parallels-VM „Windows 11“ (Pro 24H2, ARM, Deutsch, Tastatur de-DE), IP `10.211.55.9`, RDP aktiviert.
- Lokaler Testbenutzer `sprung` (Administrator + Remotedesktopbenutzer). Zugangsdaten in `.testvm.env`
  (gitignored): `SPRUNG_TEST_HOST`, `SPRUNG_TEST_USER`, `SPRUNG_TEST_PASS`.
- Befehle in der VM ohne RDP: `prlctl exec "Windows 11" powershell -NoProfile -Command "…"`
  (läuft als SYSTEM, nicht in der RDP-Sitzung).

## Architektur

- **RDP-Kern: FreeRDP 3** (Apache-2.0), als Git-Submodul `vendor/FreeRDP` auf Tag `3.32.1`, statisch
  gebaut (arm64, Deployment Target 14.0) von `scripts/build-freerdp.sh`. OpenSSL 3 statisch.
  Kanäle statisch eingebaut: drdynvc, rdpgfx, disp, cliprdr, rdpsnd (mac), rdpdr + drive (+ printer später),
  audin (später). Kein X11/SDL/Wayland/FFmpeg. H.264 später über ein eigenes VideoToolbox-Backend.
  Warum FreeRDP statt RDPKit/IronRDP: ausgereift bei NLA/NTLM/Domänen, Legacy-TLS für alte Windows,
  Laufwerks- und Druckerumleitung, Gateway. Das brauchen Marcs Ziele.
- `Sources/SprungBridge` (C): schmale Brücke zu libfreerdp (Session-Lebenszyklus, Eventloop-Thread,
  Callbacks für Frames/Pointer/Fehler/Zertifikat/Anmeldung, Eingabefunktionen).
- `Packages/KeyboardEngine` (reines Swift-Package, ohne FreeRDP): übersetzt Mac-Tastenereignisse in
  RDP-Eingabeaktionen. Vollständig unit-getestet.
- `Sources/Sprung` (App, AppKit + SwiftUI): Verbindungsliste, Einstellungen, Sitzungsfenster.
- Projekt per XcodeGen (`project.yml` committed, `.xcodeproj` nicht). Nicht sandboxed (Laufwerke,
  Event-Tap), Hardened Runtime, signiert mit der „Apple Development“-Identität (stabile TCC-Rechte
  für Bedienungshilfen).

## Tastatur (Kernfeature)

Ausgabe der Engine sind Aktionen: `scancode(code, extended, down)`, `unicode(codepoint, down)`,
`sync(capsLock, numLock, scrollLock)`.

### Physische Zuordnung
- macOS-Keycode → RDP-Scancode (Set 1) + Extended-Flag. Rechte Modifier, Pfeile, Pos1/Ende/Bild,
  Entf, Ziffernblock-Enter, Ziffernblock-/ sind extended.
- ISO-Tastaturen (deutsches MacBook): `kVK_ISO_Section` (0x0A, Taste links der 1, ^°) → 0x29,
  `kVK_ANSI_Grave` (0x32, Taste links von Y, <>) → 0x56. Bei ANSI: 0x32 → 0x29. JIS-Tasten mit abbilden.
- Help → Einfg, F13 → Druck, F14 → Rollen, F15 → Pause, Ziffernblock-Clear → Num.
- Tastaturlayout der Sitzung = aktuelles Mac-Layout (TIS-Input-Source → Windows-KLID, z. B. German
  → 0x0407, Swiss German → 0x0807, US → 0x0409, British → 0x0809, …); pro Verbindung überschreibbar.

### Modus „Mac-Kurzbefehle“ (Standard) vs. „Windows 1:1“
In 1:1: ⌘ = Win, ⌥ = Alt, ⌃ = Strg, alles Scancodes.

In „Mac-Kurzbefehle“:
- **⌘ wird zurückgehalten** (Modifier-Deferral): erst die nächste Taste entscheidet. ⌘ allein
  antippen = Win-Taste antippen (Startmenü).
- Standardregel: ⌘ + Taste → Strg + gleiche physische Taste (⌘C/V/X/A/Z/S/F/L/T/W/R/N/P …).
- Sonderregeln:
  - ⌘⇧Z → Strg+Y
  - ⌘← / ⌘→ → Pos1 / Ende (mit ⇧ markierend); ⌘↑ / ⌘↓ → Strg+Pos1 / Strg+Ende (mit ⇧)
  - ⌥← / ⌥→ / ⌥↑ / ⌥↓ → Strg+Pfeil (mit ⇧); ⌥⌫ → Strg+Rück; ⌥⌦ → Strg+Entf
  - ⌘⌫ → ⇧Pos1, Rück (bis Zeilenanfang löschen); ⌘⌦ → ⇧Ende, Entf
  - ⌘⇥ (gehalten, mehrfach ⇥) → Alt gehalten + ⇥, ⌘⇧⇥ entsprechend; Alt los erst mit ⌘ los
  - ⌘Leertaste → Win (Startsuche); ⌥⌘Esc → Strg+⇧+Esc (Task-Manager)
  - ⌃⌥⌫ (bzw. ⌃⌥⌦) → Strg+Alt+Entf
  - ⌘Q → Alt+F4 (wie Jump; Sprung beenden über Menü bzw. ⌘Q außerhalb einer Sitzung),
    ⌘[ / ⌘] → Alt+← / Alt+→
- Lokal bleiben: ⌃⌘F (Vollbild), alles mit ⌃⌥⌘ (reserviert für App-Kürzel).
- ⌃ bleibt Strg (⌃C funktioniert also auch).
- Systemkürzel (⌘⇥, ⌘Leertaste, ⌃←/→ usw.) fängt macOS vor der App ab. Optional per CGEventTap
  abfangen (braucht Bedienungshilfen-Recht): Standard „im Vollbild“, wählbar „immer“/„nie“.

### Option-Taste (⌥)
Problem: Auf dem deutschen Mac kommt @ über ⌥L, € über ⌥E, { } [ ] | \ ~ über ⌥5/6/8/9/7, ⌥⇧7, ⌥N.
Unter Windows liegen die auf AltGr+andere Tasten. Strategien (pro Verbindung, Standard „Smart“):
- **Smart:** ⌥ + Taste erzeugt laut Mac-Layout ein „nützliches“ Zeichen (druckbares ASCII,
  €, „ “ ‚ ‘ « » – — … ° § und ähnliche) → als Unicode senden. Sonst (ƒ, ∂, …) → Alt + Taste
  (Accelerator, z. B. ⌥F → Alt+F, ⌥D → Alt+D). ⌥ + F-Tasten/Pfeile/Tab → Alt (⌥F4 = Alt+F4).
- **Jump-Stil:** rechte ⌥ = Sonderzeichen (Unicode), linke ⌥ = Alt.
- **Immer Alt** / **Immer Zeichen**.
- Tote Tasten (^ ´ ` ¨ ~) im Unicode-Pfad lokal komponieren (UCKeyTranslate mit deadKeyState).

### Text ohne Modifier
Standard Scancodes (Spiele und Tastenkürzel funktionieren, Layout ist synchronisiert).
Option pro Verbindung „Unicode-Eingabe“: alle druckbaren Zeichen als Unicode (für Layout-Mismatch).

### Zustand
- Tastenwiederholung: wiederholte Key-Downs durchreichen.
- Fokusverlust, Fenster inaktiv, Sitzungswechsel: alle gedrückten Tasten loslassen (keine hängenden
  Modifier). Fokusgewinn: `sync` mit Caps/Num/Scroll senden. NumLock immer an (Mac hat keins).
- Caps Lock: bei Zustandswechsel Caps-Scancode drücken+loslassen.
- Regeln liegen als Codable-Konfiguration (JSON) vor; UI erst Schalter, später Editor.

## Zwischenablage
Automatischer Abgleich in beide Richtungen: Text (Unicode, Zeilenenden), HTML, RTF, Bilder
(PNG/TIFF ↔ DIB), Dateien (FileGroupDescriptorW + FileContents, lazy, in beide Richtungen).
Maximalgröße konfigurierbar (Standard 128 MB).

## Migration aus Jump (Pflicht, Teil von M4)
Alle Verbindungen aus Jump werden übernommen, beim ersten Start automatisch (mit Vorschau und
Bestätigung) und jederzeit erneut über „Ablage → Aus Jump importieren“. Idempotent über Jumps `UniqueId`.
- Quelle: `…/com.p5sys.jump.mac.viewer/Data/Documents/JumpDesktop/Viewer/Servers/*.jump` (JSON).
- Felder: `DisplayName`, `TcpHostName`, `TcpPort`, `Username`, `Domain`, `ProtocolTypeCode`
  (0 = RDP, 1 = VNC), `DriveMappings[]` (Name, Pfad, aktiv) + `RdpDriveRedirection`,
  `ClipboardRedirection`, `AudioPlaybackCode`, `AudioInputDevice`, `RdpPrinterRedirection`,
  `DefaultPrinter`, `UseDynamicResolutionUpdate`, `MatchScreenResolution`, `ResolutionWidth/Height`,
  `UseHIDPIResolution`, `DesktopScaleFactor`, `StartInFullscreen`, `UseAllMonitors`/`MonitorCount`,
  `KeyboardLocaleId` + `KeyboardAutomaticLocaleDetection`, `RdpUseUnicodeKeyboard`, `RdpDisableNLA`,
  `RdpConsoleSession`, `IgnoreCertificateErrors`, `SslCertificateFingerPrint` (als vertrauenswürdig
  übernehmen), `RdpAlternateShellPath/WorkingDir`, `LoadBalancerInfo`, `RDGatewayUniqueId`, `MacAddresses`
  (Wake-on-LAN), `Tags`, `LastConnectedTime`. Unbekannte Felder im Importbericht auflisten statt verwerfen.
- VNC-Einträge (m4-mini) werden mit übernommen und öffnen die macOS-Bildschirmfreigabe (`vnc://host:port`).
- Passwörter liegen nicht in den Dateien und nicht lesbar im Schlüsselbund (Jump ist sandboxed). Beim
  ersten Verbinden fragt Sprung einmal und speichert im Schlüsselbund.
- Tastaturprofil: `…/Library/Application Support/Jump Desktop/JDInputProfile.plist` (NSKeyedArchiver,
  Profile „Mac“ und „Windows“). Marcs Profile sind Jumps Standard. Daraus übernommen in Sprungs Standardregeln:
  ⌘Q → Alt+F4 (in der Sitzung, nicht App beenden), ⌘[ / ⌘] → Alt+← / Alt+→, ⌘⇧Z → Strg+Y,
  ⌃⌥⌫ → Strg+Alt+Entf. Abweichende eigene Mappings im Profil werden als Regeln importiert.
- Danach Importbericht: was übernommen wurde, was nicht (mit Grund).

## Meilensteine
- **M1** Kern: FreeRDP-Build, Bridge, Sitzungsfenster mit Bild, Maus, Scrollen, Cursorformen,
  dynamische Auflösung, Retina. Headless-Smoke-Test.
- **M2** KeyboardEngine-Package mit Tests (parallel zu M1).
- **M3** Integration Tastatur + Zwischenablage (Text, Bilder), E2E-Tests gegen die VM.
- **M4** Verbindungsverwaltung, Jump-Import, Keychain, Zertifikats-Vertrauen (TOFU), Anmeldedialog.
- **M5** Laufwerke, Audio, Dateien über die Zwischenablage, Auto-Reconnect, Vollbild-Feinschliff.
- **M6** H.264 per VideoToolbox, Drucker, Multi-Monitor, Gateway (nach Bedarf).

Fertig heißt: Marc nutzt Sprung statt Jump für seine RDP-Ziele.
