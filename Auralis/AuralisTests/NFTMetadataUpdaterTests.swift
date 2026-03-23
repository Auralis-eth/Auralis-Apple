import Testing
@testable import Auralis

@Suite
struct NFTMetadataUpdaterTests {
    @Test("metadata image updates create a missing image submodel")
    func metadataImageUpdatesCreateImageModel() {
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

        #expect(nft.image != nil)
        #expect(nft.image?.originalUrl == "https://example.com/image.png")
        #expect(nft.image?.secureUrl == "https://example.com/image.png")
    }
}
