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

    @MainActor
    private func makePersistentContainer(at storeURL: URL) throws -> ModelContainer {
        let schema = Schema([StoredReceipt.self])
        let configuration = ModelConfiguration(url: storeURL)
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

    @Test("stored receipts persist across container recreation to simulate app relaunch")
    @MainActor
    func storedReceiptPersistsAcrossRelaunch() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoredReceiptTests-\(UUID().uuidString)")
            .appendingPathExtension("store")

        defer {
            try? FileManager.default.removeItem(at: storeURL)
        }

        do {
            let firstContainer = try makePersistentContainer(at: storeURL)
            let firstContext = ModelContext(firstContainer)
            let receipt = try StoredReceipt(
                id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                sequenceID: 11,
                createdAt: Date(timeIntervalSince1970: 999),
                category: "accounts",
                kind: "account.selected",
                correlationID: "flow-11",
                payload: ReceiptPayload(values: [
                    "address": .string("0x1234567890abcdef1234567890abcdef12345678")
                ])
            )

            firstContext.insert(receipt)
            try firstContext.save()
        }

        let relaunchedContainer = try makePersistentContainer(at: storeURL)
        let relaunchedContext = ModelContext(relaunchedContainer)
        let receipts = try relaunchedContext.fetch(FetchDescriptor<StoredReceipt>())

        #expect(receipts.count == 1)

        guard let receipt = receipts.first else {
            Issue.record("Expected one relaunched receipt")
            return
        }

        #expect(receipt.id == UUID(uuidString: "33333333-3333-3333-3333-333333333333")!)
        #expect(receipt.sequenceID == 11)
        #expect(receipt.kind == "account.selected")
        #expect(receipt.correlationID == "flow-11")
        #expect(try receipt.decodedPayload().values["address"] == .string("0x1234567890abcdef1234567890abcdef12345678"))
    }
}
