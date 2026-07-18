import AuralisPrimaryModels
import Foundation

public enum MediaItemSort: String, CaseIterable, Identifiable, Codable, Equatable, Sendable {
    case dateAdded
    case titleAZ
    case creatorAZ
    case duration
    case lastPlayed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dateAdded:
            "Date Added"
        case .titleAZ:
            "Title"
        case .creatorAZ:
            "Creator"
        case .duration:
            "Duration"
        case .lastPlayed:
            "Last Played"
        }
    }
}

public enum MediaItemMediaTypeFilter: String, CaseIterable, Identifiable, Codable, Equatable, Sendable {
    case all
    case audio
    case video

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all:
            "All"
        case .audio:
            "Audio"
        case .video:
            "Video"
        }
    }
}

public struct MediaItemFilter: Codable, Equatable, Sendable {
    public var scope: AuraPlayLibraryScope
    public var selectedChains: Set<Chain>
    public var mediaType: MediaItemMediaTypeFilter
    public var unplayedOnly: Bool
    /// Browse surfaces show non-playable media dimmed; queue windows keep this false.
    public var includeNonPlayable: Bool

    public init(
        scope: AuraPlayLibraryScope,
        selectedChains: Set<Chain> = [],
        mediaType: MediaItemMediaTypeFilter = .all,
        unplayedOnly: Bool = false,
        includeNonPlayable: Bool = false
    ) {
        self.scope = scope
        self.selectedChains = selectedChains
        self.mediaType = mediaType
        self.unplayedOnly = unplayedOnly
        self.includeNonPlayable = includeNonPlayable
    }

    enum CodingKeys: String, CodingKey {
        case scope
        case selectedChains
        case mediaType
        case unplayedOnly
        case includeNonPlayable
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.scope = try container.decode(AuraPlayLibraryScope.self, forKey: .scope)
        self.selectedChains = try container.decode(Set<Chain>.self, forKey: .selectedChains)
        self.mediaType = try container.decode(MediaItemMediaTypeFilter.self, forKey: .mediaType)
        self.unplayedOnly = try container.decode(Bool.self, forKey: .unplayedOnly)
        self.includeNonPlayable = try container.decodeIfPresent(Bool.self, forKey: .includeNonPlayable) ?? false
    }
}

public struct MediaItemQueryContext: Codable, Equatable, Sendable {
    public var scope: AuraPlayLibraryScope
    public var sort: MediaItemSort
    public var filter: MediaItemFilter
    public var offset: Int
    public var limit: Int

    public init(
        scope: AuraPlayLibraryScope,
        sort: MediaItemSort = .dateAdded,
        filter: MediaItemFilter? = nil,
        offset: Int = 0,
        limit: Int = 100
    ) {
        self.scope = scope
        self.sort = sort
        self.filter = filter ?? MediaItemFilter(scope: scope)
        self.offset = max(0, offset)
        self.limit = max(1, limit)
    }

    public func nextPageContext() -> MediaItemQueryContext {
        MediaItemQueryContext(
            scope: scope,
            sort: sort,
            filter: filter,
            offset: offset + limit,
            limit: limit
        )
    }
}

public struct MediaItemQueryItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let sourceNFTID: String
    public let title: String
    public let artistName: String?
    public let collectionName: String?
    public let artworkURLString: String?
    public let durationSeconds: Double?
    public let hasAudio: Bool
    public let hasVideo: Bool
    public let isPlayable: Bool
    public let lastPlayedAt: Date?
    public let chain: Chain
    public let contractAddress: String?
    public let tokenID: String?
    public let creatorIdentifier: String?

    public init(item: AuraPlayMediaItem) {
        self.id = item.id
        self.sourceNFTID = item.sourceNFTID
        self.title = item.title
        self.artistName = item.artistName
        self.collectionName = item.collectionName
        self.artworkURLString = item.artworkURLString
        self.durationSeconds = item.durationSeconds
        self.hasAudio = item.hasAudio
        self.hasVideo = item.hasVideo
        self.isPlayable = item.isPlayable
        self.lastPlayedAt = item.lastPlayedAt
        self.chain = item.chain
        self.contractAddress = item.contractAddressRawValue
        self.tokenID = item.tokenID
        self.creatorIdentifier = item.creatorIdentifierRawValue
    }

    /// Playback presentation used when this row seeds an orchestrator queue window.
    public var playbackPresentation: AuraPlayPlaybackItemPresentation {
        AuraPlayPlaybackItemPresentation(
            id: sourceNFTID,
            title: title.isEmpty ? "Untitled" : title,
            creator: artistName,
            artworkURLString: artworkURLString,
            duration: durationSeconds,
            mediaKind: hasVideo ? .video : .audio
        )
    }
}

public struct MediaItemQueryResult: Sendable {
    public let items: [MediaItemQueryItem]
    public let totalCount: Int
    public let nextOffset: Int?

    public init(items: [MediaItemQueryItem], totalCount: Int, nextOffset: Int?) {
        self.items = items
        self.totalCount = totalCount
        self.nextOffset = nextOffset
    }
}
