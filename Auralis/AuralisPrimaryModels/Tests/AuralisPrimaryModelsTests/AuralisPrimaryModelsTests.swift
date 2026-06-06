import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import Testing

struct AuralisPrimaryModelsTests {
    @Test("chain raw values and chain IDs remain stable")
    func chainIdentifiersRemainStable() {
        #expect(Chain.ethMainnet.rawValue == "eth-mainnet")
        #expect(Chain.ethMainnet.chainId == 1)
        #expect(Chain.baseMainnet.rawValue == "base-mainnet")
        #expect(Chain.baseMainnet.chainId == 8453)
        #expect(Chain.solanaMainnet.formattedChainId == "Solana Network")
    }

    @Test("Ethereum addresses normalize whitespace, prefix, and casing")
    func ethereumAddressNormalizesSupportedInput() throws {
        let address = try #require(AuralisEthereumAddress(" ABCDEFabcdefABCDEFabcdefABCDEFabcdefABCD "))

        #expect(address.rawValue == "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd")
        #expect(AuralisEthereumAddress.normalized("0x1234567890ABCDEF1234567890abcdef12345678") == "0x1234567890abcdef1234567890abcdef12345678")
        #expect(AuralisEthereumAddress("0xnot-an-address") == nil)
    }

    @Test("NFT codable round trip preserves persisted API fields")
    func nftCodableRoundTripPreservesFields() throws {
        let nft = NFT(
            id: "ignored-by-codable",
            contract: NFT.Contract(address: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", chain: .baseMainnet),
            tokenId: "42",
            tokenType: "ERC721",
            name: "Fixture Token",
            nftDescription: "A deterministic fixture",
            image: NFT.Image(originalUrl: "https://example.com/image.png"),
            raw: nil,
            collection: NFT.Collection(name: "Fixtures", chain: .baseMainnet, contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
            tokenUri: "ipfs://fixture",
            timeLastUpdated: "2026-06-01T00:00:00Z",
            acquiredAt: nil,
            network: .baseMainnet,
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678"
        )

        let data = try JSONEncoder().encode(nft)
        let decoded = try JSONDecoder().decode(NFT.self, from: data)

        #expect(decoded.tokenId == "42")
        #expect(decoded.tokenType == "ERC721")
        #expect(decoded.name == "Fixture Token")
        #expect(decoded.nftDescription == "A deterministic fixture")
        #expect(try #require(decoded.image).originalUrl == "https://example.com/image.png")
        #expect(try #require(decoded.collection).name == "Fixtures")
        #expect(decoded.network == .ethMainnet)
    }

    @Test("refresh scope recomputes NFT and collection IDs from normalized account and chain")
    func refreshScopeRecomputesScopedIdentifiers() {
        let nft = NFT(
            id: "old",
            contract: NFT.Contract(address: "0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", chain: .ethMainnet),
            tokenId: "7",
            name: "Scoped",
            collection: NFT.Collection(name: "Scoped", chain: .ethMainnet, contractAddress: "0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"),
            network: .ethMainnet,
            accountAddress: nil
        )

        nft.applyRefreshScope(
            accountAddress: " 0x1234567890ABCDEF1234567890abcdef12345678 ",
            chain: .baseMainnet
        )

        #expect(nft.id == "0x1234567890abcdef1234567890abcdef12345678:base-mainnet:0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:7")
        #expect(nft.contract.id == "base-mainnet:0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        #expect(try #require(nft.collection).id == "base-mainnet:0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        #expect(nft.matchesScope(accountAddress: "0x1234567890abcdef1234567890abcdef12345678", chain: .baseMainnet))
    }
}
