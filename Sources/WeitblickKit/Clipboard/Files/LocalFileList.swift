import Foundation
import os

/// Files copied on the Mac, as offered to the server: folders are walked recursively (folders come
/// before their contents), and file data is read from disk only when the server asks for it.
/// Not thread safe: use it from one serial queue.
final class LocalFileList {
    let entries: [ClipboardFileEntry]
    let totalSize: UInt64
    private let urls: [URL]
    private var openFile: (index: Int, handle: FileHandle)?

    /// Largest piece read for one request; the server asks again for the rest.
    static let maxChunk = 4 << 20
    private static let logger = Logger(subsystem: "nrw.neuhaus.weitblick-remote", category: "clipboard")

    /// nil if there is nothing to offer or the files are larger than `maxTotalSize` together.
    init?(fileURLs: [URL], maxTotalSize: UInt64) {
        var entries: [ClipboardFileEntry] = []
        var urls: [URL] = []
        var total: UInt64 = 0
        func add(_ url: URL, path: String, values: URLResourceValues) {
            guard path.utf16.count <= FileGroupDescriptor.maxPathLength else {
                Self.logger.notice("skipping \(path, privacy: .private): path too long for Windows")
                return
            }
            let isDirectory = values.isDirectory == true
            let size = isDirectory ? 0 : UInt64(values.fileSize ?? 0)
            total += size
            entries.append(ClipboardFileEntry(path: path, isDirectory: isDirectory, size: size,
                                              modified: values.contentModificationDate))
            urls.append(url)
        }
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        for url in fileURLs {
            let url = url.resolvingSymlinksInPath()
            guard let values = try? url.resourceValues(forKeys: keys), values.isDirectory == true || values.isRegularFile == true
            else { continue }
            add(url, path: url.lastPathComponent, values: values)
            guard values.isDirectory == true, let walker = FileManager.default.enumerator(atPath: url.path) else { continue }
            for case let relative as String in walker {
                let child = url.appendingPathComponent(relative)
                guard child.lastPathComponent != ".DS_Store",
                      let childValues = try? child.resourceValues(forKeys: keys),
                      childValues.isDirectory == true || childValues.isRegularFile == true
                else { continue }
                let path = ([url.lastPathComponent] + relative.split(separator: "/").map(String.init)).joined(separator: "\\")
                add(child, path: path, values: childValues)
            }
        }
        guard !entries.isEmpty, total <= maxTotalSize else {
            if total > maxTotalSize { Self.logger.notice("not offering \(total) bytes of files: over the limit of \(maxTotalSize)") }
            return nil
        }
        self.entries = entries
        self.urls = urls
        self.totalSize = total
    }

    deinit {
        try? openFile?.handle.close()
    }

    var descriptor: Data { FileGroupDescriptor.encode(entries) }

    /// The answer to a server request, nil if it cannot be served.
    func answer(_ request: RemoteFileRequest) -> Data? {
        guard entries.indices.contains(request.fileIndex) else { return nil }
        let entry = entries[request.fileIndex]
        if request.sizeOnly {
            var data = Data()
            data.appendLittleEndian(entry.size)
            return data
        }
        guard !entry.isDirectory else { return nil }
        do {
            let handle = try handle(for: request.fileIndex)
            try handle.seek(toOffset: request.offset)
            return try handle.read(upToCount: min(request.length, Self.maxChunk)) ?? Data()
        } catch {
            Self.logger.error("reading \(self.urls[request.fileIndex].path, privacy: .private) failed: \(error, privacy: .public)")
            return nil
        }
    }

    private func handle(for index: Int) throws -> FileHandle {
        if let openFile, openFile.index == index { return openFile.handle }
        try openFile?.handle.close()
        openFile = nil
        let handle = try FileHandle(forReadingFrom: urls[index])
        openFile = (index, handle)
        return handle
    }
}
