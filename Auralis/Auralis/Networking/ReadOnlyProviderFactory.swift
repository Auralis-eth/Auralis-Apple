import Foundation

struct ReadOnlyProviderFactory {
    private let configurationResolver: any ProviderConfigurationResolving
    private let session: URLSession?

    init(
        configurationResolver: any ProviderConfigurationResolving = LiveProviderConfigurationResolver(),
        session: URLSession? = nil
    ) {
        self.configurationResolver = configurationResolver
        self.session = session
    }

    func makeNFTInventoryProvider(for chain: Chain) throws -> any NFTInventoryProviding {
        if let session {
            return try AlchemyNFTService(
                chain: chain,
                configurationResolver: configurationResolver,
                session: session
            )
        }

        return try AlchemyNFTService(
            chain: chain,
            configurationResolver: configurationResolver
        )
    }

    func makeGasPricingProvider() -> any GasPricingProviding {
        if let session {
            return AlchemyGasPricingProvider(
                configurationResolver: configurationResolver,
                session: session
            )
        }

        return AlchemyGasPricingProvider(
            configurationResolver: configurationResolver
        )
    }

    func makeNativeBalanceProvider() -> any NativeBalanceProviding {
        if let session {
            return AlchemyRPCProvider(
                configurationResolver: configurationResolver,
                session: session
            )
        }

        return AlchemyRPCProvider(
            configurationResolver: configurationResolver
        )
    }

    func makeTokenHoldingsProvider() -> any TokenHoldingsProviding {
        if let session {
            return AlchemyTokenHoldingsProvider(
                configurationResolver: configurationResolver,
                session: session
            )
        }

        return AlchemyTokenHoldingsProvider(
            configurationResolver: configurationResolver
        )
    }

    func makeTokenBalancesProvider() -> any TokenBalancesProviding {
        if let session {
            return AlchemyTokenHoldingsProvider(
                configurationResolver: configurationResolver,
                session: session
            )
        }

        return AlchemyTokenHoldingsProvider(
            configurationResolver: configurationResolver
        )
    }
}
