import Foundation
import SwiftData

protocol DerivedSupportDataResetting: Sendable {
    func resetDerivedSupportData() async throws
}

protocol AuraPlayPersistenceResetting: Sendable {
    func resetAuraPlayPersistence() async throws
}

@ModelActor
actor SwiftDataDerivedSupportDataResetService: DerivedSupportDataResetting {
    func resetDerivedSupportData() throws {
        try modelContext.delete(
            model: MusicLibraryItem.self,
            where: #Predicate<MusicLibraryItem> { _ in true }
        )
        try modelContext.delete(
            model: Playlist.self,
            where: #Predicate<Playlist> { _ in true }
        )
        try modelContext.deleteAllNFTData()

        let accounts = try modelContext.fetch(FetchDescriptor<EOAccount>())
        for account in accounts where account.trackedNFTCount != 0 {
            account.trackedNFTCount = 0
        }

        try modelContext.save()
    }
}

actor AuraPlayStoreResetService: AuraPlayPersistenceResetting {
    private let fileManager: FileManager
    private let baseDirectory: URL?

    init(
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory
    }

    func resetAuraPlayPersistence() throws {
        try AppModelContainer.resetStoreFiles(
            fileManager: fileManager,
            baseDirectory: baseDirectory
        )
    }
}

@ModelActor
actor SwiftDataAuraPlayPersistenceResetService: AuraPlayPersistenceResetting {
    func resetAuraPlayPersistence() throws {
        try modelContext.delete(
            model: AuraPlayMediaItem.self,
            where: #Predicate<AuraPlayMediaItem> { _ in true }
        )
        try modelContext.delete(
            model: AuraPlayNFTToken.self,
            where: #Predicate<AuraPlayNFTToken> { _ in true }
        )
        try modelContext.delete(
            model: AuraPlayWallet.self,
            where: #Predicate<AuraPlayWallet> { _ in true }
        )

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
    private let auraPlayPersistenceResetService: any AuraPlayPersistenceResetting
    private let selectionPersistence: any ShellSelectionPersisting
    private let homePinnedItemsStore: HomePinnedItemsStore

    init(
        receiptStore: any ReceiptStore,
        searchHistoryStore: SearchHistoryStore,
        ensCacheResetService: any ENSCacheResetting,
        tokenHoldingsStore: TokenHoldingsStore,
        derivedSupportDataResetService: any DerivedSupportDataResetting,
        auraPlayPersistenceResetService: any AuraPlayPersistenceResetting,
        selectionPersistence: any ShellSelectionPersisting = UserDefaultsShellSelectionPersistence(),
        homePinnedItemsStore: HomePinnedItemsStore = HomePinnedItemsStore()
    ) {
        self.receiptStore = receiptStore
        self.searchHistoryStore = searchHistoryStore
        self.ensCacheResetService = ensCacheResetService
        self.tokenHoldingsStore = tokenHoldingsStore
        self.derivedSupportDataResetService = derivedSupportDataResetService
        self.auraPlayPersistenceResetService = auraPlayPersistenceResetService
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
        try await auraPlayPersistenceResetService.resetAuraPlayPersistence()
        selectionPersistence.clearSelection()
        homePinnedItemsStore.clearAll()
    }
}

@MainActor
enum PrivacyResetServices {
    static func live(
        modelContext: ModelContext,
        auraPlayModelContainer: ModelContainer?
    ) -> PrivacyResetService {
        PrivacyResetService(
            receiptStore: ReceiptStores.live(modelContext: modelContext),
            searchHistoryStore: SearchHistoryStore(modelContext: modelContext),
            ensCacheResetService: ENSResolvers.cacheResetService(),
            tokenHoldingsStore: TokenHoldingsStore(modelContext: modelContext),
            derivedSupportDataResetService: SwiftDataDerivedSupportDataResetService(
                modelContainer: modelContext.container
            ),
            auraPlayPersistenceResetService: auraPlayModelContainer.map {
                SwiftDataAuraPlayPersistenceResetService(modelContainer: $0)
            } ?? AuraPlayStoreResetService(),
            selectionPersistence: UserDefaultsShellSelectionPersistence(),
            homePinnedItemsStore: HomePinnedItemsStore()
        )
    }
}
