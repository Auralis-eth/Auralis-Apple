import AuralisPrimaryModels
import Foundation
import ReceiptsCore
import SwiftData
import SwiftDataAdapters

@ModelActor
public actor ReceiptPersistenceStore {
    private var nextSequenceIDCache: Int?

    public func append(_ receipt: ReceiptDraft) throws -> ReceiptRecord {
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

    public func resetAll() throws {
        try modelContext.performRollbackSafeMutation {
            for receipt in try modelContext.fetch(FetchDescriptor<StoredReceipt>()) {
                modelContext.delete(receipt)
            }
        }
        nextSequenceIDCache = nil
    }

    private func allocateSequenceID() throws -> Int {
        if let nextSequenceIDCache {
            self.nextSequenceIDCache = nextSequenceIDCache + 1
            return nextSequenceIDCache
        }

        var descriptor = FetchDescriptor<StoredReceipt>(
            sortBy: [SortDescriptor(\StoredReceipt.sequenceID, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        let nextSequenceID = (try modelContext.fetch(descriptor).first?.sequenceID ?? 0) + 1
        nextSequenceIDCache = nextSequenceID + 1
        return nextSequenceID
    }
}

@MainActor
public final class SwiftDataReceiptStore: ReceiptStore {
    private let modelContext: ModelContext
    private let persistenceStore: ReceiptPersistenceStore

    public init(
        modelContext: ModelContext,
        persistenceStore: ReceiptPersistenceStore
    ) {
        self.modelContext = modelContext
        self.persistenceStore = persistenceStore
    }

    public convenience init(
        modelContext: ModelContext,
        sequenceAllocator: ReceiptSequenceAllocator
    ) {
        self.init(
            modelContext: modelContext,
            persistenceStore: ReceiptStores.persistenceStore(for: modelContext)
        )
    }

    public func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord {
        try await persistenceStore.append(receipt)
    }

    public func latest(limit: Int) throws -> [ReceiptRecord] {
        guard limit > 0 else {
            return []
        }

        var descriptor = FetchDescriptor<StoredReceipt>(
            sortBy: [
                SortDescriptor(\StoredReceipt.createdAt, order: .reverse),
                SortDescriptor(\StoredReceipt.sequenceID, order: .reverse)
            ]
        )
        descriptor.fetchLimit = limit

        return try modelContext.fetch(descriptor).map { $0.asReceiptRecord() }
    }

    public func receipts(
        forCorrelationID correlationID: String,
        limit: Int
    ) throws -> [ReceiptRecord] {
        guard limit > 0 else {
            return []
        }

        let correlationValue = correlationID
        var descriptor = FetchDescriptor<StoredReceipt>(
            predicate: #Predicate<StoredReceipt> { receipt in
                receipt.correlationID == correlationValue
            },
            sortBy: [
                SortDescriptor(\StoredReceipt.createdAt, order: .reverse),
                SortDescriptor(\StoredReceipt.sequenceID, order: .reverse)
            ]
        )
        descriptor.fetchLimit = limit

        return try modelContext.fetch(descriptor).map { $0.asReceiptRecord() }
    }

    public func exportAll() throws -> Data {
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

    public func resetAll() async throws {
        try await persistenceStore.resetAll()
    }
}

public final class ReceiptSequenceAllocator {
    public init() { }
}

@MainActor
public enum ReceiptStores {
    // These caches are keyed by long-lived shell-owned ModelContext instances.
    // We intentionally keep one receipt store and sequence allocator per context
    // rather than evicting aggressively, because churning either object would
    // break receipt ordering guarantees within that context.
    private static var cachedStores: [ObjectIdentifier: SwiftDataReceiptStore] = [:]
    private static var cachedPersistenceStores: [ObjectIdentifier: ReceiptPersistenceStore] = [:]

    public static func live(modelContext: ModelContext) -> any ReceiptStore {
        let key = ObjectIdentifier(modelContext)
        if let cachedStore = cachedStores[key] {
            return cachedStore
        }

        let store = SwiftDataReceiptStore(
            modelContext: modelContext,
            persistenceStore: persistenceStore(for: modelContext)
        )
        cachedStores[key] = store
        return store
    }

    static func persistenceStore(for modelContext: ModelContext) -> ReceiptPersistenceStore {
        let key = ObjectIdentifier(modelContext.container)
        if let cachedPersistenceStore = cachedPersistenceStores[key] {
            return cachedPersistenceStore
        }

        let newPersistenceStore = ReceiptPersistenceStore(modelContainer: modelContext.container)
        cachedPersistenceStores[key] = newPersistenceStore
        return newPersistenceStore
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
