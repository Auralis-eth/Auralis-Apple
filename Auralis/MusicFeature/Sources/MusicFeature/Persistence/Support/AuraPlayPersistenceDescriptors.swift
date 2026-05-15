import Foundation

import AuralisPrimaryModels

public struct AuraPlayAccountSyncUpdateRequest: Sendable {
    public let address: String
    public let chain: Chain
    public let displayName: String?
    public let syncedAt: Date

    public init(address: String, chain: Chain, displayName: String?, syncedAt: Date) {
        self.address = address
        self.chain = chain
        self.displayName = displayName
        self.syncedAt = syncedAt
    }
}

public struct AuraPlayMediaItemUpsertRequest: Sendable {
    public let sourceNFTID: String
    public let accountAddressRawValue: String
    public let chain: Chain
    public let contractAddressRawValue: String?
    public let tokenID: String
    public let tokenType: String?
    public let title: String
    public let artistName: String?
    public let collectionName: String?
    public let normalizedTitleKey: String
    public let normalizedArtistKey: String
    public let normalizedCollectionKey: String
    public let artworkURLString: String?
    public let playbackURLString: String?
    public let contentType: String?
    public let sourceUpdatedAtRawValue: String?
    public let hasArtwork: Bool
    public let hasAudio: Bool
    public let isPlayable: Bool
    public let isSearchable: Bool

    public init(
        sourceNFTID: String,
        accountAddressRawValue: String,
        chain: Chain,
        contractAddressRawValue: String?,
        tokenID: String,
        tokenType: String?,
        title: String,
        artistName: String?,
        collectionName: String?,
        normalizedTitleKey: String,
        normalizedArtistKey: String,
        normalizedCollectionKey: String,
        artworkURLString: String?,
        playbackURLString: String?,
        contentType: String?,
        sourceUpdatedAtRawValue: String?,
        hasArtwork: Bool,
        hasAudio: Bool,
        isPlayable: Bool,
        isSearchable: Bool
    ) {
        self.sourceNFTID = sourceNFTID
        self.accountAddressRawValue = accountAddressRawValue
        self.chain = chain
        self.contractAddressRawValue = contractAddressRawValue
        self.tokenID = tokenID
        self.tokenType = tokenType
        self.title = title
        self.artistName = artistName
        self.collectionName = collectionName
        self.normalizedTitleKey = normalizedTitleKey
        self.normalizedArtistKey = normalizedArtistKey
        self.normalizedCollectionKey = normalizedCollectionKey
        self.artworkURLString = artworkURLString
        self.playbackURLString = playbackURLString
        self.contentType = contentType
        self.sourceUpdatedAtRawValue = sourceUpdatedAtRawValue
        self.hasArtwork = hasArtwork
        self.hasAudio = hasAudio
        self.isPlayable = isPlayable
        self.isSearchable = isSearchable
    }
}
