import Foundation

struct CacheTrimmer {
    let metadataExtension: String

    func trim(toMaxBytes maxBytes: Int64, in cacheDir: URL) {
        var files = listCacheFiles(in: cacheDir)
        var total = files.reduce(0) { $0 + $1.size }
        guard total > maxBytes else { return }
        files.sort { $0.date < $1.date }
        for entry in files {
            delete(entry.url)
            total -= entry.size
            if total <= maxBytes { break }
        }
    }

    func aggressiveTrim(toWatermark watermark: Int64, in cacheDir: URL) {
        var files = listCacheFiles(in: cacheDir)
        var total = files.reduce(0) { $0 + $1.size }
        guard total > watermark else { return }
        files.sort { $0.date < $1.date }
        for entry in files {
            delete(entry.url)
            total -= entry.size
            if total <= watermark { break }
        }
    }

    private func listCacheFiles(in dir: URL) -> [(url: URL, size: Int64, date: Date)] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [(URL, Int64, Date)] = []
        for case let fileURL as URL in enumerator {
            do {
                let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey])
                if values.isDirectory == true { continue }
                if fileURL.pathExtension == metadataExtension { continue }
                let size = Int64(values.fileSize ?? 0)
                let date = values.contentModificationDate ?? .distantPast
                files.append((fileURL, size, date))
            } catch { continue }
        }
        return files
    }

    private func delete(_ fileURL: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: fileURL)
        let metaURL = fileURL.appendingPathExtension(metadataExtension)
        try? fm.removeItem(at: metaURL)
    }
}
