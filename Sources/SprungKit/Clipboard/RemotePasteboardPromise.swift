import AppKit

/// Remote clipboard content promised on the Mac pasteboard. Data is fetched from the server only
/// when an app reads a type (main thread, bounded wait on the channel thread, never the reverse).
final class RemotePasteboardPromise: NSObject, NSPasteboardItemDataProvider, Sendable {
    struct Offer: Sendable {
        let flavor: any ClipboardFlavor
        let format: WindowsClipboardFormat
        /// The server's id for `format`.
        let formatID: UInt32
    }

    let offers: [NSPasteboard.PasteboardType: Offer]
    private let fetcher: RemoteDataFetcher
    private let generation: Int
    /// How long a reading app may block on the server.
    private let timeout: TimeInterval

    init(offers: [NSPasteboard.PasteboardType: Offer], fetcher: RemoteDataFetcher, timeout: TimeInterval) {
        self.offers = offers
        self.fetcher = fetcher
        self.generation = fetcher.generation
        self.timeout = timeout
    }

    /// The type's data if it has already been fetched (no server round trip).
    func cachedData(for type: NSPasteboard.PasteboardType) -> Data? {
        guard let offer = offers[type], let remote = fetcher.cachedData(formatID: offer.formatID) else { return nil }
        return offer.flavor.macData(from: remote, format: offer.format, as: type)
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        guard let offer = offers[type],
              let remote = fetcher.fetch(formatID: offer.formatID, timeout: timeout),
              let data = offer.flavor.macData(from: remote, format: offer.format, as: type)
        else { return }
        item.setData(data, forType: type)
    }

    func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {
        fetcher.discard(generation: generation)
    }
}
