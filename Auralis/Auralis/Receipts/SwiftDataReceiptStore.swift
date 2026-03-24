import Foundation
import SwiftData

@MainActor
final class SwiftDataReceiptStore: ReceiptStore {
    private let modelContext: ModelContext
    private var nextSequenceIDCache: Int?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func append(_ receipt: ReceiptDraft) throws -> ReceiptRecord {
        let nextSequenceID = try nextSequenceID()
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
        nextSequenceIDCache = 1
    }
}

@MainActor
enum ReceiptStores {
    static func live(modelContext: ModelContext) -> any ReceiptStore {
        SwiftDataReceiptStore(modelContext: modelContext)
    }
}

private extension SwiftDataReceiptStore {
    func nextSequenceID() throws -> Int {
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
