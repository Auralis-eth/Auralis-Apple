@testable import Auralis
import AuralisPrimaryModels
import Testing

@Suite
struct ChainTests {
    @Test("routing display names stay readable for supported mainnets and testnets")
    func routingDisplayNamesAreReadable() {
        #expect(Chain.ethMainnet.routingDisplayName == "Ethereum")
        #expect(Chain.arbMainnet.routingDisplayName == "Arbitrum")
        #expect(Chain.arbNovaMainnet.routingDisplayName == "Arbitrum Nova")
        #expect(Chain.ethSepoliaTestnet.routingDisplayName == "Ethereum Sepolia")
        #expect(Chain.worldchainSepoliaTestnet.routingDisplayName == "WorldChain Sepolia")
        #expect(Chain.soneiumMinatoTestnet.routingDisplayName == "Soneium Minato")
    }
}
