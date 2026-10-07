import AppKit
import os

/// Files over the clipboard for `ClipboardSync`, in both directions (FileGroupDescriptorW plus
/// FileContents streams, MS-RDPECLIP 3.1.5.4).
///
/// Mac -> Windows: file URLs on the pasteboard are announced as a descriptor; when the server asks
/// for it, the files are listed (folders recursively) and later read in pieces as the server asks.
/// Windows -> Mac: a server descriptor becomes one pasteboard item per copied file or folder whose
/// file URL is downloaded only when an app reads it (`RemoteFileTransfer`).
@MainActor
final class ClipboardFiles {
    /// Largest total of one file copy, in either direction.
    static let defaultMaxTransferSize: UInt64 = 2 << 30

    nonisolated let fetcher: RemoteFileFetcher
    /// Our id for the descriptor in the current announcement.
    private(set) var announcedFormatID: UInt32?
    private var announcedURLs: [URL] = []
    private let remote: RemoteClipboard
    private let maxTransferSize: UInt64
    /// The list the server is reading from; touched only on the responder queue.
    private nonisolated let served = ServedList()
    private nonisolated static let logger = Logger(subsystem: "nrw.neuhaus.weitblick-remote", category: "clipboard")

    init(remote: RemoteClipboard, maxTransferSize: UInt64) {
        self.remote = remote
        self.maxTransferSize = maxTransferSize
        self.fetcher = RemoteFileFetcher { [remote] request in remote.requestFile(request) }
        DispatchQueue.global(qos: .utility).async { RemoteFileTransfer.purgeStale() }
    }

    // MARK: Mac -> Windows

    /// Local files on the pasteboard (Finder copies), or nil.
    func localFileURLs(on pasteboard: NSPasteboard) -> [URL]? {
        guard pasteboard.types?.contains(.fileURL) == true,
              let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty
        else { return nil }
        return urls
    }

    func announced(_ urls: [URL], as formatID: UInt32) {
        announcedFormatID = formatID
        announcedURLs = urls
    }

    func clearAnnouncement() {
        announcedFormatID = nil
        announcedURLs = []
    }

    /// The server asked for the announced descriptor: list the files on `queue` and answer.
    func respondWithDescriptor(on queue: DispatchQueue) {
        let urls = announcedURLs
        let remote = remote
        let maxTransferSize = maxTransferSize
        let served = served
        queue.async {
            served.list = LocalFileList(fileURLs: urls, maxTotalSize: maxTransferSize)
            if let list = served.list {
                Self.logger.notice("offering \(list.entries.count) files and folders, \(list.totalSize) bytes")
            }
            remote.respond(with: served.list?.descriptor)
        }
    }

    /// A server request for file data (channel thread); answered on `queue`.
    nonisolated func answer(_ request: RemoteFileRequest, on queue: DispatchQueue) {
        let remote = remote
        let served = served
        queue.async {
            remote.respondFile(streamID: request.streamID, data: served.list?.answer(request))
        }
    }

    // MARK: Windows -> Mac

    /// The server offers files: fetch its descriptor in the background, then hand the pasteboard
    /// items to `publish` (main actor), unless the server clipboard changed meanwhile.
    func receive(descriptorFormatID: UInt32, using dataFetcher: RemoteDataFetcher,
                 publish: @escaping @MainActor ([NSPasteboardItem]) -> Void) {
        let fetcher = fetcher
        let generation = fetcher.generation
        let maxTransferSize = maxTransferSize
        DispatchQueue.global(qos: .userInitiated).async {
            guard let data = dataFetcher.fetch(formatID: descriptorFormatID, timeout: 10),
                  let entries = FileGroupDescriptor.decode(data), !entries.isEmpty
            else {
                // A newer server clipboard (Windows often announces twice) cancels the fetch quietly.
                if fetcher.generation == generation { Self.logger.error("server file list unreadable") }
                return
            }
            let transfer = RemoteFileTransfer(entries: entries, fetcher: fetcher, generation: generation)
            guard transfer.totalSize <= maxTransferSize else {
                Self.logger.notice("not taking \(transfer.totalSize) bytes of files: over the limit of \(maxTransferSize)")
                return
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard fetcher.generation == generation else { return }
                    Self.logger.notice("server copied \(entries.count) files and folders, \(transfer.totalSize) bytes")
                    publish(transfer.pasteboardItems())
                }
            }
        }
    }

    /// The server clipboard changed or the channel closed (channel thread).
    nonisolated func reset() {
        fetcher.reset()
    }

    private final class ServedList: @unchecked Sendable {
        var list: LocalFileList?
    }
}
