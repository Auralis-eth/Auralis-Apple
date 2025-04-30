//
//  NFT.swift
//  Auralis
//
//  Created by Daniel Bell on 1/6/25.
//

import Foundation
import SwiftData
import web3


// MARK: - Helper Functions & Computed Properties
enum Chain: String, Codable, Equatable, CaseIterable, Identifiable {
    // Ethereum
    case ethMainnet = "eth-mainnet"
    case ethSepoliaTestnet = "eth-sepolia"

    // Base
    case baseMainnet = "base-mainnet"
    case baseSepoliaTestnet = "base-sepolia"

    // Arbitrum
    case arbMainnet = "arb-mainnet"
    case arbSepoliaTestnet = "arb-sepolia"
    case arbNovaMainnet = "arbnova-mainnet"

    // Optimism
    case optMainnet = "opt-mainnet"
    case optSepoliaTestnet = "opt-sepolia"

    // Polygon
    case polygonMainnet = "polygon-mainnet"
    case polygonAmoyTestnet = "polygon-amoy"

    // WorldChain
    case worldchainMainnet = "worldchain-mainnet"
    case worldchainSepoliaTestnet = "worldchain-sepolia"

    // Shape
    case shapeMainnet = "shape-mainnet"
    case shapeSepoliaTestnet = "shape-sepolia"

    // Ink
    case inkMainnet = "ink-mainnet"
    case inkSepoliaTestnet = "ink-sepolia"

    // UniChain
    case unichainMainnet = "unichain-mainnet"
    case unichainSepoliaTestnet = "unichain-sepolia"

    // Soneium
    case soneiumMainnet = "soneium-mainnet"
    case soneiumMinatoTestnet = "soneium-minato"

    // Solana
    case solanaMainnet = "solana-mainnet"
    case solanaDevnetTestnet = "solana-devnet"

    // BeraChain
    case berachainMainnet = "berachain-mainnet"

    // Zora
    case zoraMainnet = "zora-mainnet"
    case zoraSepoliaTestnet = "zora-sepolia"

    // Polynomial
    case polynomialMainnet = "polynomial-mainnet"
    case polynomialSepoliaTestnet = "polynomial-sepolia"

    var id: Int {
        chainId
    }

    var networkName: String {
        switch self {
        case .ethMainnet:
            return "Ethereum Mainnet"
        case .ethSepoliaTestnet:
            return "Ethereum Sepolia Testnet"
        case .baseMainnet:
            return "Base Mainnet"
        case .baseSepoliaTestnet:
            return "Base Sepolia Testnet"
        case .arbMainnet:
            return "Arbitrum One Mainnet"
        case .arbSepoliaTestnet:
            return "Arbitrum Sepolia Testnet"
        case .arbNovaMainnet:
            return "Arbitrum Nova Mainnet"
        case .optMainnet:
            return "Optimism Mainnet"
        case .optSepoliaTestnet:
            return "Optimism Sepolia Testnet"
        case .polygonMainnet:
            return "Polygon Mainnet"
        case .polygonAmoyTestnet:
            return "Polygon Amoy Testnet"
        case .worldchainMainnet:
            return "WorldChain Mainnet"
        case .worldchainSepoliaTestnet:
            return "WorldChain Sepolia Testnet"
        case .shapeMainnet:
            return "Shape Mainnet"
        case .shapeSepoliaTestnet:
            return "Shape Sepolia Testnet"
        case .inkMainnet:
            return "Ink Mainnet"
        case .inkSepoliaTestnet:
            return "Ink Sepolia Testnet"
        case .unichainMainnet:
            return "UniChain Mainnet"
        case .unichainSepoliaTestnet:
            return "UniChain Sepolia Testnet"
        case .soneiumMainnet:
            return "Soneium Mainnet"
        case .soneiumMinatoTestnet:
            return "Soneium Minato Testnet"
        case .solanaMainnet:
            return "Solana Mainnet"
        case .solanaDevnetTestnet:
            return "Solana Devnet"
        case .berachainMainnet:
            return "BeraChain Mainnet"
        case .zoraMainnet:
            return "Zora Mainnet"
        case .zoraSepoliaTestnet:
            return "Zora Sepolia Testnet"
        case .polynomialMainnet:
            return "Polynomial Mainnet"
        case .polynomialSepoliaTestnet:
            return "Polynomial Sepolia Testnet"
        }
    }

    var chainId: Int {
        switch self {
        case .ethMainnet:
            return 1
        case .ethSepoliaTestnet:
            return 11155111
        case .baseMainnet:
            return 8453
        case .baseSepoliaTestnet:
            return 84532
        case .arbMainnet:
            return 42161
        case .arbSepoliaTestnet:
            return 421614
        case .arbNovaMainnet:
            return 42170
        case .optMainnet:
            return 10
        case .optSepoliaTestnet:
            return 11155420
        case .polygonMainnet:
            return 137
        case .polygonAmoyTestnet:
            return 80002
        case .worldchainMainnet:
            return 480
        case .worldchainSepoliaTestnet:
            return 4801
        case .shapeMainnet:
            return 360
        case .shapeSepoliaTestnet:
            return 11011
        case .inkMainnet:
            return 57073
        case .inkSepoliaTestnet:
            return 763373
        case .unichainMainnet:
            return 130
        case .unichainSepoliaTestnet:
            return 1301
        case .soneiumMainnet:
            return 1868
        case .soneiumMinatoTestnet:
            return 1946
        case .solanaMainnet:
            return .min // Placeholder for Solana (different chain type)
        case .solanaDevnetTestnet:
            return .min // Placeholder for Solana (different chain type)
        case .berachainMainnet:
            return 80094
        case .zoraMainnet:
            return 7777777
        case .zoraSepoliaTestnet:
            return 999999999
        case .polynomialMainnet:
            return 8008
        case .polynomialSepoliaTestnet:
            return 8009
        }
    }

    var web3EthereumNetwork: EthereumNetwork {
        EthereumNetwork.fromString("\(chainId)")
    }

    var formattedChainId: String {
        if case .solanaMainnet = self, case .solanaDevnetTestnet = self {
            return "Solana Network"
        }
        return "Chain ID: \(chainId)"
    }

    var isMainnet: Bool {
        switch self {
        case .ethMainnet, .baseMainnet, .arbMainnet, .arbNovaMainnet, .optMainnet,
             .polygonMainnet, .worldchainMainnet, .shapeMainnet, .inkMainnet,
             .unichainMainnet, .soneiumMainnet, .solanaMainnet, .berachainMainnet,
             .zoraMainnet, .polynomialMainnet:
            return true
        default:
            return false
        }
    }
}

@Model
class EOAccount: Codable, Identifiable {
    #Index<EOAccount>([\.address])
    @Attribute(.unique) var address: String
    var id = UUID()
    var name: String?
    var access: EthereumAddressAccess

    @Relationship(deleteRule: .cascade) var nfts: [NFT] = []

    var privateKey: Data? {
        try? EthereumKeyChainStorage().loadPrivateKey(for: .init(address))
    }

    init(address: String, access: EthereumAddressAccess) {
        self.address = address
        self.access = access
        self.name = "Account \(String(address.prefix(4)))"
    }

    enum CodingKeys: String, CodingKey {
        case address
        case access
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        address = try container.decode(String.self, forKey: .address)
        access = try container.decode(EthereumAddressAccess.self, forKey: .access)
        name = name ?? "Account \(String(address.prefix(4)))"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(address, forKey: .address)
        try container.encode(access, forKey: .access)
    }
}






enum EthereumAddressAccess: Codable {
    case wallet
    case readonly

    /// Whether this address can sign transactions
    var canSign: Bool {
        switch self {
            case .wallet:
                return true
            case .readonly:
                return false
        }
    }
}







//// Presumed NFTTrait model structure
//struct NFTTrait {
//    var type: String
//    var value: String
//}







@Model
class NFT: Codable {
    #Unique<NFT>([\.contract, \.tokenId, \.networkRawValue])
    #Index<NFT>([\.id], [\.acquiredAt], [\.collection], [\.tokenId])

    @Attribute(.unique) var id: String
    
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

    // Complex data structures
//    var imageDetails: [String: Any]?
//    var animationDetails: [String: Any]?
//    var artistRoyalty: [String: Any]?
//    var platform: [String: Any]?
//    var copyright: [String: Any]?
//    var license: [String: Any]?
//    var generatorUrl: [String: Any]?
//    var termsOfService: [String: Any]?
//    var feeRecipient: [String: Any]?
//    var royalties: [String: Any]?
//    var royaltyInfo: [String: Any]?
//    var properties: [String: Any]?
//    var exhibitionInfo: [String: Any]?
//    var features: [String: Any]?
    // MARK: Image properties
    // MARK: Artist properties
    // MARK: Project properties

    @Transient var network: Chain? {
        get {
            Chain(rawValue: networkRawValue)
        }
        set {
            // Store the raw value when the enum is set
            networkRawValue = newValue?.rawValue ?? ""
        }
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
    
    init(id: String, contract: Contract, tokenId: String, tokenType: String? = nil, name: String? = nil, nftDescription: String? = nil, image: Image? = nil, raw: Raw? = nil, collection: Collection? = nil, tokenUri: String? = nil, timeLastUpdated: String? = nil, acquiredAt: AcquiredAt? = nil, network: Chain = .ethMainnet, contentType: String? = nil, collectionName: String? = nil, artistName: String? = nil, animationUrl: String? = nil, secureAnimationUrl: String? = nil, audioUrl: String? = nil) {
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
        self.contentType = contentType
        self.collectionName = collectionName
        self.artistName = artistName
        self.animationUrl = animationUrl
        self.secureAnimationUrl = secureAnimationUrl
        self.audioUrl = audioUrl
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        tokenType = try container.decodeIfPresent(String.self, forKey: .tokenType)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        nftDescription = try container.decodeIfPresent(String.self, forKey: .nftDescription)
        image = try container.decodeIfPresent(Image.self, forKey: .image)
        raw = try container.decodeIfPresent(Raw.self, forKey: .raw)
        collection = try container.decodeIfPresent(Collection.self, forKey: .collection)
        tokenUri = try container.decodeIfPresent(String.self, forKey: .tokenUri)
        timeLastUpdated = try container.decodeIfPresent(String.self, forKey: .timeLastUpdated)
        acquiredAt = try container.decodeIfPresent(AcquiredAt.self, forKey: .acquiredAt)
        networkRawValue = Chain.ethMainnet.rawValue

        let tokenId = try container.decode(String.self, forKey: .tokenId)
        self.tokenId = tokenId
        let contract = try container.decode(Contract.self, forKey: .contract)
        self.contract = contract
        id = (contract.address ?? UUID().uuidString) + ":" + tokenId
    }
    
    func encode(to encoder: Encoder) throws {
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
    
    
    @Model
    class Contract: Codable {
        @Attribute(.unique) var address: String?

        init(address: String?) {
            self.address = address
        }
        
        enum CodingKeys: String, CodingKey {
            case address
        }
        
        required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            address = try container.decode(String.self, forKey: .address)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(address, forKey: .address)
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
        var metadata: NFTMetadata?
        
        init(tokenUri: String? = nil, metadata: NFTMetadata? = nil) {
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
            metadata = try container.decodeIfPresent(NFTMetadata.self, forKey: .metadata)
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
    class Attribute: Codable {
        var value: String
        var traitType: String?
        
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
        var name: String?
        
        enum CodingKeys: String, CodingKey {
            case name
        }
        
        init(name: String? = nil) {
            self.name = name
        }
        
        required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decodeIfPresent(String.self, forKey: .name)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(name, forKey: .name)
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

