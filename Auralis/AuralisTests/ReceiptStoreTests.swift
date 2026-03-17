import Foundation
import SwiftData
import Testing
@testable import Auralis

@Suite
struct ReceiptStoreTests {
    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([StoredReceipt.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @MainActor
    private func makeStore() throws -> SwiftDataReceiptStore {
        let container = try makeContainer()
        let context = ModelContext(container)
        return SwiftDataReceiptStore(modelContext: context)
    }

    @Test("append assigns monotonic sequence IDs and preserves caller-provided fields")
    @MainActor
    func appendAssignsSequenceIDs() throws {
        let store = try makeStore()

        let first = try store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 100),
                category: "accounts",
                kind: "account.added",
                correlationID: "flow-1",
                payload: ReceiptPayload(values: ["address": .string("0xabc")])
            )
        )
        let second = try store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 101),
                category: "accounts",
                kind: "account.selected",
                correlationID: "flow-1",
                payload: ReceiptPayload(values: ["address": .string("0xabc")])
            )
        )

        #expect(first.sequenceID == 1)
        #expect(second.sequenceID == 2)
        #expect(first.category == "accounts")
        #expect(second.kind == "account.selected")
        #expect(second.correlationID == "flow-1")
    }

    @Test("latest returns bounded receipts ordered by newest timestamp with sequence fallback for ties")
    @MainActor
    func latestUsesStableDescendingOrdering() throws {
        let store = try makeStore()

        _ = try store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 200),
                category: "networking",
                kind: "refresh.started",
                payload: ReceiptPayload(values: [:])
            )
        )
        let second = try store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 200),
                category: "networking",
                kind: "refresh.progress",
                payload: ReceiptPayload(values: [:])
            )
        )
        let third = try store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 300),
                category: "networking",
                kind: "refresh.finished",
                payload: ReceiptPayload(values: [:])
            )
        )

        let latest = try store.latest(limit: 2)

        #expect(latest.map(\.sequenceID) == [third.sequenceID, second.sequenceID])
        #expect(latest.map(\.kind) == ["refresh.finished", "refresh.progress"])
    }

    @Test("correlation reads stay bounded and scoped to the caller-provided correlation ID")
    @MainActor
    func correlationReadsAreBounded() throws {
        let store = try makeStore()

        _ = try store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 100),
                category: "networking",
                kind: "refresh.started",
                correlationID: "refresh-1",
                payload: ReceiptPayload(values: [:])
            )
        )
        let matchingNewest = try store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 200),
                category: "networking",
                kind: "refresh.finished",
                correlationID: "refresh-1",
                payload: ReceiptPayload(values: [:])
            )
        )
        _ = try store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 300),
                category: "networking",
                kind: "refresh.started",
                correlationID: "refresh-2",
                payload: ReceiptPayload(values: [:])
            )
        )

        let correlated = try store.receipts(forCorrelationID: "refresh-1", limit: 1)

        #expect(correlated.count == 1)
        #expect(correlated.first?.sequenceID == matchingNewest.sequenceID)
        #expect(correlated.first?.correlationID == "refresh-1")
    }

    @Test("exportAll returns every receipt in deterministic ascending order for JSON export")
    @MainActor
    func exportAllUsesDeterministicOrdering() throws {
        let store = try makeStore()

        let first = try store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 100),
                category: "accounts",
                kind: "account.added",
                payload: ReceiptPayload(values: ["step": .number(1)])
            )
        )
        let second = try store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 100),
                category: "accounts",
                kind: "account.selected",
                payload: ReceiptPayload(values: ["step": .number(2)])
            )
        )

        let exportedData = try store.exportAll()
        let records = try JSONDecoder().decode([ReceiptRecord].self, from: exportedData)

        #expect(records.map(\.sequenceID) == [first.sequenceID, second.sequenceID])
        #expect(records.map(\.kind) == ["account.added", "account.selected"])
    }

    @Test("resetAll wipes the receipt store without introducing any per-item delete API")
    @MainActor
    func resetAllRemovesEverything() throws {
        let store = try makeStore()

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
                kind: "refresh.started",
                payload: ReceiptPayload(values: [:])
            )
        )

        try store.resetAll()

        #expect(try store.latest(limit: 10).isEmpty)
        let exportedData = try store.exportAll()
        let records = try JSONDecoder().decode([ReceiptRecord].self, from: exportedData)
        #expect(records.isEmpty)
    }
}
