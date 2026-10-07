import Foundation

/// App-wide preferences in UserDefaults. SwiftUI views bind the same keys with `@AppStorage`.
enum AppSettings {
    static let sessionsInOwnWindowsKey = "sessionsInOwnWindows"
    static let confirmCloseSessionKey = "confirmCloseSession"
    static let overviewSortKey = "overviewSort"

    /// Sessions open as separate windows instead of tabs next to the overview (multi-monitor work).
    static var sessionsInOwnWindows: Bool {
        get { UserDefaults.standard.bool(forKey: sessionsInOwnWindowsKey) }
        set { UserDefaults.standard.set(newValue, forKey: sessionsInOwnWindowsKey) }
    }

    /// Ask before closing a session tab disconnects it.
    static var confirmCloseSession: Bool {
        get { UserDefaults.standard.object(forKey: confirmCloseSessionKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: confirmCloseSessionKey) }
    }
}
