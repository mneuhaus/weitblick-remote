import AppKit
import KeyboardEngine

/// The menu bar, built in code (no nib). In a connected session every key goes to Windows except
/// ⌃⌘F and ⌃⌥⌘ shortcuts, so session-time commands live under ⌃⌥⌘ or have no key equivalent.
@MainActor
enum MainMenu {
    static func make(coordinator: WindowCoordinator) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(submenu(appMenu(coordinator)))
        menu.addItem(submenu(fileMenu(coordinator)))
        menu.addItem(submenu(editMenu()))
        menu.addItem(submenu(viewMenu()))
        menu.addItem(submenu(SessionMenu.make()))
        let window = windowMenu(coordinator)
        menu.addItem(submenu(window))
        NSApp.windowsMenu = window
        return menu
    }

    private static func appMenu(_ coordinator: WindowCoordinator) -> NSMenu {
        let menu = NSMenu(title: AppInfo.name)
        menu.addItem(item(String(localized: "About \(AppInfo.name)"), #selector(WindowCoordinator.showAbout(_:)), target: coordinator))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Settings…"), #selector(WindowCoordinator.showSettings(_:)), ",", target: coordinator))
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Hide \(AppInfo.name)"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        menu.addItem(.separator())
        // In a session window ⌘Q goes to Windows (Alt+F4); the menu item still quits from anywhere.
        menu.addItem(withTitle: String(localized: "Quit \(AppInfo.name)"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private static func fileMenu(_ coordinator: WindowCoordinator) -> NSMenu {
        let menu = NSMenu(title: String(localized: "File"))
        menu.addItem(item(String(localized: "New Connection…"), #selector(WindowCoordinator.newConnection(_:)), "n", target: coordinator))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Import from Jump Desktop…"), #selector(WindowCoordinator.importFromJump(_:)), target: coordinator))
        menu.addItem(item(String(localized: "Import .rdp File…"), #selector(WindowCoordinator.importRDPFile(_:)), "o", target: coordinator))
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Close Window"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        return menu
    }

    /// Standard text editing for the fields in the overview, editor and sheets.
    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Edit"))
        menu.addItem(withTitle: String(localized: "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: String(localized: "Redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: String(localized: "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "View"))
        let fullScreen = menu.addItem(withTitle: String(localized: "Enter Full Screen"), action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.control, .command]
        return menu
    }

    /// Tabs: ⌃⌥⌘1 = overview, ⌃⌥⌘2…9 = sessions in tab order, ⌃⌥⌘← / → = previous / next.
    private static func windowMenu(_ coordinator: WindowCoordinator) -> NSMenu {
        let menu = NSMenu(title: String(localized: "Window"))
        menu.addItem(withTitle: String(localized: "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: String(localized: "Zoom"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        let tabModifiers: NSEvent.ModifierFlags = [.control, .option, .command]
        let previous = item(String(localized: "Show Previous Tab"), #selector(WindowCoordinator.selectPreviousTab(_:)),
                            String(UnicodeScalar(NSLeftArrowFunctionKey)!), target: coordinator)
        let next = item(String(localized: "Show Next Tab"), #selector(WindowCoordinator.selectNextTab(_:)),
                        String(UnicodeScalar(NSRightArrowFunctionKey)!), target: coordinator)
        for entry in [previous, next] {
            entry.keyEquivalentModifierMask = tabModifiers
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        for tag in 0...8 {
            let entry = item(tag == 0 ? String(localized: "Overview") : String(localized: "Session \(tag)"), #selector(WindowCoordinator.selectTab(_:)),
                             "\(tag + 1)", target: coordinator)
            entry.tag = tag
            entry.keyEquivalentModifierMask = tabModifiers
            entry.allowsKeyEquivalentWhenHidden = true
            entry.isHidden = tag > 0
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Open Sessions in Separate Windows"), #selector(WindowCoordinator.toggleSessionsInOwnWindows(_:)),
                          target: coordinator))
        menu.delegate = coordinator
        return menu
    }

    private static func item(_ title: String, _ action: Selector, _ key: String = "", target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        return item
    }

    /// The item shows the menu's own title unless `title` says otherwise.
    static func submenu(_ menu: NSMenu, title: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title ?? menu.title, action: nil, keyEquivalent: "")
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
        let menu = NSMenu(title: String(localized: "Session"))
        add(String(localized: "Reconnect"), #selector(SessionWindowController.reconnect(_:)), to: menu)
        menu.addItem(.separator())
        add(String(localized: "Send Ctrl+Alt+Del"), #selector(SessionWindowController.sendCtrlAltDelete(_:)), to: menu)
        add(String(localized: "Windows Key"), #selector(SessionWindowController.sendWindowsKey(_:)), to: menu)
        add("Alt+Tab", #selector(SessionWindowController.sendAltTab(_:)), to: menu)
        add(String(localized: "Print Screen"), #selector(SessionWindowController.sendPrintScreen(_:)), to: menu)
        menu.addItem(.separator())
        for (tag, title) in [String(localized: "Keyboard: Mac Shortcuts"), String(localized: "Keyboard: Windows 1:1")].enumerated() {
            add(title, #selector(SessionWindowController.selectKeyboardMode(_:)), tag: tag, to: menu)
        }
        let option = NSMenu(title: String(localized: "⌥ Key"))
        for (tag, title) in [String(localized: "Smart"), String(localized: "Jump Style (Right ⌥ = Characters)"),
                                   String(localized: "Always Alt"), String(localized: "Always Characters")].enumerated() {
            add(title, #selector(SessionWindowController.selectOptionStrategy(_:)), tag: tag, to: option)
        }
        menu.addItem(MainMenu.submenu(option))
        menu.addItem(.separator())
        add(String(localized: "Sync Clipboard"), #selector(SessionWindowController.toggleClipboardSync(_:)), to: menu)
        menu.addItem(.separator())
        let capture = NSMenu(title: String(localized: "System Shortcuts to Windows"))
        for (tag, title) in [String(localized: "In Full Screen"), String(localized: "Always"), String(localized: "Never")].enumerated() {
            add(title, #selector(SessionWindowController.selectSystemShortcutCapture(_:)), tag: tag, to: capture)
        }
        menu.addItem(MainMenu.submenu(capture, title: String(localized: "System Shortcuts to Windows (⌘⇥, ⌘Space, ⌃←/→)")))
        let hint = add(String(localized: "Allow Accessibility Access for System Shortcuts…"),
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
