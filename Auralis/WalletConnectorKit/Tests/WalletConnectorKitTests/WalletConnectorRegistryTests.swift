import Testing
@testable import WalletConnectorKit

@Suite("Wallet connector registry")
struct WalletConnectorRegistryTests {
    @Test("Default catalog includes Phase 4 provider families")
    func defaultCatalogIncludesPhase4Providers() {
        let providerIDs = Set(WalletConnectorCatalog.defaultProviders.map(\.id.rawValue))

        #expect(providerIDs == [
            "rabby",
            "metamask",
            "rainbow",
            "coinbase-wallet",
            "phantom",
            "backpack",
            "solflare",
            "privy",
            "dynamic",
            "generic-wallet",
        ])
    }

    @Test("Registry filters providers by chain support")
    func registryFiltersProvidersByChainSupport() {
        let registry = WalletConnectorRegistry()

        let evmIDs = Set(registry.providers(supporting: .base).map(\.id.rawValue))
        let solanaIDs = Set(registry.providers(supporting: .solana).map(\.id.rawValue))

        #expect(evmIDs.isSuperset(of: ["rabby", "rainbow", "coinbase-wallet", "metamask", "phantom", "backpack", "privy", "dynamic", "generic-wallet"]))
        #expect(!evmIDs.contains("solflare"))
        #expect(solanaIDs == ["phantom", "backpack", "solflare", "generic-wallet"])
    }

    @Test("Deep-link schemes are normalized and discoverable")
    func deepLinkSchemesAreDiscoverable() {
        #expect(WalletConnectorCatalog.metamask.deepLinkScheme == "metamask")
        #expect(WalletConnectorCatalog.coinbaseWallet.deepLinkScheme == "cbwallet")
        #expect(WalletConnectorCatalog.genericWallet.deepLinkScheme == nil)
        #expect(WalletConnectorCatalog.genericWallet.supportsGenericPairingFallback)
    }
}
