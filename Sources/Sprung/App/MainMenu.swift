import AppKit

/// The menu bar, built in code (no nib).
@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(submenu(appMenu()))
        menu.addItem(submenu(viewMenu(), title: "Darstellung"))
        return menu
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "Sprung")
        menu.addItem(withTitle: "Über Sprung", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Sprung ausblenden", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        menu.addItem(.separator())
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

    private static func submenu(_ menu: NSMenu, title: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
