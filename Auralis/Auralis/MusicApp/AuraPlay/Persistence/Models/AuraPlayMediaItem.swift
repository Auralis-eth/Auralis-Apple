import Foundation
import SwiftData

@Model
final class AuraPlayMediaItem {
    @Attribute(.unique) var id: String

    var walletID: String
    var tokenCompositeID: String
    var sourceNFTID: String
    var accountAddressRawValue: String
    var chainRawValue: String
    var title: String
    var artistName: String?
    var collectionName: String?
    var normalizedTitleKey: String
    var normalizedArtistKey: String
    var normalizedCollectionKey: String
    var artworkURLString: String?
    var playbackURLString: String?
    var contentType: String?
    var sourceUpdatedAtRawValue: String?
    var hasArtwork: Bool
    var hasAudio: Bool
    var isPlayable: Bool
    var isSearchable: Bool
    var createdAt: Date
    var updatedAt: Date

    var wallet: AuraPlayWallet?
    var token: AuraPlayNFTToken?

    init(
        walletID: String,
        tokenCompositeID: String,
        sourceNFTID: String,
        accountAddressRawValue: String,
        chain: Chain,
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
        isSearchable: Bool,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = sourceNFTID
        self.walletID = walletID
        self.tokenCompositeID = tokenCompositeID
        self.sourceNFTID = sourceNFTID
        self.accountAddressRawValue = accountAddressRawValue
        self.chainRawValue = chain.rawValue
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
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var chain: Chain {
        get { Chain(rawValue: chainRawValue) ?? .ethMainnet }
        set { chainRawValue = newValue.rawValue }
    }
}
