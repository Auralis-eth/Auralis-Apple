import Foundation

import AuralisPrimaryModels

struct AuraPlayAccountSyncUpdateRequest: Sendable {
    let address: String
    let chain: Chain
    let displayName: String?
    let syncedAt: Date
}

struct AuraPlayMediaItemUpsertRequest: Sendable {
    let sourceNFTID: String
    let accountAddressRawValue: String
    let chain: Chain
    let contractAddressRawValue: String?
    let tokenID: String
    let tokenType: String?
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
