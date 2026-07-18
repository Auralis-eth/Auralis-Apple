import AuralisPrimaryModels
import Foundation

public enum NFTDiscoveryProvider: String, Codable, Equatable, Sendable {
    case alchemy
    case helius
    case unknown
}

public struct NFTTokenDTO: Equatable, Sendable {
    public let compositeID: String
    public let chain: Chain
    public let walletAddress: String
    public let contractAddress: String?
    public let tokenId: String
    public let tokenStandard: String?
    public let collectionName: String?
    public let name: String?
    public let description: String?
    public let imageURL: String?
    public let metadataURL: String?
    public let metadataRaw: String?
    public let providerUpdatedAt: String?
    public let isActive: Bool
    public let provider: NFTDiscoveryProvider

    public init(
        compositeID: String? = nil,
        chain: Chain,
        walletAddress: String,
        contractAddress: String?,
        tokenId: String,
        tokenStandard: String? = nil,
        collectionName: String? = nil,
        name: String? = nil,
        description: String? = nil,
        imageURL: String? = nil,
        metadataURL: String? = nil,
        metadataRaw: String? = nil,
        providerUpdatedAt: String? = nil,
        isActive: Bool = true,
        provider: NFTDiscoveryProvider = .unknown
    ) {
        let normalizedWalletAddress = Self.normalizedScopeComponent(walletAddress) ?? walletAddress
        let normalizedContractAddress = Self.normalizedScopeComponent(contractAddress)

        self.compositeID = compositeID ?? Self.makeCompositeID(
            chain: chain,
            contractAddress: normalizedContractAddress,
            tokenId: tokenId,
            walletAddress: normalizedWalletAddress,
            tokenStandard: tokenStandard,
            name: name,
            metadataURL: metadataURL
        )
        self.chain = chain
        self.walletAddress = normalizedWalletAddress
        self.contractAddress = normalizedContractAddress
        self.tokenId = tokenId
        self.tokenStandard = tokenStandard
        self.collectionName = collectionName
        self.name = name
        self.description = description
        self.imageURL = imageURL
        self.metadataURL = metadataURL
        self.metadataRaw = metadataRaw
        self.providerUpdatedAt = providerUpdatedAt
        self.isActive = isActive
        self.provider = provider
    }

    public static func makeCompositeID(
        chain: Chain,
        contractAddress: String?,
        tokenId: String,
        walletAddress: String,
        tokenStandard: String? = nil,
        name: String? = nil,
        metadataURL: String? = nil
    ) -> String {
        let normalizedWalletAddress = normalizedScopeComponent(walletAddress) ?? "unscoped"
        let resolvedContractAddress = normalizedScopeComponent(contractAddress) ?? ""

        return "\(chain.rawValue):\(resolvedContractAddress):\(tokenId):\(normalizedWalletAddress)"
    }

    public static func normalizedScopeComponent(_ value: String?) -> String? {
        guard let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedValue.isEmpty else {
            return nil
        }

        return trimmedValue.lowercased()
    }

}

public enum MetadataSchema: String, Codable, Equatable, Sendable {
    case soundXyz
    case zora
    case metaplex
    case erc1155
    case openSea
    case unknown
}

public struct MetadataParsed: Equatable, Sendable {
    public let name: String?
    public let description: String?
    public let creatorName: String?
    public let collectionName: String?
    public let artworkURL: String?
    public let audioURL: String?
    public let videoURL: String?
    public let duration: Double?
    public let format: String?
    public let attributes: [String: String]
    public let schemaVersion: MetadataSchema
    public let rawJSON: String

    public init(
        name: String? = nil,
        description: String? = nil,
        creatorName: String? = nil,
        collectionName: String? = nil,
        artworkURL: String? = nil,
        audioURL: String? = nil,
        videoURL: String? = nil,
        duration: Double? = nil,
        format: String? = nil,
        attributes: [String: String] = [:],
        schemaVersion: MetadataSchema,
        rawJSON: String
    ) {
        self.name = name
        self.description = description
        self.creatorName = creatorName
        self.collectionName = collectionName
        self.artworkURL = artworkURL
        self.audioURL = audioURL
        self.videoURL = videoURL
        self.duration = duration
        self.format = format
        self.attributes = attributes
        self.schemaVersion = schemaVersion
        self.rawJSON = rawJSON
    }
}

public struct MediaItemDTO: Equatable, Sendable {
    public let id: String
    public let nftTokenId: String
    public let title: String
    public let creatorName: String?
    public let collectionName: String?
    public let artworkURL: String?
    public let audioURL: String?
    public let videoURL: String?
    public let durationSeconds: Double?
    public let format: String?
    public let hasAudio: Bool
    public let hasVideo: Bool
    public let isPlayable: Bool
    public let chain: Chain
    public let contractAddress: String?
    public let tokenId: String
    public let tokenStandard: String?
    public let walletAddress: String
    public let classifiedAt: Date
    public let createdAt: Date

    public init(
        id: String,
        nftTokenId: String,
        title: String,
        creatorName: String?,
        collectionName: String?,
        artworkURL: String?,
        audioURL: String?,
        videoURL: String?,
        durationSeconds: Double?,
        format: String?,
        hasAudio: Bool,
        hasVideo: Bool,
        isPlayable: Bool,
        chain: Chain,
        contractAddress: String?,
        tokenId: String,
        tokenStandard: String?,
        walletAddress: String,
        classifiedAt: Date,
        createdAt: Date
    ) {
        self.id = id
        self.nftTokenId = nftTokenId
        self.title = title
        self.creatorName = creatorName
        self.collectionName = collectionName
        self.artworkURL = artworkURL
        self.audioURL = audioURL
        self.videoURL = videoURL
        self.durationSeconds = durationSeconds
        self.format = format
        self.hasAudio = hasAudio
        self.hasVideo = hasVideo
        self.isPlayable = isPlayable
        self.chain = chain
        self.contractAddress = contractAddress
        self.tokenId = tokenId
        self.tokenStandard = tokenStandard
        self.walletAddress = walletAddress
        self.classifiedAt = classifiedAt
        self.createdAt = createdAt
    }
}

public protocol EVMNFTDiscovering: Sendable {
    func fetchAll(owner: String, chain: Chain) async throws -> [NFTTokenDTO]
}

public protocol SolanaNFTDiscovering: Sendable {
    func fetchAll(owner: String) async throws -> [NFTTokenDTO]
}

public protocol TokenMetadataFetching: Sendable {
    func fetch(metadataURL: String) async throws -> String
}

public protocol MetadataParsing: Sendable {
    func parse(json: String) -> MetadataParsed
}

public protocol MediaClassifying: Sendable {
    func classify(parsed: MetadataParsed, token: NFTTokenDTO) -> MediaItemDTO
}

public protocol NFTTokenPersisting: Sendable {
    func upsertAll(_ tokens: [NFTTokenDTO]) async throws
    func activeIDs(walletAddress: String, chain: Chain) async throws -> Set<String>
    func markInactive(ids: Set<String>) async throws
}

public protocol AuraPlayMediaPersisting: Sendable {
    func upsertAll(_ items: [MediaItemDTO]) async throws
}

public protocol ArtworkPrefetching: Sendable {
    func prefetch(artworkURLs: [String]) async
}

public struct NFTDiscoveryScope: Equatable, Sendable {
    public let walletAddress: String
    public let chain: Chain

    public init(walletAddress: String, chain: Chain) {
        self.walletAddress = walletAddress
        self.chain = chain
    }
}

public protocol NFTDiscoveryScopeProviding: Sendable {
    func activeScopes() async throws -> [NFTDiscoveryScope]
}

public protocol MediaItemIndexing: Sendable {
    func indexItems(_ ids: [String]) async
    func deleteItems(_ ids: [String]) async
}

public protocol EmbeddingQueueProcessing: Sendable {
    func processQueue(limit: Int) async
}

public protocol AuraPlaySemanticSearching: Sendable {
    func search(
        query: String,
        in scope: AuraPlayLibraryScope,
        limit: Int,
        minimumScore: Float
    ) async throws -> [AuraPlaySemanticSearchResult]
}

public struct NoOpMediaItemIndexer: MediaItemIndexing {
    public init() {}
    public func indexItems(_ ids: [String]) async {}
    public func deleteItems(_ ids: [String]) async {}
}

public struct NoOpEmbeddingQueueProcessor: EmbeddingQueueProcessing {
    public init() {}
    public func processQueue(limit: Int) async {}
}

public struct NoOpAuraPlaySemanticSearchService: AuraPlaySemanticSearching {
    public init() {}

    public func search(
        query: String,
        in scope: AuraPlayLibraryScope,
        limit: Int,
        minimumScore: Float
    ) async throws -> [AuraPlaySemanticSearchResult] {
        []
    }
}
