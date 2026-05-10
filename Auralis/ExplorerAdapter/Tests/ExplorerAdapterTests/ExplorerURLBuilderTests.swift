import AuralisPrimaryModels
import ExplorerAdapter
import Testing

@Suite
struct ExplorerURLBuilderTests {
    private let builder = ExplorerURLBuilder()
    private let contract = "0x1234567890abcdef1234567890abcdef12345678"
    private let transaction = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

    @Test("Explorer builder creates chain-specific address URLs")
    func addressURL() throws {
        let url = try builder.url(for: .address(contract, chain: .baseMainnet))
        #expect(url.absoluteString == "https://basescan.org/address/0x1234567890abcdef1234567890abcdef12345678")
    }

    @Test("Explorer builder creates transaction URLs")
    func transactionURL() throws {
        let url = try builder.url(for: .transaction(transaction, chain: .ethMainnet))
        #expect(url.absoluteString == "https://etherscan.io/tx/0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
    }

    @Test("Explorer builder creates NFT URLs")
    func nftURL() throws {
        let url = try builder.url(for: .nft(contract: contract, tokenID: "1", chain: .baseMainnet))
        #expect(url.absoluteString == "https://basescan.org/token/0x1234567890abcdef1234567890abcdef12345678?a=1")
    }

    @Test("Solana chains fail instead of falling back to mainnet")
    func solanaIsUnsupported() throws {
        #expect(throws: ExplorerURLBuildError.unsupportedChain(.solanaMainnet)) {
            try builder.url(for: .address(contract, chain: .solanaMainnet))
        }
    }

    @Test("Malformed addresses are rejected")
    func malformedAddressIsRejected() throws {
        #expect(throws: ExplorerURLBuildError.invalidAddress("0xabc")) {
            try builder.url(for: .address("0xabc", chain: .ethMainnet))
        }
    }
}
