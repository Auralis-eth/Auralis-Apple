import AuralisPrimaryModels
import Foundation
import SwiftData

@Model
final class AuraPlayNFTToken {
    #Index<AuraPlayNFTToken>(
        [\.walletID, \.sourceNFTID],
        [\.walletID, \.contractAddressRawValue, \.tokenID],
        [\.walletID, \.updatedAt]
    )

    @Attribute(.unique) var compositeID: String

    var walletID: String
    var sourceNFTID: String
    var contractAddressRawValue: String
    var tokenID: String
    var tokenType: String?
    var title: String
    var artistName: String?
    var collectionName: String?
    var artworkURLString: String?
    var playbackURLString: String?
    var contentType: String?
    var sourceUpdatedAtRawValue: String?
    var createdAt: Date
    var updatedAt: Date

    var wallet: AuraPlayWallet?

    @Relationship(deleteRule: .cascade, inverse: \AuraPlayMediaItem.token)
    var mediaItem: AuraPlayMediaItem?

    init(
        walletID: String,
        sourceNFTID: String,
        contractAddressRawValue: String,
        tokenID: String,
        tokenType: String?,
        title: String,
        artistName: String?,
        collectionName: String?,
        artworkURLString: String?,
        playbackURLString: String?,
        contentType: String?,
        sourceUpdatedAtRawValue: String?,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.compositeID = Self.makeCompositeID(
            walletID: walletID,
            contractAddressRawValue: contractAddressRawValue,
            tokenID: tokenID
        )
        self.walletID = walletID
        self.sourceNFTID = sourceNFTID
        self.contractAddressRawValue = contractAddressRawValue
        self.tokenID = tokenID
        self.tokenType = tokenType
        self.title = title
        self.artistName = artistName
        self.collectionName = collectionName
        self.artworkURLString = artworkURLString
        self.playbackURLString = playbackURLString
        self.contentType = contentType
        self.sourceUpdatedAtRawValue = sourceUpdatedAtRawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func makeCompositeID(
        walletID: String,
        contractAddressRawValue: String,
        tokenID: String
    ) -> String {
        let normalizedContractAddress = NFT.normalizedScopeComponent(contractAddressRawValue) ?? contractAddressRawValue
        return "\(walletID):\(normalizedContractAddress):\(tokenID)"
    }
}
