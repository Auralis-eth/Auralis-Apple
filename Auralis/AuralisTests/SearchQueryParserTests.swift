import Foundation
import Testing
@testable import Auralis

@Suite
struct SearchQueryParserTests {
    private let parser = SearchQueryParser()

    @Test("classifies valid ENS input and rejects ENS-like invalid strings")
    func classifiesENSInputs() {
        let ensIndex = SearchLocalIndex(
            accounts: [],
            ensEntries: [
                .init(
                    ensName: "vitalik.eth",
                    displayName: "vitalik.eth",
                    address: "0x1234567890abcdef1234567890abcdef12345678"
                )
            ],
            contracts: [],
            tokenSymbols: [],
            nftNames: [],
            collections: []
        )

        let valid = parser.classify(query: "vitalik.eth", index: ensIndex)
        #expect(valid.kind == .ensName)
        #expect(valid.localMatches.count == 1)

        let invalid = parser.classify(query: "vitalik..eth", index: ensIndex)
        #expect(invalid.kind == .invalidENSLike)
    }

    @Test("distinguishes wallet, contract, ambiguous, and invalid address input")
    func classifiesAddressInputs() {
        let index = SearchLocalIndex(
            accounts: [
                .init(
                    address: "0x1111111111111111111111111111111111111111",
                    displayName: "Primary Wallet"
                )
            ],
            ensEntries: [],
            contracts: [
                .init(
                    address: "0x2222222222222222222222222222222222222222",
                    label: "Moonpunks",
                    chain: .ethMainnet
                )
            ],
            tokenSymbols: [],
            nftNames: [],
            collections: []
        )

        #expect(
            parser.classify(
                query: "0x1111111111111111111111111111111111111111",
                index: index
            ).kind == .walletAddress
        )
        #expect(
            parser.classify(
                query: "0x2222222222222222222222222222222222222222",
                index: index
            ).kind == .contractAddress
        )
        #expect(
            parser.classify(
                query: "0x3333333333333333333333333333333333333333",
                index: index
            ).kind == .ambiguousAddress
        )
        #expect(
            parser.classify(
                query: "0x1234",
                index: index
            ).kind == .invalidAddress
        )
        #expect(
            parser.classify(
                query: "0xnotactuallyhex",
                index: index
            ).kind == .invalidAddress
        )
    }

    @Test("detects exact local symbol, NFT name, and collection matches deterministically")
    func classifiesLocalSearchMatches() {
        let index = SearchLocalIndex(
            accounts: [],
            ensEntries: [],
            contracts: [],
            tokenSymbols: [
                .init(
                    symbol: "USDC",
                    label: "USD Coin",
                    contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                    chain: .ethMainnet
                )
            ],
            nftNames: [
                .init(
                    nftID: "moonpunk-4890",
                    normalizedName: "moonpunk #4890",
                    displayName: "Moonpunk #4890",
                    collectionDisplayName: "Moonpunks"
                )
            ],
            collections: [
                .init(
                    id: "moonpunks:eth",
                    normalizedName: "moonpunks",
                    displayName: "Moonpunks",
                    chain: .ethMainnet,
                    contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
                )
            ]
        )

        #expect(parser.classify(query: "usdc", index: index).kind == .tokenSymbol)
        #expect(parser.classify(query: "Moonpunk #4890", index: index).kind == .nftName)
        #expect(parser.classify(query: "Moonpunks", index: index).kind == .collectionName)
    }

    @Test("falls back to text classification when there is no deterministic local type match")
    func fallsBackToTextQuery() {
        let result = parser.classify(query: "surreal landscape", index: .empty)
        #expect(result.kind == .text)
        #expect(result.localMatches.isEmpty)
    }

    @Test("builds the local index from active-scope NFTs and accounts")
    func buildsLocalIndexFromCurrentScope() {
        let matchingNFT = NFT(
            id: "matching",
            contract: NFT.Contract(address: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", chain: .ethMainnet),
            tokenId: "1",
            name: "Moonpunk #1",
            collection: NFT.Collection(
                name: "Moonpunks",
                chain: .ethMainnet,
                contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
            ),
            network: .ethMainnet,
            accountAddress: "0x1111111111111111111111111111111111111111",
            collectionName: "Moonpunks"
        )
        matchingNFT.symbols = "MPK"

        let outOfScopeNFT = NFT(
            id: "other",
            contract: NFT.Contract(address: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", chain: .baseMainnet),
            tokenId: "2",
            name: "Base Artifact",
            collection: NFT.Collection(
                name: "Base Relics",
                chain: .baseMainnet,
                contractAddress: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
            ),
            network: .baseMainnet,
            accountAddress: "0x9999999999999999999999999999999999999999",
            collectionName: "Base Relics"
        )
        outOfScopeNFT.symbols = "BASE"

        let accounts = [
            EOAccount(
                address: "0x1111111111111111111111111111111111111111",
                name: "alpha.eth"
            )
        ]

        let index = SearchLocalIndex.make(
            nfts: [matchingNFT, outOfScopeNFT],
            holdings: [
                TokenHolding(
                    accountAddress: "0x1111111111111111111111111111111111111111",
                    chain: .ethMainnet,
                    contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                    symbol: "MPK",
                    displayName: "Moonpunk Token",
                    amountDisplay: "12.0",
                    balanceKind: .erc20
                )
            ],
            accounts: accounts,
            currentAccountAddress: "0x1111111111111111111111111111111111111111",
            currentChain: .ethMainnet
        )

        #expect(index.accounts.count == 1)
        #expect(index.ensEntries.map(\.ensName) == ["alpha.eth"])
        #expect(index.contracts.map(\.address) == ["0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"])
        #expect(index.tokenSymbols.map(\.symbol) == ["MPK"])
        #expect(index.nftNames.map(\.displayName) == ["Moonpunk #1"])
        #expect(index.collections.map(\.displayName) == ["Moonpunks"])
    }
}
