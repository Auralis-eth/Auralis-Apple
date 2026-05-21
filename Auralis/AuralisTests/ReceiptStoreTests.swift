import ReceiptsCore
import ReceiptStorage
@testable import Auralis
import AuralisPrimaryModels
import Foundation
import SwiftData
import Testing

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
        return SwiftDataReceiptStore(
            modelContext: context,
            sequenceAllocator: ReceiptSequenceAllocator()
        )
    }

    @MainActor
    private func makeStoreWithInspectableIntegrityHeads() throws -> (
        store: SwiftDataReceiptStore,
        context: ModelContext,
        headStore: InMemoryReceiptIntegrityHeadStore
    ) {
        let container = try makeContainer()
        let context = ModelContext(container)
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let store = SwiftDataReceiptStore(
            modelContext: context,
            persistenceStore: ReceiptPersistenceStore(
                modelContainer: container,
                integrityHeadStore: headStore
            )
        )
        return (store, context, headStore)
    }

    @Test("append assigns monotonic sequence IDs and preserves caller-provided fields")
    @MainActor
    func appendAssignsSequenceIDs() async throws {
        let store = try makeStore()

        let first = try await store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 100),
                category: "accounts",
                kind: "account.added",
                correlationID: "flow-1",
                payload: ReceiptPayload(values: ["address": .string("0xabc")])
            )
        )
        let second = try await store.append(
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
        #expect(first.accountSequenceID == 1)
        #expect(second.accountSequenceID == 2)
        #expect(!first.payloadHash.isEmpty)
        #expect(first.previousReceiptHash == "GENESIS")
        #expect(!first.chainHash.isEmpty)
        #expect(second.previousReceiptHash == first.chainHash)
    }

    @Test("latest returns bounded receipts ordered by newest timestamp with sequence fallback for ties")
    @MainActor
    func latestUsesStableDescendingOrdering() async throws {
        let store = try makeStore()

        _ = try await store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 200),
                category: "networking",
                kind: "refresh.started",
                payload: ReceiptPayload(values: [:])
            )
        )
        let second = try await store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 200),
                category: "networking",
                kind: "refresh.progress",
                payload: ReceiptPayload(values: [:])
            )
        )
        let third = try await store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 300),
                category: "networking",
                kind: "refresh.finished",
                payload: ReceiptPayload(values: [:])
            )
        )

        let latest = try await store.latest(limit: 2)

        #expect(latest.map(\.sequenceID) == [third.sequenceID, second.sequenceID])
        #expect(latest.map(\.kind) == ["refresh.finished", "refresh.progress"])
    }

    @Test("correlation reads stay bounded and scoped to the caller-provided correlation ID")
    @MainActor
    func correlationReadsAreBounded() async throws {
        let store = try makeStore()

        _ = try await store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 100),
                category: "networking",
                kind: "refresh.started",
                correlationID: "refresh-1",
                payload: ReceiptPayload(values: [:])
            )
        )
        let matchingNewest = try await store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 200),
                category: "networking",
                kind: "refresh.finished",
                correlationID: "refresh-1",
                payload: ReceiptPayload(values: [:])
            )
        )
        _ = try await store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 300),
                category: "networking",
                kind: "refresh.started",
                correlationID: "refresh-2",
                payload: ReceiptPayload(values: [:])
            )
        )

        let correlated = try await store.receipts(forCorrelationID: "refresh-1", limit: 1)

        #expect(correlated.count == 1)
        #expect(correlated.first?.sequenceID == matchingNewest.sequenceID)
        #expect(correlated.first?.correlationID == "refresh-1")
    }

    @Test("exportAll returns every receipt in deterministic ascending order for JSON export")
    @MainActor
    func exportAllUsesDeterministicOrdering() async throws {
        let store = try makeStore()

        let first = try await store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 100),
                category: "accounts",
                kind: "account.added",
                payload: ReceiptPayload(values: ["step": .number(1)])
            )
        )
        let second = try await store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 100),
                category: "accounts",
                kind: "account.selected",
                payload: ReceiptPayload(values: ["step": .number(2)])
            )
        )

        let exportedData = try await store.exportAll()
        let records = try JSONDecoder().decode([ReceiptRecord].self, from: exportedData)

        #expect(records.map(\.sequenceID) == [first.sequenceID, second.sequenceID])
        #expect(records.map(\.kind) == ["account.added", "account.selected"])
    }

    @Test("exportAll emits the sanitized payloads exactly as persisted")
    @MainActor
    func exportAllUsesSanitizedPersistedPayloads() async throws {
        let store = try makeStore()
        let sanitizer = DefaultReceiptPayloadSanitizer()
        let sanitizedPayload = sanitizer.sanitize(
            RawReceiptPayload(
                fields: [
                    .public("rpcURL", string: "https://rpc.example/secret", kind: .url),
                    .public("error", string: "provider failure", kind: .errorMessage)
                ]
            )
        )

        _ = try await store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 100),
                category: "networking",
                kind: "refresh.failed",
                payload: sanitizedPayload
            )
        )

        let exportedData = try await store.exportAll()
        let records = try JSONDecoder().decode([ReceiptRecord].self, from: exportedData)

        #expect(records.count == 1)
        #expect(records.first?.payload.values["rpcURL"] == .string("<redacted-url>"))
        #expect(records.first?.payload.values["error"] == .string("<redacted-error>"))
    }

    @Test("resetAll wipes the receipt store without introducing any per-item delete API")
    @MainActor
    func resetAllRemovesEverything() async throws {
        let store = try makeStore()

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
                kind: "refresh.started",
                payload: ReceiptPayload(values: [:])
            )
        )

        try await store.resetAll()

        #expect(try await store.latest(limit: 10).isEmpty)
        let exportedData = try await store.exportAll()
        let records = try JSONDecoder().decode([ReceiptRecord].self, from: exportedData)
        #expect(records.isEmpty)
    }

    @Test("failed integrity head writes roll back the just-persisted receipt")
    @MainActor
    func failedIntegrityHeadWriteDoesNotLeavePersistedReceipt() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = SwiftDataReceiptStore(
            modelContext: context,
            persistenceStore: ReceiptPersistenceStore(
                modelContainer: container,
                integrityHeadStore: FailingReceiptIntegrityHeadStore(failOnSave: true)
            )
        )

        do {
            _ = try await store.append(
                ReceiptDraft(
                    createdAt: Date(timeIntervalSince1970: 100),
                    category: "accounts",
                    kind: "account.added",
                    payload: ReceiptPayload(values: [:])
                )
            )
            Issue.record("Expected receipt append to fail when the integrity head write fails.")
        } catch {
            #expect(try context.fetch(FetchDescriptor<StoredReceipt>()).isEmpty)
        }
    }

    @Test("receipt integrity verification fails when metadata is missing")
    @MainActor
    func integrityVerificationRejectsMissingMetadata() async throws {
        let (store, context, _) = try makeStoreWithInspectableIntegrityHeads()
        let accountAddress = "0x2222222222222222222222222222222222222222"

        _ = try await store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 100),
                category: "accounts",
                kind: "account.added",
                payload: ReceiptPayload(values: ["address": .string(accountAddress)]),
                timelineAccountAddress: accountAddress
            )
        )
        #expect(try await store.verifyIntegrity().isValid)

        let receipt = try #require(try context.fetch(
            FetchDescriptor<StoredReceipt>(
                sortBy: [SortDescriptor(\StoredReceipt.sequenceID)]
            )
        ).first)
        receipt.payloadHash = ""
        try context.save()

        let result = try await store.verifyIntegrity()
        #expect(result.isValid == false)
        #expect(result.failureReason == "Receipt \(receipt.id.uuidString) is missing integrity metadata.")
    }

    @Test("receipt integrity verification fails after out-of-band mutation or deletion")
    @MainActor
    func integrityVerificationDetectsTampering() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = SwiftDataReceiptStore(
            modelContext: context,
            sequenceAllocator: ReceiptSequenceAllocator()
        )
        let accountAddress = "0x1111111111111111111111111111111111111111"

        _ = try await store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 100),
                category: "accounts",
                kind: "account.added",
                payload: ReceiptPayload(values: ["address": .string(accountAddress)]),
                timelineAccountAddress: accountAddress
            )
        )
        _ = try await store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 101),
                category: "accounts",
                kind: "account.selected",
                payload: ReceiptPayload(values: ["address": .string(accountAddress)]),
                timelineAccountAddress: accountAddress
            )
        )

        #expect(try await store.verifyIntegrity().isValid)

        var descriptor = FetchDescriptor<StoredReceipt>(
            sortBy: [SortDescriptor(\StoredReceipt.sequenceID)]
        )
        descriptor.fetchLimit = 1
        let mutatedReceipt = try #require(context.fetch(descriptor).first)
        mutatedReceipt.summary = "mutated outside receipt store"
        try context.save()

        #expect(try await store.verifyIntegrity().isValid == false)

        try await store.resetAll()
        _ = try await store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 200),
                category: "accounts",
                kind: "account.added",
                payload: ReceiptPayload(values: ["address": .string(accountAddress)]),
                timelineAccountAddress: accountAddress
            )
        )
        _ = try await store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 201),
                category: "accounts",
                kind: "account.selected",
                payload: ReceiptPayload(values: ["address": .string(accountAddress)]),
                timelineAccountAddress: accountAddress
            )
        )

        let latestReceipt = try #require(
            context.fetch(
                FetchDescriptor<StoredReceipt>(
                    sortBy: [SortDescriptor(\StoredReceipt.sequenceID, order: .reverse)]
                )
            ).first
        )
        context.delete(latestReceipt)
        try context.save()

        #expect(try await store.verifyIntegrity().isValid == false)
    }

    @Test("receipt integrity verification fails when every receipt for an account is deleted out of band")
    @MainActor
    func integrityVerificationDetectsFullAccountReceiptDeletion() async throws {
        let (store, context, _) = try makeStoreWithInspectableIntegrityHeads()
        let accountAddress = "0x1111111111111111111111111111111111111111"

        _ = try await store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 100),
                category: "accounts",
                kind: "account.added",
                payload: ReceiptPayload(values: ["address": .string(accountAddress)]),
                timelineAccountAddress: accountAddress
            )
        )
        _ = try await store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 101),
                category: "accounts",
                kind: "account.selected",
                payload: ReceiptPayload(values: ["address": .string(accountAddress)]),
                timelineAccountAddress: accountAddress
            )
        )
        #expect(try await store.verifyIntegrity().isValid)

        for receipt in try context.fetch(FetchDescriptor<StoredReceipt>()) {
            context.delete(receipt)
        }
        try context.save()

        let result = try await store.verifyIntegrity()
        #expect(result.isValid == false)
        #expect(result.failureReason == "Receipt integrity has protected heads without persisted receipts.")
    }

    @Test("receipt integrity verification fails when one account's receipt chain is removed")
    @MainActor
    func integrityVerificationDetectsPartialAccountReceiptDeletion() async throws {
        let (store, context, _) = try makeStoreWithInspectableIntegrityHeads()
        let firstAccountAddress = "0x1111111111111111111111111111111111111111"
        let secondAccountAddress = "0x2222222222222222222222222222222222222222"

        _ = try await store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 100),
                category: "accounts",
                kind: "account.added",
                payload: ReceiptPayload(values: ["address": .string(firstAccountAddress)]),
                timelineAccountAddress: firstAccountAddress
            )
        )
        _ = try await store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 101),
                category: "accounts",
                kind: "account.added",
                payload: ReceiptPayload(values: ["address": .string(secondAccountAddress)]),
                timelineAccountAddress: secondAccountAddress
            )
        )
        #expect(try await store.verifyIntegrity().isValid)

        for receipt in try context.fetch(FetchDescriptor<StoredReceipt>()) where receipt.accountAddress == firstAccountAddress {
            context.delete(receipt)
        }
        try context.save()

        let result = try await store.verifyIntegrity()
        #expect(result.isValid == false)
        #expect(result.failureReason == "Receipt integrity has protected heads without persisted receipts.")
    }

    @Test("receipt integrity verification fails when persisted receipts lose their protected head")
    @MainActor
    func integrityVerificationDetectsMissingProtectedHead() async throws {
        let (store, _, headStore) = try makeStoreWithInspectableIntegrityHeads()
        let accountAddress = "0x1111111111111111111111111111111111111111"

        _ = try await store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 100),
                category: "accounts",
                kind: "account.added",
                payload: ReceiptPayload(values: ["address": .string(accountAddress)]),
                timelineAccountAddress: accountAddress
            )
        )
        #expect(try await store.verifyIntegrity().isValid)

        await headStore.clearHead(for: accountAddress)

        let result = try await store.verifyIntegrity()
        #expect(result.isValid == false)
        #expect(result.failureReason == "Receipt integrity has persisted receipts without protected heads.")
    }

    @Test("receipt integrity verification remains valid after an intentional full reset")
    @MainActor
    func integrityVerificationAcceptsIntentionalReset() async throws {
        let (store, _, _) = try makeStoreWithInspectableIntegrityHeads()
        let accountAddress = "0x1111111111111111111111111111111111111111"

        _ = try await store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 100),
                category: "accounts",
                kind: "account.added",
                payload: ReceiptPayload(values: ["address": .string(accountAddress)]),
                timelineAccountAddress: accountAddress
            )
        )
        #expect(try await store.verifyIntegrity().isValid)

        try await store.resetAll()

        #expect(try await store.verifyIntegrity().isValid)
    }
}

private actor FailingReceiptIntegrityHeadStore: ReceiptIntegrityHeadStoring {
    struct Failure: Error { }

    let failOnSave: Bool

    init(failOnSave: Bool) {
        self.failOnSave = failOnSave
    }

    func loadHead(for accountKey: String) throws -> String? {
        nil
    }

    func loadAllHeads() throws -> [String: String] {
        [:]
    }

    func saveHead(_ hash: String, for accountKey: String) throws {
        if failOnSave {
            throw Failure()
        }
    }

    func clearHead(for accountKey: String) throws { }

    func clearAllHeads() throws { }
}
