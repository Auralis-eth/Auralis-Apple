import AuralisPrimaryModels
import Foundation
import ReceiptStorage
import ReceiptsCore
import SwiftData
import Testing

@MainActor
@Suite
struct SwiftDataReceiptStorageTests {
    @Test("append receipt persists expected stored receipt")
    func appendPersistsStoredReceipt() async throws {
        let context = try makeContext()
        let store = SwiftDataReceiptStore(
            modelContext: context,
            sequenceAllocator: ReceiptSequenceAllocator()
        )

        let record = try await store.append(makeDraft(kind: "account.added", correlationID: "flow-1"))
        let storedReceipts = try context.fetch(FetchDescriptor<StoredReceipt>())

        #expect(record.sequenceID == 1)
        #expect(storedReceipts.count == 1)
        #expect(storedReceipts.first?.trigger == "account.added")
        #expect(storedReceipts.first?.correlationID == "flow-1")
    }

    @Test("fetch and export ordering match receipt timeline behavior")
    func fetchAndExportOrdering() async throws {
        let context = try makeContext()
        let store = SwiftDataReceiptStore(
            modelContext: context,
            sequenceAllocator: ReceiptSequenceAllocator()
        )

        let first = try await store.append(
            makeDraft(createdAt: Date(timeIntervalSince1970: 100), kind: "first")
        )
        let second = try await store.append(
            makeDraft(createdAt: Date(timeIntervalSince1970: 100), kind: "second")
        )
        let newest = try await store.append(
            makeDraft(createdAt: Date(timeIntervalSince1970: 300), kind: "newest")
        )

        let latest = try await store.latest(limit: 2)
        let exportedRecords = try JSONDecoder().decode([ReceiptRecord].self, from: try await store.exportAll())

        #expect(latest.map(\.sequenceID) == [newest.sequenceID, second.sequenceID])
        #expect(exportedRecords.map(\.sequenceID) == [first.sequenceID, second.sequenceID, newest.sequenceID])
    }

    @Test("reset deletes persisted receipts and restarts sequence allocation")
    func resetDeletesPersistedReceipts() async throws {
        let context = try makeContext()
        let store = SwiftDataReceiptStore(
            modelContext: context,
            sequenceAllocator: ReceiptSequenceAllocator()
        )
        let resetService = SwiftDataReceiptResetService(modelContext: context)

        _ = try await store.append(makeDraft(kind: "first"))
        _ = try await store.append(makeDraft(kind: "second"))

        try await resetService.resetReceipts()
        let replacement = try await store.append(makeDraft(kind: "replacement"))

        #expect(try context.fetch(FetchDescriptor<StoredReceipt>()).map(\.trigger) == ["replacement"])
        #expect(replacement.sequenceID == 1)
    }

    @Test("reset handles inserted unsaved receipts in the main context")
    func resetHandlesInsertedUnsavedReceipts() async throws {
        let context = try makeContext()
        let resetService = SwiftDataReceiptResetService(modelContext: context)
        context.insert(try makeStoredReceipt(sequenceID: 99, kind: "unsaved"))

        try await resetService.resetReceipts()

        #expect(try context.fetch(FetchDescriptor<StoredReceipt>()).isEmpty)
    }

    @Test("receipt event logger sanitizes payloads with moved store")
    func loggerSanitizesThroughMovedStore() async throws {
        let context = try makeContext()
        let store = SwiftDataReceiptStore(
            modelContext: context,
            sequenceAllocator: ReceiptSequenceAllocator()
        )
        let logger = ReceiptEventLogger(receiptStore: store)

        _ = try await logger.append(
            trigger: "network.failed",
            scope: "networking",
            summary: "Network request failed",
            provenance: "test",
            rawPayload: RawReceiptPayload(
                fields: [
                    .public("url", string: "https://rpc.example/secret", kind: .url),
                    .public("error", string: "provider failed", kind: .errorMessage)
                ]
            )
        )

        let receipt = try #require(try await store.latest(limit: 1).first)
        #expect(receipt.details.values["url"] == .string("<redacted-url>"))
        #expect(receipt.details.values["error"] == .string("<redacted-error>"))
    }
}

private func makeContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: Schema([StoredReceipt.self]),
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return ModelContext(container)
}

private func makeDraft(
    createdAt: Date = Date(timeIntervalSince1970: 100),
    kind: String,
    correlationID: String? = nil
) -> ReceiptDraft {
    ReceiptDraft(
        createdAt: createdAt,
        category: "accounts",
        kind: kind,
        correlationID: correlationID,
        payload: ReceiptPayload(values: ["address": .string("0xabc")])
    )
}

private func makeStoredReceipt(
    sequenceID: Int,
    kind: String
) throws -> StoredReceipt {
    try StoredReceipt(
        sequenceID: sequenceID,
        createdAt: Date(timeIntervalSince1970: 100),
        actor: .system,
        mode: .observe,
        trigger: kind,
        scope: "accounts",
        summary: "Fixture",
        provenance: "test",
        isSuccess: true,
        correlationID: nil,
        timelineAccountAddress: nil,
        timelineChainRawValue: nil,
        accountSequenceID: sequenceID,
        payloadHash: "payload-hash-\(sequenceID)",
        previousReceiptHash: "previous-hash-\(sequenceID)",
        chainHash: "chain-hash-\(sequenceID)",
        details: ReceiptPayload(values: [:])
    )
}
