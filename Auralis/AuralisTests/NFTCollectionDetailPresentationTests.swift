@testable import Auralis
import Testing

@Suite
struct NFTCollectionDetailPresentationTests {
    @Test("contract-backed collection detail filters by contract")
    func contractBackedCollectionFiltersByContract() {
        let matching = NFT(
            id: "matching",
            contract: NFT.Contract(address: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", chain: .ethMainnet),
            tokenId: "1",
            name: "Moonpunk #1",
            collection: NFT.Collection(name: "Moonpunks", chain: .ethMainnet, contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
            network: .ethMainnet,
            accountAddress: "0x1111111111111111111111111111111111111111",
            collectionName: "Moonpunks"
        )
        let other = NFT(
            id: "other",
            contract: NFT.Contract(address: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", chain: .ethMainnet),
            tokenId: "2",
            name: "Other",
            collection: NFT.Collection(name: "Other", chain: .ethMainnet, contractAddress: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"),
            network: .ethMainnet,
            accountAddress: "0x1111111111111111111111111111111111111111",
            collectionName: "Other"
        )

        let presentation = NFTCollectionDetailView.makePresentation(
            route: .collection(
                contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                title: "Moonpunks",
                chain: .ethMainnet
            ),
            nfts: [matching, other],
            currentChain: .ethMainnet
        )

        #expect(presentation.title == "Moonpunks")
        #expect(presentation.items.count == 1)
        #expect(presentation.items.first?.title == "Moonpunk #1")
    }
}
