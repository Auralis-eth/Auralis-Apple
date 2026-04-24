import Foundation
import SwiftData

@ModelActor
actor ReceiptPersistenceStore {
    private var nextSequenceIDCache: Int?

    func append(_ receipt: ReceiptDraft) throws -> ReceiptRecord {
        let nextSequenceID = try allocateSequenceID()
        let storedReceipt = try StoredReceipt(
            sequenceID: nextSequenceID,
            createdAt: receipt.createdAt,
            actor: receipt.actor,
            mode: receipt.mode,
            trigger: receipt.trigger,
            scope: receipt.scope,
            summary: receipt.summary,
            provenance: receipt.provenance,
            isSuccess: receipt.isSuccess,
            correlationID: receipt.correlationID,
            timelineAccountAddress: receipt.timelineAccountAddress,
            timelineChainRawValue: receipt.timelineChainRawValue,
            details: receipt.details
        )

        modelContext.insert(storedReceipt)
        try modelContext.save()
        return storedReceipt.asReceiptRecord()
    }

    func resetAll() throws {
        let receipts = try modelContext.fetch(FetchDescriptor<StoredReceipt>())
        for receipt in receipts {
            modelContext.delete(receipt)
        }
        try modelContext.save()
        nextSequenceIDCache = nil
    }

    private func allocateSequenceID() throws -> Int {
        if let nextSequenceIDCache {
            self.nextSequenceIDCache = nextSequenceIDCache + 1
            return nextSequenceIDCache
        }

        let descriptor = FetchDescriptor<StoredReceipt>(
            sortBy: [SortDescriptor(\StoredReceipt.sequenceID, order: .reverse)]
        )

        let nextSequenceID = (try modelContext.fetch(descriptor).first?.sequenceID ?? 0) + 1
        nextSequenceIDCache = nextSequenceID + 1
        return nextSequenceID
    }
}

@MainActor
final class SwiftDataReceiptStore: ReceiptStore {
    private let modelContext: ModelContext
    private let persistenceStore: ReceiptPersistenceStore

    init(
        modelContext: ModelContext,
        persistenceStore: ReceiptPersistenceStore
    ) {
        self.modelContext = modelContext
        self.persistenceStore = persistenceStore
    }

    convenience init(
        modelContext: ModelContext,
        sequenceAllocator: ReceiptSequenceAllocator
    ) {
        self.init(
            modelContext: modelContext,
            persistenceStore: ReceiptPersistenceStore(modelContainer: modelContext.container)
        )
    }

    func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord {
        try await persistenceStore.append(receipt)
    }

    func latest(limit: Int) throws -> [ReceiptRecord] {
        guard limit > 0 else {
            return []
        }

        let descriptor = FetchDescriptor<StoredReceipt>(
            sortBy: [
                SortDescriptor(\StoredReceipt.createdAt, order: .reverse),
                SortDescriptor(\StoredReceipt.sequenceID, order: .reverse)
            ]
        )

        return try modelContext.fetch(descriptor)
            .prefix(limit)
            .map { $0.asReceiptRecord() }
    }

    func receipts(
        forCorrelationID correlationID: String,
        limit: Int
    ) throws -> [ReceiptRecord] {
        guard limit > 0 else {
            return []
        }

        let correlationValue = correlationID
        let descriptor = FetchDescriptor<StoredReceipt>(
            predicate: #Predicate<StoredReceipt> { receipt in
                receipt.correlationID == correlationValue
            },
            sortBy: [
                SortDescriptor(\StoredReceipt.createdAt, order: .reverse),
                SortDescriptor(\StoredReceipt.sequenceID, order: .reverse)
            ]
        )

        return try modelContext.fetch(descriptor)
            .prefix(limit)
            .map { $0.asReceiptRecord() }
    }

    func exportAll() throws -> Data {
        let descriptor = FetchDescriptor<StoredReceipt>(
            sortBy: [
                SortDescriptor(\StoredReceipt.createdAt),
                SortDescriptor(\StoredReceipt.sequenceID)
            ]
        )

        let records = try modelContext.fetch(descriptor).map { $0.asReceiptRecord() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(records)
    }

    func resetAll() async throws {
        try await persistenceStore.resetAll()
    }
}

final class ReceiptSequenceAllocator {
    init() { }
}

@MainActor
enum ReceiptStores {
    // These caches are keyed by long-lived shell-owned ModelContext instances.
    // We intentionally keep one receipt store and sequence allocator per context
    // rather than evicting aggressively, because churning either object would
    // break receipt ordering guarantees within that context.
    private static var cachedStores: [ObjectIdentifier: SwiftDataReceiptStore] = [:]
    private static var cachedPersistenceStores: [ObjectIdentifier: ReceiptPersistenceStore] = [:]

    static func live(modelContext: ModelContext) -> any ReceiptStore {
        let key = ObjectIdentifier(modelContext)
        if let cachedStore = cachedStores[key] {
            return cachedStore
        }

        let persistenceStore: ReceiptPersistenceStore
        if let cachedPersistenceStore = cachedPersistenceStores[key] {
            persistenceStore = cachedPersistenceStore
        } else {
            let newPersistenceStore = ReceiptPersistenceStore(modelContainer: modelContext.container)
            cachedPersistenceStores[key] = newPersistenceStore
            persistenceStore = newPersistenceStore
        }

        let store = SwiftDataReceiptStore(
            modelContext: modelContext,
            persistenceStore: persistenceStore
        )
        cachedStores[key] = store
        return store
    }
}

private extension StoredReceipt {
    func asReceiptRecord() -> ReceiptRecord {
        ReceiptRecord(
            id: id,
            sequenceID: sequenceID,
            createdAt: createdAt,
            actor: actor,
            mode: mode,
            trigger: trigger,
            scope: scope,
            summary: summary,
            provenance: provenance,
            isSuccess: isSuccess,
            correlationID: correlationID,
            details: decodedDetailsOrEmpty()
        )
    }
}
