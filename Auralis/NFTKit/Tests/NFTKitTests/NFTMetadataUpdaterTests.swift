import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Testing
import NFTDomain
import NFTPersistence
import NFTPresentation
import NFTProviderAdapters

@Suite
struct NFTMetadataUpdaterTests {
    @Test("metadata image updates create a missing image submodel")
    func metadataImageUpdatesCreateImageModel() throws {
        let nft = NFT(
            id: "0x1234567890abcdef1234567890abcdef12345678:eth-mainnet:0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:1",
            contract: NFT.Contract(address: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", chain: .ethMainnet),
            tokenId: "1",
            name: "Fixture",
            image: nil,
            raw: nil,
            collection: NFT.Collection(
                name: "Collection",
                chain: .ethMainnet,
                contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
            ),
            tokenUri: "ipfs://fixture-1",
            network: .ethMainnet,
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678"
        )

        NFTMetadataUpdater.updateNFTFromMetadata(
            nft: nft,
            metadata: [
                "image": .string("https://example.com/image.png")
            ]
        )

        let image = try #require(nft.image)
        #expect(image.originalUrl == "https://example.com/image.png")
        #expect(image.secureUrl == "https://example.com/image.png")
    }

    @Test("nil metadata leaves cached NFT fields unchanged")
    func nilMetadataLeavesCachedFieldsUnchanged() throws {
        let nft = makeNFT(
            name: "Cached Name",
            image: makeImage(url: "https://example.com/cached.png")
        )

        NFTMetadataUpdater.updateNFTFromMetadata(nft: nft, metadata: nil)

        #expect(nft.name == "Cached Name")
        #expect(try #require(nft.image).originalUrl == "https://example.com/cached.png")
        #expect(try #require(nft.image).secureUrl == "https://example.com/cached.png")
    }

    @Test("partial metadata updates known fields and preserves cached image URLs")
    func partialMetadataUpdatesKnownFieldsAndPreservesImageURLs() throws {
        let nft = makeNFT(
            name: "Old Name",
            image: makeImage(url: "https://example.com/cached.png")
        )

        NFTMetadataUpdater.updateNFTFromMetadata(
            nft: nft,
            metadata: [
                "name": .string("New Name"),
                "collectionName": .string("New Collection"),
                "artist": .string("New Artist")
            ]
        )

        #expect(nft.name == "New Name")
        #expect(nft.collectionName == "New Collection")
        #expect(nft.artistName == "New Artist")
        #expect(try #require(nft.image).originalUrl == "https://example.com/cached.png")
    }

    @Test("empty metadata object preserves cached fields")
    func emptyMetadataObjectPreservesCachedFields() throws {
        let nft = makeNFT(
            name: "Cached Name",
            image: makeImage(url: "https://example.com/cached.png")
        )

        NFTMetadataUpdater.updateNFTFromMetadata(nft: nft, metadata: [:])

        #expect(nft.name == "Cached Name")
        #expect(try #require(nft.image).originalUrl == "https://example.com/cached.png")
        #expect(try #require(nft.image).secureUrl == "https://example.com/cached.png")
    }

    @Test("metadata image replacement updates both original and secure URLs")
    func metadataImageReplacementUpdatesImageURLs() throws {
        let nft = makeNFT(
            name: "Cached Name",
            image: makeImage(url: "https://example.com/old.png")
        )

        NFTMetadataUpdater.updateNFTFromMetadata(
            nft: nft,
            metadata: [
                "image": .string("ipfs://new-image")
            ]
        )

        #expect(try #require(nft.image).originalUrl == "https://gateway.pinata.cloud/ipfs/new-image")
        #expect(try #require(nft.image).secureUrl == "https://gateway.pinata.cloud/ipfs/new-image")
    }
}

private func makeNFT(name: String?, image: NFT.Image?) -> NFT {
    NFT(
        id: "0x1234567890abcdef1234567890abcdef12345678:eth-mainnet:0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:1",
        contract: NFT.Contract(address: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", chain: .ethMainnet),
        tokenId: "1",
        name: name,
        image: image,
        raw: nil,
        collection: NFT.Collection(
            name: "Collection",
            chain: .ethMainnet,
            contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        ),
        tokenUri: "ipfs://fixture-1",
        network: .ethMainnet,
        accountAddress: "0x1234567890abcdef1234567890abcdef12345678"
    )
}

private func makeImage(url: String) -> NFT.Image {
    let image = NFT.Image(originalUrl: url)
    image.secureUrl = url
    return image
}
