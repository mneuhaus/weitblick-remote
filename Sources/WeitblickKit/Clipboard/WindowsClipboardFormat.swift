/// A Windows clipboard format independent of the numeric id a peer assigned to it: standard
/// formats by id, registered formats by name (ids of registered formats differ per side).
public enum WindowsClipboardFormat: Hashable, Sendable {
    case standard(UInt32)
    case registered(String)

    public static let unicodeText = WindowsClipboardFormat.standard(13) // CF_UNICODETEXT
    public static let dib = WindowsClipboardFormat.standard(8) // CF_DIB
    public static let dibV5 = WindowsClipboardFormat.standard(17) // CF_DIBV5
    public static let html = WindowsClipboardFormat.registered("HTML Format")
    public static let rtf = WindowsClipboardFormat.registered("Rich Text Format")
    public static let png = WindowsClipboardFormat.registered("PNG")

    /// Whether `format` from a peer's format list is this format. Registered names compare
    /// case-insensitively, like `RegisterClipboardFormat`.
    func matches(_ format: RemoteClipboardFormat) -> Bool {
        switch self {
        case .standard(let id): format.name == nil && format.id == id
        case .registered(let name): format.name?.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    /// First id of the range Windows uses for registered formats; ours are numbered from here.
    static let firstRegisteredID: UInt32 = 0xC000
}
