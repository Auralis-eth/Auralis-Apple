import Foundation

/// Simple on-disk cache for remote audio files.
/// - Cache directory: Library/Caches/AudioCache
/// - Cache key: Base64(URL.absoluteString)
actor AudioFileCache {
    static let shared = AudioFileCache()

    private let cacheDirName = "AudioCache"

    // Dedicated session with explicit timeouts and connectivity behavior
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30 // connect/read timeout per request
        config.timeoutIntervalForResource = 90 // overall resource timeout
        config.waitsForConnectivity = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    // Cache policy
    private let maxCacheBytes: Int64 = 500 * 1024 * 1024 // 500 MB cap
    private let metadataExtension = "meta" // sidecar extension for ETag/Last-Modified

    // MARK: - Public API

    /// Returns a local file URL for the remote audio URL.
    /// If present in cache, returns immediately. Otherwise downloads and stores it.
    func localURL(forRemote url: URL) async throws -> URL {
        let cacheDir = try cacheDirectory()
        let key = cacheKey(for: url)
        if let existing = try? existingCachedURL(forKey: key, in: cacheDir) {
            // Attempt conditional revalidation with ETag/Last-Modified
            let meta = loadMetadata(forFileURL: existing)
            do {
                let request = buildConditionalRequest(for: url, with: meta)
                let (_, response) = try await session.data(for: request)
                try Task.checkCancellation()
                if let http = response as? HTTPURLResponse, http.statusCode == 304 {
                    // Not modified, return cached
                    return existing
                }
                // Modified or unvalidated but successful; fall through to full download
            } catch {
                // Network error during validation: use stale cache optimistically
                return existing
            }
        }

        // Download with timeout, retry, and MIME validation
        let (tmpURL, response) = try await downloadWithRetry(from: url)
        try Task.checkCancellation()

        // Determine destination extension: prefer URL's own ext; if missing, map from MIME
        let urlExt = url.pathExtension.isEmpty ? nil : url.pathExtension
        let mappedExt = response.mimeType.flatMap { mimeToPreferredExtension($0) }
        let finalExt = urlExt ?? mappedExt

        let destURL = destinationURL(forKey: key, ext: finalExt, in: cacheDir)

        // Ensure destination parent exists
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        // Remove any stale file (unlikely) then move
        try? FileManager.default.removeItem(at: destURL)
        try FileManager.default.moveItem(at: tmpURL, to: destURL)
        // Save validators
        saveMetadata(from: response, forFileURL: destURL, originalURL: url)
        // Enforce cache size
        trimCacheIfNeeded(in: cacheDir)
        return destURL
    }

    /// Returns URL if already cached, otherwise nil.
    func cachedURL(forRemote url: URL) throws -> URL? {
        let cacheDir = try cacheDirectory()
        let key = cacheKey(for: url)
        return try existingCachedURL(forKey: key, in: cacheDir)
    }

    /// AE-003: Trim memory/disk usage aggressively (LRU eviction beyond normal cap)
    func trimMemoryAggressively() {
        do {
            let dir = try cacheDirectory()
            trimCacheAggressively(in: dir)
        } catch { /* ignore */ }
    }

    /// AE-003: Clear all cached items (files + metadata)
    func clearAll() {
        do {
            let dir = try cacheDirectory()
            let fm = FileManager.default
            if let items = try? fm.contentsOfDirectory(atPath: dir.path) {
                for name in items {
                    let url = dir.appendingPathComponent(name)
                    try? fm.removeItem(at: url)
                }
            }
        } catch { /* ignore */ }
    }

    // MARK: - Internals

    private struct CacheMetadata: Codable {
        var originalURL: String
        var etag: String?
        var lastModified: String?
        var createdAt: Date
        var updatedAt: Date
    }

    private func cacheDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent(cacheDirName, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cachedDestination(for url: URL, in cacheDir: URL) -> (URL, Bool) {
        let key = cacheKey(for: url)
        let ext = url.pathExtension.isEmpty ? nil : url.pathExtension
        let fileName = ext.map { "\(key).\($0)" } ?? key
        let dest = cacheDir.appendingPathComponent(fileName, isDirectory: false)
        let exists = FileManager.default.fileExists(atPath: dest.path)
        return (dest, exists)
    }

    private func cacheKey(for url: URL) -> String {
        let raw = url.absoluteString
        return Data(raw.utf8).base64EncodedString()
    }

    // Prefer common audio extensions for known MIME types
    private func mimeToPreferredExtension(_ mime: String) -> String? {
        switch mime.lowercased() {
        case "audio/mpeg", "audio/mp3":
            return "mp3"
        case "audio/aac":
            return "aac"
        case "audio/mp4", "audio/x-m4a", "audio/aacp":
            return "m4a"
        case "audio/wav", "audio/x-wav", "audio/wave":
            return "wav"
        case "audio/flac", "audio/x-flac":
            return "flac"
        case let m where m.hasPrefix("audio/"):
            // Unknown audio subtype; don't force an extension
            return nil
        default:
            return nil
        }
    }

    // Build destination URL using cache key and optional extension
    private func destinationURL(forKey key: String, ext: String?, in cacheDir: URL) -> URL {
        let fileName = ext.map { "\(key).\($0)" } ?? key
        return cacheDir.appendingPathComponent(fileName, isDirectory: false)
    }

    private func metadataURL(forFileURL fileURL: URL) -> URL {
        fileURL.appendingPathExtension(metadataExtension)
    }

    private func saveMetadata(from response: URLResponse, forFileURL fileURL: URL, originalURL: URL) {
        guard let http = response as? HTTPURLResponse else { return }
        let meta = CacheMetadata(
            originalURL: originalURL.absoluteString,
            etag: http.value(forHTTPHeaderField: "ETag"),
            lastModified: http.value(forHTTPHeaderField: "Last-Modified"),
            createdAt: Date(),
            updatedAt: Date()
        )
        let url = metadataURL(forFileURL: fileURL)
        do {
            let data = try JSONEncoder().encode(meta)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Best effort; ignore failures
        }
    }

    private func loadMetadata(forFileURL fileURL: URL) -> CacheMetadata? {
        let url = metadataURL(forFileURL: fileURL)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CacheMetadata.self, from: data)
    }

    private func buildConditionalRequest(for url: URL, with meta: CacheMetadata?) -> URLRequest {
        var req = buildRequest(for: url)
        if let meta {
            if let etag = meta.etag { req.addValue(etag, forHTTPHeaderField: "If-None-Match") }
            if let lm = meta.lastModified { req.addValue(lm, forHTTPHeaderField: "If-Modified-Since") }
        }
        return req
    }

    // Find an existing cached file that matches the key, with or without an extension
    private func existingCachedURL(forKey key: String, in cacheDir: URL) throws -> URL? {
        let fm = FileManager.default
        do {
            let items = try fm.contentsOfDirectory(atPath: cacheDir.path)
            if let match = items.first(where: { $0 == key || $0.hasPrefix("\(key).") }) {
                let url = cacheDir.appendingPathComponent(match, isDirectory: false)
                // Touch access date for LRU
                var attrs = try fm.attributesOfItem(atPath: url.path)
                attrs[.creationDate] = attrs[.creationDate] ?? Date()
                attrs[.modificationDate] = Date()
                try fm.setAttributes(attrs, ofItemAtPath: url.path)
                return url
            }
            return nil
        } catch {
            return nil
        }
    }

    private func trimCacheIfNeeded(in cacheDir: URL) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: cacheDir, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { return }

        var files: [(url: URL, size: Int64, date: Date)] = []
        var total: Int64 = 0

        for case let fileURL as URL in enumerator {
            do {
                let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey])
                if values.isDirectory == true { continue }
                // Skip metadata files in size accounting but keep them paired with their main file remove
                if fileURL.pathExtension == metadataExtension { continue }
                let size = Int64(values.fileSize ?? 0)
                let date = values.contentModificationDate ?? Date.distantPast
                files.append((fileURL, size, date))
                total += size
            } catch { continue }
        }

        guard total > maxCacheBytes else { return }
        // Sort by oldest modification date first (LRU-like)
        files.sort { $0.date < $1.date }

        for entry in files {
            do {
                try fm.removeItem(at: entry.url)
                let metaURL = metadataURL(forFileURL: entry.url)
                try? fm.removeItem(at: metaURL)
                total -= entry.size
                if total <= maxCacheBytes { break }
            } catch { continue }
        }
    }

    // AE-003: Aggressive trim that frees until we are at ~70% of max
    private func trimCacheAggressively(in cacheDir: URL) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: cacheDir, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { return }

        var files: [(url: URL, size: Int64, date: Date)] = []
        var total: Int64 = 0

        for case let fileURL as URL in enumerator {
            do {
                let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey])
                if values.isDirectory == true { continue }
                if fileURL.pathExtension == metadataExtension { continue }
                let size = Int64(values.fileSize ?? 0)
                let date = values.contentModificationDate ?? Date.distantPast
                files.append((fileURL, size, date))
                total += size
            } catch { continue }
        }

        // Target 70% of max as a post-trim watermark
        let target = Int64(Double(maxCacheBytes) * 0.7)
        guard total > target else { return }
        files.sort { $0.date < $1.date }
        for entry in files {
            do {
                try fm.removeItem(at: entry.url)
                let metaURL = metadataURL(forFileURL: entry.url)
                try? fm.removeItem(at: metaURL)
                total -= entry.size
                if total <= target { break }
            } catch { continue }
        }
    }

    // MARK: - Networking Helpers
    private func buildRequest(for url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        req.timeoutInterval = 30.0 // ~30s timeout
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.httpMethod = "GET"
        return req
    }

    private func validate(response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        // Validate MIME type begins with audio/
        if let mime = response.mimeType, !mime.lowercased().hasPrefix("audio/") {
            throw URLError(.cannotDecodeContentData)
        }
    }

    private func downloadWithRetry(from url: URL) async throws -> (URL, URLResponse) {
        var lastError: Error?
        var delay: UInt64 = 500_000_000 // 0.5s
        for attempt in 0..<3 { // initial try + up to 2 retries
            do {
                let request = buildRequest(for: url)
                let (tmpURL, response) = try await session.download(for: request)
                try Task.checkCancellation()
                try validate(response: response)
                return (tmpURL, response)
            } catch {
                lastError = error
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: delay)
                    delay = min(delay * 2, 4_000_000_000) // cap at 4s
                    continue
                } else {
                    throw error
                }
            }
        }
        throw lastError ?? URLError(.unknown)
    }
}
