import Foundation

/// The app's user-visible name, from the bundle (`CFBundleDisplayName`), so a rename touches only
/// the build settings. Texts that do not need the name avoid it.
enum AppInfo {
    static let name: String = {
        let info = Bundle.main.infoDictionary ?? [:]
        return info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? ProcessInfo.processInfo.processName
    }()
}
