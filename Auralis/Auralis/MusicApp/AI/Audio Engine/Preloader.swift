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
/// - Eviction policy: The token inserted/promoted by a preload (or transient reinsert) is protected from eviction within the same operation. When capacity == 1, the newly inserted token overrides any existing pin ("new token wins").
///
/// Capacity==1 semantics (product contract): When capacity is 1, the "new token wins". If inserting/promoting a new token would exceed capacity and the only candidate for eviction is a pinned token that isn't the protected (newly inserted/promoted) one, the pinned token is evicted. This ensures the latest user selection is always prepared. Example UI copy: "Preparing latest item".
///
/// Cancellation contract: `cancel()` only cancels the in-flight resolver task for the most recent `preload(nft:url:)`. It does not evict or clear already-prepared entries returned by fast paths (e.g., file URLs or memo hits).
///
/// `.notPrepared` guidance (dev UX): Translate to UI/metrics as "already consumed or evicted". Recommended analytics key: `audio.preloader.not_prepared` with dimensions `{ reason: consumed|evicted, capacity, isPinned }` if available.
///
/// QA checklist:
/// - Capacity==1: (a) Pin token A, then preload token B — expect A evicted, B prepared. (b) Rapid toggles A↔B — latest remains prepared.
/// - Cancel semantics: (a) Preload(fileURL) then `cancel()` — consume still succeeds (not `.notPrepared`). (b) Start async preload(non-file), call `cancel()` — await throws `.cancelled`, prepared set unchanged.
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
    private let resolver: (URL) async throws -> URL
    private let clock = ContinuousClock()

    /// Memo keys use normalized remote URLs (scheme/host lowercase, default ports removed, fragment dropped,
    /// percent-escape hex uppercased). Query order preserved.
    private var memo: [URL: (canonical: URL, timestamp: ContinuousClock.Instant)] = [:]
    private var pinned: (token: Token, expiry: ContinuousClock.Instant)?

    // MARK: - State

    // Latest-wins identifier and in-flight resolver for the most recent preload
    private var latestOperationID: UUID?
    private var resolverTask: Task<URL, Error>?

    // Tiny LRU of prepared tokens (MRU at index 0)
    private var prepared: [Token] = []

    // MARK: - Init

    /// Capacity and memoization are configurable; default capacity is 3.
    init(capacity: Int = 3, memoTTL: TimeInterval = 2.0, memoCapacity: Int = 8, pinWindow: TimeInterval = 0.75, resolver: @escaping (URL) async throws -> URL = { url in try await AudioFileCache.shared.localURL(forRemote: url) }) {
        self.capacity = max(1, capacity)
        self.memoTTL = max(0, memoTTL)
        self.memoCapacity = max(1, memoCapacity)
        self.pinWindow = max(0, pinWindow)
        self.resolver = resolver
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
            let resolved = try await resolver(url)
            try Task.checkCancellation()
            guard resolved.isFileURL else {
                throw PreloadError.resolutionFailed(underlyingDescription: "Resolver must return a file URL, got: \(resolved.absoluteString)")
            }
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
        if let p = pinned, clock.now >= p.expiry {
            pinned = nil
        }
    }

    private func pin(_ token: Token) {
        clearPinIfExpired()
        pinned = (token, clock.now.advanced(by: .seconds(pinWindow)))
    }

    private func unpinIfMatches(_ token: Token) {
        if let p = pinned, p.token == token {
            pinned = nil
        }
    }

    private func evictLRURespectingPin(protect protected: Token?) {
        clearPinIfExpired()
        guard prepared.count > capacity else { return }

        // Capacity==1 policy: New token wins over an existing pin.
        // If we exceed capacity and the only conflict is with a pinned token that isn't protected,
        // evict the pinned one to ensure the protected (newly inserted/promoted) token remains.
        let pinnedToken = pinned?.token

        // Select a victim from LRU end toward MRU, skipping the protected token.
        // Normally we respect the pin, but if all remaining candidates are either the protected or the pinned,
        // we evict the pinned to honor the "new token wins" policy when necessary to satisfy capacity.
        var victimIndex: Int? = nil
        for idx in stride(from: prepared.count - 1, through: 0, by: -1) {
            let candidate = prepared[idx]
            if let protected = protected, candidate == protected {
                continue // never evict the protected token
            }
            if let pinnedToken, candidate == pinnedToken {
                // Defer evicting the pinned token unless we have no other choice
                if victimIndex == nil { victimIndex = idx } // provisional victim if nothing else found
                continue
            }
            // Found a non-protected, non-pinned candidate; evict it
            victimIndex = idx
            break
        }

        if let victimIndex {
            // If victim is the pinned token, clear the pin as we are evicting it.
            if let pinnedToken, prepared[victimIndex] == pinnedToken {
                pinned = nil
            }
            prepared.remove(at: victimIndex)
        } else if let pinnedToken, let idx = prepared.firstIndex(of: pinnedToken) {
            // Fallback: only candidates were protected/pinned; evict the pinned to keep protected
            pinned = nil
            prepared.remove(at: idx)
        } else {
            // As a last resort (shouldn't happen), pop LRU
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
        // Replace occurrences of %xx with %XX (uppercase hex) only when xx are valid hex digits.
        // No decoding/encoding beyond case normalization. Safe on malformed/trailing sequences.
        guard !s.isEmpty else { return s }
        var result = s
        var i = result.startIndex
        func isHex(_ c: Character) -> Bool {
            switch c {
            case "0","1","2","3","4","5","6","7","8","9",
                 "a","b","c","d","e","f",
                 "A","B","C","D","E","F":
                return true
            default:
                return false
            }
        }
        while i < result.endIndex {
            if result[i] == "%" {
                let n1i = result.index(i, offsetBy: 1)
                if n1i >= result.endIndex { break } // trailing '%'
                let n2i = result.index(i, offsetBy: 2)
                if n2i >= result.endIndex { break } // trailing incomplete sequence
                let c1 = result[n1i]
                let c2 = result[n2i]
                if isHex(c1) && isHex(c2) {
                    // Uppercase the two hex digits
                    let upper = String([c1, c2]).uppercased()
                    result.replaceSubrange(n1i...n2i, with: upper)
                    // Advance past the sequence
                    i = result.index(i, offsetBy: 3)
                    continue
                }
            }
            i = result.index(after: i)
        }
        return result
    }

    private func pruneExpiredMemoEntries() {
        if memoTTL <= 0 { return }
        let now = clock.now
        let ttl = Duration.seconds(memoTTL)
        let expiredKeys = memo.compactMap { (key, entry) in
            (now - entry.timestamp) > ttl ? key : nil
        }
        for key in expiredKeys {
            memo.removeValue(forKey: key)
        }
    }

    /// Memo keys use normalized remote URLs (scheme/host lowercase, default ports removed, fragment dropped,
    /// percent-escape hex uppercased). Query order preserved.
    private func memoLookup(for url: URL) -> URL? {
        let key = normalizeRemoteURLForMemo(url)
        pruneExpiredMemoEntries()
        if let entry = memo[key] {
            let now = clock.now
            let ttl = Duration.seconds(memoTTL)
            if (now - entry.timestamp) <= ttl {
                return entry.canonical
            } else {
                memo.removeValue(forKey: key)
            }
        }
        return nil
    }

    private func memoStore(original: URL, canonical: URL) {
        let key = normalizeRemoteURLForMemo(original)
        pruneExpiredMemoEntries()
        memo[key] = (canonical, clock.now)
        // Opportunistically prune again after insert (in case TTL just expired others)
        pruneExpiredMemoEntries()
        // Enforce capacity by evicting oldest by timestamp deterministically
        while memo.count > memoCapacity {
            if let oldest = memo.min(by: { $0.value.timestamp < $1.value.timestamp })?.key {
                memo.removeValue(forKey: oldest)
            } else {
                break
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
            evictLRURespectingPin(protect: token)
        }
    }

    // MARK: - Testing helpers (internal)

    /// Returns true if the given token is currently prepared (for tests).
    func preparedContains(_ token: Token) -> Bool {
        return prepared.contains(token)
    }

    /// Returns the current prepared count (for tests).
    func preparedCount() -> Int {
        return prepared.count
    }

    private static func canonicalize(_ fileURL: URL) -> URL {
        let std = fileURL.standardizedFileURL
        let resolvedPath = (std.path as NSString).resolvingSymlinksInPath
        return URL(fileURLWithPath: resolvedPath, isDirectory: false)
    }

    /// Classifies AVAudioFile open errors into transient vs permanent categories.
    /// Transient (causes reinsertion): POSIX EAGAIN(35), EBUSY(16), EINTR(4), ETIMEDOUT(60); NSURLErrorDomain timeouts/connectivity (TimedOut, CannotConnectToHost, NetworkConnectionLost, ResourceUnavailable).
    /// Permanent (no reinsertion): Common NSCocoaErrorDomain file errors (no such file, permission, invalid/corrupt/unsupported/too large), and default for NSOSStatusErrorDomain.
    /// Note: Policy is intentionally conservative to avoid endless retries.
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
