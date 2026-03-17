import Foundation
import SwiftData
import Testing
@testable import Auralis

@Suite
struct StoredReceiptTests {
    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([StoredReceipt.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @Test("stored receipt persists contract fields and sanitized payload bytes")
    @MainActor
    func storedReceiptPersistsPayload() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let payload = ReceiptPayload(
            values: [
                "rpcURL": .string("<redacted-rpc-url>"),
                "error": .string("<redacted-error>"),
                "attempt": .number(2)
            ]
        )
        let receipt = try StoredReceipt(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            sequenceID: 7,
            createdAt: Date(timeIntervalSince1970: 789),
            category: "networking",
            kind: "nft.refresh.failed",
            correlationID: "refresh-7",
            payload: payload
        )

        context.insert(receipt)
        try context.save()

        let storedReceipts = try context.fetch(FetchDescriptor<StoredReceipt>())
        #expect(storedReceipts.count == 1)

        guard let storedReceipt = storedReceipts.first else {
            Issue.record("Expected one stored receipt")
            return
        }

        #expect(storedReceipt.id == UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)
        #expect(storedReceipt.sequenceID == 7)
        #expect(storedReceipt.createdAt == Date(timeIntervalSince1970: 789))
        #expect(storedReceipt.category == "networking")
        #expect(storedReceipt.kind == "nft.refresh.failed")
        #expect(storedReceipt.correlationID == "refresh-7")
        #expect(try storedReceipt.decodedPayload() == payload)
    }
}
