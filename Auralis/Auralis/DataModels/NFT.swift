//
//  NFT.swift
//  Auralis
//
//  Created by Daniel Bell on 1/6/25.
//

import Foundation
import OSLog
import SwiftData

private let nftLogger = Logger(subsystem: "Auralis", category: "NFT")
@Model
/// Persisted NFT model scoped by account and chain for use across browsing and playback features.
public class NFT: Codable {
    #Unique<NFT>([\.contract, \.tokenId, \.networkRawValue, \.accountAddressRawValue])
    #Index<NFT>([\.id], [\.acquiredAt], [\.collection], [\.tokenId], [\.accountAddressRawValue, \.networkRawValue])

    /// Stable scoped identifier for the NFT.
    @Attribute(.unique) public var id: String
    
    var contract: Contract
    var tokenId: String
    var tokenType: String?
    var name: String?
    var nftDescription: String?
    var image: Image?
    var raw: Raw?
    var collection: Collection?
    var tokenUri: String?
    var timeLastUpdated: String?
    var acquiredAt: AcquiredAt?
    var networkRawValue: String
    var accountAddressRawValue: String
    var contentType: String?
    var collectionName: String?
    var artistName: String?
    var animationUrl: String?
    var secureAnimationUrl: String?
    var audioUrl: String?
    var externalUrl: String?
    var modelUrl: String?
    var backgroundColor: String?
    var collectionID: String?
    var projectID: String?
    var series: String?
    var seriesID: String?
    var primaryAssetUrl: String?
    var securePrimaryAssetUrl: String?
    var previewAssetUrl: String?
    var securePreviewAssetUrl: String?
    var artistWebsite: String?
    var uniqueID: String?
    var timestamp: String?
    var tokenHash: String?
    var medium: String?
    var metadataVersion: String?
    var imageDataUrl: String?
    var secureImageDataUrl: String?
    var imageHrUrl: String?
    var secureImageHrUrl: String?
    var imageHash: String?

    // Adding the new properties from the parsing code
    var symbols: String?
    var seed: String?
    var original: String?
    var agreement: String?
    var website: String?
    var payoutAddress: String?
    var scriptType: String?
    var engineType: String?
    var accessArtworkFiles: String?

    // Numeric properties
    var sellerFeeBasisPoints: Int?
    var minted: Int?
    var isStatic: Int?
    var aspectRatio: Double?

    @Relationship(deleteRule: .cascade, inverse: \Attribute.nft)
    var attributes: [NFT.Attribute]?
    @Relationship(deleteRule: .nullify, inverse: \Tag.nfts)
    var tags: [Tag]?

    @Transient var network: Chain? {
        get {
            Chain(rawValue: networkRawValue)
        }
        set {
            networkRawValue = newValue?.rawValue ?? ""
        }
    }

    @Transient var accountAddress: String? {
        get {
            Self.normalizedScopeComponent(accountAddressRawValue)
        }
        set {
            accountAddressRawValue = Self.normalizedScopeComponent(newValue) ?? ""
        }
    }

    func applyRefreshScope(accountAddress: String?, chain: Chain) {
        accountAddressRawValue = Self.normalizedScopeComponent(accountAddress) ?? ""
        networkRawValue = chain.rawValue
        contract.updateScope(chain: chain)
        collection?.updateScope(chain: chain, contractAddress: contract.address)
        id = Self.makeScopedNFTID(
            accountAddress: accountAddress,
            chain: chain,
            contractAddress: contract.address,
            tokenId: tokenId,
            tokenType: tokenType,
            name: name,
            tokenUri: tokenUri
        )
    }

    func matchesScope(accountAddress: String?, chain: Chain) -> Bool {
        let normalizedAccountAddress = Self.normalizedScopeComponent(accountAddress) ?? ""
        return accountAddressRawValue == normalizedAccountAddress && networkRawValue == chain.rawValue
    }
    
    func isMusic() -> Bool {
        audioUrl?.isEmpty == false
    }
    
    var musicURL: URL? {
        guard let audioUrl else {
            return nil
        }

        return URL.sanitizedRemoteMediaURL(from: audioUrl)
    }

    enum CodingKeys: String, CodingKey {
        case contract
        case tokenId
        case tokenType
        case name
        case nftDescription = "description"
        case image
        case raw
        case collection
        case tokenUri
        case timeLastUpdated
        case acquiredAt
    }
    
    init(id: String, contract: Contract, tokenId: String, tokenType: String? = nil, name: String? = nil, nftDescription: String? = nil, image: Image? = nil, raw: Raw? = nil, collection: Collection?, tokenUri: String? = nil, timeLastUpdated: String? = nil, acquiredAt: AcquiredAt? = nil, network: Chain = .ethMainnet, accountAddress: String? = nil, contentType: String? = nil, collectionName: String? = nil, artistName: String? = nil, animationUrl: String? = nil, secureAnimationUrl: String? = nil, audioUrl: String? = nil, tags: [Tag]? = nil) {
        self.id = id
        self.contract = contract
        self.tokenId = tokenId
        self.tokenType = tokenType
        self.name = name
        self.nftDescription = nftDescription
        self.image = image
        self.raw = raw
        self.collection = collection
        self.tokenUri = tokenUri
        self.timeLastUpdated = timeLastUpdated
        self.acquiredAt = acquiredAt
        self.networkRawValue = network.rawValue
        self.accountAddressRawValue = Self.normalizedScopeComponent(accountAddress) ?? ""
        self.contentType = contentType
        self.collectionName = collectionName
        self.artistName = artistName
        self.animationUrl = animationUrl
        self.secureAnimationUrl = secureAnimationUrl
        self.audioUrl = audioUrl
        self.tags = tags ?? []
        applyRefreshScope(accountAddress: accountAddress, chain: network)
    }

    /// Decodes an NFT from provider payloads and rebuilds its scoped identifier.
    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        let tokenType = try container.decodeIfPresent(String.self, forKey: .tokenType)
        self.tokenType = tokenType
        let name = try container.decodeIfPresent(String.self, forKey: .name)
        self.name = name
        nftDescription = try container.decodeIfPresent(String.self, forKey: .nftDescription)
        image = try container.decodeIfPresent(Image.self, forKey: .image)
        raw = try container.decodeIfPresent(Raw.self, forKey: .raw)
        collection = try container.decodeIfPresent(Collection.self, forKey: .collection)
        let tokenUri = try container.decodeIfPresent(String.self, forKey: .tokenUri)
        self.tokenUri = tokenUri
        timeLastUpdated = try container.decodeIfPresent(String.self, forKey: .timeLastUpdated)
        acquiredAt = try container.decodeIfPresent(AcquiredAt.self, forKey: .acquiredAt)
        networkRawValue = Chain.ethMainnet.rawValue
        accountAddressRawValue = ""

        let tokenId = try container.decode(String.self, forKey: .tokenId)
        self.tokenId = tokenId
        let fallbackContractAddress = Self.fallbackContractAddress(
            tokenId: tokenId,
            tokenType: tokenType,
            name: name,
            tokenUri: tokenUri
        )
        let contract = try container.decodeIfPresent(Contract.self, forKey: .contract)
            ?? Contract(address: fallbackContractAddress)
        self.contract = contract
        id = Self.makeScopedNFTID(
            accountAddress: nil,
            chain: .ethMainnet,
            contractAddress: contract.address,
            tokenId: tokenId,
            tokenType: tokenType,
            name: name,
            tokenUri: tokenUri
        )
        applyRefreshScope(accountAddress: nil, chain: .ethMainnet)
    }
    
    /// Encodes the provider-facing NFT payload.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(contract, forKey: .contract)
        try container.encode(tokenId, forKey: .tokenId)
        try container.encodeIfPresent(tokenType, forKey: .tokenType)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(nftDescription, forKey: .nftDescription)
        try container.encodeIfPresent(image, forKey: .image)
        try container.encodeIfPresent(raw, forKey: .raw)
        try container.encodeIfPresent(collection, forKey: .collection)
        try container.encodeIfPresent(tokenUri, forKey: .tokenUri)
        try container.encodeIfPresent(timeLastUpdated, forKey: .timeLastUpdated)
        try container.encodeIfPresent(acquiredAt, forKey: .acquiredAt)
    }

    private static func makeScopedNFTID(
        accountAddress: String?,
        chain: Chain,
        contractAddress: String?,
        tokenId: String,
        tokenType: String?,
        name: String?,
        tokenUri: String?
    ) -> String {
        let resolvedAccountAddress = normalizedScopeComponent(accountAddress) ?? "unscoped"
        let fallbackContractAddress = fallbackContractAddress(
            tokenId: tokenId,
            tokenType: tokenType,
            name: name,
            tokenUri: tokenUri
        )
        let resolvedContractAddress = Self.normalizedScopeComponent(contractAddress) ?? fallbackContractAddress
        return "\(resolvedAccountAddress):\(chain.rawValue):\(resolvedContractAddress):\(tokenId)"
    }

    private static func fallbackContractAddress(
        tokenId: String,
        tokenType: String?,
        name: String?,
        tokenUri: String?
    ) -> String {
        "__missing_contract__\(tokenType ?? ""):\(name ?? ""):\(tokenUri ?? ""):\(tokenId)"
    }

    static func normalizedScopeComponent(_ value: String?) -> String? {
        guard let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmedValue.isEmpty else {
            return nil
        }

        return trimmedValue.lowercased()
    }
    
    
    @Model
    class Contract: Codable {
        @Attribute(.unique) var id: String
        var address: String?
        var chainRawValue: String

        init(address: String?, chain: Chain = .ethMainnet) {
            self.id = Self.makeScopedID(chain: chain, address: address)
            self.address = address
            self.chainRawValue = chain.rawValue
        }
        
        enum CodingKeys: String, CodingKey {
            case address
        }
        
        required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let decodedAddress = try container.decodeIfPresent(String.self, forKey: .address)
            address = decodedAddress
            chainRawValue = Chain.ethMainnet.rawValue
            id = Self.makeScopedID(chain: .ethMainnet, address: decodedAddress)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(address, forKey: .address)
        }

        func updateScope(chain: Chain) {
            chainRawValue = chain.rawValue
            id = Self.makeScopedID(chain: chain, address: address)
        }

        private static func makeScopedID(chain: Chain, address: String?) -> String {
            let resolvedAddress = NFT.normalizedScopeComponent(address) ?? "unknown"
            return "\(chain.rawValue):\(resolvedAddress)"
        }
    }
    
    @Model
    class Image: Codable {
        var originalUrl: String?
        var thumbnailUrl: String?
        var secureUrl: String?

        init(originalUrl: String? = nil, thumbnailUrl: String? = nil) {
            self.originalUrl = originalUrl
            self.thumbnailUrl = thumbnailUrl
        }
        
        enum CodingKeys: String, CodingKey {
            case originalUrl
            case thumbnailUrl
        }
        
        required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            originalUrl = try container.decodeIfPresent(String.self, forKey: .originalUrl)
            thumbnailUrl = try container.decodeIfPresent(String.self, forKey: .thumbnailUrl)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(originalUrl, forKey: .originalUrl)
            try container.encodeIfPresent(thumbnailUrl, forKey: .thumbnailUrl)
        }
    }
    
    @Model
    class Raw: Codable {
        var tokenUri: String?
        var metadata: [String: JSONValue]?
        var error: String?

        init(tokenUri: String? = nil, metadata: [String: JSONValue]? = nil) {
            self.tokenUri = tokenUri
            self.metadata = metadata
        }
        
        enum CodingKeys: String, CodingKey {
            case tokenUri
            case metadata
        }
        
        required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            tokenUri = try container.decodeIfPresent(String.self, forKey: .tokenUri)
            do {
                metadata = try container.decodeIfPresent([String: JSONValue].self, forKey: .metadata)
            } catch {
                let website = try container.decodeIfPresent(String.self, forKey: .metadata)
                metadata = ["data": .string(website ?? "")]
            }
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(tokenUri, forKey: .tokenUri)
            try container.encodeIfPresent(metadata, forKey: .metadata)
        }
    }
    
    @Model
    class NFTMetadata: Codable {
        var image: String?
        var name: String?
        var metadataDescription: String?
        var attributes: [Attribute]?
        
        enum CodingKeys: String, CodingKey {
            case image
            case name
            case metadataDescription = "description"
            case attributes
        }
        
        init(image: String? = nil, name: String? = nil, metadataDescription: String? = nil, attributes: [Attribute]? = nil) {
            self.image = image
            self.name = name
            self.metadataDescription = metadataDescription
            self.attributes = attributes
        }
        
        required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            image = try container.decodeIfPresent(String.self, forKey: .image)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            metadataDescription = try container.decodeIfPresent(String.self, forKey: .metadataDescription)
            attributes = try container.decodeIfPresent([Attribute].self, forKey: .attributes)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(image, forKey: .image)
            try container.encodeIfPresent(name, forKey: .name)
            try container.encodeIfPresent(metadataDescription, forKey: .metadataDescription)
            try container.encodeIfPresent(attributes, forKey: .attributes)
        }
    }
    
    @Model
    class Attribute: Codable, Identifiable {
        var value: String
        var traitType: String?

        var nft: NFT?

        enum CodingKeys: String, CodingKey {
            case value
            case traitType = "trait_type"
        }
        
        init(value: String, traitType: String? = nil) {
            self.value = value
            self.traitType = traitType
        }
        
        required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            value = try container.decode(String.self, forKey: .value)
            traitType = try container.decodeIfPresent(String.self, forKey: .traitType)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(value, forKey: .value)
            try container.encodeIfPresent(traitType, forKey: .traitType)
        }
    }
    
    @Model
    class Collection: Codable {
        @Attribute(.unique) var id: String
        var name: String?
        var chainRawValue: String
        var contractAddress: String?
        
        enum CodingKeys: String, CodingKey {
            case name
        }
        
        init(
            name: String?,
            chain: Chain = .ethMainnet,
            contractAddress: String? = nil
        ) {
            self.id = Self.makeScopedID(
                chain: chain,
                name: name,
                contractAddress: contractAddress
            )
            self.name = name
            self.chainRawValue = chain.rawValue
            self.contractAddress = contractAddress
        }
        
        required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let decodedName = try container.decodeIfPresent(String.self, forKey: .name)
            name = decodedName
            chainRawValue = Chain.ethMainnet.rawValue
            contractAddress = nil
            id = Self.makeScopedID(chain: .ethMainnet, name: decodedName, contractAddress: nil)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(name, forKey: .name)
        }

        func updateScope(chain: Chain, contractAddress: String?) {
            chainRawValue = chain.rawValue
            self.contractAddress = contractAddress
            id = Self.makeScopedID(
                chain: chain,
                name: name,
                contractAddress: contractAddress
            )
        }

        private static func makeScopedID(
            chain: Chain,
            name: String?,
            contractAddress: String?
        ) -> String {
            if let resolvedContractAddress = NFT.normalizedScopeComponent(contractAddress) {
                return "\(chain.rawValue):\(resolvedContractAddress)"
            }

            let resolvedName = NFT.normalizedScopeComponent(name) ?? "unknown"
            return "\(chain.rawValue):name:\(resolvedName)"
        }
    }
    
    @Model
    class AcquiredAt: Codable {
        var blockTimestamp: String?
        
        enum CodingKeys: String, CodingKey {
            case blockTimestamp
        }
        
        init(blockTimestamp: String? = nil) {
            self.blockTimestamp = blockTimestamp
        }
        
        required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            blockTimestamp = try container.decodeIfPresent(String.self, forKey: .blockTimestamp)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(blockTimestamp, forKey: .blockTimestamp)
        }
    }
}
