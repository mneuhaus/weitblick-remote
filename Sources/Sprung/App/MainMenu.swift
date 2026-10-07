import AppKit
import KeyboardEngine

/// The menu bar, built in code (no nib).
@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(submenu(appMenu()))
        menu.addItem(submenu(viewMenu(), title: "Darstellung"))
        menu.addItem(submenu(SessionMenu.make(), title: "Sitzung"))
        return menu
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "Sprung")
        menu.addItem(withTitle: "Über Sprung", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Sprung ausblenden", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        menu.addItem(.separator())
        // In a session window ⌘Q goes to Windows (Alt+F4); the menu item still quits from anywhere.
        menu.addItem(withTitle: "Sprung beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "Darstellung")
        let fullScreen = menu.addItem(withTitle: "Vollbild", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.control, .command]
        menu.addItem(withTitle: "Fenster schließen", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        return menu
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
