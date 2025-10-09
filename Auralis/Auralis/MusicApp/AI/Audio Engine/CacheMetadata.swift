import Foundation

struct CacheMetadata: Codable, Sendable {
    var originalURL: URL
    var etag: String?
    var lastModified: Date?
    var createdAt: Date
    var updatedAt: Date
    var schemaVersion: Int = 1

    private enum CodingKeys: String, CodingKey {
        case originalURL, etag, lastModified, createdAt, updatedAt
        case schemaVersion
    }

    init(originalURL: URL, etag: String?, lastModified: Date?, createdAt: Date, updatedAt: Date) {
        self.originalURL = originalURL
        self.etag = etag
        self.lastModified = lastModified
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let url = try? container.decode(URL.self, forKey: .originalURL) {
            self.originalURL = url
        } else {
            let urlString = try container.decode(String.self, forKey: .originalURL)
            guard let url = URL(string: urlString) else {
                throw DecodingError.dataCorruptedError(forKey: .originalURL, in: container, debugDescription: "Invalid URL string: \(urlString)")
            }
            self.originalURL = url
        }

        self.etag = try? container.decode(String.self, forKey: .etag)

        if let date = try? container.decode(Date.self, forKey: .lastModified) {
            self.lastModified = date
        } else if let lmString = try? container.decode(String.self, forKey: .lastModified) {
            self.lastModified = HTTPDateParser.parse(lmString)
        } else {
            self.lastModified = nil
        }

        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.schemaVersion = (try? container.decode(Int.self, forKey: .schemaVersion)) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(originalURL, forKey: .originalURL)
        try container.encodeIfPresent(etag, forKey: .etag)
        try container.encodeIfPresent(lastModified, forKey: .lastModified)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(schemaVersion, forKey: .schemaVersion)
    }
}

struct CacheMetadataStore {
    let sidecarExtension: String

    private let ioQueue: DispatchQueue
    private static let maxSidecarBytes: Int = 32 * 1024 // 32KB cap for sidecar JSON

    init(sidecarExtension: String) {
        self.sidecarExtension = sidecarExtension
        self.ioQueue = DispatchQueue(label: "CacheMetadataStore.IO", qos: .utility)
    }

    func url(forFileURL fileURL: URL) -> URL {
        fileURL.appendingPathExtension(sidecarExtension)
    }

    private func saveSync(from response: URLResponse, forFileURL fileURL: URL, originalURL: URL) {
        dispatchPrecondition(condition: .onQueue(ioQueue))

        guard let http = response as? HTTPURLResponse else { return }

        func clamp(_ s: String, to max: Int) -> String { return s.count <= max ? s : String(s.prefix(max)) }

        let rawETag = http.value(forHTTPHeaderField: "ETag").map { clamp($0, to: 1024) }
        let safeETag = rawETag.flatMap { sanitizeETag($0) }

        let meta = CacheMetadata(
            originalURL: canonicalizedURL(originalURL),
            etag: safeETag,
            lastModified: http.value(forHTTPHeaderField: "Last-Modified").flatMap { HTTPDateParser.parse($0) },
            createdAt: Date(),
            updatedAt: Date()
        )
        do {
#if os(iOS) || os(tvOS) || os(watchOS)
            let writeOptions: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
#else
            let writeOptions: Data.WritingOptions = [.atomic]
#endif
            let encoder = JSONEncoder()
            if #available(iOS 11.0, tvOS 11.0, watchOS 4.0, macOS 10.13, *) {
                encoder.dateEncodingStrategy = .iso8601
            }
            var data = try encoder.encode(meta)
            if data.count > Self.maxSidecarBytes {
                // Try dropping ETag to reduce size
                let trimmedMeta = CacheMetadata(
                    originalURL: meta.originalURL,
                    etag: nil,
                    lastModified: meta.lastModified,
                    createdAt: meta.createdAt,
                    updatedAt: meta.updatedAt
                )
                data = try encoder.encode(trimmedMeta)
                if data.count > Self.maxSidecarBytes {
                    // Too large even after trimming; skip write
                    return
                }
            }
            let destURL = url(forFileURL: fileURL)
            try data.write(to: destURL, options: writeOptions)
        } catch {
            // best effort
        }
    }

    private func loadSync(forFileURL fileURL: URL) -> CacheMetadata? {
        dispatchPrecondition(condition: .onQueue(ioQueue))

        let url = url(forFileURL: fileURL)
        // Defensive: reject oversized sidecar before loading to avoid memory/CPU waste
        if let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
           let size = values.fileSize,
           size > Self.maxSidecarBytes {
            // Best-effort cleanup of poisoned/oversized sidecar
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        // Prefer ISO-8601 (RFC3339) first
        do {
            let decoder = JSONDecoder()
            if #available(iOS 11.0, tvOS 11.0, watchOS 4.0, macOS 10.13, *) {
                decoder.dateDecodingStrategy = .iso8601
            }
            return try decoder.decode(CacheMetadata.self, from: data)
        } catch {
            // Fallback 1: Foundation's default (.deferredToDate)
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .deferredToDate
                return try decoder.decode(CacheMetadata.self, from: data)
            } catch {
                // Fallback 2: milliseconds since 1970
                do {
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .millisecondsSince1970
                    return try decoder.decode(CacheMetadata.self, from: data)
                } catch {
                    // Fallback 3: seconds since 1970
                    do {
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .secondsSince1970
                        return try decoder.decode(CacheMetadata.self, from: data)
                    } catch {
                        return nil
                    }
                }
            }
        }
    }

    private func deleteSync(forFileURL fileURL: URL) {
        dispatchPrecondition(condition: .onQueue(ioQueue))
        try? FileManager.default.removeItem(at: url(forFileURL: fileURL))
    }

    // MARK: - Public async API (non-blocking)
    /// Async, non-blocking save that persists sidecar metadata.
    /// Use from UI or background without risking priority inversion.
    func save(from response: URLResponse, forFileURL fileURL: URL, originalURL: URL) async {
        await saveAsync(from: response, forFileURL: fileURL, originalURL: originalURL)
    }

    /// Async, non-blocking load of sidecar metadata.
    func load(forFileURL fileURL: URL) async -> CacheMetadata? {
        return await loadAsync(forFileURL: fileURL)
    }

    /// Async, non-blocking delete of sidecar metadata.
    func delete(forFileURL fileURL: URL) async {
        await deleteAsync(forFileURL: fileURL)
    }

    // MARK: - Async I/O helpers
    func saveAsync(from response: URLResponse, forFileURL fileURL: URL, originalURL: URL) async {
        if Task.isCancelled { return }
        final class CancelFlag { var cancelled = false }
        let flag = CancelFlag()
        await withTaskCancellationHandler(handler: {
            flag.cancelled = true
        }, operation: {
            await withCheckedContinuation { continuation in
                if Task.isCancelled || flag.cancelled {
                    continuation.resume()
                    return
                }
                ioQueue.async {
                    if Task.isCancelled {
                        continuation.resume()
                        return
                    }
                    if flag.cancelled {
                        continuation.resume()
                        return
                    }
                    self.saveSync(from: response, forFileURL: fileURL, originalURL: originalURL)
                    continuation.resume()
                }
            }
        })
    }

    func loadAsync(forFileURL fileURL: URL) async -> CacheMetadata? {
        if Task.isCancelled { return nil }
        final class CancelFlag { var cancelled = false }
        let flag = CancelFlag()
        return await withTaskCancellationHandler(handler: {
            flag.cancelled = true
        }, operation: {
            await withCheckedContinuation { continuation in
                if Task.isCancelled || flag.cancelled {
                    continuation.resume(returning: nil)
                    return
                }
                ioQueue.async {
                    if Task.isCancelled {
                        continuation.resume(returning: nil)
                        return
                    }
                    if flag.cancelled {
                        continuation.resume(returning: nil)
                        return
                    }
                    let result = self.loadSync(forFileURL: fileURL)
                    continuation.resume(returning: result)
                }
            }
        })
    }

    func deleteAsync(forFileURL fileURL: URL) async {
        if Task.isCancelled { return }
        final class CancelFlag { var cancelled = false }
        let flag = CancelFlag()
        await withTaskCancellationHandler(handler: {
            flag.cancelled = true
        }, operation: {
            await withCheckedContinuation { continuation in
                if Task.isCancelled || flag.cancelled {
                    continuation.resume()
                    return
                }
                ioQueue.async {
                    if Task.isCancelled {
                        continuation.resume()
                        return
                    }
                    if flag.cancelled {
                        continuation.resume()
                        return
                    }
                    self.deleteSync(forFileURL: fileURL)
                    continuation.resume()
                }
            }
        })
    }
}

extension URLRequest {
    mutating func applyConditionalHeaders(from meta: CacheMetadata?) {
        guard let meta else { return }

        if let rawETag = meta.etag, let safeETag = sanitizeETag(rawETag) {
            setValue(safeETag, forHTTPHeaderField: "If-None-Match")
        }

        if let lmDate = meta.lastModified {
            let lm = HTTPDateParser.rfc1123String(from: lmDate)
            setValue(lm, forHTTPHeaderField: "If-Modified-Since")
        }
    }
}

private func sanitizeETag(_ raw: String) -> String? {
    // Trim surrounding whitespace/newlines
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return nil }

    // Reject if contains CR or LF to prevent header injection
    if trimmed.contains("\r") || trimmed.contains("\n") { return nil }

    // Enforce visible ASCII only (no control chars, no DEL)
    for scalar in trimmed.unicodeScalars {
        let v = scalar.value
        if v < 0x20 || v == 0x7F { return nil }
    }

    // Enforce RFC7232 entity-tag grammar: W?/quoted-string
    // entity-tag = [ weak ] opaque-tag
    // weak = "W/" ; case-sensitive
    // opaque-tag = DQUOTE *etagc DQUOTE
    // etagc = %x21 / %x23-7E (we already restricted to visible ASCII; exclude DQUOTE 0x22)
    let s = trimmed
    if s.hasPrefix("W/") {
        let rest = String(s.dropFirst(2))
        guard isQuotedOpaqueETag(rest) else { return nil }
        return "W/" + rest
    } else {
        guard isQuotedOpaqueETag(s) else { return nil }
        return s
    }
}

private func isQuotedOpaqueETag(_ s: String) -> Bool {
    guard s.count >= 2, s.first == "\"", s.last == "\"" else { return false }
    let inner = s.dropFirst().dropLast()
    // Ensure no embedded DQUOTE characters
    return !inner.contains("\"")
}

private func idnaASCIIHost(_ host: String) -> String {
    // Convert Unicode host to IDNA ASCII (Punycode) using URLComponents/URL round-trip
    var tmp = URLComponents()
    tmp.scheme = "http" // scheme required to build a URL
    tmp.host = host
    tmp.path = "/" // minimal valid path
    return tmp.url?.host ?? host
}

private func canonicalizedURL(_ url: URL) -> URL {
    guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }

    // Lowercase scheme and host
    if let scheme = comps.scheme { comps.scheme = scheme.lowercased() }
    if let host = comps.host { comps.host = idnaASCIIHost(host).lowercased() }

    // Remove fragment
    comps.fragment = nil

    // Normalize default ports (http:80, https:443)
    if let scheme = comps.scheme, let port = comps.port {
        if (scheme == "http" && port == 80) || (scheme == "https" && port == 443) {
            comps.port = nil
        }
    }

    // Collapse dot-segments and standardize trailing slash in the path
    let rawPath = comps.path
    let collapsed = collapseDotSegments(in: rawPath)
    let standardized = standardizeTrailingSlash(for: collapsed)
    comps.path = standardized

    // Ensure empty path becomes "/"
    if comps.path.isEmpty { comps.path = "/" }

    return comps.url ?? url
}

private func collapseDotSegments(in path: String) -> String {
    // Split while preserving absolute path leading slash semantics
    let isAbsolute = path.hasPrefix("/")
    let hadTrailingSlash = path.count > 1 && path.hasSuffix("/")
    let segments = path.split(separator: "/", omittingEmptySubsequences: false)
    var stack: [String] = []

    for segSub in segments {
        let seg = String(segSub)
        if seg == "." || seg.isEmpty {
            // skip current dir and empty segments (collapses repeated slashes)
            continue
        } else if seg == ".." {
            if !stack.isEmpty { _ = stack.popLast() }
            // If stack is empty and path is absolute, stay at root; if relative, we could keep ".." but URLs here should be absolute
        } else {
            stack.append(seg)
        }
    }

    var result = stack.joined(separator: "/")
    if isAbsolute { result = "/" + result }
    if hadTrailingSlash && !result.isEmpty && result != "/" && !result.hasSuffix("/") {
        result += "/"
    }
    return result
}

private func standardizeTrailingSlash(for path: String) -> String {
    // Preserve trailing slash semantics; normalization is handled by collapseDotSegments.
    return path
}

private enum HTTPDateParser {
    // Thread-confined DateFormatter factories to ensure concurrency safety
    private static func rfc1123Formatter() -> DateFormatter {
        let key = "HTTPDateParser.rfc1123"
        if let cached = Thread.current.threadDictionary[key] as? DateFormatter { return cached }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss 'GMT'"
        Thread.current.threadDictionary[key] = df
        return df
    }

    private static func rfc850Formatter() -> DateFormatter {
        let key = "HTTPDateParser.rfc850"
        if let cached = Thread.current.threadDictionary[key] as? DateFormatter { return cached }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "EEEE',' dd-MMM-yy HH':'mm':'ss 'GMT'"
        Thread.current.threadDictionary[key] = df
        return df
    }

    private static func asctimeFormatter() -> DateFormatter {
        let key = "HTTPDateParser.asctime"
        if let cached = Thread.current.threadDictionary[key] as? DateFormatter { return cached }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "EEE MMM d HH':'mm':'ss yyyy"
        Thread.current.threadDictionary[key] = df
        return df
    }

    static func parse(_ string: String) -> Date? {
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if let d = rfc1123Formatter().date(from: s) { return d }
        if let d = rfc850Formatter().date(from: s) { return d }
        if let d = asctimeFormatter().date(from: s) { return d }
        return nil
    }

    static func rfc1123String(from date: Date) -> String {
        return rfc1123Formatter().string(from: date)
    }
}

