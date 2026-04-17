@testable import Auralis
import Foundation
import SwiftData
import Testing

@Suite
struct ReceiptResetServiceTests {
    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([StoredReceipt.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @MainActor
    private func makeStoreAndResetService() throws -> (SwiftDataReceiptStore, ReceiptResetService) {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = SwiftDataReceiptStore(
            modelContext: context,
            sequenceAllocator: ReceiptSequenceAllocator()
        )
        let resetService = ReceiptResetService(receiptStore: store)
        return (store, resetService)
    }

    @Test("explicit receipt reset wipes all persisted receipts through the destructive reset seam")
    @MainActor
    func resetServiceWipesAllReceipts() throws {
        let (store, resetService) = try makeStoreAndResetService()

        _ = try store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 100),
                category: "accounts",
                kind: "account.added",
                payload: ReceiptPayload(values: [:])
            )
        )
        _ = try store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 200),
                category: "networking",
                kind: "nft.refresh.started",
                correlationID: "refresh-1",
                payload: ReceiptPayload(values: [:])
            )
        )

        try resetService.resetReceipts()

        #expect(try store.latest(limit: 20).isEmpty)
        let exportedData = try store.exportAll()
        let exportedReceipts = try JSONDecoder().decode([ReceiptRecord].self, from: exportedData)
        #expect(exportedReceipts.isEmpty)
    }

    @Test("reset leaves the store clean enough for new appends to start a fresh sequence timeline")
    @MainActor
    func resetServiceAllowsFreshAppends() throws {
        let (store, resetService) = try makeStoreAndResetService()

        _ = try store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 100),
                category: "accounts",
                kind: "account.added",
                payload: ReceiptPayload(values: [:])
            )
        )

        try resetService.resetReceipts()

        let newReceipt = try store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 200),
                category: "accounts",
                kind: "account.selected",
                payload: ReceiptPayload(values: [:])
            )
        )

        #expect(newReceipt.sequenceID == 1)
        #expect(try store.latest(limit: 10).map(\.kind) == ["account.selected"])
    }
}
