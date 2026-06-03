@testable import Auralis
import AuralisPrimaryModels
import Testing

@Suite
struct ChainTests {
    @Test(
        "routing display names stay readable for supported mainnets and testnets",
        arguments: [
            (Chain.ethMainnet, "Ethereum"),
            (.arbMainnet, "Arbitrum"),
            (.arbNovaMainnet, "Arbitrum Nova"),
            (.ethSepoliaTestnet, "Ethereum Sepolia"),
            (.worldchainSepoliaTestnet, "WorldChain Sepolia"),
            (.soneiumMinatoTestnet, "Soneium Minato")
        ] as [(Chain, String)]
    )
    func routingDisplayNameMatchesExpected(chain: Chain, expected: String) {
        #expect(chain.routingDisplayName == expected)
    }
}
