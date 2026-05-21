import AuralisPrimaryModels
import Foundation
import PolicyCore
import ReceiptsCore
import Testing

@MainActor
@Suite
struct ActionPolicyGateReceiptTests {
    @Test("denied high-risk actions append denied policy receipts")
    func deniedHighRiskActionAppendsReceipt() async throws {
        let store = RecordingReceiptStore()

        let result = await ActionPolicyGate.attempt(
            .approveSpending,
            mode: .observe,
            receiptStore: store
        )

        let receipt = try #require(store.appendedReceipts.first)
        #expect(result.isAllowed == false)
        #expect(receipt.trigger == "policy.denied")
        #expect(receipt.scope == "policy")
        #expect(receipt.mode == .observe)
        #expect(receipt.isSuccess == false)
        #expect(receipt.details.values["action"] == .string("approve_spending"))
        #expect(receipt.details.values["decision"] == .string("denied"))
        #expect(receipt.details.values["policy_denied"] == .bool(true))
        #expect(receipt.details.values["policy_approved"] == .bool(false))
    }

    @Test("plugin actions are denied in Observe mode and append denied policy receipts")
    func observeModePluginActionAppendsDeniedReceipt() async throws {
        let store = RecordingReceiptStore()

        let result = await ActionPolicyGate.attempt(
            .runPlugin,
            mode: .observe,
            receiptStore: store
        )

        let receipt = try #require(store.appendedReceipts.first)
        #expect(result.isAllowed == false)
        #expect(result.userMessage == "Not available in Observe mode")
        #expect(receipt.trigger == "policy.denied")
        #expect(receipt.scope == "policy")
        #expect(receipt.mode == .observe)
        #expect(receipt.isSuccess == false)
        #expect(receipt.details.values["action"] == .string("run_plugin"))
        #expect(receipt.details.values["decision"] == .string("denied"))
        #expect(receipt.details.values["policy_denied"] == .bool(true))
        #expect(receipt.details.values["policy_approved"] == .bool(false))
    }
}

@MainActor
private final class RecordingReceiptStore: ReceiptStore {
    private(set) var appendedReceipts: [ReceiptDraft] = []

    func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord {
        appendedReceipts.append(receipt)
        return ReceiptRecord(
            id: UUID(),
            sequenceID: appendedReceipts.count,
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
    }

    func latest(limit: Int) async throws -> [ReceiptRecord] {
        []
    }

    func receipts(forCorrelationID correlationID: String, limit: Int) async throws -> [ReceiptRecord] {
        []
    }

    func exportAll() async throws -> Data {
        Data()
    }

    func resetAll() async throws { }
}
