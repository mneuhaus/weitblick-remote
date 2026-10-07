import AppKit
import KeyboardEngine

/// The menu bar, built in code (no nib). In a connected session every key goes to Windows except
/// ⌃⌘F and ⌃⌥⌘ shortcuts, so session-time commands live under ⌃⌥⌘ or have no key equivalent.
@MainActor
enum MainMenu {
    static func make(coordinator: WindowCoordinator) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(submenu(appMenu(coordinator)))
        menu.addItem(submenu(fileMenu(coordinator), title: "Ablage"))
        menu.addItem(submenu(editMenu(), title: "Bearbeiten"))
        menu.addItem(submenu(viewMenu(), title: "Darstellung"))
        menu.addItem(submenu(SessionMenu.make(), title: "Sitzung"))
        let window = windowMenu(coordinator)
        menu.addItem(submenu(window, title: "Fenster"))
        NSApp.windowsMenu = window
        return menu
    }

    private static func appMenu(_ coordinator: WindowCoordinator) -> NSMenu {
        let menu = NSMenu(title: AppInfo.name)
        menu.addItem(withTitle: "Über \(AppInfo.name)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(item("Einstellungen…", #selector(WindowCoordinator.showSettings(_:)), ",", target: coordinator))
        menu.addItem(.separator())
        menu.addItem(withTitle: "\(AppInfo.name) ausblenden", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        menu.addItem(.separator())
        // In a session window ⌘Q goes to Windows (Alt+F4); the menu item still quits from anywhere.
        menu.addItem(withTitle: "\(AppInfo.name) beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private static func fileMenu(_ coordinator: WindowCoordinator) -> NSMenu {
        let menu = NSMenu(title: "Ablage")
        menu.addItem(item("Neue Verbindung…", #selector(WindowCoordinator.newConnection(_:)), "n", target: coordinator))
        menu.addItem(.separator())
        menu.addItem(item("Aus Jump importieren…", #selector(WindowCoordinator.importFromJump(_:)), target: coordinator))
        menu.addItem(item(".rdp importieren…", #selector(WindowCoordinator.importRDPFile(_:)), "o", target: coordinator))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Fenster schließen", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        return menu
    }

    /// Standard text editing for the fields in the overview, editor and sheets.
    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Bearbeiten")
        menu.addItem(withTitle: "Widerrufen", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: "Wiederholen", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: "Ausschneiden", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Kopieren", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Einsetzen", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Alles auswählen", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "Darstellung")
        let fullScreen = menu.addItem(withTitle: "Vollbild", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.control, .command]
        return menu
    }

    /// Tabs: ⌃⌥⌘1 = Übersicht, ⌃⌥⌘2…9 = sessions in tab order, ⌃⌥⌘← / → = previous / next.
    private static func windowMenu(_ coordinator: WindowCoordinator) -> NSMenu {
        let menu = NSMenu(title: "Fenster")
        menu.addItem(withTitle: "Im Dock ablegen", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoomen", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        let tabModifiers: NSEvent.ModifierFlags = [.control, .option, .command]
        let previous = item("Vorheriger Tab", #selector(WindowCoordinator.selectPreviousTab(_:)),
                            String(UnicodeScalar(NSLeftArrowFunctionKey)!), target: coordinator)
        let next = item("Nächster Tab", #selector(WindowCoordinator.selectNextTab(_:)),
                        String(UnicodeScalar(NSRightArrowFunctionKey)!), target: coordinator)
        for entry in [previous, next] {
            entry.keyEquivalentModifierMask = tabModifiers
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        for tag in 0...8 {
            let entry = item(tag == 0 ? "Übersicht" : "Sitzung \(tag)", #selector(WindowCoordinator.selectTab(_:)),
                             "\(tag + 1)", target: coordinator)
            entry.tag = tag
            entry.keyEquivalentModifierMask = tabModifiers
            entry.allowsKeyEquivalentWhenHidden = true
            entry.isHidden = tag > 0
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        menu.addItem(item("Sitzungen in eigenen Fenstern öffnen", #selector(WindowCoordinator.toggleSessionsInOwnWindows(_:)),
                          target: coordinator))
        menu.delegate = coordinator
        return menu
    }

    private static func item(_ title: String, _ action: Selector, _ key: String = "", target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        return item
    }

    static func submenu(_ menu: NSMenu, title: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}

/// Commands for the key session window (handled by `SessionWindowController`). No key
/// equivalents: in a session every key belongs to Windows except ⌃⌘F and ⌃⌥⌘ shortcuts.
@MainActor
enum SessionMenu {
    static let keyboardModes: [KeyboardConfig.Mode] = [.macShortcuts, .windowsDirect]
    static let optionStrategies: [KeyboardConfig.OptionStrategy] = [.smart, .jumpStyle, .alwaysAlt, .alwaysCharacters]

    static func make() -> NSMenu {
        let menu = NSMenu(title: "Sitzung")
        add("Erneut verbinden", #selector(SessionWindowController.reconnect(_:)), to: menu)
        menu.addItem(.separator())
        add("Strg+Alt+Entf senden", #selector(SessionWindowController.sendCtrlAltDelete(_:)), to: menu)
        add("Windows-Taste", #selector(SessionWindowController.sendWindowsKey(_:)), to: menu)
        add("Alt+Tab", #selector(SessionWindowController.sendAltTab(_:)), to: menu)
        add("Druck", #selector(SessionWindowController.sendPrintScreen(_:)), to: menu)
        menu.addItem(.separator())
        for (tag, title) in ["Tastatur: Mac-Kurzbefehle", "Tastatur: Windows 1:1"].enumerated() {
            add(title, #selector(SessionWindowController.selectKeyboardMode(_:)), tag: tag, to: menu)
        }
        let option = NSMenu(title: "⌥-Taste")
        for (tag, title) in ["Smart", "Jump-Stil (rechte ⌥ = Zeichen)", "Immer Alt", "Immer Zeichen"].enumerated() {
            add(title, #selector(SessionWindowController.selectOptionStrategy(_:)), tag: tag, to: option)
        }
        menu.addItem(MainMenu.submenu(option, title: "⌥-Taste"))
        menu.addItem(.separator())
        add("Zwischenablage abgleichen", #selector(SessionWindowController.toggleClipboardSync(_:)), to: menu)
        menu.addItem(.separator())
        let capture = NSMenu(title: "Systemkürzel an Windows")
        for (tag, title) in ["Im Vollbild", "Immer", "Nie"].enumerated() {
            add(title, #selector(SessionWindowController.selectSystemShortcutCapture(_:)), tag: tag, to: capture)
        }
        menu.addItem(MainMenu.submenu(capture, title: "Systemkürzel an Windows (⌘⇥, ⌘Leertaste, ⌃←/→)"))
        let hint = add("Systemkürzel brauchen Bedienungshilfen-Recht – Einstellungen öffnen…",
                       #selector(AccessibilityHint.openSettings(_:)), to: menu)
        hint.target = accessibilityHint
        accessibilityHint.hint = hint
        menu.delegate = accessibilityHint
        return menu
    }

    @discardableResult
    private static func add(_ title: String, _ action: Selector, tag: Int = 0, to menu: NSMenu) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.tag = tag
        return item
    }

    private static let accessibilityHint = AccessibilityHint()

    /// The permission hint: shown only while it matters (decided each time the menu opens, since
    /// hidden items are not validated); opens the Accessibility pane. Never prompts on its own.
    private final class AccessibilityHint: NSObject, NSMenuDelegate {
        weak var hint: NSMenuItem?

        func menuNeedsUpdate(_ menu: NSMenu) {
            MainActor.assumeIsolated {
                hint?.isHidden = SystemShortcutTap.isPermitted || SystemShortcutCapture.setting == .never
            }
        }

        @objc func openSettings(_ sender: Any?) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }
}
