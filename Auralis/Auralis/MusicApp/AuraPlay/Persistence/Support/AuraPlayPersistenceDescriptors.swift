import Foundation

struct AuraPlayWalletUpsertRequest: Sendable {
    let address: String
    let chain: Chain
    let displayName: String?
    let syncedAt: Date
}

struct AuraPlayNFTTokenUpsertRequest: Sendable {
    let walletID: String
    let sourceNFTID: String
    let contractAddressRawValue: String
    let tokenID: String
    let tokenType: String?
    let title: String
    let artistName: String?
    let collectionName: String?
    let artworkURLString: String?
    let playbackURLString: String?
    let contentType: String?
    let sourceUpdatedAtRawValue: String?
}

struct AuraPlayMediaItemUpsertRequest: Sendable {
    let walletID: String
    let tokenCompositeID: String
    let sourceNFTID: String
    let accountAddressRawValue: String
    let chain: Chain
    let title: String
    let artistName: String?
    let collectionName: String?
    let normalizedTitleKey: String
    let normalizedArtistKey: String
    let normalizedCollectionKey: String
    let artworkURLString: String?
    let playbackURLString: String?
    let contentType: String?
    let sourceUpdatedAtRawValue: String?
    let hasArtwork: Bool
    let hasAudio: Bool
    let isPlayable: Bool
    let isSearchable: Bool
}
