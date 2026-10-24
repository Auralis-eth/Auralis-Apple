@testable import Auralis
import AuralisPrimaryModels
import Foundation
import ReceiptsCore
import ReceiptStorage
import SwiftData
import Testing

struct ReceiptResetServiceTests {
    @MainActor
    private func makeStoreAndResetService() throws -> (SwiftDataReceiptStore, SwiftDataReceiptResetService) {
        let container = try TestModelContainers.inMemory(TestSchemas.receipts)
        let context = ModelContext(container)
        let store = SwiftDataReceiptStore(
            modelContext: context
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
                correlationID: nil,
                payload: ReceiptPayload(values: [:]),
                actorDetail: .system,
                authorityDetail: nil
            )
        )
        _ = try await store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 200),
                category: "networking",
                kind: "nft.refresh.started",
                correlationID: "refresh-1",
                payload: ReceiptPayload(values: [:]),
                actorDetail: .system,
                authorityDetail: nil
            )
        )

        try await resetService.resetReceipts()

        #expect(try await store.latest(limit: 20).isEmpty)
        let exportedData = try await store.exportAll()
        let exportedReceipts = try ReceiptCanonicalJSON.decoder().decode(ReceiptProvenanceExport.self, from: exportedData).records
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
                correlationID: nil,
                payload: ReceiptPayload(values: [:]),
                actorDetail: .system,
                authorityDetail: nil
            )
        )

        try await resetService.resetReceipts()

        let newReceipt = try await store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 200),
                category: "accounts",
                kind: "account.selected",
                correlationID: nil,
                payload: ReceiptPayload(values: [:]),
                actorDetail: .system,
                authorityDetail: nil
            )
        )

        #expect(newReceipt.sequenceID == 1)
        #expect(try await store.latest(limit: 10).map(\.kind) == ["account.selected"])
    }
}
