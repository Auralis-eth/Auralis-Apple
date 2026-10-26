import AuralisPrimaryModels
import Foundation
import SwiftData

@Model
public final class AuraPlayNFTToken {
    #Index<AuraPlayNFTToken>(
        [\.walletAddress, \.chainRawValue, \.compositeID],
        [\.walletAddress, \.chainRawValue, \.isActive]
    )

    @Attribute(.unique) public var compositeID: String
    public var chainRawValue: String
    public var walletAddress: String
    public var contractAddress: String?
    public var tokenId: String
    public var tokenStandard: String?
    public var collectionName: String?
    public var name: String?
    public var tokenDescription: String?
    public var imageURL: String?
    public var metadataURL: String?
    public var metadataRaw: String?
    public var providerUpdatedAt: String?
    public var isActive: Bool
    public var providerRawValue: String
    public var updatedAt: Date
    public var createdAt: Date

    public init(dto: NFTTokenDTO, now: Date = .now) {
        self.compositeID = dto.compositeID
        self.chainRawValue = dto.chain.rawValue
        self.walletAddress = dto.walletAddress
        self.contractAddress = dto.contractAddress
        self.tokenId = dto.tokenId
        self.tokenStandard = dto.tokenStandard
        self.collectionName = dto.collectionName
        self.name = dto.name
        self.tokenDescription = dto.description
        self.imageURL = dto.imageURL
        self.metadataURL = dto.metadataURL
        self.metadataRaw = dto.metadataRaw
        self.providerUpdatedAt = dto.providerUpdatedAt
        self.isActive = dto.isActive
        self.providerRawValue = dto.provider.rawValue
        self.updatedAt = now
        self.createdAt = now
    }

    public var chain: Chain {
        get { Chain(rawValue: chainRawValue) ?? .ethMainnet }
        set { chainRawValue = newValue.rawValue }
    }

    public var provider: NFTDiscoveryProvider {
        get { NFTDiscoveryProvider(rawValue: providerRawValue) ?? .unknown }
        set { providerRawValue = newValue.rawValue }
    }

    public func apply(_ dto: NFTTokenDTO, now: Date = .now) {
        chainRawValue = dto.chain.rawValue
        walletAddress = dto.walletAddress
        contractAddress = dto.contractAddress
        tokenId = dto.tokenId
        tokenStandard = dto.tokenStandard
        collectionName = dto.collectionName
        name = dto.name
        tokenDescription = dto.description
        imageURL = dto.imageURL
        metadataURL = dto.metadataURL
        metadataRaw = dto.metadataRaw
        providerUpdatedAt = dto.providerUpdatedAt
        isActive = dto.isActive
        providerRawValue = dto.provider.rawValue
        updatedAt = now
    }
}
