import AuralisPrimaryModels
import NFTDomain
import NFTPersistence
import NFTPresentation
import NFTProviderAdapters
import ProviderKit

@MainActor
struct ProviderAssembly {
    let readOnlyProviderFactory: ReadOnlyProviderFactory

    init(readOnlyProviderFactory: ReadOnlyProviderFactory = ReadOnlyProviderFactory()) {
        self.readOnlyProviderFactory = readOnlyProviderFactory
    }

    func makeNativeBalanceProvider() -> any NativeBalanceProviding {
        readOnlyProviderFactory.makeNativeBalanceProvider()
    }

    func makeGasPricingProvider() -> any GasPricingProviding {
        readOnlyProviderFactory.makeGasPricingProvider()
    }

    func makeTokenHoldingsProvider() -> any TokenHoldingsProviding {
        readOnlyProviderFactory.makeTokenHoldingsProvider()
    }

    func makeNFTInventoryProvider(for chain: Chain) throws -> any NFTInventoryProviding {
        try readOnlyProviderFactory.makeNFTInventoryProvider(for: chain)
    }
}
