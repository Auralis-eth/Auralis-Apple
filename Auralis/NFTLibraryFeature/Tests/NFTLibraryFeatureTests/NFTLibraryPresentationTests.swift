import AuralisPrimaryModels
import AuralisPrimaryPersistence
@testable import NFTLibraryFeature
import Testing

struct NFTLibraryPresentationTests {
    @Test("contract-backed collection detail filters by contract")
    func contractBackedCollectionFiltersByContract() {
        let matching = NFTLibraryTestFactory.nft(
            id: "matching",
            contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            tokenID: "1",
            name: "Moonpunk #1",
            collectionName: "Moonpunks"
        )
        let other = NFTLibraryTestFactory.nft(
            id: "other",
            contractAddress: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            tokenID: "2",
            name: "Other",
            collectionName: "Other"
        )

        let presentation = NFTLibraryPresentation.collectionDetail(
            route: .collection(
                contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                title: "Moonpunks",
                chain: .ethMainnet
            ),
            nfts: [matching, other],
            currentChain: .ethMainnet
        )

        #expect(presentation.title == "Moonpunks")
        #expect(presentation.items.map(\.id) == [matching.id])
        #expect(try #require(presentation.items.first).title == "Moonpunk #1")
        #expect(presentation.contractAddressLine == "0xaaaa...aaaa")
    }

    @Test("name-backed collection detail filters by collection name")
    func nameBackedCollectionFiltersByCollectionName() {
        let matching = NFTLibraryTestFactory.nft(
            id: "matching",
            contractAddress: nil,
            tokenID: "8",
            name: nil,
            collectionName: "Everydays",
            network: .baseMainnet
        )
        let presentation = NFTLibraryPresentation.collectionDetail(
            route: .collection(contractAddress: nil, title: "everydays", chain: .baseMainnet),
            nfts: [matching],
            currentChain: .baseMainnet
        )

        #expect(presentation.items.count == 1)
        #expect(try #require(presentation.items.first).title == "Untitled NFT")
        #expect(presentation.subtitle == "1 item in Base")
    }

    @Test("display title and subtitle have stable fallbacks")
    func displayFallbacks() {
        let nft = NFTLibraryTestFactory.nft(
            id: "fallback",
            contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            tokenID: "42",
            name: nil,
            collectionName: nil,
            network: .polygonMainnet
        )

        #expect(NFTLibraryPresentation.displayTitle(for: nft) == "Untitled NFT")
        #expect(NFTLibraryPresentation.displaySubtitle(for: nft, chain: .polygonMainnet) == "Polygon - Token 42")
    }

    @Test("image URL prefers original then thumbnail")
    func imageURLPreference() throws {
        let nft = NFTLibraryTestFactory.nft(
            id: "image",
            contractAddress: nil,
            tokenID: "1",
            name: "Image",
            collectionName: nil,
            image: .init(originalUrl: "https://example.com/original.png", thumbnailUrl: "https://example.com/thumb.png")
        )

        let imageURL = try #require(NFTLibraryPresentation.imageURL(for: nft))
        #expect(imageURL.absoluteString == "https://example.com/original.png")
    }
}

private enum NFTLibraryTestFactory {
    static func nft(
        id: String,
        contractAddress: String?,
        tokenID: String,
        name: String?,
        collectionName: String?,
        network: Chain = .ethMainnet,
        image: NFT.Image? = nil
    ) -> NFT {
        NFT(
            id: id,
            contract: NFT.Contract(address: contractAddress, chain: network),
            tokenId: tokenID,
            tokenType: nil,
            name: name,
            nftDescription: nil,
            image: image,
            raw: nil,
            collection: collectionName.map {
                NFT.Collection(name: $0, chain: network, contractAddress: contractAddress)
            },
            tokenUri: nil,
            timeLastUpdated: nil,
            acquiredAt: nil,
            network: network,
            accountAddress: "0x1111111111111111111111111111111111111111",
            collectionName: collectionName
        )
    }
}
