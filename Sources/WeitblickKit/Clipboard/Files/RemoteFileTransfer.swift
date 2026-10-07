import AppKit
import os

/// Files copied on the server, offered on the Mac pasteboard as one item per copied file or folder
/// with a lazy file URL. When an app reads an item's URL (Finder on paste), that file or folder is
/// downloaded into a private temporary folder and its URL handed out; the app then copies it.
///
/// Reading blocks the reading thread (AppKit's main thread for other apps) until the download is
/// done; it never waits for the main thread, and a stalled server fails it after
/// `RemoteFileFetcher.stallTimeout`.
final class RemoteFileTransfer: @unchecked Sendable {
    let entries: [ClipboardFileEntry]
    private let fetcher: RemoteFileFetcher
    private let generation: Int
    private let directory: URL
    private let lock = NSLock()
    private var materialized: [Int: URL] = [:] // guarded by `lock`; serializes downloads too

    private static let logger = Logger(subsystem: "nrw.neuhaus.weitblick-remote", category: "clipboard")
    /// Where downloads go; one subfolder per transfer.
    static let rootDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(AppIdentity.supportFolderName)-Clipboard", isDirectory: true)
    /// Downloaded files stay this long after the pasteboard moved on (an app may still be copying them).
    static let keepAfterUse: TimeInterval = 10 * 60

    init(entries: [ClipboardFileEntry], fetcher: RemoteFileFetcher, generation: Int) {
        self.entries = entries
        self.fetcher = fetcher
        self.generation = generation
        self.directory = Self.rootDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    var totalSize: UInt64 { entries.reduce(0) { $0 + $1.size } }

    /// One pasteboard item per top-level entry.
    func pasteboardItems() -> [NSPasteboardItem] {
        entries.indices.filter { entries[$0].isTopLevel }.map { index in
            let item = NSPasteboardItem()
            item.setDataProvider(ItemProvider(transfer: self, index: index), forTypes: [.fileURL])
            return item
        }
    }

    /// Downloads the top-level entry `index` with everything below it; its local URL, or nil.
    func materialize(_ index: Int) -> URL? {
        lock.lock()
        defer { lock.unlock() }
        if let url = materialized[index] { return url }
        let top = entries[index]
        let started = Date()
        var bytes: UInt64 = 0
        for (entryIndex, entry) in entries.enumerated() where entryIndex == index || entry.path.hasPrefix(top.path + "\\") {
            let url = entry.components.reduce(directory) { $0.appendingPathComponent($1) }
            guard download(entryIndex, to: url) else {
                Self.logger.error("download of \(entry.path, privacy: .private) failed")
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(top.path))
                return nil
            }
            bytes += entry.size
        }
        let seconds = Date().timeIntervalSince(started)
        Self.logger.notice("downloaded \(top.path, privacy: .private): \(bytes) bytes in \(String(format: "%.2f", seconds), privacy: .public) s")
        let url = directory.appendingPathComponent(top.path, isDirectory: top.isDirectory)
        materialized[index] = url
        return url
    }

    /// Removes the downloads after a grace period.
    func discardLater() {
        let directory = directory
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.keepAfterUse) {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// Removes downloads of earlier app runs.
    static func purgeStale(olderThan age: TimeInterval = 24 * 60 * 60) {
        let fileManager = FileManager.default
        guard let folders = try? fileManager.contentsOfDirectory(at: rootDirectory, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return }
        for folder in folders {
            let modified = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, Date().timeIntervalSince(modified) > age { try? fileManager.removeItem(at: folder) }
        }
    }

    private func download(_ index: Int, to url: URL) -> Bool {
        let entry = entries[index]
        let fileManager = FileManager.default
        do {
            if entry.isDirectory {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
                return true
            }
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard fileManager.createFile(atPath: url.path, contents: nil) else { return false }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            let size = entry.size > 0 ? entry.size : (fetcher.size(of: index, generation: generation) ?? 0)
            guard fetcher.download(fileIndex: index, size: size, generation: generation, write: { try handle.write(contentsOf: $0) }) else {
                return false
            }
            if let modified = entry.modified {
                try? fileManager.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
            }
            return true
        } catch {
            Self.logger.error("writing \(url.path, privacy: .private) failed: \(error, privacy: .public)")
            return false
        }
    }

    private final class ItemProvider: NSObject, NSPasteboardItemDataProvider, @unchecked Sendable {
        let transfer: RemoteFileTransfer
        let index: Int

        init(transfer: RemoteFileTransfer, index: Int) {
            self.transfer = transfer
            self.index = index
        }

        func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
            guard type == .fileURL, let url = transfer.materialize(index) else { return }
            item.setString(url.absoluteString, forType: .fileURL)
        }

        func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {
            transfer.discardLater()
        }
    }
}
