import Foundation

public protocol AuraPlayableMedia: Sendable {
    associatedtype ID: Hashable & Sendable

    var id: ID { get }
    var sourceURL: URL { get }
    var declaredFormat: String? { get }
    var contentKind: AuraPlayableContentKind { get }
    var cachedFileState: AuraCachedFileState { get }
    var approxLoudnessLUFS: Double? { get }
}

public enum AuraPlayableContentKind: String, Sendable, CaseIterable, Codable {
    case music
    case spokenWord
    case video
    case unknown
}

/// What the cache currently holds on disk for a media item, however it got
/// there. Complements ``MediaOfflineState``, which tracks the lifecycle of an
/// explicit user-requested offline download.
public enum AuraCachedFileState: String, Sendable, CaseIterable, Codable {
    case notCached
    case partial
    case cached
    case pinned
}

/// A type-erased playable media value.
///
/// Erasure stringifies the source ID via `String(describing:)`, so IDs that
/// print identically from different ID types (`Int` 42 and `String` "42")
/// collide. Callers mixing ID types in one collection must namespace their IDs.
public struct AnyAuraPlayableMedia: AuraPlayableMedia, Identifiable {
    public let id: String
    public let sourceURL: URL
    public let declaredFormat: String?
    public let contentKind: AuraPlayableContentKind
    public let cachedFileState: AuraCachedFileState
    public let approxLoudnessLUFS: Double?

    public init(
        id: String,
        sourceURL: URL,
        declaredFormat: String? = nil,
        contentKind: AuraPlayableContentKind = .unknown,
        cachedFileState: AuraCachedFileState = .notCached,
        approxLoudnessLUFS: Double? = nil
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.declaredFormat = declaredFormat
        self.contentKind = contentKind
        self.cachedFileState = cachedFileState
        self.approxLoudnessLUFS = approxLoudnessLUFS
    }

    public init<M: AuraPlayableMedia>(_ media: M) {
        self.id = String(describing: media.id)
        self.sourceURL = media.sourceURL
        self.declaredFormat = media.declaredFormat
        self.contentKind = media.contentKind
        self.cachedFileState = media.cachedFileState
        self.approxLoudnessLUFS = media.approxLoudnessLUFS
    }
}
