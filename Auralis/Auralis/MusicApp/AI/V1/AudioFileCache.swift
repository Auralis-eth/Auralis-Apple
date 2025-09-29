import Foundation

/// Simple on-disk cache for remote audio files.
/// - Cache directory: Library/Caches/AudioCache
/// - Cache key: Base64(URL.absoluteString)
actor AudioFileCache {
    static let shared = AudioFileCache()

    private let cacheDirName = "AudioCache"

    // MARK: - Public API

    /// Returns a local file URL for the remote audio URL.
    /// If present in cache, returns immediately. Otherwise downloads and stores it.
    func localURL(forRemote url: URL) async throws -> URL {
        let cacheDir = try cacheDirectory()
        let key = cacheKey(for: url)
        if let existing = try? existingCachedURL(forKey: key, in: cacheDir) {
            return existing
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
        return destURL
    }

    /// Returns URL if already cached, otherwise nil.
    func cachedURL(forRemote url: URL) throws -> URL? {
        let cacheDir = try cacheDirectory()
        let key = cacheKey(for: url)
        return try existingCachedURL(forKey: key, in: cacheDir)
    }

    // MARK: - Internals

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

    // Find an existing cached file that matches the key, with or without an extension
    private func existingCachedURL(forKey key: String, in cacheDir: URL) throws -> URL? {
        let fm = FileManager.default
        do {
            let items = try fm.contentsOfDirectory(atPath: cacheDir.path)
            if let match = items.first(where: { $0 == key || $0.hasPrefix("\(key).") }) {
                return cacheDir.appendingPathComponent(match, isDirectory: false)
            }
            return nil
        } catch {
            // If directory doesn't exist yet, treat as miss
            return nil
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
        for attempt in 0..<2 { // initial try + 1 retry
            do {
                let request = buildRequest(for: url)
                let (tmpURL, response) = try await URLSession.shared.download(for: request)
                try Task.checkCancellation()
                try validate(response: response)
                return (tmpURL, response)
            } catch {
                lastError = error
                if attempt == 0 {
                    // Small backoff before retry
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                    continue
                } else {
                    throw error
                }
            }
        }
        throw lastError ?? URLError(.unknown)
    }
}
