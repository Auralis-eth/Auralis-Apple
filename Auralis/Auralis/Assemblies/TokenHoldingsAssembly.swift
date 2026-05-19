import ProviderKit
import SwiftData
import TokenStorage

@MainActor
struct TokenHoldingsAssembly {
    private let providerAssembly: ProviderAssembly

    init(providerAssembly: ProviderAssembly) {
        self.providerAssembly = providerAssembly
    }

    func makeStore(modelContext: ModelContext) -> SwiftDataTokenHoldingsStore {
        SwiftDataTokenHoldingsStore(modelContext: modelContext)
    }

    func makeProvider() -> any TokenHoldingsProviding {
        providerAssembly.makeTokenHoldingsProvider()
    }

    func makeSyncer(modelContext: ModelContext) -> any ERC20HoldingsSyncing {
        LiveERC20HoldingsSyncUseCase(
            tokenHoldingsProviderFactory: { [providerAssembly] in
                providerAssembly.makeTokenHoldingsProvider()
            },
            tokenHoldingsStoreFactory: { modelContext in
                SwiftDataTokenHoldingsStore(modelContext: modelContext)
            },
            modelContext: modelContext
        )
    }
}
