import Foundation
import SwiftData

@MainActor
final class SwiftDataReceiptStore: ReceiptStore {
    private let modelContext: ModelContext
    private let sequenceAllocator: ReceiptSequenceAllocator

    init(
        modelContext: ModelContext,
        sequenceAllocator: ReceiptSequenceAllocator
    ) {
        self.modelContext = modelContext
        self.sequenceAllocator = sequenceAllocator
    }

    func append(_ receipt: ReceiptDraft) throws -> ReceiptRecord {
        let nextSequenceID = try sequenceAllocator.allocate(using: modelContext)
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
            details: receipt.details
        )

        modelContext.insert(storedReceipt)
        try modelContext.save()

        return try storedReceipt.asReceiptRecord()
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
            .map { try $0.asReceiptRecord() }
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
            .map { try $0.asReceiptRecord() }
    }

    func exportAll() throws -> Data {
        let descriptor = FetchDescriptor<StoredReceipt>(
            sortBy: [
                SortDescriptor(\StoredReceipt.createdAt),
                SortDescriptor(\StoredReceipt.sequenceID)
            ]
        )

        let records = try modelContext.fetch(descriptor).map { try $0.asReceiptRecord() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(records)
    }

    func resetAll() throws {
        let receipts = try modelContext.fetch(FetchDescriptor<StoredReceipt>())
        for receipt in receipts {
            modelContext.delete(receipt)
        }
        try modelContext.save()
        sequenceAllocator.reset()
    }
}

@MainActor
enum ReceiptStores {
    private static var cachedStores: [ObjectIdentifier: SwiftDataReceiptStore] = [:]
    private static var cachedAllocators: [ObjectIdentifier: ReceiptSequenceAllocator] = [:]

    static func live(modelContext: ModelContext) -> any ReceiptStore {
        let key = ObjectIdentifier(modelContext)
        if let cachedStore = cachedStores[key] {
            return cachedStore
        }

        let allocator: ReceiptSequenceAllocator
        if let cachedAllocator = cachedAllocators[key] {
            allocator = cachedAllocator
        } else {
            let newAllocator = ReceiptSequenceAllocator()
            cachedAllocators[key] = newAllocator
            allocator = newAllocator
        }

        let store = SwiftDataReceiptStore(
            modelContext: modelContext,
            sequenceAllocator: allocator
        )
        cachedStores[key] = store
        return store
    }
}

@MainActor
final class ReceiptSequenceAllocator {
    private var nextSequenceIDCache: Int?

    func allocate(using modelContext: ModelContext) throws -> Int {
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

    func reset() {
        nextSequenceIDCache = nil
    }
}

private extension StoredReceipt {
    func asReceiptRecord() throws -> ReceiptRecord {
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
            details: try decodedDetails()
        )
    }
}
