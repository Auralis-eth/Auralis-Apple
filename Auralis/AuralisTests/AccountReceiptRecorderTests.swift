import Foundation
import SwiftData
import Testing
@testable import Auralis

@Suite
struct AccountReceiptRecorderTests {
    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([EOAccount.self, NFT.self, Tag.self, StoredReceipt.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @Test("receipt-backed account recorder emits real receipts for account add select and remove flows")
    @MainActor
    func accountStoreWritesReceiptsThroughRecorderSeam() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let receiptStore = SwiftDataReceiptStore(modelContext: context)
        let recorder = ReceiptBackedAccountEventRecorder(
            receiptStore: receiptStore,
            payloadSanitizer: DefaultReceiptPayloadSanitizer()
        )
        let accountStore = AccountStore(modelContext: context, eventRecorder: recorder)

        let account = try accountStore.createWatchAccount(
            from: "0x1234567890abcdef1234567890abcdef12345678",
            now: Date(timeIntervalSince1970: 100)
        )
        _ = try accountStore.selectAccount(
            address: account.address,
            selectedAt: Date(timeIntervalSince1970: 200)
        )
        _ = try accountStore.removeAccount(
            address: account.address,
            activeAddress: account.address
        )

        let receipts = try receiptStore.latest(limit: 10)

        #expect(receipts.count == 3)
        #expect(receipts.map(\.kind) == [
            "account.removed",
            "account.selected",
            "account.added"
        ])
        #expect(receipts.allSatisfy { $0.category == "accounts" })
        #expect(receipts.map(\.sequenceID) == [3, 2, 1])
        #expect(receipts.allSatisfy {
            $0.payload.values["address"] == .string("0x1234567890abcdef1234567890abcdef12345678")
        })
    }
}
