import Foundation

// Thread-safe randomness injection for jitter. Avoids mutable static state.
protocol AudioRandomNumberGenerator: Sendable {
    func random(in range: ClosedRange<UInt64>) -> UInt64
}

struct SystemAudioRNG: AudioRandomNumberGenerator {
    func random(in range: ClosedRange<UInt64>) -> UInt64 { UInt64.random(in: range) }
}

/// A handle to a temporary file that automatically cleans up the file on deallocation
/// unless it has been marked as moved. This provides a safety net against temp file
/// accumulation when callers forget to clean up or the app crashes before cleanup.
final class TemporaryFileHandle: @unchecked Sendable {
    let url: URL
    private let fm = FileManager.default
    private var moved = false

    init(url: URL) { self.url = url }

    /// Access the underlying temporary file URL.
    var fileURL: URL { url }

    /// Move the temporary file to a durable destination.
    /// - Parameters:
    ///   - destinationURL: The final location to move the file to.
    ///   - replace: If true, an existing item at `destinationURL` will be removed before moving.
    /// - Important: On success, this marks the handle as moved to prevent cleanup on deinit.
    func move(to destinationURL: URL, replace: Bool = false) throws {
        if replace && fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }
        try fm.moveItem(at: url, to: destinationURL)
        moved = true
    }

    /// If you moved or deleted the file by other means, call this to prevent deinit cleanup.
    func markMoved() { moved = true }

    deinit {
        if !moved {
            try? fm.removeItem(at: url)
        }
    }
}

/// A downloader specialized for audio files with robust retry/backoff and cancellation handling.
///
/// Contract:
/// - On success, returns a `TemporaryFileHandle` (auto-cleaning) plus the typed `HTTPURLResponse`.
///   The handle deletes the temp file in `deinit` unless you move it or call `markMoved()`.
/// - On any failure (including validation failures and retries), this type ensures any
///   temporary file created by the attempt is removed to prevent tmp bloat.
/// - Crash-safety: If the caller crashes or forgets to clean up, the temp file is reclaimed when
///   the handle is deallocated.
/// - Total attempts = 1 initial attempt + `maxRetries` retries.
/// - Cancellation: cancellation is checked once at the start of each attempt and the backoff sleep
///   is cancellation-aware (throws), so a cancelled parent task never causes an extra attempt.
/// - Validation: accepts `audio/*` and (pragmatically) `application/octet-stream`; rejects known
///   playlist MIME types; treats explicit zero `Content-Length` as invalid; only performs on-disk
///   size checks when the header is missing (to avoid blocking hot paths).
/// - Retry-After: honors numeric seconds and common HTTP-date variants, clamped to `maxDelay`.
/// - URL requirements: only `http` and `https` schemes are supported.
///
/// Concurrency:
/// - This type is immutable and safe to share across tasks. Its stored properties are `let` and not mutated.
/// - Instances are Sendable; usage across tasks is safe. Callers should not mutate the underlying URLSession configuration concurrently.
struct AudioDownloader: Sendable {
    /// Controls how jitter is applied to the exponential backoff delays.
    enum JitterStrategy: Sendable {
        /// No jitter. Deterministic backoff (useful for some tests).
        case none
        /// Equal jitter (aka "Decorrelated jitter"): delay = base/2 ... base.
        case equal
        /// Full jitter: delay = 0 ... base.
        case full
    }

    // Normalize potentially invalid configuration values.
    private static func normalize(maxRetries: Int, initialDelay: UInt64, maxDelay: UInt64) -> (Int, UInt64, UInt64) {
        let retries = max(0, maxRetries)
        let initDelay = initialDelay
        let maxD = max(maxDelay, initDelay == 0 ? 0 : initDelay) // ensure maxDelay >= initialDelay
        return (retries, initDelay, maxD)
    }

    let session: URLSession

    /// Maximum number of retries after the initial attempt.
    let maxRetries: Int
    /// Initial backoff delay (nanoseconds).
    let initialDelay: UInt64
    /// Maximum backoff delay (nanoseconds).
    let maxDelay: UInt64
    /// Jitter behavior for backoff delays.
    let jitter: JitterStrategy
    /// Randomness source for jitter (injected for testability).
    let rng: any AudioRandomNumberGenerator

    /// Create a downloader with a specific `URLSession` and default retry/backoff configuration.
    init(session: URLSession) {
        self.session = session
        let (r, i, m) = Self.normalize(maxRetries: 2, initialDelay: 500_000_000, maxDelay: 4_000_000_000)
        self.maxRetries = r
        self.initialDelay = i
        self.maxDelay = m
        self.jitter = .equal
        self.rng = SystemAudioRNG()
    }

    /// Create a downloader with full configuration.
    init(session: URLSession,
         maxRetries: Int,
         initialDelay: UInt64,
         maxDelay: UInt64,
         jitter: JitterStrategy,
         rng: any AudioRandomNumberGenerator = SystemAudioRNG()) {
        self.session = session
        let (r, i, m) = Self.normalize(maxRetries: maxRetries, initialDelay: initialDelay, maxDelay: maxDelay)
        self.maxRetries = r
        self.initialDelay = i
        self.maxDelay = m
        self.jitter = jitter
        self.rng = rng
    }

    @inline(__always)
    func ensureNotCancelled() throws {
        try Task.checkCancellation()
    }

    /// Downloads an audio resource with retries, honoring cancellation, server backoff hints,
    /// and selective retry policies.
    ///
    /// Total attempts = 1 initial attempt + `maxRetries` retries.
    /// - Returns: A `TemporaryFileHandle` and the typed HTTP response. Caller must move the file.
    func downloadWithRetry(from url: URL) async throws -> (TemporaryFileHandle, HTTPURLResponse) {
        // Fail fast on unsupported schemes
        if let scheme = url.scheme?.lowercased(), scheme != "http" && scheme != "https" {
            throw URLError(.unsupportedURL)
        }

        try ensureNotCancelled()

        let totalAttempts = maxRetries + 1
        var delay = initialDelay

        for attempt in 1...totalAttempts {
            try ensureNotCancelled() // single point of cancellation check before attempt

            var tmpURLForCleanup: URL?
            do {
                let request = URLRequest.audioGET(url)
                let (tmpURL, response) = try await session.download(for: request)
                tmpURLForCleanup = tmpURL

                guard let http = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }

                // Header-level validation first (status/MIME)
                try validateAudioHTTPResponse(http)

                // Guard against zero-length file downloads (prefer header; fall back to disk check if header missing or invalid)
                let contentLengthHeader = http.value(forHTTPHeaderField: "Content-Length")?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let parsedContentLength: Int64? = contentLengthHeader.flatMap(Int64.init)

                if let cl = parsedContentLength {
                    if cl < 0 {
                        throw HTTPValidationError(response: http, reason: "Invalid negative Content-Length")
                    }
                    if cl == 0 {
                        throw HTTPValidationError(response: http, reason: "Zero Content-Length for file download")
                    }
                } else {
                    // Fall back to disk check only if header missing or invalid
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: tmpURL.path()),
                       let size = attrs[.size] as? NSNumber, size.int64Value == 0 {
                        throw HTTPValidationError(response: http, reason: "Downloaded file is empty")
                    }
                }

                // Passed validation — keep temp file and return typed response
                return (TemporaryFileHandle(url: tmpURL), http)
            } catch {
                // Always cleanup temp file if we created one during this attempt
                if let tmp = tmpURLForCleanup {
                    try? FileManager.default.removeItem(at: tmp)
                }

                // If this is an explicit cancellation, rethrow immediately (no more retries)
                if Task.isCancelled || error is CancellationError {
                    throw error
                }

                // Decide whether to retry based on error/response classification
                let classification = classify(error: error)
                let shouldRetry = shouldRetry(for: classification, attempt: attempt, totalAttempts: totalAttempts)
                if !shouldRetry {
                    // Permanent failure or out of attempts — stop here
                    throw error
                }

                // Compute next delay (single source of truth), honoring Retry-After when available.
                // nextBackoffDelay owns the exponential growth and jitter.
                let httpForRetryAfter = classification.extractHTTPResponse()
                let nextDelay = nextBackoffDelay(current: delay, classification: classification, http: httpForRetryAfter)

                // Sleep in a cancellation-respecting way. If cancelled, this throws and exits.
                try await Task.sleep(nanoseconds: nextDelay)

                // Record the computed delay for the next iteration (do not double again).
                delay = nextDelay
            }
        }

        // Explicit terminal outcome in case of unforeseen control flow
        throw URLError(.unknown)
    }
}

// MARK: - Retry Classification & Policies
private extension AudioDownloader {
    /// Encapsulates whether an error is transient (retryable) and any HTTP details.
    enum RetryClassification {
        case transient
        case permanent
        case http(HTTPURLResponse) // http is transient only for certain codes; see helper

        var isTransient: Bool {
            switch self {
            case .transient: return true
            case .http(let http):
                switch http.statusCode {
                case 408, 429, 500...599: return true
                default: return false
                }
            case .permanent: return false
            }
        }

        /// Extract the associated HTTPURLResponse if present.
        func extractHTTPResponse() -> HTTPURLResponse? {
            if case .http(let resp) = self { return resp }
            return nil
        }
    }

    func classify(error: Error) -> RetryClassification {
        // Cancellation is never retried (handled by caller of this method)
        if error is CancellationError { return .permanent }

        // URL errors — map common transient network failures
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
                 .dnsLookupFailed, .notConnectedToInternet, .internationalRoamingOff,
                 .callIsActive, .dataNotAllowed, .secureConnectionFailed,
                 .cannotLoadFromNetwork:
                return .transient
            case .cancelled:
                return .permanent
            default:
                break
            }
        }

        // Response validation errors may carry an HTTPURLResponse; treat 408/429/5xx as transient
        if let responseError = error as? HTTPValidationError {
            return .http(responseError.response)
        }

        // If we can unwrap an HTTPURLResponse from a badServerResponse scenario, handle that
        if let http = (error as NSError).userInfo["HTTPURLResponse"] as? HTTPURLResponse {
            return .http(http)
        }

        return .permanent
    }

    func shouldRetry(for classification: RetryClassification, attempt: Int, totalAttempts: Int) -> Bool {
        guard classification.isTransient else { return false }
        return attempt < totalAttempts
    }

    func nextBackoffDelay(current: UInt64, classification: RetryClassification, http: HTTPURLResponse?) -> UInt64 {
        var next = min(current * 2, maxDelay)
        if case .http(let resp) = classification, let override = retryAfterDelay(from: resp) {
            next = min(override, maxDelay)
        } else if let http = http, let override = retryAfterDelay(from: http) {
            next = min(override, maxDelay)
        }
        return applyJitter(to: next)
    }
}

// MARK: - Validation
private extension AudioDownloader {
    /// An error type that captures HTTP validation failures with access to the response.
    struct HTTPValidationError: LocalizedError, Sendable {
        let response: HTTPURLResponse
        let reason: String
        var errorDescription: String? { reason }
    }

    /// Validate that the response is a successful audio response.
    /// - Throws: `HTTPValidationError` for non-2xx or clearly non-audio content.
    func validateAudioHTTPResponse(_ http: HTTPURLResponse) throws {
        guard (200...299).contains(http.statusCode) else {
            throw HTTPValidationError(response: http, reason: "HTTP status \(http.statusCode) not successful")
        }

        // Content-Type validation (allow audio/* or application/octet-stream as permissive)
        if let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() {
            // Strip parameters (e.g., "; charset=utf-8")
            let type = contentType.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? contentType
            let isAudio = type.hasPrefix("audio/")
            let isOctet = type == "application/octet-stream"
            // Common playlist types to reject for file downloads
            let playlistTypes: Set<String> = [
                "application/vnd.apple.mpegurl", // HLS m3u8
                "application/x-mpegurl",
                "audio/mpegurl",
                "audio/x-mpegurl",
                "application/pls+xml",
                "audio/x-scpls",
                "application/xspf+xml"
            ]
            if playlistTypes.contains(type) {
                throw HTTPValidationError(response: http, reason: "Content-Type \(type) is a playlist, not a file")
            }
            if !(isAudio || isOctet) {
                throw HTTPValidationError(response: http, reason: "Content-Type \(type) is not audio")
            }
        }
        // If header missing, be tolerant and allow
    }
}

// MARK: - Retry-After & Backoff with Jitter
private extension AudioDownloader {
    /// Parses Retry-After header (seconds or HTTP-date). Returns nanoseconds to wait.
    func retryAfterDelay(from http: HTTPURLResponse) -> UInt64? {
        guard let rawValue = http.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespacesAndNewlines), !rawValue.isEmpty else {
            return nil
        }

        // Numeric seconds take precedence
        if let seconds = Double(rawValue), seconds.isFinite, seconds >= 0 {
            let nanosDouble = seconds * 1_000_000_000
            guard nanosDouble.isFinite && nanosDouble >= 0 else { return nil }
            // Clamp first to configured maxDelay, then to UInt64.max before converting.
            let clampedToMaxDelay = min(nanosDouble, Double(maxDelay))
            let clampedToUInt = min(clampedToMaxDelay, Double(UInt64.max))
            return UInt64(clampedToUInt)
        }

        // Try common HTTP-date variants, most common first (RFC 1123), then fall back.
        if let date = Self.rfc1123Formatter.date(from: rawValue) {
            let delta = date.timeIntervalSinceNow
            if delta.isFinite, delta >= 0 {
                if delta == 0 { return 0 }
                let nanosDouble = delta * 1_000_000_000
                guard nanosDouble.isFinite && nanosDouble > 0 else { return nil }
                let clampedToMaxDelay = min(nanosDouble, Double(maxDelay))
                let clampedToUInt = min(clampedToMaxDelay, Double(UInt64.max))
                return UInt64(clampedToUInt)
            } else {
                return nil
            }
        }
        if let date = Self.rfc850Formatter.date(from: rawValue) {
            let delta = date.timeIntervalSinceNow
            if delta.isFinite, delta >= 0 {
                if delta == 0 { return 0 }
                let nanosDouble = delta * 1_000_000_000
                guard nanosDouble.isFinite && nanosDouble > 0 else { return nil }
                let clampedToMaxDelay = min(nanosDouble, Double(maxDelay))
                let clampedToUInt = min(clampedToMaxDelay, Double(UInt64.max))
                return UInt64(clampedToUInt)
            } else {
                return nil
            }
        }
        if let date = Self.asctimeFormatter.date(from: rawValue) {
            let delta = date.timeIntervalSinceNow
            if delta.isFinite, delta >= 0 {
                if delta == 0 { return 0 }
                let nanosDouble = delta * 1_000_000_000
                guard nanosDouble.isFinite && nanosDouble > 0 else { return nil }
                let clampedToMaxDelay = min(nanosDouble, Double(maxDelay))
                let clampedToUInt = min(clampedToMaxDelay, Double(UInt64.max))
                return UInt64(clampedToUInt)
            } else {
                return nil
            }
        }

        return nil
    }

    func applyJitter(to delay: UInt64) -> UInt64 {
        guard delay > 0 else { return 0 }
        switch jitter {
        case .none:
            return delay
        case .equal:
            // Random in [delay/2, delay]
            let half = delay / 2
            let range = rng.random(in: 0...half)
            return half + range
        case .full:
            // Random in [0, delay]
            return rng.random(in: 0...delay)
        }
    }
}

private extension AudioDownloader {
    static let rfc1123Formatter: DateFormatter = {
        let tz = TimeZone(secondsFromGMT: 0)
        let loc = Locale(identifier: "en_US_POSIX")
        let df = DateFormatter()
        df.locale = loc; df.timeZone = tz; df.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return df
    }()

    static let rfc850Formatter: DateFormatter = {
        let tz = TimeZone(secondsFromGMT: 0)
        let loc = Locale(identifier: "en_US_POSIX")
        let df = DateFormatter()
        df.locale = loc; df.timeZone = tz; df.dateFormat = "EEEE',' dd-MMM-yy HH':'mm':'ss zzz"
        return df
    }()

    static let asctimeFormatter: DateFormatter = {
        let tz = TimeZone(secondsFromGMT: 0)
        let loc = Locale(identifier: "en_US_POSIX")
        let df = DateFormatter()
        df.locale = loc; df.timeZone = tz; df.dateFormat = "EEE MMM d HH':'mm':'ss yyyy"
        return df
    }()
}

// MARK: - URLRequest helper
private extension URLRequest {
    static func audioGET(_ url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        // Prefer audio content types if server negotiates
        req.setValue("audio/*,application/octet-stream;q=0.9,*/*;q=0.5", forHTTPHeaderField: "Accept")
        return req
    }
}

