import AuralisFoundation
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import AuralisTestSupport

struct NFTFixture: @unchecked Sendable {
    static let music = NFTFixture(
        tokenId: "music-1",
        contentType: "audio/mpeg",
        animationUrl: "https://example.com/music-1.mp3",
        audioUrl: "https://example.com/music-1.mp3"
    )
    static let image = NFTFixture(
        tokenId: "image-1",
        contentType: "image/png",
        animationUrl: nil,
        audioUrl: nil,
        includeOwnedChildren: true
    )

    var tokenId: String
    var id: String?
    var accountAddress: String
    var contractAddress: String
    var collectionName: String?
    var network: Chain
    var tokenType: String?
    var name: String?
    var nftDescription: String?
    var imageOriginalUrl: String?
    var imageThumbnailUrl: String?
    var tokenURI: String?
    var rawTokenURI: String?
    var rawMetadata: [String: JSONValue]?
    var timeLastUpdated: String?
    var contentType: String?
    var artistName: String?
    var animationUrl: String?
    var audioUrl: String?
    var includeOwnedChildren: Bool

    init(
        tokenId: String = "fixture-token",
        id: String? = nil,
        accountAddress: String = Fixture.Accounts.primary,
        contractAddress: String = Fixture.Contracts.default,
        collectionName: String? = "Fixture Collection",
        network: Chain = .ethMainnet,
        tokenType: String? = nil,
        name: String? = nil,
        nftDescription: String? = nil,
        imageOriginalUrl: String? = nil,
        imageThumbnailUrl: String? = nil,
        tokenURI: String? = nil,
        rawTokenURI: String? = nil,
        rawMetadata: [String: JSONValue]? = nil,
        timeLastUpdated: String? = "2025-01-01T00:00:00Z",
        contentType: String? = nil,
        artistName: String? = "Fixture Artist",
        animationUrl: String? = nil,
        audioUrl: String? = nil,
        includeOwnedChildren: Bool = false
    ) {
        self.tokenId = tokenId
        self.id = id
        self.accountAddress = accountAddress
        self.contractAddress = contractAddress
        self.collectionName = collectionName
        self.network = network
        self.tokenType = tokenType
        self.name = name
        self.nftDescription = nftDescription
        self.imageOriginalUrl = imageOriginalUrl
        self.imageThumbnailUrl = imageThumbnailUrl
        self.tokenURI = tokenURI
        self.rawTokenURI = rawTokenURI
        self.rawMetadata = rawMetadata
        self.timeLastUpdated = timeLastUpdated
        self.contentType = contentType
        self.artistName = artistName
        self.animationUrl = animationUrl
        self.audioUrl = audioUrl
        self.includeOwnedChildren = includeOwnedChildren
    }

    func with(_ transform: (inout NFTFixture) -> Void) -> NFTFixture {
        var copy = self
        transform(&copy)
        return copy
    }

    func build() -> NFT {
        let normalizedAccountAddress = NFT.normalizedScopeComponent(accountAddress) ?? "unscoped"
        let normalizedContractAddress = NFT.normalizedScopeComponent(contractAddress) ?? "unknown"
        let resolvedTokenURI = tokenURI ?? "ipfs://fixture-\(tokenId)"
        let resolvedImageOriginalUrl = imageOriginalUrl ?? "https://example.com/\(tokenId).png"
        let resolvedImageThumbnailUrl = imageThumbnailUrl ?? "https://example.com/\(tokenId)-thumb.png"
        let raw = rawTokenURI == nil && rawMetadata == nil && includeOwnedChildren == false
            ? nil
            : NFT.Raw(
                tokenUri: rawTokenURI ?? resolvedTokenURI,
                metadata: rawMetadata ?? ["title": .string("Fixture \(tokenId)")]
            )

        return NFT(
            id: id ?? "\(normalizedAccountAddress):\(network.rawValue):\(normalizedContractAddress):\(tokenId)",
            contract: NFT.Contract(address: contractAddress, chain: network),
            tokenId: tokenId,
            tokenType: tokenType,
            name: name ?? "Fixture \(tokenId)",
            nftDescription: nftDescription,
            image: includeOwnedChildren || imageOriginalUrl != nil || imageThumbnailUrl != nil ? {
                let image = NFT.Image(
                    originalUrl: resolvedImageOriginalUrl,
                    thumbnailUrl: resolvedImageThumbnailUrl
                )
                image.secureUrl = resolvedImageOriginalUrl
                return image
            }() : nil,
            raw: raw,
            collection: collectionName.map {
                NFT.Collection(
                    name: $0,
                    chain: network,
                    contractAddress: contractAddress
                )
            },
            tokenUri: resolvedTokenURI,
            timeLastUpdated: timeLastUpdated,
            acquiredAt: includeOwnedChildren ? NFT.AcquiredAt(blockTimestamp: "2025-01-01T00:00:00Z") : nil,
            network: network,
            accountAddress: accountAddress,
            contentType: contentType,
            collectionName: collectionName,
            artistName: artistName,
            animationUrl: animationUrl,
            audioUrl: audioUrl
        )
    }
}
