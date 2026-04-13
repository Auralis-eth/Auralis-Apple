import Foundation
import SwiftData

@MainActor
protocol PrivacyResetting {
    func resetLocalPrivacyData() async throws
}

@MainActor
struct PrivacyResetService: PrivacyResetting {
    private let receiptStore: any ReceiptStore
    private let searchHistoryStore: SearchHistoryStore
    private let ensCacheResetService: any ENSCacheResetting
    private let tokenHoldingsStore: TokenHoldingsStore

    init(
        receiptStore: any ReceiptStore,
        searchHistoryStore: SearchHistoryStore,
        ensCacheResetService: any ENSCacheResetting,
        tokenHoldingsStore: TokenHoldingsStore
    ) {
        self.receiptStore = receiptStore
        self.searchHistoryStore = searchHistoryStore
        self.ensCacheResetService = ensCacheResetService
        self.tokenHoldingsStore = tokenHoldingsStore
    }

    func resetLocalPrivacyData() async throws {
        try receiptStore.resetAll()
        searchHistoryStore.clearAll()
        await ensCacheResetService.resetCache()
        await GasPriceCache.shared.clearCache()
        try tokenHoldingsStore.clearAll()
    }
}

@MainActor
enum PrivacyResetServices {
    static func live(modelContext: ModelContext) -> PrivacyResetService {
        PrivacyResetService(
            receiptStore: ReceiptStores.live(modelContext: modelContext),
            searchHistoryStore: SearchHistoryStore(),
            ensCacheResetService: ENSResolvers.cacheResetService(),
            tokenHoldingsStore: TokenHoldingsStore(modelContext: modelContext)
        )
    }
}
