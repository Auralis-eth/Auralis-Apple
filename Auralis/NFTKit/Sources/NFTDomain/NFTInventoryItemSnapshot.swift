import AuralisPrimaryModels
import Foundation

public struct NFTInventoryItemSnapshot: Codable, Sendable {
    public struct Contract: Codable, Sendable {
        public var address: String?
        public var chain: Chain

        private enum CodingKeys: String, CodingKey {
            case address
            case chain
        }

        public init(address: String?, chain: Chain = .ethMainnet) {
            self.address = address
            self.chain = chain
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            address = try container.decodeIfPresent(String.self, forKey: .address)
            chain = try container.decodeIfPresent(Chain.self, forKey: .chain) ?? .ethMainnet
        }
    }

    public struct Image: Codable, Sendable {
        public var originalURL: String?
        public var thumbnailURL: String?
        public var secureURL: String?

        private enum CodingKeys: String, CodingKey {
            case originalURL = "originalUrl"
            case thumbnailURL = "thumbnailUrl"
            case secureURL = "secureUrl"
        }

        public init(originalURL: String?, thumbnailURL: String?, secureURL: String?) {
            self.originalURL = originalURL
            self.thumbnailURL = thumbnailURL
            self.secureURL = secureURL
        }
    }

    public struct Raw: Codable, Sendable {
        public var tokenURI: String?
        public var metadata: [String: JSONValue]?
        public var error: String?

        private enum CodingKeys: String, CodingKey {
            case tokenURI = "tokenUri"
            case metadata
            case error
        }

        public init(tokenURI: String?, metadata: [String: JSONValue]?, error: String?) {
            self.tokenURI = tokenURI
            self.metadata = metadata
            self.error = error
        }
    }

    public struct Collection: Codable, Sendable {
        public var name: String?
        public var chain: Chain
        public var contractAddress: String?

        private enum CodingKeys: String, CodingKey {
            case name
            case chain
            case contractAddress
        }

        public init(name: String?, chain: Chain = .ethMainnet, contractAddress: String?) {
            self.name = name
            self.chain = chain
            self.contractAddress = contractAddress
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            chain = try container.decodeIfPresent(Chain.self, forKey: .chain) ?? .ethMainnet
            contractAddress = try container.decodeIfPresent(String.self, forKey: .contractAddress)
        }
    }

    public struct AcquiredAt: Codable, Sendable {
        public var blockTimestamp: String?

        public init(blockTimestamp: String?) {
            self.blockTimestamp = blockTimestamp
        }
    }

    public struct Attribute: Codable, Sendable {
        public var value: String
        public var traitType: String?

        private enum CodingKeys: String, CodingKey {
            case value
            case traitType = "trait_type"
        }

        public init(value: String, traitType: String?) {
            self.value = value
            self.traitType = traitType
        }
    }

    public var id: String
    public var contract: Contract
    public var tokenId: String
    public var tokenType: String?
    public var name: String?
    public var nftDescription: String?
    public var image: Image?
    public var raw: Raw?
    public var collection: Collection?
    public var tokenURI: String?
    public var timeLastUpdated: String?
    public var acquiredAt: AcquiredAt?
    public var network: Chain
    public var accountAddress: String?
    public var contentType: String?
    public var collectionName: String?
    public var artistName: String?
    public var animationURL: String?
    public var secureAnimationURL: String?
    public var audioURL: String?
    public var externalURL: String?
    public var modelURL: String?
    public var backgroundColor: String?
    public var collectionID: String?
    public var projectID: String?
    public var series: String?
    public var seriesID: String?
    public var primaryAssetURL: String?
    public var securePrimaryAssetURL: String?
    public var previewAssetURL: String?
    public var securePreviewAssetURL: String?
    public var artistWebsite: String?
    public var uniqueID: String?
    public var timestamp: String?
    public var tokenHash: String?
    public var medium: String?
    public var metadataVersion: String?
    public var imageDataURL: String?
    public var secureImageDataURL: String?
    public var imageHrURL: String?
    public var secureImageHrURL: String?
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
    public var attributes: [Attribute]

    private enum CodingKeys: String, CodingKey {
        case contract
        case tokenId
        case tokenType
        case name
        case nftDescription = "description"
        case image
        case raw
        case collection
        case tokenURI = "tokenUri"
        case timeLastUpdated
        case acquiredAt
    }

    public init(
        id: String,
        contract: Contract,
        tokenId: String,
        tokenType: String?,
        name: String?,
        nftDescription: String?,
        image: Image?,
        raw: Raw?,
        collection: Collection?,
        tokenURI: String?,
        timeLastUpdated: String?,
        acquiredAt: AcquiredAt?,
        network: Chain = .ethMainnet,
        accountAddress: String? = nil,
        contentType: String? = nil,
        collectionName: String? = nil,
        artistName: String? = nil,
        animationURL: String? = nil,
        secureAnimationURL: String? = nil,
        audioURL: String? = nil,
        externalURL: String? = nil,
        modelURL: String? = nil,
        backgroundColor: String? = nil,
        collectionID: String? = nil,
        projectID: String? = nil,
        series: String? = nil,
        seriesID: String? = nil,
        primaryAssetURL: String? = nil,
        securePrimaryAssetURL: String? = nil,
        previewAssetURL: String? = nil,
        securePreviewAssetURL: String? = nil,
        artistWebsite: String? = nil,
        uniqueID: String? = nil,
        timestamp: String? = nil,
        tokenHash: String? = nil,
        medium: String? = nil,
        metadataVersion: String? = nil,
        imageDataURL: String? = nil,
        secureImageDataURL: String? = nil,
        imageHrURL: String? = nil,
        secureImageHrURL: String? = nil,
        imageHash: String? = nil,
        symbols: String? = nil,
        seed: String? = nil,
        original: String? = nil,
        agreement: String? = nil,
        website: String? = nil,
        payoutAddress: String? = nil,
        scriptType: String? = nil,
        engineType: String? = nil,
        accessArtworkFiles: String? = nil,
        sellerFeeBasisPoints: Int? = nil,
        minted: Int? = nil,
        isStatic: Int? = nil,
        aspectRatio: Double? = nil,
        attributes: [Attribute] = []
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
        self.tokenURI = tokenURI
        self.timeLastUpdated = timeLastUpdated
        self.acquiredAt = acquiredAt
        self.network = network
        self.accountAddress = accountAddress
        self.contentType = contentType
        self.collectionName = collectionName
        self.artistName = artistName
        self.animationURL = animationURL
        self.secureAnimationURL = secureAnimationURL
        self.audioURL = audioURL
        self.externalURL = externalURL
        self.modelURL = modelURL
        self.backgroundColor = backgroundColor
        self.collectionID = collectionID
        self.projectID = projectID
        self.series = series
        self.seriesID = seriesID
        self.primaryAssetURL = primaryAssetURL
        self.securePrimaryAssetURL = securePrimaryAssetURL
        self.previewAssetURL = previewAssetURL
        self.securePreviewAssetURL = securePreviewAssetURL
        self.artistWebsite = artistWebsite
        self.uniqueID = uniqueID
        self.timestamp = timestamp
        self.tokenHash = tokenHash
        self.medium = medium
        self.metadataVersion = metadataVersion
        self.imageDataURL = imageDataURL
        self.secureImageDataURL = secureImageDataURL
        self.imageHrURL = imageHrURL
        self.secureImageHrURL = secureImageHrURL
        self.imageHash = imageHash
        self.symbols = symbols
        self.seed = seed
        self.original = original
        self.agreement = agreement
        self.website = website
        self.payoutAddress = payoutAddress
        self.scriptType = scriptType
        self.engineType = engineType
        self.accessArtworkFiles = accessArtworkFiles
        self.sellerFeeBasisPoints = sellerFeeBasisPoints
        self.minted = minted
        self.isStatic = isStatic
        self.aspectRatio = aspectRatio
        self.attributes = attributes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tokenId = try container.decode(String.self, forKey: .tokenId)
        let tokenType = try container.decodeIfPresent(String.self, forKey: .tokenType)
        let name = try container.decodeIfPresent(String.self, forKey: .name)
        let tokenURI = try container.decodeIfPresent(String.self, forKey: .tokenURI)
        self.init(
            id: Self.makeScopedNFTID(
                accountAddress: nil,
                chain: .ethMainnet,
                contractAddress: try container.decodeIfPresent(Contract.self, forKey: .contract)?.address,
                tokenId: tokenId,
                tokenType: tokenType,
                name: name,
                tokenURI: tokenURI
            ),
            contract: try container.decodeIfPresent(Contract.self, forKey: .contract)
                ?? Contract(
                    address: Self.fallbackContractAddress(
                        tokenId: tokenId,
                        tokenType: tokenType,
                        name: name,
                        tokenURI: tokenURI
                    )
                ),
            tokenId: tokenId,
            tokenType: tokenType,
            name: name,
            nftDescription: try container.decodeIfPresent(String.self, forKey: .nftDescription),
            image: try container.decodeIfPresent(Image.self, forKey: .image),
            raw: try container.decodeIfPresent(Raw.self, forKey: .raw),
            collection: try container.decodeIfPresent(Collection.self, forKey: .collection),
            tokenURI: tokenURI,
            timeLastUpdated: try container.decodeIfPresent(String.self, forKey: .timeLastUpdated),
            acquiredAt: try container.decodeIfPresent(AcquiredAt.self, forKey: .acquiredAt)
        )
    }

    public mutating func applyRefreshScope(accountAddress: String?, chain: Chain) {
        self.accountAddress = Self.normalizedScopeComponent(accountAddress)
        network = chain
        contract.chain = chain
        collection?.chain = chain
        collection?.contractAddress = contract.address
        id = Self.makeScopedNFTID(
            accountAddress: accountAddress,
            chain: chain,
            contractAddress: contract.address,
            tokenId: tokenId,
            tokenType: tokenType,
            name: name,
            tokenURI: tokenURI
        )
    }

    public static func normalizedScopeComponent(_ value: String?) -> String? {
        guard let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedValue.isEmpty else {
            return nil
        }

        return trimmedValue.lowercased()
    }

    private static func makeScopedNFTID(
        accountAddress: String?,
        chain: Chain,
        contractAddress: String?,
        tokenId: String,
        tokenType: String?,
        name: String?,
        tokenURI: String?
    ) -> String {
        let resolvedAccountAddress = normalizedScopeComponent(accountAddress) ?? "unscoped"
        let fallbackContractAddress = fallbackContractAddress(
            tokenId: tokenId,
            tokenType: tokenType,
            name: name,
            tokenURI: tokenURI
        )
        let resolvedContractAddress = normalizedScopeComponent(contractAddress) ?? fallbackContractAddress
        return "\(resolvedAccountAddress):\(chain.rawValue):\(resolvedContractAddress):\(tokenId)"
    }

    private static func fallbackContractAddress(
        tokenId: String,
        tokenType: String?,
        name: String?,
        tokenURI: String?
    ) -> String {
        "__missing_contract__\(tokenType ?? ""):\(name ?? ""):\(tokenURI ?? ""):\(tokenId)"
    }
}
