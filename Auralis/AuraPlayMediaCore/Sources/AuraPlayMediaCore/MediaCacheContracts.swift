import CryptoKit
import Foundation

public struct CachedLoudnessMeasurement: Equatable, Sendable {
    public let mediaID: String
    public let approxLoudnessLUFS: Double

    public init(mediaID: String, approxLoudnessLUFS: Double) {
        self.mediaID = mediaID
        self.approxLoudnessLUFS = approxLoudnessLUFS
    }
}

public struct CacheProgress: Equatable, Sendable {
    public let mediaID: String
    public let bytesWritten: Int64
    public let expectedBytes: Int64?
    public let state: AuraCachedFileState

    public init(mediaID: String, bytesWritten: Int64, expectedBytes: Int64?, state: AuraCachedFileState) {
        self.mediaID = mediaID
        self.bytesWritten = bytesWritten
        self.expectedBytes = expectedBytes
        self.state = state
    }
}

public protocol MediaCacheManaging: Sendable {
    /// `AsyncStream` is single-consumer, so each access must return a new,
    /// independent stream. Events are broadcast to every stream that is active
    /// when they occur and are not replayed to late subscribers.
    var progress: AsyncStream<CacheProgress> { get }
    /// Same contract as ``progress``: a fresh broadcast stream on every access,
    /// no replay for late subscribers.
    var loudnessMeasurements: AsyncStream<CachedLoudnessMeasurement> { get }

    func localFile<M: AuraPlayableMedia>(for media: M) async throws -> URL
    func localFileWhenPlayable<M: AuraPlayableMedia>(for media: M, minimumPlayableBytes: Int64) async throws -> URL
    func isCached<M: AuraPlayableMedia>(_ media: M) async -> Bool
    func prefetch<M: AuraPlayableMedia>(_ media: M) async
    func pin<M: AuraPlayableMedia>(_ media: M) async throws
    func unpin<M: AuraPlayableMedia>(_ media: M) async throws
}

/// A filesystem-safe cache key: a short human-readable stub followed by a SHA-256
/// digest of the full identity, so distinct identities never collide after
/// sanitization and keys stay well under filename length limits.
public struct CacheKey: Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(mediaID: some Hashable & Sendable) {
        self.rawValue = CacheKey.stableKey(for: String(describing: mediaID), namespace: "media")
    }

    @available(*, unavailable, message: "Use CacheKey(url:) so URL-derived keys get the url namespace.")
    public init(mediaID: URL) {
        fatalError("Unavailable: use CacheKey(url:) instead.")
    }

    public init(url: URL) {
        self.rawValue = CacheKey.stableKey(for: url.absoluteString, namespace: "url")
    }

    private static let maximumStubLength = 40

    private static func stableKey(for value: String, namespace: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let stub = sanitizedStub(for: value)
        return stub.isEmpty ? "\(namespace)-\(digest)" : "\(namespace)-\(stub)-\(digest)"
    }

    private static func sanitizedStub(for value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = value.unicodeScalars.prefix(maximumStubLength).map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        return String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-."))
    }
}
