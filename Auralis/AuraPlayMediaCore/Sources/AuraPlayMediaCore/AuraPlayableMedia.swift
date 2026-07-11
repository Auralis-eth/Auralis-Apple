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

public enum AuraCachedFileState: String, Sendable, CaseIterable {
    case notCached
    case partial
    case cached
    case pinned
}

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
