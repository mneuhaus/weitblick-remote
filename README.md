# Sprung

Nativer RDP-Client für macOS (Apple Silicon, macOS 14+), gebaut auf FreeRDP 3. Ziel und Meilensteine
stehen in [docs/SPEC.md](docs/SPEC.md), der Arbeitsstand in [docs/worklog/](docs/worklog/).

## Voraussetzungen

- Xcode 26, `brew install cmake ninja xcodegen openssl@3`
- Submodul: `git submodule update --init vendor/FreeRDP`

## Bauen

```sh
scripts/build.sh            # FreeRDP (falls nötig), Xcode-Projekt, App + Smoke-Tool (Debug) nach build/
open build/Sprung.app
```

`scripts/build-freerdp.sh` baut FreeRDP/WinPR statisch nach `vendor/install` und überspringt sich, solange
Submodul-Commit, Flags und Skript unverändert sind (`--force` erzwingt einen Neubau).
`project.yml` ist die Quelle des Xcode-Projekts (`xcodegen generate`); `Sprung.xcodeproj` wird nicht eingecheckt.

## Testen

```sh
scripts/smoke.sh                       # Headless gegen die Test-VM aus .testvm.env, 10 Verbindungszyklen
scripts/smoke.sh --cycles 3 --soak 180 # zusätzlich 3 Minuten Maus/Tastatur/Resize-Last
scripts/e2e.sh                         # Tastatur + Zwischenablage gegen die VM, 3 Durchläufe
xcodebuild -project Sprung.xcodeproj -scheme Sprung -derivedDataPath build/DerivedData test
(cd Packages/KeyboardEngine && swift test)
```

`scripts/e2e.sh` tippt über die KeyboardEngine (deutsches Mac-Layout) in Notepad, prüft die
Kurzbefehl-Übersetzung und schickt Text, Bilder, HTML und RTF in beide Richtungen über die
Zwischenablage, mit einer privaten Pasteboard (die echte Zwischenablage bleibt unberührt). Ergebnisse
und Belege landen in `build/evidence/m3-e2e-<Zeit>/`.

Der Smoke-Test schreibt `build/smoke.png`, `build/smoke-resized.png` und `build/cursors/` und endet mit
`SMOKE OK` (Exit 0) oder `SMOKE FAIL: <Grund>` (Exit 1). Windows 11 Pro erlaubt nur eine aktive Sitzung:
Ist an der VM-Konsole jemand angemeldet, bricht `smoke.sh` ab; `--takeover` trennt diese Sitzung vorher
(`tsdiscon`, die Programme laufen weiter).

Debug-Builds füllen das Verbindungsformular aus `.testvm.env`; `Sprung --autoconnect` verbindet sofort.

## Aufbau

- `Sources/SprungBridge` – C-Brücke zu libfreerdp (Sitzung, Eventloop-Thread, Framebuffer, Eingabe)
- `Sources/SprungKit` – Swift-Hülle `RDPSession` und Zwischenablage-Abgleich, von App und Testwerkzeugen genutzt
- `Sources/Sprung` – App (AppKit, Formular in SwiftUI)
- `Sources/SprungSmoke` – Headless-Smoke-Test
- `Sources/SprungE2E` – Tastatur- und Zwischenablage-E2E-Test gegen die VM
- `Packages/KeyboardEngine` – Tastaturübersetzung (M2)

Lizenz: Apache-2.0
