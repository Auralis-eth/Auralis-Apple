import AuralisReceipts
import AuralisRuntime
import SwiftData

@MainActor
struct SearchAssembly {
    private let spotlightScopeRegistry = SearchSpotlightScopeRegistry()

    func makeSearchHistoryStore(modelContext: ModelContext) -> SearchHistoryStore {
        SearchHistoryStore(modelContext: modelContext)
    }

    func makeSpotlightIndexer(modelContext: ModelContext) -> any SearchSpotlightIndexing {
        SearchSpotlightIndexer(modelContext: modelContext, scopeRegistry: spotlightScopeRegistry)
    }

    func makeAssistant(modelContext: ModelContext) -> any SearchAssistantProviding {
        #if canImport(CoreSpotlight)
        // Keep this gate conservative until the shipping SDK baseline for SpotlightSearchTool is confirmed.
        if #available(iOS 27.0, *) {
            return SearchAssistantService(
                hydrationDelegate: SearchSpotlightHydrationDelegate(
                    modelContainer: modelContext.container,
                    scopeRegistry: spotlightScopeRegistry
                ),
                modelRouter: ModelProviderComposition.router,
                modelInferenceClient: ModelProviderComposition.inferenceClient,
                receiptStore: ReceiptStores.live(modelContext: modelContext)
            )
        }
        return UnavailableSearchAssistantService(
            availability: .unavailable("Assistant-backed search requires iOS 27 or newer. Exact search still works.")
        )
        #else
        return UnavailableSearchAssistantService()
        #endif
    }
}
