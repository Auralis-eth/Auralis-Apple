@testable import Auralis
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import NFTLibraryFeature
import Testing

@Suite
@MainActor
struct NFTCollectionDetailPresentationTests {
    @Test("contract-backed collection detail filters by contract")
    func contractBackedCollectionFiltersByContract() throws {
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
        #expect(try #require(presentation.items.first).title == "Moonpunk #1")
    }

    @Test("collection detail falls back to collection name when contract address is absent")
    func collectionDetailFallsBackToCollectionName() {
        let matching = NFT(
            id: "matching-name",
            contract: NFT.Contract(address: nil, chain: .ethMainnet),
            tokenId: "3",
            name: nil,
            collection: NFT.Collection(name: "Name Only", chain: .ethMainnet, contractAddress: nil),
            network: .ethMainnet,
            accountAddress: "0x1111111111111111111111111111111111111111",
            collectionName: "Name Only"
        )
        let other = NFT(
            id: "other-name",
            contract: NFT.Contract(address: nil, chain: .ethMainnet),
            tokenId: "",
            name: "Other",
            collection: NFT.Collection(name: "Other", chain: .ethMainnet, contractAddress: nil),
            network: .ethMainnet,
            accountAddress: "0x1111111111111111111111111111111111111111",
            collectionName: "Other"
        )

        let presentation = NFTCollectionDetailView.makePresentation(
            route: .collection(contractAddress: nil, title: "Name Only", chain: .ethMainnet),
            nfts: [matching, other],
            currentChain: .ethMainnet
        )

        #expect(presentation.title == "Name Only")
        #expect(presentation.subtitle == "1 item in Ethereum")
        #expect(presentation.contractAddressLine == nil)
        #expect(presentation.items == [
            NFTCollectionDetailPresentation.Item(
                id: "0x1111111111111111111111111111111111111111:eth-mainnet:__missing_contract__:::3:3",
                title: "Untitled NFT",
                subtitle: "Ethereum - Token 3"
            )
        ])
    }

    @Test("collection detail reports an empty current scope")
    func collectionDetailReportsEmptyScope() {
        let presentation = NFTCollectionDetailView.makePresentation(
            route: .collection(
                contractAddress: "0xcccccccccccccccccccccccccccccccccccccccc",
                title: "Empty",
                chain: .baseMainnet
            ),
            nfts: [],
            currentChain: .baseMainnet
        )

        #expect(presentation.title == "Empty")
        #expect(presentation.subtitle == "No items available in the current scope")
        #expect(presentation.contractAddressLine == "0xcccc...cccc")
        #expect(presentation.items.isEmpty)
    }

    @Test("collection detail excludes matching contracts from another chain")
    func collectionDetailExcludesMatchingContractsFromOtherChains() {
        let wrongChain = NFT(
            id: "wrong-chain",
            contract: NFT.Contract(address: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", chain: .baseMainnet),
            tokenId: "4",
            name: "Base Item",
            collection: NFT.Collection(name: "Moonpunks", chain: .baseMainnet, contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
            network: .baseMainnet,
            accountAddress: "0x1111111111111111111111111111111111111111",
            collectionName: "Moonpunks"
        )

        let presentation = NFTCollectionDetailView.makePresentation(
            route: .collection(
                contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                title: "Moonpunks",
                chain: .ethMainnet
            ),
            nfts: [wrongChain],
            currentChain: .ethMainnet
        )

        #expect(presentation.subtitle == "No items available in the current scope")
        #expect(presentation.items.isEmpty)
    }
}
