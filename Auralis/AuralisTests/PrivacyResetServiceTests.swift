@testable import Auralis
import Foundation
import SwiftData
import Testing

@MainActor
@Suite
struct PrivacyResetServiceTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([SearchHistoryRecord.self, TokenHolding.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @Test("resetLocalPrivacyData clears persisted search history rows")
    func resetLocalPrivacyDataClearsSearchHistory() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let searchHistoryStore = SearchHistoryStore(modelContext: context)
        let tokenHoldingsStore = TokenHoldingsStore(modelContext: context)
        let receiptStore = RecordingReceiptStore()
        let ensCacheResetService = RecordingENSCacheResetService()
        let selectionPersistence = RecordingShellSelectionPersistence()
        let pinnedItemsStore = HomePinnedItemsStore(userDefaults: UserDefaults(suiteName: #function)!)
        let service = PrivacyResetService(
            receiptStore: receiptStore,
            searchHistoryStore: searchHistoryStore,
            ensCacheResetService: ensCacheResetService,
            tokenHoldingsStore: tokenHoldingsStore,
            selectionPersistence: selectionPersistence,
            homePinnedItemsStore: pinnedItemsStore
        )

        try await searchHistoryStore.recordCommittedQuery("Moonpunks", accountAddress: nil)
        try await searchHistoryStore.recordCommittedQuery("USDC", accountAddress: "0x1111111111111111111111111111111111111111")
        try await tokenHoldingsStore.upsertNativeHolding(
            accountAddress: "0x1111111111111111111111111111111111111111",
            chain: .ethMainnet,
            amountDisplay: "1.25",
            updatedAt: .now
        )
        try pinnedItemsStore.togglePin(
            .openNews,
            accountAddress: "0x1111111111111111111111111111111111111111"
        )

        try await service.resetLocalPrivacyData()

        #expect(searchHistoryStore.entries(for: nil).isEmpty)
        #expect(searchHistoryStore.entries(for: "0x1111111111111111111111111111111111111111").isEmpty)
        #expect(receiptStore.resetAllCallCount == 1)
        #expect(await ensCacheResetService.resetCount() == 1)
        #expect(try context.fetch(FetchDescriptor<TokenHolding>()).isEmpty)
        #expect(selectionPersistence.clearSelectionCallCount == 1)
        #expect(pinnedItemsStore.pinnedActions(for: "0x1111111111111111111111111111111111111111").isEmpty)
    }
}

@MainActor
private final class RecordingReceiptStore: ReceiptStore {
    private(set) var resetAllCallCount = 0

    func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord {
        fatalError("append is not used in PrivacyResetServiceTests")
    }

    func latest(limit: Int) throws -> [ReceiptRecord] {
        fatalError("latest is not used in PrivacyResetServiceTests")
    }

    func receipts(forCorrelationID correlationID: String, limit: Int) throws -> [ReceiptRecord] {
        fatalError("receipts(forCorrelationID:limit:) is not used in PrivacyResetServiceTests")
    }

    func exportAll() throws -> Data {
        fatalError("exportAll is not used in PrivacyResetServiceTests")
    }

    func resetAll() async throws {
        resetAllCallCount += 1
    }
}

private actor RecordingENSCacheResetService: ENSCacheResetting {
    private var resetCallCount = 0

    func resetCache() async {
        resetCallCount += 1
    }

    func resetCount() -> Int {
        resetCallCount
    }
}

@MainActor
private final class RecordingShellSelectionPersistence: ShellSelectionPersisting {
    private(set) var clearSelectionCallCount = 0

    func loadSelection() -> (address: String, chainID: String) {
        ("", Chain.ethMainnet.rawValue)
    }

    func saveSelection(address: String, chainID: String) { }

    func clearSelection() {
        clearSelectionCallCount += 1
    }
}
