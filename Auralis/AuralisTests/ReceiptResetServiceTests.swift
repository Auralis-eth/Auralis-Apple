import ReceiptsCore
import ReceiptStorage
@testable import Auralis
import AuralisPrimaryModels
import Foundation
import SwiftData
import Testing

struct ReceiptResetServiceTests {
    @MainActor
    private func makeStoreAndResetService() throws -> (SwiftDataReceiptStore, SwiftDataReceiptResetService) {
        let container = try TestModelContainers.inMemory(TestSchemas.receipts)
        let context = ModelContext(container)
        let store = SwiftDataReceiptStore(
            modelContext: context,
            sequenceAllocator: ReceiptSequenceAllocator()
        )
        let resetService = SwiftDataReceiptResetService(receiptStore: store)
        return (store, resetService)
    }

    @Test("explicit receipt reset wipes all persisted receipts through the destructive reset seam")
    @MainActor
    func resetServiceWipesAllReceipts() async throws {
        let (store, resetService) = try makeStoreAndResetService()

        _ = try await store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 100),
                category: "accounts",
                kind: "account.added",
                payload: ReceiptPayload(values: [:])
            )
        )
        _ = try await store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 200),
                category: "networking",
                kind: "nft.refresh.started",
                correlationID: "refresh-1",
                payload: ReceiptPayload(values: [:])
            )
        )

        try await resetService.resetReceipts()

        #expect(try await store.latest(limit: 20).isEmpty)
        let exportedData = try await store.exportAll()
        let exportedReceipts = try JSONDecoder().decode([ReceiptRecord].self, from: exportedData)
        #expect(exportedReceipts.isEmpty)
    }

    @Test("reset leaves the store clean enough for new appends to start a fresh sequence timeline")
    @MainActor
    func resetServiceAllowsFreshAppends() async throws {
        let (store, resetService) = try makeStoreAndResetService()

        _ = try await store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 100),
                category: "accounts",
                kind: "account.added",
                payload: ReceiptPayload(values: [:])
            )
        )

        try await resetService.resetReceipts()

        let newReceipt = try await store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 200),
                category: "accounts",
                kind: "account.selected",
                payload: ReceiptPayload(values: [:])
            )
        )

        #expect(newReceipt.sequenceID == 1)
        #expect(try await store.latest(limit: 10).map(\.kind) == ["account.selected"])
    }
}
