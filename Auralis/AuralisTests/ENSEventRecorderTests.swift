import Foundation
import SwiftData
import Testing
@testable import Auralis

@Suite
struct ENSEventRecorderTests {
    @MainActor
    private func makeReceiptStore() throws -> any ReceiptStore {
        let schema = Schema([StoredReceipt.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        return SwiftDataReceiptStore(
            modelContext: context,
            sequenceAllocator: ReceiptSequenceAllocator()
        )
    }

    @Test("ENS receipt recorder emits sanitized cache start success mapping and failure receipts")
    @MainActor
    func ensRecorderWritesExpectedReceipts() async throws {
        let store = try makeReceiptStore()
        let recorder = ReceiptBackedENSEventRecorder(
            receiptStore: store,
            payloadSanitizer: DefaultReceiptPayloadSanitizer()
        )
        let fetchedAt = Date(timeIntervalSince1970: 123)

        await recorder.recordCacheHit(
            kind: "forward",
            key: "vitalik.eth",
            fetchedAt: fetchedAt,
            correlationID: "ens-flow"
        )
        await recorder.recordLookupStarted(
            kind: "forward",
            key: "vitalik.eth",
            correlationID: "ens-flow"
        )
        await recorder.recordLookupSucceeded(
            kind: "forward",
            key: "vitalik.eth",
            value: "0x1234567890abcdef1234567890abcdef12345678",
            verification: nil,
            correlationID: "ens-flow"
        )
        await recorder.recordMappingChanged(
            kind: "forward",
            key: "vitalik.eth",
            oldValue: "0x1234567890abcdef1234567890abcdef12345678",
            newValue: "0x9999999999999999999999999999999999999999",
            correlationID: "ens-flow"
        )
        await recorder.recordLookupFailed(
            kind: "forward",
            key: "vitalik.eth",
            correlationID: "ens-flow",
            error: StubError.rpcFailure
        )

        let receipts = try store.receipts(forCorrelationID: "ens-flow", limit: 10)

        #expect(receipts.map { $0.trigger } == [
            "ens.forward.failed",
            "ens.forward.mapping_changed",
            "ens.forward.succeeded",
            "ens.forward.started",
            "ens.forward.cache_hit"
        ])
        #expect(receipts.allSatisfy { $0.scope == "identity.ens" })
        #expect(receipts.first?.details.values["error"] == ReceiptJSONValue.string("<redacted-error>"))
        #expect(receipts.last?.details.values["fetchedAt"] == ReceiptJSONValue.string("1970-01-01T00:02:03Z"))
    }
}

private enum StubError: Error {
    case rpcFailure
}
