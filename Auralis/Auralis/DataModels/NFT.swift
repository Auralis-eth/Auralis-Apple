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

    var hasMetaData: Bool {
        return contentType != nil ||
               collectionName != nil ||
               artistName != nil ||
               animationUrl != nil ||
               secureAnimationUrl != nil ||
               audioUrl != nil ||
               externalUrl != nil ||
               modelUrl != nil ||
               backgroundColor != nil ||
               collectionID != nil ||
               projectID != nil ||
               series != nil ||
               seriesID != nil ||
               primaryAssetUrl != nil ||
               securePrimaryAssetUrl != nil ||
               previewAssetUrl != nil ||
               securePreviewAssetUrl != nil ||
               artistWebsite != nil ||
               uniqueID != nil ||
               timestamp != nil ||
               tokenHash != nil ||
               medium != nil ||
               metadataVersion != nil ||
               imageDataUrl != nil ||
               secureImageDataUrl != nil ||
               imageHrUrl != nil ||
               secureImageHrUrl != nil ||
               imageHash != nil ||
               symbols != nil ||
               seed != nil ||
               original != nil ||
               agreement != nil ||
               website != nil ||
               payoutAddress != nil ||
               scriptType != nil ||
               engineType != nil ||
               accessArtworkFiles != nil ||
               sellerFeeBasisPoints != nil ||
               minted != nil ||
               isStatic != nil ||
               aspectRatio != nil
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
            do {
                metadata = try container.decodeIfPresent(NFTMetadata.self, forKey: .metadata)
            } catch {
                let website = try container.decodeIfPresent(String.self, forKey: .metadata)
                metadata = NFTMetadata(image: nil, name: nil, metadataDescription: website, attributes: nil)
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

//======================================================================================


import Foundation

extension NFT {

    // MARK: - Sample Data

    static var sampleData: [NFT] {
        return [
            cryptoPunk1,
            boredApe2,
            artBlocks3,
            worldOfWomen4,
            moonbirds5,
            azuki6,
            doodles7,
            coolCats8,
            veeFriends9,
            chromieSquiggle10
        ]
    }

    // MARK: - Individual Sample NFTs

    static var cryptoPunk1: NFT {
        let contract = Contract(address: "0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB")
        let image = Image(
            originalUrl: "https://larvalabs.com/cryptopunks/cryptopunk7804.png",
            thumbnailUrl: "https://larvalabs.com/cryptopunks/cryptopunk7804_thumb.png"
        )
        let collection = Collection(name: "CryptoPunks")
        let acquiredAt = AcquiredAt(blockTimestamp: "1697832000")

        let attributes = [
            Attribute(value: "Male", traitType: "Type"),
            Attribute(value: "Mohawk", traitType: "Hair"),
            Attribute(value: "Earring", traitType: "Accessory")
        ]

        let metadata = NFTMetadata(
            image: "https://larvalabs.com/cryptopunks/cryptopunk7804.png",
            name: "CryptoPunk #7804",
            metadataDescription: "A unique digital collectible from the original CryptoPunks collection",
            attributes: attributes
        )

        let raw = Raw(
            tokenUri: "https://api.cryptopunks.app/api/punk/7804",
            metadata: metadata
        )

        let nft = NFT(
            id: "0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB:7804",
            contract: contract,
            tokenId: "7804",
            tokenType: "ERC721",
            name: "CryptoPunk #7804",
            nftDescription: "A unique digital collectible from the original CryptoPunks collection",
            image: image,
            raw: raw,
            collection: collection,
            tokenUri: "https://api.cryptopunks.app/api/punk/7804",
            timeLastUpdated: "2024-01-15T10:30:00Z",
            acquiredAt: acquiredAt,
            network: .ethMainnet
        )

        nft.artistName = "Larva Labs"
        nft.sellerFeeBasisPoints = 0
        nft.contentType = "image/png"
        nft.externalUrl = "https://larvalabs.com/cryptopunks/details/7804"

        return nft
    }

    static var boredApe2: NFT {
        let contract = Contract(address: "0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D")
        let image = Image(
            originalUrl: "https://ipfs.io/ipfs/QmSsYRx3LpDAb1GZQm7zZ1AuHZjfbPkD6J7s9r41xu1mf8",
            thumbnailUrl: "https://ipfs.io/ipfs/QmSsYRx3LpDAb1GZQm7zZ1AuHZjfbPkD6J7s9r41xu1mf8_thumb"
        )
        let collection = Collection(name: "Bored Ape Yacht Club")
        let acquiredAt = AcquiredAt(blockTimestamp: "1698436800")

        let attributes = [
            Attribute(value: "Angry", traitType: "Mouth"),
            Attribute(value: "Blue", traitType: "Background"),
            Attribute(value: "Striped Tee", traitType: "Clothes"),
            Attribute(value: "Cyborg", traitType: "Eyes")
        ]

        let metadata = NFTMetadata(
            image: "https://ipfs.io/ipfs/QmSsYRx3LpDAb1GZQm7zZ1AuHZjfbPkD6J7s9r41xu1mf8",
            name: "Bored Ape Yacht Club #3749",
            metadataDescription: "The Bored Ape Yacht Club is a collection of 10,000 unique Bored Ape NFTs",
            attributes: attributes
        )

        let raw = Raw(
            tokenUri: "https://boredapeyachtclub.com/api/mutants/3749",
            metadata: metadata
        )

        let nft = NFT(
            id: "0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D:3749",
            contract: contract,
            tokenId: "3749",
            tokenType: "ERC721",
            name: "Bored Ape Yacht Club #3749",
            nftDescription: "The Bored Ape Yacht Club is a collection of 10,000 unique Bored Ape NFTs",
            image: image,
            raw: raw,
            collection: collection,
            tokenUri: "https://boredapeyachtclub.com/api/mutants/3749",
            timeLastUpdated: "2024-01-20T14:22:00Z",
            acquiredAt: acquiredAt,
            network: .ethMainnet
        )

        nft.artistName = "Yuga Labs"
        nft.sellerFeeBasisPoints = 250
        nft.contentType = "image/png"
        nft.externalUrl = "https://boredapeyachtclub.com/#/gallery/3749"

        return nft
    }

    static var artBlocks3: NFT {
        let contract = Contract(address: "0xa7d8d9ef8D8Ce8992Df33D8b8CF4Aebabd5bD270")
        let image = Image(
            originalUrl: "https://media.artblocks.io/renditions/3749/live_view",
            thumbnailUrl: "https://media.artblocks.io/renditions/3749/thumb"
        )
        let collection = Collection(name: "Art Blocks Curated")
        let acquiredAt = AcquiredAt(blockTimestamp: "1699041600")

        let attributes = [
            Attribute(value: "Fidenza", traitType: "Project"),
            Attribute(value: "Tyler Hobbs", traitType: "Artist"),
            Attribute(value: "High", traitType: "Density"),
            Attribute(value: "Organic", traitType: "Style")
        ]

        let metadata = NFTMetadata(
            image: "https://media.artblocks.io/renditions/3749/live_view",
            name: "Fidenza #313",
            metadataDescription: "Fidenza is the result of years of experimentation with procedural aesthetics",
            attributes: attributes
        )

        let raw = Raw(
            tokenUri: "https://api.artblocks.io/api/v1/project/78/token/313",
            metadata: metadata
        )

        let nft = NFT(
            id: "0xa7d8d9ef8D8Ce8992Df33D8b8CF4Aebabd5bD270:313",
            contract: contract,
            tokenId: "313",
            tokenType: "ERC721",
            name: "Fidenza #313",
            nftDescription: "Fidenza is the result of years of experimentation with procedural aesthetics",
            image: image,
            raw: raw,
            collection: collection,
            tokenUri: "https://api.artblocks.io/api/v1/project/78/token/313",
            timeLastUpdated: "2024-01-25T09:15:00Z",
            acquiredAt: acquiredAt,
            network: .ethMainnet
        )

        nft.artistName = "Tyler Hobbs"
        nft.sellerFeeBasisPoints = 1000
        nft.contentType = "image/svg+xml"
        nft.scriptType = "p5js"
        nft.seed = "0x313deadbeef"
        nft.aspectRatio = 1.0
        nft.isStatic = 0

        return nft
    }

    static var worldOfWomen4: NFT {
        let contract = Contract(address: "0xe785E82358879F061BC3dcAC6f0444462D4b5330")
        let image = Image(
            originalUrl: "https://ipfs.io/ipfs/QmYDvPAXtiJg7s8JdRBSLWdgSphQdac8j1YuQNNxcGE1hg/1337.png",
            thumbnailUrl: "https://ipfs.io/ipfs/QmYDvPAXtiJg7s8JdRBSLWdgSphQdac8j1YuQNNxcGE1hg/1337_thumb.png"
        )
        let collection = Collection(name: "World of Women")
        let acquiredAt = AcquiredAt(blockTimestamp: "1699646400")

        let attributes = [
            Attribute(value: "Light", traitType: "Skin"),
            Attribute(value: "Purple", traitType: "Hair"),
            Attribute(value: "Elegant", traitType: "Dress"),
            Attribute(value: "Diamond", traitType: "Earrings")
        ]

        let metadata = NFTMetadata(
            image: "https://ipfs.io/ipfs/QmYDvPAXtiJg7s8JdRBSLWdgSphQdac8j1YuQNNxcGE1hg/1337.png",
            name: "World of Women #1337",
            metadataDescription: "World of Women is a collection of 10,000 NFTs that gives women representation in the space",
            attributes: attributes
        )

        let raw = Raw(
            tokenUri: "https://api.worldofwomen.art/api/token/1337",
            metadata: metadata
        )

        let nft = NFT(
            id: "0xe785E82358879F061BC3dcAC6f0444462D4b5330:1337",
            contract: contract,
            tokenId: "1337",
            tokenType: "ERC721",
            name: "World of Women #1337",
            nftDescription: "World of Women is a collection of 10,000 NFTs that gives women representation in the space",
            image: image,
            raw: raw,
            collection: collection,
            tokenUri: "https://api.worldofwomen.art/api/token/1337",
            timeLastUpdated: "2024-02-01T16:45:00Z",
            acquiredAt: acquiredAt,
            network: .ethMainnet
        )

        nft.artistName = "Yam Karkai"
        nft.sellerFeeBasisPoints = 500
        nft.contentType = "image/png"
        nft.externalUrl = "https://worldofwomen.art/wow/1337"

        return nft
    }

    static var moonbirds5: NFT {
        let contract = Contract(address: "0x23581767a106ae21c074b2276D25e5C3e136a68b")
        let image = Image(
            originalUrl: "https://live---metadata-5covpqijaa-uc.a.run.app/images/2048.png",
            thumbnailUrl: "https://live---metadata-5covpqijaa-uc.a.run.app/images/2048_thumb.png"
        )
        let collection = Collection(name: "Moonbirds")
        let acquiredAt = AcquiredAt(blockTimestamp: "1700251200")

        let attributes = [
            Attribute(value: "Crescent", traitType: "Beak"),
            Attribute(value: "Purple", traitType: "Background"),
            Attribute(value: "Striped", traitType: "Body"),
            Attribute(value: "Rainbow", traitType: "Feathers")
        ]

        let metadata = NFTMetadata(
            image: "https://live---metadata-5covpqijaa-uc.a.run.app/images/2048.png",
            name: "Moonbirds #2048",
            metadataDescription: "A collection of 10,000 utility-enabled PFPs that feature a richly diverse and unique pool of rarity-powered traits",
            attributes: attributes
        )

        let raw = Raw(
            tokenUri: "https://live---metadata-5covpqijaa-uc.a.run.app/metadata/2048",
            metadata: metadata
        )

        let nft = NFT(
            id: "0x23581767a106ae21c074b2276D25e5C3e136a68b:2048",
            contract: contract,
            tokenId: "2048",
            tokenType: "ERC721",
            name: "Moonbirds #2048",
            nftDescription: "A collection of 10,000 utility-enabled PFPs that feature a richly diverse and unique pool of rarity-powered traits",
            image: image,
            raw: raw,
            collection: collection,
            tokenUri: "https://live---metadata-5covpqijaa-uc.a.run.app/metadata/2048",
            timeLastUpdated: "2024-02-05T11:30:00Z",
            acquiredAt: acquiredAt,
            network: .ethMainnet
        )

        nft.artistName = "PROOF Collective"
        nft.sellerFeeBasisPoints = 500
        nft.contentType = "image/png"
        nft.externalUrl = "https://moonbirds.xyz/moonbird/2048"

        return nft
    }

    static var azuki6: NFT {
        let contract = Contract(address: "0xED5AF388653567Af2F388E6224dC7C4b3241C544")
        let image = Image(
            originalUrl: "https://ikzttp.mypinata.cloud/ipfs/QmQFkLSQysj94s5GvTHPyzTxrawwtjgiiYS2TBLgrvw8CW/789.png",
            thumbnailUrl: "https://ikzttp.mypinata.cloud/ipfs/QmQFkLSQysj94s5GvTHPyzTxrawwtjgiiYS2TBLgrvw8CW/789_thumb.png"
        )
        let collection = Collection(name: "Azuki")
        let acquiredAt = AcquiredAt(blockTimestamp: "1700856000")

        let attributes = [
            Attribute(value: "Kimono", traitType: "Clothing"),
            Attribute(value: "Closed", traitType: "Eyes"),
            Attribute(value: "Pink", traitType: "Hair"),
            Attribute(value: "Headband", traitType: "Headgear")
        ]

        let metadata = NFTMetadata(
            image: "https://ikzttp.mypinata.cloud/ipfs/QmQFkLSQysj94s5GvTHPyzTxrawwtjgiiYS2TBLgrvw8CW/789.png",
            name: "Azuki #789",
            metadataDescription: "A collection of 10,000 avatars that give you membership access to The Garden",
            attributes: attributes
        )

        let raw = Raw(
            tokenUri: "https://ikzttp.mypinata.cloud/ipfs/QmQFkLSQysj94s5GvTHPyzTxrawwtjgiiYS2TBLgrvw8CW/789",
            metadata: metadata
        )

        let nft = NFT(
            id: "0xED5AF388653567Af2F388E6224dC7C4b3241C544:789",
            contract: contract,
            tokenId: "789",
            tokenType: "ERC721",
            name: "Azuki #789",
            nftDescription: "A collection of 10,000 avatars that give you membership access to The Garden",
            image: image,
            raw: raw,
            collection: collection,
            tokenUri: "https://ikzttp.mypinata.cloud/ipfs/QmQFkLSQysj94s5GvTHPyzTxrawwtjgiiYS2TBLgrvw8CW/789",
            timeLastUpdated: "2024-02-10T13:20:00Z",
            acquiredAt: acquiredAt,
            network: .ethMainnet
        )

        nft.artistName = "Chiru Labs"
        nft.sellerFeeBasisPoints = 500
        nft.contentType = "image/png"
        nft.externalUrl = "https://azuki.com/gallery/789"

        return nft
    }

    static var doodles7: NFT {
        let contract = Contract(address: "0x8a90CAb2b38dba80c64b7734e58Ee1dB38B8992e")
        let image = Image(
            originalUrl: "https://ipfs.io/ipfs/QmPMc4tcBsMqLRuCQtPmPe84bpSjrC3Ky7t3JWuHXYB4aS/1337.png",
            thumbnailUrl: "https://ipfs.io/ipfs/QmPMc4tcBsMqLRuCQtPmPe84bpSjrC3Ky7t3JWuHXYB4aS/1337_thumb.png"
        )
        let collection = Collection(name: "Doodles")
        let acquiredAt = AcquiredAt(blockTimestamp: "1701460800")

        let attributes = [
            Attribute(value: "Gradient", traitType: "Background"),
            Attribute(value: "Happy", traitType: "Face"),
            Attribute(value: "Bucket Hat", traitType: "Head"),
            Attribute(value: "Hoodie", traitType: "Body")
        ]

        let metadata = NFTMetadata(
            image: "https://ipfs.io/ipfs/QmPMc4tcBsMqLRuCQtPmPe84bpSjrC3Ky7t3JWuHXYB4aS/1337.png",
            name: "Doodles #1337",
            metadataDescription: "A community-driven collectibles project featuring art by Burnt Toast",
            attributes: attributes
        )

        let raw = Raw(
            tokenUri: "https://ipfs.io/ipfs/QmPMc4tcBsMqLRuCQtPmPe84bpSjrC3Ky7t3JWuHXYB4aS/1337",
            metadata: metadata
        )

        let nft = NFT(
            id: "0x8a90CAb2b38dba80c64b7734e58Ee1dB38B8992e:1337",
            contract: contract,
            tokenId: "1337",
            tokenType: "ERC721",
            name: "Doodles #1337",
            nftDescription: "A community-driven collectibles project featuring art by Burnt Toast",
            image: image,
            raw: raw,
            collection: collection,
            tokenUri: "https://ipfs.io/ipfs/QmPMc4tcBsMqLRuCQtPmPe84bpSjrC3Ky7t3JWuHXYB4aS/1337",
            timeLastUpdated: "2024-02-15T08:45:00Z",
            acquiredAt: acquiredAt,
            network: .ethMainnet
        )

        nft.artistName = "Burnt Toast"
        nft.sellerFeeBasisPoints = 500
        nft.contentType = "image/png"
        nft.externalUrl = "https://doodles.app/doodle/1337"

        return nft
    }

    static var coolCats8: NFT {
        let contract = Contract(address: "0x1A92f7381B9F03921564a437210bB9396471050C")
        let image = Image(
            originalUrl: "https://ipfs.io/ipfs/QmVJhZGMjyGwYTEa9UKQJ6YJHWKqzKD3qPdGmMbBMkKLJG/5555.png",
            thumbnailUrl: "https://ipfs.io/ipfs/QmVJhZGMjyGwYTEa9UKQJ6YJHWKqzKD3qPdGmMbBMkKLJG/5555_thumb.png"
        )
        let collection = Collection(name: "Cool Cats NFT")
        let acquiredAt = AcquiredAt(blockTimestamp: "1702065600")

        let attributes = [
            Attribute(value: "Blue", traitType: "Body"),
            Attribute(value: "Sunglasses", traitType: "Face"),
            Attribute(value: "Backwards Cap", traitType: "Hat"),
            Attribute(value: "Shirt", traitType: "Shirt")
        ]

        let metadata = NFTMetadata(
            image: "https://ipfs.io/ipfs/QmVJhZGMjyGwYTEa9UKQJ6YJHWKqzKD3qPdGmMbBMkKLJG/5555.png",
            name: "Cool Cat #5555",
            metadataDescription: "Cool Cats is a collection of 9,999 randomly generated and stylistically curated NFTs",
            attributes: attributes
        )

        let raw = Raw(
            tokenUri: "https://api.coolcatsnft.com/cat/5555",
            metadata: metadata
        )

        let nft = NFT(
            id: "0x1A92f7381B9F03921564a437210bB9396471050C:5555",
            contract: contract,
            tokenId: "5555",
            tokenType: "ERC721",
            name: "Cool Cat #5555",
            nftDescription: "Cool Cats is a collection of 9,999 randomly generated and stylistically curated NFTs",
            image: image,
            raw: raw,
            collection: collection,
            tokenUri: "https://api.coolcatsnft.com/cat/5555",
            timeLastUpdated: "2024-02-20T12:15:00Z",
            acquiredAt: acquiredAt,
            network: .ethMainnet
        )

        nft.artistName = "Cool Cats Team"
        nft.sellerFeeBasisPoints = 750
        nft.contentType = "image/png"
        nft.externalUrl = "https://coolcatsnft.com/cool-cats/5555"

        return nft
    }

    static var veeFriends9: NFT {
        let contract = Contract(address: "0xa3AEe8BcE55BEeA1951EF834b99f3Ac60d1ABeeB")
        let image = Image(
            originalUrl: "https://ipfs.io/ipfs/QmYH6HpWN8gcHEUdGGqgWvdDkZXzQcvmkMNHJiLKwkdmTD/2024.png",
            thumbnailUrl: "https://ipfs.io/ipfs/QmYH6HpWN8gcHEUdGGqgWvdDkZXzQcvmkMNHJiLKwkdmTD/2024_thumb.png"
        )
        let collection = Collection(name: "VeeFriends")
        let acquiredAt = AcquiredAt(blockTimestamp: "1702670400")

        let attributes = [
            Attribute(value: "Accountable Ant", traitType: "Character"),
            Attribute(value: "Green", traitType: "Background"),
            Attribute(value: "Rare", traitType: "Rarity"),
            Attribute(value: "Series 1", traitType: "Series")
        ]

        let metadata = NFTMetadata(
            image: "https://ipfs.io/ipfs/QmYH6HpWN8gcHEUdGGqgWvdDkZXzQcvmkMNHJiLKwkdmTD/2024.png",
            name: "VeeFriends #2024",
            metadataDescription: "VeeFriends is Gary Vaynerchuk's first NFT project around meaningful intellectual property",
            attributes: attributes
        )

        let raw = Raw(
            tokenUri: "https://api.veefriends.com/v1/nft/2024",
            metadata: metadata
        )

        let nft = NFT(
            id: "0xa3AEe8BcE55BEeA1951EF834b99f3Ac60d1ABeeB:2024",
            contract: contract,
            tokenId: "2024",
            tokenType: "ERC721",
            name: "VeeFriends #2024",
            nftDescription: "VeeFriends is Gary Vaynerchuk's first NFT project around meaningful intellectual property",
            image: image,
            raw: raw,
            collection: collection,
            tokenUri: "https://api.veefriends.com/v1/nft/2024",
            timeLastUpdated: "2024-02-25T15:00:00Z",
            acquiredAt: acquiredAt,
            network: .ethMainnet
        )

        nft.artistName = "Gary Vaynerchuk"
        nft.sellerFeeBasisPoints = 1000
        nft.contentType = "image/png"
        nft.externalUrl = "https://veefriends.com/nft/2024"

        return nft
    }

    static var chromieSquiggle10: NFT {
        let contract = Contract(address: "0x059EDD72Cd353dF5106D2B9cC5ab83a52287aC3a")
        let image = Image(
            originalUrl: "https://api.artblocks.io/image/1000222",
            thumbnailUrl: "https://api.artblocks.io/image/1000222?width=350"
        )
        let collection = Collection(name: "Chromie Squiggle")
        let acquiredAt = AcquiredAt(blockTimestamp: "1703275200")

        let attributes = [
            Attribute(value: "Hyper Rainbow", traitType: "Color"),
            Attribute(value: "Fuzzy", traitType: "Style"),
            Attribute(value: "High", traitType: "Spectrum"),
            Attribute(value: "Slalom", traitType: "Segmentation")
        ]

        let metadata = NFTMetadata(
            image: "https://api.artblocks.io/image/1000222",
            name: "Chromie Squiggle #222",
            metadataDescription: "Simple and easily identifiable, each squiggle embodies the soul of the Art Blocks platform",
            attributes: attributes
        )

        let raw = Raw(
            tokenUri: "https://api.artblocks.io/token/1000222",
            metadata: metadata
        )

        let nft = NFT(
            id: "0x059EDD72Cd353dF5106D2B9cC5ab83a52287aC3a:1000222",
            contract: contract,
            tokenId: "1000222",
            tokenType: "ERC721",
            name: "Chromie Squiggle #222",
            nftDescription: "Simple and easily identifiable, each squiggle embodies the soul of the Art Blocks platform",
            image: image,
            raw: raw,
            collection: collection,
            tokenUri: "https://api.artblocks.io/token/1000222",
            timeLastUpdated: "2024-03-01T10:00:00Z",
            acquiredAt: acquiredAt,
            network: .ethMainnet
        )

        nft.artistName = "Snowfro"
        nft.sellerFeeBasisPoints = 1000
        nft.contentType = "image/svg+xml"
        nft.scriptType = "p5js"
        nft.engineType = "Art Blocks Engine"
        nft.seed = "0x222cafebabe"
        nft.aspectRatio = 1.0
        nft.isStatic = 0
        nft.projectID = "0"
        nft.series = "Curated"

        return nft
    }

}

// MARK: - Convenience Methods

extension NFT {

    /// Returns a random sample NFT from the collection
    static var randomSample: NFT {
        return sampleData.randomElement() ?? cryptoPunk1
    }

    /// Returns a subset of sample NFTs for testing
    static func sampleData(count: Int) -> [NFT] {
        let shuffled = sampleData.shuffled()
        return Array(shuffled.prefix(count))
    }

    /// Returns sample NFTs from a specific collection
    static func sampleData(from collectionName: String) -> [NFT] {
        return sampleData.filter { $0.collection?.name == collectionName }
    }

    /// Returns sample NFTs by a specific artist
    static func sampleData(by artistName: String) -> [NFT] {
        return sampleData.filter { $0.artistName == artistName }
    }

}
