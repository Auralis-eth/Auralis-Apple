import Foundation
import AVFoundation

/// Internal preloader for resolving canonical local URLs for audio assets.
///
/// Concurrency & ownership (internal contract):
/// - Actor-isolated: all mutable state is confined to this actor.
/// - Latest-wins: starting a new preload cancels any in-flight operation; only the latest may commit state.
/// - Token lifecycle: `preload(nft:url:)` returns a stable Token; `consume(token:)` is single-use and removes that token from the prepared set.
/// - I/O: Preload performs only URL resolution and canonicalization. The `AVAudioFile` is opened lazily in `consume(token:)` and must not be shared across isolation domains concurrently.
/// - Cancellation: Cancellation is observed before and after awaited operations; cancelled work does not mutate state.
actor Preloader {
    // MARK: - Types

    struct Token: Hashable, Sendable {
        let nftID: String
        let localURL: URL // canonical, standardized file URL
    }

    enum PreloadError: Error, Equatable, Sendable {
        case cancelled
        case resolutionFailed(underlyingDescription: String)
        case notPrepared
    }

    // MARK: - Configuration
    private let capacity: Int // Tiny LRU buffer (configurable)
    private let memoTTL: TimeInterval
    private let memoCapacity: Int
    private let pinWindow: TimeInterval
    // Short-TTL memo for URL -> canonical file URL

    /// Memo keys use normalized remote URLs (scheme/host lowercase, default ports removed, fragment dropped,
    /// percent-escape hex uppercased). Query order preserved.
    private var memo: [URL: (canonical: URL, timestamp: Date)] = [:]
    private var pinned: (token: Token, expiry: Date)?

    // MARK: - State

    // Latest-wins identifier and in-flight resolver for the most recent preload
    private var latestOperationID: UUID?
    private var resolverTask: Task<URL, Error>?

    // Tiny LRU of prepared tokens (MRU at index 0)
    private var prepared: [Token] = []

    // MARK: - Init

    /// Capacity and memoization are configurable; default capacity is 3.
    init(capacity: Int = 3, memoTTL: TimeInterval = 2.0, memoCapacity: Int = 8, pinWindow: TimeInterval = 0.75) {
        self.capacity = max(1, capacity)
        self.memoTTL = max(0, memoTTL)
        self.memoCapacity = max(1, memoCapacity)
        self.pinWindow = max(0, pinWindow)
    }

    // MARK: - Public API (internal)

    /// Resolve and prepare a token for the given NFT and URL.
    /// - Returns: A stable Token that can be used with `consume(token:)`.
    /// - Throws: `PreloadError.cancelled` if superseded/cancelled; `resolutionFailed` for underlying failures.
    @discardableResult
    func preload(nft: NFT, url: URL) async throws -> Token {
        // Establish latest-wins generation and cancel prior work.
        let opID = UUID()
        latestOperationID = opID
        resolverTask?.cancel()

        // Fast path for file URLs: canonicalize and promote/insert without async work
        if url.isFileURL {
            let canonical = Self.canonicalize(url)
            if let found = preparedLookup(nftID: nft.id, local: canonical) {
                insertOrPromote(found.token)
                resolverTask = nil
                pin(found.token)
                latestOperationID = nil // T6: no in-flight task on fast path
                return found.token
            } else {
                let token = Token(nftID: nft.id, localURL: canonical)
                insertOrPromote(token)
                resolverTask = nil
                pin(token)
                latestOperationID = nil // T6
                return token
            }
        }

        // Non-file: try memo first to avoid resolver I/O
        if let cachedCanonical = memoLookup(for: url) {
            if let found = preparedLookup(nftID: nft.id, local: cachedCanonical) {
                insertOrPromote(found.token)
                resolverTask = nil
                pin(found.token)
                latestOperationID = nil // T6
                return found.token
            } else {
                let token = Token(nftID: nft.id, localURL: cachedCanonical)
                insertOrPromote(token)
                resolverTask = nil
                pin(token)
                latestOperationID = nil // T6
                return token
            }
        }

        // Build resolver task for this preload
        let task = Task { () throws -> URL in
            try Task.checkCancellation()
            let resolved = try await AudioFileCache.shared.localURL(forRemote: url)
            try Task.checkCancellation()
            return Self.canonicalize(resolved)
        }
        resolverTask = task

        do {
            let canonicalLocal = try await task.value
            try Task.checkCancellation()
            // Ensure this result still belongs to the latest operation.
            guard latestOperationID == opID else { throw PreloadError.cancelled }
            // Memoize and commit token
            memoStore(original: url, canonical: canonicalLocal)
            if let found = preparedLookup(nftID: nft.id, local: canonicalLocal) {
                insertOrPromote(found.token)
                latestOperationID = nil
                resolverTask = nil
                pin(found.token)
                return found.token
            } else {
                let token = Token(nftID: nft.id, localURL: canonicalLocal)
                insertOrPromote(token)
                latestOperationID = nil
                resolverTask = nil
                pin(token)
                return token
            }
        } catch is CancellationError {
            latestOperationID = nil
            resolverTask = nil
            throw PreloadError.cancelled
        } catch {
            latestOperationID = nil
            resolverTask = nil
            throw PreloadError.resolutionFailed(underlyingDescription: String(describing: error))
        }
    }

    /// Consume a previously prepared token and open the audio file.
    /// - Important: Single-use: subsequent attempts will throw `.notPrepared`.
    /// - Throws: `PreloadError.notPrepared` if the token is not currently prepared; underlying file-open errors will be thrown by `AVAudioFile`.
    /// - Reinsertion policy: only transient open failures reinsert the token (MRU); permanent failures keep it evicted.
    func consume(token: Token) throws -> AVAudioFile {
        if let found = preparedLookup(token: token) {
            prepared.remove(at: found.index)
            unpinIfMatches(token)
        } else {
            throw PreloadError.notPrepared
        }

        do {
            return try AVAudioFile(forReading: token.localURL)
        } catch {
            // Transient vs permanent classification; reinsert only for transient
            if isTransientOpenError(error) {
                insertOrPromote(token) // MRU; capacity enforced inside
            }
            throw error
        }
    }

    /// Transitional API for legacy call sites (deprecated internally).
    /// - Note: Deprecated internal: does not perform network/disk resolution; matches only against prepared tokens or memoized resolutions.
    /// Normalizes to canonical local URL and attempts to consume a matching prepared token.
    @available(*, deprecated, message: "Use consume(token:) with a Token returned from preload(nft:url:)")
    func consume(nft: NFT, url: URL) async -> AVAudioFile? {
        // Legacy path: do not perform resolver I/O. Only match against currently prepared tokens.
        if url.isFileURL {
            let canonical = Self.canonicalize(url)
            let token = Token(nftID: nft.id, localURL: canonical)
            return try? consume(token: token)
        } else if let canonical = memoLookup(for: url) {
            let token = Token(nftID: nft.id, localURL: canonical)
            return try? consume(token: token)
        } else {
            return nil
        }
    }

    /// Cancel any in-flight preload and clear the latest-wins marker.
    func cancel() {
        resolverTask?.cancel()
        resolverTask = nil
        latestOperationID = nil
        // Do not clear prepared LRU on cancel; callers may still consume already-prepared tokens.
    }

    // MARK: - Helpers

    private func clearPinIfExpired() {
        if let p = pinned, Date() >= p.expiry {
            pinned = nil
        }
    }

    private func pin(_ token: Token) {
        clearPinIfExpired()
        pinned = (token, Date().addingTimeInterval(pinWindow))
    }

    private func unpinIfMatches(_ token: Token) {
        if let p = pinned, p.token == token {
            pinned = nil
        }
    }

    private func evictLRURespectingPin() {
        clearPinIfExpired()
        guard prepared.count > capacity else { return }
        if let pinnedToken = pinned?.token {
            // Find the last index that is not the pinned token
            if let idx = prepared.lastIndex(where: { $0 != pinnedToken }) {
                prepared.remove(at: idx)
            } else {
                // All entries are the pinned token (or capacity misconfiguration); nothing to evict
                // Fall back: do nothing to avoid evicting the pinned token
            }
        } else {
            _ = prepared.popLast()
        }
    }

    private func normalizeRemoteURLForMemo(_ url: URL) -> URL {
        // Non-file only; do not perform I/O. Normalize: scheme/host lowercase, drop default port, drop fragment,
        // normalize percent-escape hex case in path and query. Preserve query order.
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        if let scheme = comps.scheme { comps.scheme = scheme.lowercased() }
        if let host = comps.host { comps.host = host.lowercased() }
        // Drop default ports for http/https
        if let scheme = comps.scheme, let port = comps.port {
            if (scheme == "http" && port == 80) || (scheme == "https" && port == 443) {
                comps.port = nil
            }
        }
        // Remove fragment
        comps.fragment = nil
        // Normalize percent-escape hex case in path and query without altering content
        if !comps.percentEncodedPath.isEmpty {
            comps.percentEncodedPath = normalizePercentEscapesCase(comps.percentEncodedPath)
        }
        if let peQuery = comps.percentEncodedQuery, !peQuery.isEmpty {
            comps.percentEncodedQuery = normalizePercentEscapesCase(peQuery)
        }
        // Return rebuilt URL or original if rebuild fails
        return comps.url ?? url
    }

    private func normalizePercentEscapesCase(_ s: String) -> String {
        // Replace occurrences of %xx with %XX (uppercase hex). No decoding/encoding beyond case normalization.
        var result = s
        var i = result.startIndex
        while i < result.endIndex {
            if result[i] == "%" {
                let next1 = result.index(i, offsetBy: 1, limitedBy: result.endIndex)
                let next2 = next1.flatMap { result.index($0, offsetBy: 1, limitedBy: result.endIndex) }
                if let n1 = next1, let n2 = next2, n2 < result.endIndex {
                    let hex = String(result[result.index(after: i)...n2])
                    if hex.count == 2 {
                        let upper = hex.uppercased()
                        result.replaceSubrange(result.index(after: i)...n2, with: upper)
                        i = result.index(i, offsetBy: 3)
                        continue
                    }
                }
            }
            i = result.index(after: i)
        }
        return result
    }

    /// Memo keys use normalized remote URLs (scheme/host lowercase, default ports removed, fragment dropped,
    /// percent-escape hex uppercased). Query order preserved.
    private func memoLookup(for url: URL) -> URL? {
        let key = normalizeRemoteURLForMemo(url)
        if let entry = memo[key] {
            if Date().timeIntervalSince(entry.timestamp) <= memoTTL {
                return entry.canonical
            } else {
                memo.removeValue(forKey: key)
            }
        }
        return nil
    }

    private func memoStore(original: URL, canonical: URL) {
        let key = normalizeRemoteURLForMemo(original)
        memo[key] = (canonical, Date())
        if memo.count > memoCapacity {
            // Evict oldest by timestamp deterministically
            if let oldest = memo.min(by: { $0.value.timestamp < $1.value.timestamp })?.key {
                memo.removeValue(forKey: oldest)
            }
        }
    }

    private func preparedLookup(nftID: String, local: URL) -> (index: Int, token: Token)? {
        if let idx = prepared.firstIndex(where: { $0.nftID == nftID && $0.localURL == local }) {
            return (idx, prepared[idx])
        }
        return nil
    }

    private func preparedLookup(token: Token) -> (index: Int, token: Token)? {
        return preparedLookup(nftID: token.nftID, local: token.localURL)
    }

    private func insertOrPromote(_ token: Token) {
        clearPinIfExpired()
        if let found = preparedLookup(token: token) {
            // Promote to MRU
            prepared.remove(at: found.index)
            prepared.insert(found.token, at: 0)
        } else {
            // Insert as MRU
            prepared.insert(token, at: 0)
            evictLRURespectingPin()
        }
    }

    private static func canonicalize(_ fileURL: URL) -> URL {
        let std = fileURL.standardizedFileURL
        let resolvedPath = (std.path as NSString).resolvingSymlinksInPath
        return URL(fileURLWithPath: resolvedPath, isDirectory: false)
    }

    private func isTransientOpenError(_ error: Error) -> Bool {
        let ns = error as NSError

        // Explicitly treat common permanent file errors as non-transient
        if ns.domain == NSCocoaErrorDomain {
            // Not found, no such file, read no such file, permission, read no permission, file read unsupported/corrupt
            let permanent: Set<Int> = [
                NSFileNoSuchFileError,
                NSFileReadNoSuchFileError,
                NSFileReadNoPermissionError,
                NSFileReadInvalidFileNameError,
                NSFileReadInapplicableStringEncodingError,
                NSFileReadCorruptFileError,
                NSFileReadUnsupportedSchemeError,
                NSFileReadTooLargeError
            ]
            if permanent.contains(ns.code) { return false }
        }

        if ns.domain == NSPOSIXErrorDomain {
            // Clearly transient POSIX conditions: EAGAIN(35), EBUSY(16), EINTR(4), ETIMEDOUT(60)
            let transient: Set<Int> = [35, 16, 4, 60]
            return transient.contains(ns.code)
        }

        if ns.domain == NSURLErrorDomain {
            // Timeouts and temporary connectivity issues (even though we usually open local files)
            let transient: Set<Int> = [NSURLErrorTimedOut, NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost, NSURLErrorResourceUnavailable]
            return transient.contains(ns.code)
        }

        if ns.domain == NSOSStatusErrorDomain {
            // Commonly transient OSStatus values related to interruption/busy if encountered
            // (Values like kAudioQueueErr_EnqueueDuringReset, kAudioFilePermissionsError are permanent — do not treat as transient.)
            // Without specific mapping, default to non-transient.
            return false
        }

        // Default to non-transient to avoid endless retries
        return false
    }
}

