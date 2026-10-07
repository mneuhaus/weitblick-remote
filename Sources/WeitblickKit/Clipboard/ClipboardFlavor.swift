import AppKit
import UniformTypeIdentifiers

/// One kind of clipboard content and how it maps between Mac pasteboard types and Windows formats.
/// Conversions are pure and may run on any thread.
///
/// Files (M5) fit in as another flavor for the descriptor ("FileGroupDescriptorW" <-> file URLs);
/// their contents additionally need FileContents requests on `RemoteClipboard`.
protocol ClipboardFlavor: Sendable {
    /// Mac types, best first: published for remote content, read for local content.
    var macTypes: [NSPasteboard.PasteboardType] { get }
    /// Windows formats, best first: announced for local content, requested for remote content.
    var windowsFormats: [WindowsClipboardFormat] { get }
    /// Whether local content with these pasteboard types should be offered to the remote side.
    func offers(_ types: [NSPasteboard.PasteboardType]) -> Bool
    /// Local data (of `type`, one of `macTypes`) converted to a Windows format.
    func windowsData(from data: Data, type: NSPasteboard.PasteboardType, as format: WindowsClipboardFormat) -> Data?
    /// Remote data (in `format`) converted to a Mac type.
    func macData(from data: Data, format: WindowsClipboardFormat, as type: NSPasteboard.PasteboardType) -> Data?
}

extension ClipboardFlavor {
    func offers(_ types: [NSPasteboard.PasteboardType]) -> Bool {
        macTypes.contains(where: types.contains)
    }
}

enum ClipboardFlavors {
    static let all: [any ClipboardFlavor] = [TextFlavor(), HTMLFlavor(), RTFFlavor(), ImageFlavor()]
}

/// Plain text: public.utf8-plain-text <-> CF_UNICODETEXT.
struct TextFlavor: ClipboardFlavor {
    let macTypes: [NSPasteboard.PasteboardType] = [.string]
    let windowsFormats: [WindowsClipboardFormat] = [.unicodeText]

    func windowsData(from data: Data, type: NSPasteboard.PasteboardType, as format: WindowsClipboardFormat) -> Data? {
        WindowsText.encode(String(decoding: data, as: UTF8.self))
    }

    func macData(from data: Data, format: WindowsClipboardFormat, as type: NSPasteboard.PasteboardType) -> Data? {
        Data(WindowsText.decode(data).utf8)
    }
}

/// public.html <-> "HTML Format" (CF_HTML with its offset header).
struct HTMLFlavor: ClipboardFlavor {
    let macTypes: [NSPasteboard.PasteboardType] = [.html]
    let windowsFormats: [WindowsClipboardFormat] = [.html]

    func windowsData(from data: Data, type: NSPasteboard.PasteboardType, as format: WindowsClipboardFormat) -> Data? {
        ClipboardHTML.encode(String(decoding: data, as: UTF8.self))
    }

    func macData(from data: Data, format: WindowsClipboardFormat, as type: NSPasteboard.PasteboardType) -> Data? {
        ClipboardHTML.decode(data).map { Data($0.utf8) }
    }
}

/// public.rtf <-> "Rich Text Format". RTF is 7-bit text on both sides; Windows adds a NUL.
struct RTFFlavor: ClipboardFlavor {
    let macTypes: [NSPasteboard.PasteboardType] = [.rtf]
    let windowsFormats: [WindowsClipboardFormat] = [.rtf]

    func windowsData(from data: Data, type: NSPasteboard.PasteboardType, as format: WindowsClipboardFormat) -> Data? {
        data + [0]
    }

    func macData(from data: Data, format: WindowsClipboardFormat, as type: NSPasteboard.PasteboardType) -> Data? {
        Data(data.prefix { $0 != 0 })
    }
}

/// public.png / public.tiff <-> "PNG", CF_DIBV5, CF_DIB.
struct ImageFlavor: ClipboardFlavor {
    let macTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]
    let windowsFormats: [WindowsClipboardFormat] = [.png, .dibV5, .dib]

    /// Finder puts file icons next to copied files; those are not the user's image.
    func offers(_ types: [NSPasteboard.PasteboardType]) -> Bool {
        macTypes.contains(where: types.contains) && !types.contains(.fileURL)
    }

    func windowsData(from data: Data, type: NSPasteboard.PasteboardType, as format: WindowsClipboardFormat) -> Data? {
        if format == .png, ClipboardImage.isPNG(data) { return data }
        guard let image = ClipboardImage.decode(data) else { return nil }
        switch format {
        case .png: return ClipboardImage.encode(image, as: .png)
        case .dibV5: return DeviceIndependentBitmap.encodeDIBV5(image)
        case .dib: return DeviceIndependentBitmap.encodeDIB(image)
        default: return nil
        }
    }

    func macData(from data: Data, format: WindowsClipboardFormat, as type: NSPasteboard.PasteboardType) -> Data? {
        if format == .png, type == .png, ClipboardImage.isPNG(data) { return data }
        let image = format == .png ? ClipboardImage.decode(data) : DeviceIndependentBitmap.decode(data)
        guard let image else { return nil }
        return ClipboardImage.encode(image, as: type == .png ? .png : .tiff)
    }
}
