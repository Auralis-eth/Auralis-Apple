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
    private let selectionPersistence: any ShellSelectionPersisting
    private let homePinnedItemsStore: HomePinnedItemsStore

    init(
        receiptStore: any ReceiptStore,
        searchHistoryStore: SearchHistoryStore,
        ensCacheResetService: any ENSCacheResetting,
        tokenHoldingsStore: TokenHoldingsStore,
        selectionPersistence: any ShellSelectionPersisting = UserDefaultsShellSelectionPersistence(),
        homePinnedItemsStore: HomePinnedItemsStore = HomePinnedItemsStore()
    ) {
        self.receiptStore = receiptStore
        self.searchHistoryStore = searchHistoryStore
        self.ensCacheResetService = ensCacheResetService
        self.tokenHoldingsStore = tokenHoldingsStore
        self.selectionPersistence = selectionPersistence
        self.homePinnedItemsStore = homePinnedItemsStore
    }

    func resetLocalPrivacyData() async throws {
        try await receiptStore.resetAll()
        try await searchHistoryStore.clearAll()
        await ensCacheResetService.resetCache()
        await GasPriceCache.shared.clearCache()
        try await tokenHoldingsStore.clearAll()
        selectionPersistence.clearSelection()
        homePinnedItemsStore.clearAll()
    }
}

@MainActor
enum PrivacyResetServices {
    static func live(modelContext: ModelContext) -> PrivacyResetService {
        PrivacyResetService(
            receiptStore: ReceiptStores.live(modelContext: modelContext),
            searchHistoryStore: SearchHistoryStore(modelContext: modelContext),
            ensCacheResetService: ENSResolvers.cacheResetService(),
            tokenHoldingsStore: TokenHoldingsStore(modelContext: modelContext),
            selectionPersistence: UserDefaultsShellSelectionPersistence(),
            homePinnedItemsStore: HomePinnedItemsStore()
        )
    }
}
