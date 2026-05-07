import Foundation
import OSLog
import SwiftData

private let nftLogger = Logger(subsystem: "Auralis", category: "NFT")

@Model
/// Persisted NFT model scoped by account and chain for use across browsing and playback features.
public final class NFT: Codable {
    #Unique<NFT>([\.contract, \.tokenId, \.networkRawValue, \.accountAddressRawValue])
    #Index<NFT>([\.id], [\.acquiredAt], [\.collection], [\.tokenId], [\.accountAddressRawValue, \.networkRawValue])

    @Attribute(.unique) public var id: String
    @Relationship(deleteRule: .nullify) public var contract: Contract
    public var tokenId: String
    public var tokenType: String?
    public var name: String?
    public var nftDescription: String?
    @Relationship(deleteRule: .cascade) public var image: Image?
    @Relationship(deleteRule: .cascade) public var raw: Raw?
    @Relationship(deleteRule: .nullify) public var collection: Collection?
    public var tokenUri: String?
    public var timeLastUpdated: String?
    @Relationship(deleteRule: .cascade) public var acquiredAt: AcquiredAt?
    public var networkRawValue: String
    public var accountAddressRawValue: String
    public var contentType: String?
    public var collectionName: String?
    public var artistName: String?
    public var animationUrl: String?
    public var secureAnimationUrl: String?
    public var audioUrl: String?
    public var externalUrl: String?
    public var modelUrl: String?
    public var backgroundColor: String?
    public var collectionID: String?
    public var projectID: String?
    public var series: String?
    public var seriesID: String?
    public var primaryAssetUrl: String?
    public var securePrimaryAssetUrl: String?
    public var previewAssetUrl: String?
    public var securePreviewAssetUrl: String?
    public var artistWebsite: String?
    public var uniqueID: String?
    public var timestamp: String?
    public var tokenHash: String?
    public var medium: String?
    public var metadataVersion: String?
    public var imageDataUrl: String?
    public var secureImageDataUrl: String?
    public var imageHrUrl: String?
    public var secureImageHrUrl: String?
    public var imageHash: String?
    public var symbols: String?
    public var seed: String?
    public var original: String?
    public var agreement: String?
    public var website: String?
    public var payoutAddress: String?
    public var scriptType: String?
    public var engineType: String?
    public var accessArtworkFiles: String?
    public var sellerFeeBasisPoints: Int?
    public var minted: Int?
    public var isStatic: Int?
    public var aspectRatio: Double?
    @Relationship(deleteRule: .cascade, inverse: \Attribute.nft) public var attributes: [NFT.Attribute]?
    @Relationship(deleteRule: .nullify, inverse: \Tag.nfts) public var tags: [Tag]?
    public var account: EOAccount?
    public var playlists: [Playlist] = []

    @Transient public var network: Chain? {
        get { Chain(rawValue: networkRawValue) }
        set { networkRawValue = newValue?.rawValue ?? "" }
    }

    @Transient public var accountAddress: String? {
        get { Self.normalizedScopeComponent(accountAddressRawValue) }
        set { accountAddressRawValue = Self.normalizedScopeComponent(newValue) ?? "" }
    }

    public func applyRefreshScope(accountAddress: String?, chain: Chain) {
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

    public func assignOwnership(to account: EOAccount?) {
        self.account = account
        accountAddressRawValue = Self.normalizedScopeComponent(account?.address) ?? accountAddressRawValue
    }

    public func archiveForPlaylistRetention() {
        let archivedScope = Self.archivedPlaylistScopeComponent(for: accountAddressRawValue)
        account = nil
        applyRefreshScope(accountAddress: archivedScope, chain: network ?? .ethMainnet)
    }

    public func matchesScope(accountAddress: String?, chain: Chain) -> Bool {
        let normalizedAccountAddress = Self.normalizedScopeComponent(accountAddress) ?? ""
        return accountAddressRawValue == normalizedAccountAddress && networkRawValue == chain.rawValue
    }

    public func isMusic() -> Bool {
        audioUrl?.isEmpty == false
    }

    public var musicURL: URL? {
        guard let audioUrl else {
            return nil
        }

        return URL.sanitizedAuralisRemoteMediaURL(from: audioUrl)
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

    public init(
        id: String,
        contract: Contract,
        tokenId: String,
        tokenType: String? = nil,
        name: String? = nil,
        nftDescription: String? = nil,
        image: Image? = nil,
        raw: Raw? = nil,
        collection: Collection?,
        tokenUri: String? = nil,
        timeLastUpdated: String? = nil,
        acquiredAt: AcquiredAt? = nil,
        network: Chain = .ethMainnet,
        accountAddress: String? = nil,
        contentType: String? = nil,
        collectionName: String? = nil,
        artistName: String? = nil,
        animationUrl: String? = nil,
        secureAnimationUrl: String? = nil,
        audioUrl: String? = nil,
        tags: [Tag]? = nil
    ) {
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

    public required init(from decoder: Decoder) throws {
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

    public static func normalizedScopeComponent(_ value: String?) -> String? {
        guard let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmedValue.isEmpty else {
            return nil
        }

        return trimmedValue.lowercased()
    }

    public static func archivedPlaylistScopeComponent(for normalizedAccountAddress: String) -> String {
        "playlist:\(normalizedAccountAddress)"
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

    @Model
    public final class Contract: Codable {
        @Attribute(.unique) public var id: String
        public var address: String?
        public var chainRawValue: String

        public init(address: String?, chain: Chain = .ethMainnet) {
            self.id = Self.makeScopedID(chain: chain, address: address)
            self.address = address
            self.chainRawValue = chain.rawValue
        }

        public required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: NFTContractCodingKeys.self)
            let decodedAddress = try container.decodeIfPresent(String.self, forKey: .address)
            address = decodedAddress
            chainRawValue = Chain.ethMainnet.rawValue
            id = Self.makeScopedID(chain: .ethMainnet, address: decodedAddress)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: NFTContractCodingKeys.self)
            try container.encode(address, forKey: .address)
        }

        public func updateScope(chain: Chain) {
            chainRawValue = chain.rawValue
            id = Self.makeScopedID(chain: chain, address: address)
        }

        private static func makeScopedID(chain: Chain, address: String?) -> String {
            let resolvedAddress = NFT.normalizedScopeComponent(address) ?? "unknown"
            return "\(chain.rawValue):\(resolvedAddress)"
        }
    }

    @Model
    public final class Image: Codable {
        public var originalUrl: String?
        public var thumbnailUrl: String?
        public var secureUrl: String?

        public init(originalUrl: String? = nil, thumbnailUrl: String? = nil) {
            self.originalUrl = originalUrl
            self.thumbnailUrl = thumbnailUrl
        }

        public required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: NFTImageCodingKeys.self)
            originalUrl = try container.decodeIfPresent(String.self, forKey: .originalUrl)
            thumbnailUrl = try container.decodeIfPresent(String.self, forKey: .thumbnailUrl)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: NFTImageCodingKeys.self)
            try container.encodeIfPresent(originalUrl, forKey: .originalUrl)
            try container.encodeIfPresent(thumbnailUrl, forKey: .thumbnailUrl)
        }
    }

    @Model
    public final class Raw: Codable {
        public var tokenUri: String?
        public var metadata: [String: JSONValue]?
        public var error: String?

        public init(tokenUri: String? = nil, metadata: [String: JSONValue]? = nil) {
            self.tokenUri = tokenUri
            self.metadata = metadata
        }

        public required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: NFTRawCodingKeys.self)
            tokenUri = try container.decodeIfPresent(String.self, forKey: .tokenUri)
            do {
                metadata = try container.decodeIfPresent([String: JSONValue].self, forKey: .metadata)
            } catch {
                let website = try container.decodeIfPresent(String.self, forKey: .metadata)
                metadata = ["data": .string(website ?? "")]
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: NFTRawCodingKeys.self)
            try container.encodeIfPresent(tokenUri, forKey: .tokenUri)
            try container.encodeIfPresent(metadata, forKey: .metadata)
        }
    }

    @Model
    public final class NFTMetadata: Codable {
        public var image: String?
        public var name: String?
        public var metadataDescription: String?
        public var attributes: [Attribute]?

        public init(image: String? = nil, name: String? = nil, metadataDescription: String? = nil, attributes: [Attribute]? = nil) {
            self.image = image
            self.name = name
            self.metadataDescription = metadataDescription
            self.attributes = attributes
        }

        public required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: NFTMetadataCodingKeys.self)
            image = try container.decodeIfPresent(String.self, forKey: .image)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            metadataDescription = try container.decodeIfPresent(String.self, forKey: .metadataDescription)
            attributes = try container.decodeIfPresent([Attribute].self, forKey: .attributes)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: NFTMetadataCodingKeys.self)
            try container.encodeIfPresent(image, forKey: .image)
            try container.encodeIfPresent(name, forKey: .name)
            try container.encodeIfPresent(metadataDescription, forKey: .metadataDescription)
            try container.encodeIfPresent(attributes, forKey: .attributes)
        }
    }

    @Model
    public final class Attribute: Codable, Identifiable {
        public var value: String
        public var traitType: String?
        public var nft: NFT?

        public init(value: String, traitType: String? = nil) {
            self.value = value
            self.traitType = traitType
        }

        public required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: NFTAttributeCodingKeys.self)
            value = try container.decode(String.self, forKey: .value)
            traitType = try container.decodeIfPresent(String.self, forKey: .traitType)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: NFTAttributeCodingKeys.self)
            try container.encode(value, forKey: .value)
            try container.encodeIfPresent(traitType, forKey: .traitType)
        }
    }

    @Model
    public final class Collection: Codable {
        @Attribute(.unique) public var id: String
        public var name: String?
        public var chainRawValue: String
        public var contractAddress: String?

        public init(name: String?, chain: Chain = .ethMainnet, contractAddress: String? = nil) {
            self.id = Self.makeScopedID(chain: chain, name: name, contractAddress: contractAddress)
            self.name = name
            self.chainRawValue = chain.rawValue
            self.contractAddress = contractAddress
        }

        public required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: NFTCollectionCodingKeys.self)
            let decodedName = try container.decodeIfPresent(String.self, forKey: .name)
            name = decodedName
            chainRawValue = Chain.ethMainnet.rawValue
            contractAddress = nil
            id = Self.makeScopedID(chain: .ethMainnet, name: decodedName, contractAddress: nil)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: NFTCollectionCodingKeys.self)
            try container.encodeIfPresent(name, forKey: .name)
        }

        public func updateScope(chain: Chain, contractAddress: String?) {
            chainRawValue = chain.rawValue
            self.contractAddress = contractAddress
            id = Self.makeScopedID(chain: chain, name: name, contractAddress: contractAddress)
        }

        private static func makeScopedID(chain: Chain, name: String?, contractAddress: String?) -> String {
            if let resolvedContractAddress = NFT.normalizedScopeComponent(contractAddress) {
                return "\(chain.rawValue):\(resolvedContractAddress)"
            }

            let resolvedName = NFT.normalizedScopeComponent(name) ?? "unknown"
            return "\(chain.rawValue):name:\(resolvedName)"
        }
    }

    @Model
    public final class AcquiredAt: Codable {
        public var blockTimestamp: String?

        public init(blockTimestamp: String? = nil) {
            self.blockTimestamp = blockTimestamp
        }

        public required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: NFTAcquiredAtCodingKeys.self)
            blockTimestamp = try container.decodeIfPresent(String.self, forKey: .blockTimestamp)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: NFTAcquiredAtCodingKeys.self)
            try container.encodeIfPresent(blockTimestamp, forKey: .blockTimestamp)
        }
    }
}

private enum NFTContractCodingKeys: String, CodingKey {
    case address
}

private enum NFTImageCodingKeys: String, CodingKey {
    case originalUrl
    case thumbnailUrl
}

private enum NFTRawCodingKeys: String, CodingKey {
    case tokenUri
    case metadata
}

private enum NFTMetadataCodingKeys: String, CodingKey {
    case image
    case name
    case metadataDescription = "description"
    case attributes
}

private enum NFTAttributeCodingKeys: String, CodingKey {
    case value
    case traitType = "trait_type"
}

private enum NFTCollectionCodingKeys: String, CodingKey {
    case name
}

private enum NFTAcquiredAtCodingKeys: String, CodingKey {
    case blockTimestamp
}
