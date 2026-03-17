import Foundation
import SwiftData

@MainActor
final class SwiftDataReceiptStore: ReceiptStore {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func append(_ receipt: ReceiptDraft) throws -> ReceiptRecord {
        let nextSequenceID = try nextSequenceID()
        let storedReceipt = try StoredReceipt(
            sequenceID: nextSequenceID,
            createdAt: receipt.createdAt,
            category: receipt.category,
            kind: receipt.kind,
            correlationID: receipt.correlationID,
            payload: receipt.payload
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
        return try JSONEncoder().encode(records)
    }

    func resetAll() throws {
        let receipts = try modelContext.fetch(FetchDescriptor<StoredReceipt>())
        for receipt in receipts {
            modelContext.delete(receipt)
        }
        try modelContext.save()
    }
}

private extension SwiftDataReceiptStore {
    func nextSequenceID() throws -> Int {
        let descriptor = FetchDescriptor<StoredReceipt>(
            sortBy: [SortDescriptor(\StoredReceipt.sequenceID, order: .reverse)]
        )

        return (try modelContext.fetch(descriptor).first?.sequenceID ?? 0) + 1
    }
}

private extension StoredReceipt {
    func asReceiptRecord() throws -> ReceiptRecord {
        ReceiptRecord(
            id: id,
            sequenceID: sequenceID,
            createdAt: createdAt,
            category: category,
            kind: kind,
            correlationID: correlationID,
            payload: try decodedPayload()
        )
    }
}
