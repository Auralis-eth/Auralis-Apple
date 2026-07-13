import Foundation

public struct MediaMetadata: Equatable, Sendable {
    public let id: String
    public let title: String
    public let artist: String?
    public let artworkURL: URL?

    public init(id: String, title: String, artist: String?, artworkURL: URL?) {
        self.id = id
        self.title = title
        self.artist = artist
        self.artworkURL = artworkURL
    }
}

public struct AuraPlayableMediaItem: AuraPlayableMedia, Identifiable {
    public let id: String
    public let sourceURL: URL
    public let declaredFormat: String?
    public let contentKind: AuraPlayableContentKind
    public let cachedFileState: AuraCachedFileState
    public let approxLoudnessLUFS: Double?
    public let metadata: MediaMetadata

    public init(
        id: String,
        sourceURL: URL,
        declaredFormat: String? = nil,
        contentKind: AuraPlayableContentKind = .unknown,
        cachedFileState: AuraCachedFileState = .notCached,
        approxLoudnessLUFS: Double? = nil,
        metadata: MediaMetadata
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.declaredFormat = declaredFormat
        self.contentKind = contentKind
        self.cachedFileState = cachedFileState
        self.approxLoudnessLUFS = approxLoudnessLUFS
        self.metadata = metadata
    }

    /// Stringifies `media.id` via `String(describing:)`; see
    /// ``AnyAuraPlayableMedia`` for the ID-collision caveat.
    public init<M: AuraPlayableMedia>(_ media: M, metadata: MediaMetadata) {
        self.id = String(describing: media.id)
        self.sourceURL = media.sourceURL
        self.declaredFormat = media.declaredFormat
        self.contentKind = media.contentKind
        self.cachedFileState = media.cachedFileState
        self.approxLoudnessLUFS = media.approxLoudnessLUFS
        self.metadata = metadata
    }
}
