import Foundation

struct ReadOnlyProviderFactory {
    private let configurationResolver: any ProviderConfigurationResolving
    private let session: URLSession

    init(
        configurationResolver: any ProviderConfigurationResolving = LiveProviderConfigurationResolver(),
        session: URLSession = .shared
    ) {
        self.configurationResolver = configurationResolver
        self.session = session
    }

    func makeNFTInventoryProvider(for chain: Chain) throws -> any NFTInventoryProviding {
        try AlchemyNFTService(
            chain: chain,
            configurationResolver: configurationResolver
        )
    }

    func makeGasPricingProvider() -> any GasPricingProviding {
        AlchemyGasPricingProvider(
            configurationResolver: configurationResolver,
            session: session
        )
    }

    func makeNativeBalanceProvider() -> any NativeBalanceProviding {
        AlchemyRPCProvider(
            configurationResolver: configurationResolver,
            session: session
        )
    }

    func makeTokenHoldingsProvider() -> any TokenHoldingsProviding {
        AlchemyTokenHoldingsProvider(
            configurationResolver: configurationResolver,
            session: session
        )
    }

    func makeTokenBalancesProvider() -> any TokenBalancesProviding {
        AlchemyTokenHoldingsProvider(
            configurationResolver: configurationResolver,
            session: session
        )
    }
}
