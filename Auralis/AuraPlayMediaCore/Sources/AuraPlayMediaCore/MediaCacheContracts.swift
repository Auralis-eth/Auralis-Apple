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
    var progress: AsyncStream<CacheProgress> { get }
    var loudnessMeasurements: AsyncStream<CachedLoudnessMeasurement> { get }

    func localFile<M: AuraPlayableMedia>(for media: M) async throws -> URL
    func localFileWhenPlayable<M: AuraPlayableMedia>(for media: M, minimumPlayableBytes: Int64) async throws -> URL
    func isCached<M: AuraPlayableMedia>(_ media: M) async -> Bool
    func prefetch<M: AuraPlayableMedia>(_ media: M) async
    func pin<M: AuraPlayableMedia>(_ media: M) async throws
    func unpin<M: AuraPlayableMedia>(_ media: M) async throws
}

public struct CacheKey: Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(mediaID: some Any) {
        self.rawValue = CacheKey.sanitized(String(describing: mediaID))
    }

    public init(url: URL) {
        self.rawValue = CacheKey.urlSafeBase64(url.absoluteString)
    }

    private static func sanitized(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let sanitized = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        guard !sanitized.isEmpty else {
            return fallbackKey(for: value)
        }
        return sanitized
    }

    private static func fallbackKey(for value: String) -> String {
        guard !value.isEmpty else {
            return "media-empty"
        }
        let hex = value.utf8.map { String(format: "%02x", $0) }.joined()
        return "media-\(hex)"
    }

    private static func urlSafeBase64(_ value: String) -> String {
        Data(value.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }
}
