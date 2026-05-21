import AuralisPrimaryModels
import ChainProviders
import Foundation
import NFTDomain
import NFTPersistence
import NFTPresentation
import NFTProviderAdapters
import ProviderKit

struct ReadOnlyProviderFactory: Sendable {
    private let chainProviderFactory: ReadOnlyChainProviderFactory
    private let configurationResolver: any ProviderConfigurationResolving
    private let session: URLSession?

    init(
        configurationResolver: any ProviderConfigurationResolving = LiveProviderConfigurationResolver(),
        session: URLSession? = nil
    ) {
        self.configurationResolver = configurationResolver
        self.session = session
        self.chainProviderFactory = ReadOnlyChainProviderFactory(
            configurationResolver: configurationResolver,
            session: session
        )
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
        chainProviderFactory.makeGasPricingProvider()
    }

    func makeNativeBalanceProvider() -> any NativeBalanceProviding {
        chainProviderFactory.makeNativeBalanceProvider()
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
