import Foundation
import SwiftData

protocol DerivedSupportDataResetting: Sendable {
    func resetDerivedSupportData() async throws
}

@ModelActor
actor SwiftDataDerivedSupportDataResetService: DerivedSupportDataResetting {
    func resetDerivedSupportData() throws {
        let musicLibraryItems = try modelContext.fetch(FetchDescriptor<MusicLibraryItem>())
        for item in musicLibraryItems {
            modelContext.delete(item)
        }

        let nfts = try modelContext.fetch(FetchDescriptor<NFT>())
        for nft in nfts {
            modelContext.delete(nft)
        }

        let accounts = try modelContext.fetch(FetchDescriptor<EOAccount>())
        for account in accounts where account.trackedNFTCount != 0 {
            account.trackedNFTCount = 0
        }

        try modelContext.save()
    }
}

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
    private let derivedSupportDataResetService: any DerivedSupportDataResetting
    private let selectionPersistence: any ShellSelectionPersisting
    private let homePinnedItemsStore: HomePinnedItemsStore

    init(
        receiptStore: any ReceiptStore,
        searchHistoryStore: SearchHistoryStore,
        ensCacheResetService: any ENSCacheResetting,
        tokenHoldingsStore: TokenHoldingsStore,
        derivedSupportDataResetService: any DerivedSupportDataResetting,
        selectionPersistence: any ShellSelectionPersisting = UserDefaultsShellSelectionPersistence(),
        homePinnedItemsStore: HomePinnedItemsStore = HomePinnedItemsStore()
    ) {
        self.receiptStore = receiptStore
        self.searchHistoryStore = searchHistoryStore
        self.ensCacheResetService = ensCacheResetService
        self.tokenHoldingsStore = tokenHoldingsStore
        self.derivedSupportDataResetService = derivedSupportDataResetService
        self.selectionPersistence = selectionPersistence
        self.homePinnedItemsStore = homePinnedItemsStore
    }

    func resetLocalPrivacyData() async throws {
        try await receiptStore.resetAll()
        try await searchHistoryStore.clearAll()
        await ensCacheResetService.resetCache()
        await GasPriceCache.shared.clearCache()
        try await tokenHoldingsStore.clearAll()
        try await derivedSupportDataResetService.resetDerivedSupportData()
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
            derivedSupportDataResetService: SwiftDataDerivedSupportDataResetService(
                modelContainer: modelContext.container
            ),
            selectionPersistence: UserDefaultsShellSelectionPersistence(),
            homePinnedItemsStore: HomePinnedItemsStore()
        )
    }
}
