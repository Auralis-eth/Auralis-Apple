import AuralisCrypto
import Foundation
import SwiftData

@Model
public final class AuraPlayMediaItem {
    #Index<AuraPlayMediaItem>(
        [\.accountAddressRawValue, \.chainRawValue, \.sourceNFTID],
        [\.accountAddressRawValue, \.chainRawValue, \.contractAddressRawValue, \.tokenID],
        [\.accountAddressRawValue, \.chainRawValue, \.normalizedArtistKey, \.normalizedTitleKey, \.id],
        [\.accountAddressRawValue, \.chainRawValue, \.creatorIdentifierRawValue],
        [\.accountAddressRawValue, \.chainRawValue, \.lastPlayedAt],
        [\.accountAddressRawValue, \.chainRawValue]
    )

    @Attribute(.unique) public var id: String
    public var sourceNFTID: String
    public var accountAddressRawValue: String
    public var chainRawValue: String
    public var contractAddressRawValue: String?
    public var tokenID: String
    public var tokenType: String?
    public var title: String
    public var artistName: String?
    public var creatorIdentifierRawValue: String?
    public var collectionName: String?
    public var normalizedTitleKey: String
    public var normalizedArtistKey: String
    public var normalizedCollectionKey: String
    public var artworkURLString: String?
    /// User-owned presentation metadata. Provider values above remain untouched
    /// so a later network refresh can never erase a person's edits.
    public var userTitleOverride: String?
    public var userArtistNameOverride: String?
    public var userCollectionNameOverride: String?
    public var userArtworkURLStringOverride: String?
    public var playbackURLString: String?
    public var durationSeconds: Double?
    public var contentType: String?
    public var sourceUpdatedAtRawValue: String?
    public var hasArtwork: Bool
    public var hasAudio: Bool
    public var hasVideo: Bool
    public var isPlayable: Bool
    public var isSearchable: Bool
    public var cachedFileStateRawValue: String = "notCached"
    public var approxLoudnessLUFS: Double?
    public var lastPlayedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        sourceNFTID: String,
        accountAddressRawValue: String,
        chain: Chain,
        contractAddressRawValue: String?,
        tokenID: String,
        tokenType: String?,
        title: String,
        artistName: String?,
        creatorIdentifierRawValue: String? = nil,
        collectionName: String?,
        normalizedTitleKey: String,
        normalizedArtistKey: String,
        normalizedCollectionKey: String,
        artworkURLString: String?,
        userTitleOverride: String? = nil,
        userArtistNameOverride: String? = nil,
        userCollectionNameOverride: String? = nil,
        userArtworkURLStringOverride: String? = nil,
        playbackURLString: String?,
        durationSeconds: Double? = nil,
        contentType: String?,
        sourceUpdatedAtRawValue: String?,
        hasArtwork: Bool,
        hasAudio: Bool,
        hasVideo: Bool,
        isPlayable: Bool,
        isSearchable: Bool,
        cachedFileStateRawValue: String = "notCached",
        approxLoudnessLUFS: Double? = nil,
        lastPlayedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = sourceNFTID
        self.sourceNFTID = sourceNFTID
        self.accountAddressRawValue = accountAddressRawValue
        self.chainRawValue = chain.rawValue
        self.contractAddressRawValue = contractAddressRawValue
        self.tokenID = tokenID
        self.tokenType = tokenType
        self.title = title
        self.artistName = artistName
        self.creatorIdentifierRawValue = creatorIdentifierRawValue
        self.collectionName = collectionName
        self.normalizedTitleKey = normalizedTitleKey
        self.normalizedArtistKey = normalizedArtistKey
        self.normalizedCollectionKey = normalizedCollectionKey
        self.artworkURLString = artworkURLString
        self.userTitleOverride = userTitleOverride
        self.userArtistNameOverride = userArtistNameOverride
        self.userCollectionNameOverride = userCollectionNameOverride
        self.userArtworkURLStringOverride = userArtworkURLStringOverride
        self.playbackURLString = playbackURLString
        self.durationSeconds = durationSeconds.map { max(0, $0) }
        self.contentType = contentType
        self.sourceUpdatedAtRawValue = sourceUpdatedAtRawValue
        self.hasArtwork = hasArtwork
        self.hasAudio = hasAudio
        self.hasVideo = hasVideo
        self.isPlayable = isPlayable
        self.isSearchable = isSearchable
        self.cachedFileStateRawValue = cachedFileStateRawValue
        self.approxLoudnessLUFS = approxLoudnessLUFS
        self.lastPlayedAt = lastPlayedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var chain: Chain {
        get { Chain(rawValue: chainRawValue) ?? .ethMainnet }
        set { chainRawValue = newValue.rawValue }
    }

    public var displayTitle: String { Self.nonEmpty(userTitleOverride) ?? title }
    public var displayArtistName: String? { Self.nonEmpty(userArtistNameOverride) ?? Self.nonEmpty(artistName) }
    public var displayCollectionName: String? { Self.nonEmpty(userCollectionNameOverride) ?? Self.nonEmpty(collectionName) }
    public var displayArtworkURLString: String? { Self.nonEmpty(userArtworkURLStringOverride) ?? Self.nonEmpty(artworkURLString) }

    public var displayNormalizedTitleKey: String { Self.normalizedKey(displayTitle) }
    public var displayNormalizedArtistKey: String { Self.normalizedKey(displayArtistName) }
    public var displayNormalizedCollectionKey: String { Self.normalizedKey(displayCollectionName) }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func normalizedKey(_ value: String?) -> String {
        nonEmpty(value)?.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) ?? ""
    }
}
