import AuralisPrimaryModels
import ExplorerAdapter
import Testing

@Suite
struct OpenSeaDestinationBuilderTests {
    private let builder = OpenSeaDestinationBuilder()
    private let contract = "0x1234567890abcdef1234567890abcdef12345678"

    @Test("OpenSea URLs are chain aware")
    func openseaURLsAreChainAware() throws {
        let url = try builder.url(contract: contract, tokenID: "1", chain: .baseMainnet)
        #expect(url.absoluteString == "https://opensea.io/assets/base/0x1234567890abcdef1234567890abcdef12345678/1")
    }

    @Test("Unsupported OpenSea chains fail explicitly")
    func unsupportedOpenSeaChainFails() throws {
        #expect(throws: ExplorerURLBuildError.unsupportedChain(.baseSepoliaTestnet)) {
            try builder.url(contract: contract, tokenID: "1", chain: .baseSepoliaTestnet)
        }
    }
}
