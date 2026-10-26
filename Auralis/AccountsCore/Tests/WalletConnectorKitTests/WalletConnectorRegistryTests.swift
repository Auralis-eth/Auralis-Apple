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

    @Test("Known chains accept project defaults and canonical CAIP aliases")
    func knownChainsAcceptProjectDefaultsAndCanonicalCAIPAliases() {
        #expect(WalletChain.solana.caip2 == "solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp")
        #expect(WalletChain(caip2: "solana:mainnet") == .solana)
        #expect(WalletChain(caip2: "solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp") == .solana)
        #expect(WalletChain.solana.caip2Values.contains("solana:mainnet"))
        #expect(WalletChain.solana.caip2Values.contains("solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp"))
    }

    @Test("Extended EVM chains resolve their CAIP-2 references round-trip")
    func extendedEVMChainsResolveCAIP2() {
        let expected: [WalletChain: String] = [
            .avalanche: "eip155:43114",
            .bnb: "eip155:56",
            .zksync: "eip155:324",
            .linea: "eip155:59144",
        ]
        for (chain, caip2) in expected {
            #expect(chain.namespace == "eip155")
            #expect(chain.caip2 == caip2)
            #expect(WalletChain(caip2: caip2) == chain)
            #expect(WalletChain.evmChains.contains(chain))
        }
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

    @Test("Registry tolerates duplicate provider IDs without trapping (keeps the first)")
    func registryToleratesDuplicateProviderIDs() {
        let first = ThirdPartyWalletProvider(
            id: "metamask",
            displayName: "MetaMask",
            supportedChains: WalletChain.evmChains,
            connectionMethods: [.deepLink(scheme: "metamask")]
        )
        let collidingDuplicate = ThirdPartyWalletProvider(
            id: "metamask",
            displayName: "MetaMask (duplicate)",
            supportedChains: [.ethereum],
            connectionMethods: [.deepLink(scheme: "metamask-2")]
        )

        // Must not trap (as `Dictionary(uniqueKeysWithValues:)` would); the first
        // occurrence wins.
        let registry = WalletConnectorRegistry(providers: [first, collidingDuplicate])

        #expect(registry.providers.count == 1)
        #expect(registry.provider(id: "metamask")?.displayName == "MetaMask")
    }

    @Test("Deep-link schemes are normalized and discoverable")
    func deepLinkSchemesAreDiscoverable() {
        #expect(WalletConnectorCatalog.metamask.deepLinkScheme == "metamask")
        #expect(WalletConnectorCatalog.coinbaseWallet.deepLinkScheme == "cbwallet")
        #expect(WalletConnectorCatalog.genericWallet.deepLinkScheme == nil)
        #expect(WalletConnectorCatalog.genericWallet.supportsGenericPairingFallback)
    }

    @Test("Provider configuration requirements expose host app URL wiring")
    func providerConfigurationRequirementsExposeHostAppURLWiring() {
        #expect(WalletConnectorCatalog.metamask.configurationRequirements.querySchemes == ["metamask"])
        #expect(WalletConnectorCatalog.metamask.configurationRequirements.universalLinks == ["https://metamask.app.link"])
        #expect(WalletConnectorCatalog.metamask.configurationRequirements.mobileSDKIdentifiers == ["metamask-mobile-sdk"])
        #expect(WalletConnectorCatalog.coinbaseWallet.configurationRequirements.querySchemes == ["cbwallet"])
    }

    @Test("Provider launch families distinguish WalletConnect direct SDK embedded and fallback routes")
    func providerLaunchFamiliesDistinguishWalletConnectDirectSDKEmbeddedAndFallbackRoutes() {
        #expect(WalletConnectorCatalog.metamask.launchFamilies == [.walletConnect, .directSDK])
        #expect(WalletConnectorCatalog.privy.launchFamilies == [.embeddedWallet])
        #expect(WalletConnectorCatalog.dynamic.launchFamilies == [.embeddedWallet])
        #expect(WalletConnectorCatalog.genericWallet.launchFamilies == [.browserExtension])
        #expect(WalletConnectorCatalog.privy.requiresAuthenticationSession)
        #expect(WalletConnectorCatalog.dynamic.requiresAuthenticationSession)
        #expect(!WalletConnectorCatalog.metamask.requiresAuthenticationSession)
    }

    @Test("Provider metadata exposes role custody support and semantic capabilities")
    func providerMetadataExposesRoleCustodySupportAndSemanticCapabilities() {
        #expect(WalletConnectorCatalog.privy.role == .embeddedWalletProvider)
        #expect(WalletConnectorCatalog.privy.custodyModel == .providerManaged)
        #expect(WalletConnectorCatalog.privy.capabilities.contains(.embeddedWallet))
        #expect(WalletConnectorCatalog.privy.capabilities.contains(.evm))
        #expect(WalletConnectorCatalog.dynamic.capabilities.contains(.embeddedWallet))
        #expect(WalletConnectorCatalog.dynamic.capabilities.contains(.evm))
        #expect(!WalletConnectorCatalog.privy.capabilities.contains(.solana))
        #expect(!WalletConnectorCatalog.privy.capabilities.contains(.transactionSigning))
        #expect(!WalletConnectorCatalog.privy.capabilities.contains(.batchTransactionSigning))
        #expect(!WalletConnectorCatalog.privy.capabilities.contains(.signAndSend))
        #expect(!WalletConnectorCatalog.dynamic.capabilities.contains(.solana))
        #expect(WalletConnectorCatalog.dynamic.capabilities.contains(.transactionSigning))
        #expect(!WalletConnectorCatalog.dynamic.capabilities.contains(.batchTransactionSigning))
        #expect(!WalletConnectorCatalog.dynamic.capabilities.contains(.signAndSend))
        #expect(WalletConnectorCatalog.metamask.capabilities.contains(.customSchemeReturn))
        #expect(WalletConnectorCatalog.metamask.capabilities.contains(.evm))
        #expect(!WalletConnectorCatalog.metamask.capabilities.contains(.walletConnectIRN))
        #expect(WalletConnectorCatalog.coinbaseWallet.capabilities.contains(.directRequestResponse))
        #expect(!WalletConnectorCatalog.coinbaseWallet.capabilities.contains(.walletConnectIRN))
        #expect(WalletConnectorCatalog.genericWallet.capabilities.contains(.persistentSession))
        #expect(!WalletConnectorCatalog.genericWallet.capabilities.contains(.walletConnectIRN))
        guard case .deprecated(let message) = WalletConnectorCatalog.metamask.supportStatus else {
            Issue.record("Expected MetaMask support status to be deprecated.")
            return
        }
        #expect(message.contains("archived"))
    }

    @Test("Registry filters providers by chain request method and exact capability")
    func registryFiltersProvidersByChainRequestMethodAndExactCapability() {
        let registry = WalletConnectorRegistry()

        let messageIDs = Set(registry.providers(supporting: .base, method: .ethPersonalSign).map(\.id.rawValue))
        let transactionIDs = Set(registry.providers(supporting: .base, method: .ethSendTransaction).map(\.id.rawValue))
        let chainSwitchIDs = Set(registry.providers(supporting: .base, method: .walletSwitchEthereumChain).map(\.id.rawValue))
        let addChainIDs = Set(registry.providers(supporting: .base, method: .walletAddEthereumChain).map(\.id.rawValue))
        let solanaIDs = Set(registry.providers(supporting: .solana, method: .solanaSignMessage).map(\.id.rawValue))
        let unsupportedIDs = Set(registry.providers(supporting: .solana, method: .ethPersonalSign).map(\.id.rawValue))

        #expect(messageIDs.contains("metamask"))
        #expect(messageIDs.contains("coinbase-wallet"))
        #expect(messageIDs.contains("privy"))
        #expect(!messageIDs.contains("solflare"))
        #expect(transactionIDs.contains("dynamic"))
        #expect(!transactionIDs.contains("privy"))
        #expect(!chainSwitchIDs.contains("coinbase-wallet"))
        #expect(!chainSwitchIDs.contains("privy"))
        #expect(!chainSwitchIDs.contains("dynamic"))
        #expect(addChainIDs.contains("coinbase-wallet"))
        #expect(!addChainIDs.contains("privy"))
        #expect(!addChainIDs.contains("dynamic"))
        #expect(solanaIDs == ["phantom", "backpack", "solflare", "generic-wallet"])
        #expect(unsupportedIDs.isEmpty)
    }
}
