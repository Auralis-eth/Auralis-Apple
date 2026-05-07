import AuralisPrimaryModels
import Foundation
import SwiftData

@Model
final class AuraPlayWallet {
    #Index<AuraPlayWallet>(
        [\.addressRawValue, \.chainRawValue],
        [\.lastSyncedAt]
    )

    @Attribute(.unique) var id: String

    var addressRawValue: String
    var chainRawValue: String
    var displayName: String?
    var createdAt: Date
    var updatedAt: Date
    var lastSyncedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \AuraPlayNFTToken.wallet)
    var tokens: [AuraPlayNFTToken]?

    @Relationship(deleteRule: .cascade, inverse: \AuraPlayMediaItem.wallet)
    var mediaItems: [AuraPlayMediaItem]?

    init(
        address: String,
        chain: Chain,
        displayName: String?,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lastSyncedAt: Date? = nil
    ) {
        self.id = Self.scopedID(address: address, chain: chain)
        self.addressRawValue = address
        self.chainRawValue = chain.rawValue
        self.displayName = displayName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastSyncedAt = lastSyncedAt
    }

    var chain: Chain {
        get { Chain(rawValue: chainRawValue) ?? .ethMainnet }
        set { chainRawValue = newValue.rawValue }
    }

    static func scopedID(address: String, chain: Chain) -> String {
        let normalizedAddress = NFT.normalizedScopeComponent(address) ?? address
        return "\(normalizedAddress):\(chain.rawValue)"
    }
}
