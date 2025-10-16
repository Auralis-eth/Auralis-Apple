import Foundation
import UIKit
import os.log

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

    // Extracted helpers
    private lazy var metadataStore = CacheMetadataStore(sidecarExtension: metadataExtension)
    private lazy var trimmer = CacheTrimmer(metadataExtension: metadataExtension)
    private lazy var downloader = AudioDownloader(session: session)
    private lazy var downloadManager = AudioDownloadManager.shared

    // MARK: - Public API

    /// Returns a local file URL for the remote audio URL.
    /// If present in cache, returns immediately. Otherwise downloads and stores it.
    func localURL(forRemote url: URL) async throws -> URL {
        let cacheDir = try cacheDirectory()
        let key = url.audioCacheKey
        if let existing = try? existingCachedURL(forKey: key, in: cacheDir) {
            // Attempt conditional revalidation with ETag/Last-Modified
            let meta = await metadataStore.load(forFileURL: existing)
            do {
                var request = URLRequest.audioGET(url)
                request.applyConditionalHeaders(from: meta)
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
        let (tmpURL, response) = try await downloadManager.awaitDownload(from: url)
        try Task.checkCancellation()

        // Determine destination extension: prefer URL's own ext; if missing, map from MIME
        let urlExt = url.safePathExtensionOrNil
        let mappedExt = response.mimeType.flatMap { AudioMIMEMapper.preferredExtension(for: $0) }
        let finalExt = urlExt ?? mappedExt

//        let destURL = destinationURL(forKey: key, ext: finalExt, in: cacheDir)

        // Ensure destination parent exists
//        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        // Remove any stale file (unlikely) then move
//        try? FileManager.default.removeItem(at: destURL)
//        try FileManager.default.moveItem(at: tmpURL, to: destURL)
        // Save validators
        await metadataStore.save(from: response, forFileURL: tmpURL, originalURL: url)
        // Enforce cache size
        await trimmer.trim(toMaxBytes: maxCacheBytes, in: cacheDir)
        return tmpURL
    }

    /// Returns URL if already cached, otherwise nil.
    func cachedURL(forRemote url: URL) throws -> URL? {
        let cacheDir = try cacheDirectory()
        let key = url.audioCacheKey
        return try existingCachedURL(forKey: key, in: cacheDir)
    }

    /// AE-003: Trim memory/disk usage aggressively (LRU eviction beyond normal cap)
    func trimMemoryAggressively() {
        do {
            let dir = try cacheDirectory()
            let target = Int64(Double(maxCacheBytes) * 0.7)
            trimmer.aggressiveTrim(toWatermark: target, in: dir)
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

    private func cacheDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent(cacheDirName, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func destinationURL(forKey key: String, ext: String?, in cacheDir: URL) -> URL {
        let fileName = ext.map { "\(key).\($0)" } ?? key
        return cacheDir.appendingPathComponent(fileName, isDirectory: false)
    }

    private func existingCachedURL(forKey key: String, in cacheDir: URL) throws -> URL? {
        let fm = FileManager.default
        do {
            let items = try fm.contentsOfDirectory(atPath: cacheDir.path)
            if let match = items.first(where: { $0 == key || $0.hasPrefix("\(key).") }) {
                let url = cacheDir.appendingPathComponent(match, isDirectory: false)
                // Touch access date for LRU
                try FileManager.default.touch(atPath: url.path)
                return url
            }
            return nil
        } catch {
            return nil
        }
    }
    
    private func postProgress(url: URL, bytes: Int64, total: Int64) {
        // reserved for future wiring
    }
}
