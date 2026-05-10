import Foundation
import ProviderKit

public struct ReadOnlyChainProviderFactory: Sendable {
    private let configurationResolver: any ProviderConfigurationResolving
    private let session: URLSession?

    public init(
        configurationResolver: any ProviderConfigurationResolving = LiveProviderConfigurationResolver(),
        session: URLSession? = nil
    ) {
        self.configurationResolver = configurationResolver
        self.session = session
    }

    public func makeGasPricingProvider() -> any GasPricingProviding {
        AlchemyGasPricingProvider(
            configurationResolver: configurationResolver,
            session: session
        )
    }

    public func makeNativeBalanceProvider() -> any NativeBalanceProviding {
        AlchemyRPCProvider(
            configurationResolver: configurationResolver,
            session: session
        )
    }
}
