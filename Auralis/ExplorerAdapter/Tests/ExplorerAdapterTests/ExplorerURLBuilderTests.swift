import AuralisPrimaryModels
import ExplorerAdapter
import Testing

@Suite
struct ExplorerURLBuilderTests {
    private let builder = ExplorerURLBuilder()
    private let contract = "0x1234567890abcdef1234567890abcdef12345678"
    private let transaction = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

    @Test("Every supported EVM chain has an explicit explorer entry")
    func everySupportedEVMChainHasExplorerEntry() {
        let expectedChains = Set(Self.supportedExplorerCases.map(\.chain))
            .union([.solanaMainnet, .solanaDevnetTestnet])

        #expect(expectedChains == Set(Chain.allCases))
    }

    @Test("Explorer builder creates chain-specific address URLs", arguments: Self.supportedExplorerCases)
    private func addressURL(testCase: ExplorerCase) throws {
        let url = try builder.url(for: .address(contract, chain: testCase.chain))

        #expect(url.absoluteString == "\(testCase.baseURL)/address/\(contract)")
    }

    @Test("Explorer builder creates chain-specific transaction URLs", arguments: Self.supportedExplorerCases)
    private func transactionURL(testCase: ExplorerCase) throws {
        let url = try builder.url(for: .transaction(transaction, chain: testCase.chain))

        #expect(url.absoluteString == "\(testCase.baseURL)/tx/\(transaction)")
    }

    @Test("Explorer builder creates chain-specific token contract URLs", arguments: Self.supportedExplorerCases)
    private func tokenURL(testCase: ExplorerCase) throws {
        let url = try builder.url(for: .token(contract: contract, chain: testCase.chain))

        #expect(url.absoluteString == "\(testCase.baseURL)/token/\(contract)")
    }

    @Test("Explorer builder creates chain-specific NFT asset URLs", arguments: Self.supportedExplorerCases)
    private func nftURL(testCase: ExplorerCase) throws {
        let url = try builder.url(for: .nft(contract: contract, tokenID: "1", chain: testCase.chain))

        #expect(url.absoluteString == "\(testCase.baseURL)/token/\(contract)?a=1")
    }

    @Test("Explorer labels match the catalog", arguments: Self.supportedExplorerCases)
    private func labelsMatchCatalog(testCase: ExplorerCase) {
        #expect(builder.label(for: testCase.chain) == testCase.label)
    }

    @Test("Catalog exposes every supported explorer host for allowlist handoff")
    func catalogExposesAllowedHosts() {
        #expect(ExplorerCatalog.default.allowedHosts == Set(Self.supportedExplorerCases.map(\.host)))
    }

    @Test("Solana chains fail instead of falling back to mainnet", arguments: [
        Chain.solanaMainnet,
        Chain.solanaDevnetTestnet,
    ])
    func solanaIsUnsupported(chain: Chain) throws {
        #expect(throws: ExplorerURLBuildError.unsupportedChain(chain)) {
            try builder.url(for: .address(contract, chain: chain))
        }
    }

    @Test("Malformed addresses are rejected")
    func malformedAddressIsRejected() throws {
        #expect(throws: ExplorerURLBuildError.invalidAddress("0xabc")) {
            try builder.url(for: .address("0xabc", chain: .ethMainnet))
        }
    }

    @Test("Empty transaction hashes are rejected")
    func emptyTransactionHashIsRejected() throws {
        #expect(throws: ExplorerURLBuildError.invalidTransactionHash("")) {
            try builder.url(for: .transaction("", chain: .ethMainnet))
        }
    }

    @Test("Empty token IDs are rejected")
    func emptyTokenIDIsRejected() throws {
        #expect(throws: ExplorerURLBuildError.invalidTokenID(" ")) {
            try builder.url(for: .nft(contract: contract, tokenID: " ", chain: .ethMainnet))
        }
    }

    @Test("Unprefixed Ethereum addresses are normalized before URL construction")
    func unprefixedAddressIsNormalized() throws {
        let unprefixedContract = "1234567890abcdef1234567890abcdef12345678"
        let url = try builder.url(for: .address(unprefixedContract, chain: .baseMainnet))

        #expect(url.absoluteString == "https://basescan.org/address/0x\(unprefixedContract)")
    }

    private struct ExplorerCase: Sendable, CustomTestStringConvertible {
        let chain: Chain
        let label: String
        let baseURL: String

        var host: String {
            baseURL
                .replacingOccurrences(of: "https://", with: "")
        }

        var testDescription: String {
            chain.rawValue
        }
    }

    private static let supportedExplorerCases: [ExplorerCase] = [
        ExplorerCase(chain: .ethMainnet, label: "Etherscan", baseURL: "https://etherscan.io"),
        ExplorerCase(chain: .ethSepoliaTestnet, label: "Etherscan", baseURL: "https://sepolia.etherscan.io"),
        ExplorerCase(chain: .baseMainnet, label: "BaseScan", baseURL: "https://basescan.org"),
        ExplorerCase(chain: .baseSepoliaTestnet, label: "BaseScan", baseURL: "https://sepolia.basescan.org"),
        ExplorerCase(chain: .arbMainnet, label: "Arbiscan", baseURL: "https://arbiscan.io"),
        ExplorerCase(chain: .arbSepoliaTestnet, label: "Arbiscan", baseURL: "https://sepolia.arbiscan.io"),
        ExplorerCase(chain: .arbNovaMainnet, label: "Arbiscan", baseURL: "https://nova.arbiscan.io"),
        ExplorerCase(chain: .optMainnet, label: "Optimistic Etherscan", baseURL: "https://optimistic.etherscan.io"),
        ExplorerCase(chain: .optSepoliaTestnet, label: "Optimistic Etherscan", baseURL: "https://sepolia-optimism.etherscan.io"),
        ExplorerCase(chain: .polygonMainnet, label: "PolygonScan", baseURL: "https://polygonscan.com"),
        ExplorerCase(chain: .polygonAmoyTestnet, label: "PolygonScan", baseURL: "https://amoy.polygonscan.com"),
        ExplorerCase(chain: .worldchainMainnet, label: "WorldScan", baseURL: "https://worldscan.org"),
        ExplorerCase(chain: .worldchainSepoliaTestnet, label: "WorldScan", baseURL: "https://sepolia.worldscan.org"),
        ExplorerCase(chain: .shapeMainnet, label: "ShapeScan", baseURL: "https://shapescan.xyz"),
        ExplorerCase(chain: .shapeSepoliaTestnet, label: "ShapeScan", baseURL: "https://sepolia.shapescan.xyz"),
        ExplorerCase(chain: .inkMainnet, label: "Ink Explorer", baseURL: "https://explorer.inkonchain.com"),
        ExplorerCase(chain: .inkSepoliaTestnet, label: "Ink Explorer", baseURL: "https://explorer-sepolia.inkonchain.com"),
        ExplorerCase(chain: .unichainMainnet, label: "Uniscan", baseURL: "https://uniscan.xyz"),
        ExplorerCase(chain: .unichainSepoliaTestnet, label: "Uniscan", baseURL: "https://sepolia.uniscan.xyz"),
        ExplorerCase(chain: .soneiumMainnet, label: "Soneium Blockscout", baseURL: "https://soneium.blockscout.com"),
        ExplorerCase(chain: .soneiumMinatoTestnet, label: "Soneium Blockscout", baseURL: "https://soneium-minato.blockscout.com"),
        ExplorerCase(chain: .berachainMainnet, label: "BeraScan", baseURL: "https://berascan.com"),
        ExplorerCase(chain: .zoraMainnet, label: "Zora Explorer", baseURL: "https://explorer.zora.energy"),
        ExplorerCase(chain: .zoraSepoliaTestnet, label: "Zora Explorer", baseURL: "https://sepolia.explorer.zora.energy"),
        ExplorerCase(chain: .polynomialMainnet, label: "PolynomialScan", baseURL: "https://polynomialscan.io"),
        ExplorerCase(chain: .polynomialSepoliaTestnet, label: "PolynomialScan", baseURL: "https://sepolia.polynomialscan.io"),
    ]
}
