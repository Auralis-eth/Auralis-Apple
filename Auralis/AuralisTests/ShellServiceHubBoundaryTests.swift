import Foundation
import SwiftData
import Testing
@testable import Auralis

@Suite
struct ShellServiceHubBoundaryTests {
    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            EOAccount.self,
            NFT.self,
            Tag.self,
            StoredReceipt.self,
            TokenHolding.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @Test("live shell service hub creates account stores through the shared recorder seam")
    @MainActor
    func accountStoreFactoryUsesSharedRecorderSeam() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let accountStore = ShellServiceHub.live.accountStoreFactory(context)
        let receiptStore = ShellServiceHub.live.receiptStoreFactory(context)

        _ = try accountStore.activateWatchAccount(
            from: "0x1234567890abcdef1234567890abcdef12345678",
            correlationID: "shell-account-store"
        )

        let receipts = try receiptStore.receipts(forCorrelationID: "shell-account-store", limit: 10)
        #expect(receipts.map(\.kind) == ["account.selected", "account.added"])
    }

    @Test("live shell service hub creates receipt loggers through the shared receipt-store seam")
    @MainActor
    func receiptEventLoggerFactoryUsesSharedReceiptStore() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let receiptLogger = ShellServiceHub.live.receiptEventLoggerFactory(context)
        let receiptStore = ShellServiceHub.live.receiptStoreFactory(context)

        _ = receiptLogger.recordCopyAction(
            subject: "nft.id",
            value: "nft-123",
            surface: "tests.boundary",
            correlationID: "shell-receipt-logger"
        )

        let receipts = try receiptStore.receipts(forCorrelationID: "shell-receipt-logger", limit: 10)
        #expect(receipts.count == 1)
        #expect(receipts.first?.trigger == "copy.performed")
    }

    @Test("live shell service hub creates token-holdings stores through the shared persistence seam")
    @MainActor
    func tokenHoldingsStoreFactoryPersistsNativeHoldings() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = ShellServiceHub.live.tokenHoldingsStoreFactory(context)

        try store.upsertNativeHolding(
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet,
            amountDisplay: "1.25 ETH",
            updatedAt: Date(timeIntervalSince1970: 123)
        )

        let holdings = try context.fetch(FetchDescriptor<TokenHolding>())
        #expect(holdings.count == 1)
        #expect(holdings.first?.balanceKind == .native)
        #expect(holdings.first?.amountDisplay == "1.25 ETH")
    }

    @Test("live shell service hub creates home pinned-items stores through the shared preference seam")
    @MainActor
    func homePinnedItemsStoreFactoryPersistsScopedPins() {
        let store = ShellServiceHub.live.homePinnedItemsStoreFactory()
        let accountAddress = "0x\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(40))"

        let isPinned = store.togglePin(.openSearch, accountAddress: accountAddress)

        #expect(isPinned)
        #expect(store.isPinned(.openSearch, accountAddress: accountAddress))
        #expect(store.pinnedCount(for: accountAddress) == 1)
    }
}
