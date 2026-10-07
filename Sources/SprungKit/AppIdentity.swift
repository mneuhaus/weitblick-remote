/// Names on disk that carry the app's name, in one place for a rename. User-visible German
/// messages in SprungKit do not mention the app; Windows sees the Mac's computer name, not ours.
public enum AppIdentity {
    /// Folder under Application Support and prefix of temporary folders. The app's connection
    /// store has its own copy (ConnectionStore.applicationSupportFolderName).
    public static let supportFolderName = "Sprung"
}
