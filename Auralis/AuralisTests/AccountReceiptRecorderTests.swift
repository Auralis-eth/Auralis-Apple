import ReceiptsCore
import ReceiptStorage
@testable import Auralis
import AccountStorage
import AccountsCore
import AccountsFeature
import AuralisPrimaryModels
import Foundation
import PolicyCore
import SwiftData
import Testing

@Suite
struct AccountReceiptRecorderTests {
    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: PrimaryStoreSchema.schema,
            configurations: [configuration]
        )
    }

    @Test("receipt-backed account recorder emits real receipts for account add select and remove flows")
    @MainActor
    func accountStoreWritesReceiptsThroughRecorderSeam() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let receiptStore = SwiftDataReceiptStore(
            modelContext: context,
            sequenceAllocator: ReceiptSequenceAllocator()
        )
        let recorder = ReceiptBackedAccountEventRecorder(
            receiptStore: receiptStore,
            payloadSanitizer: DefaultReceiptPayloadSanitizer()
        )
        let accountStore = SwiftDataAccountStore(modelContext: context, eventRecorder: recorder)

        let account = try await accountStore.createWatchAccount(
            from: "0x1234567890abcdef1234567890abcdef12345678",
            now: Date(timeIntervalSince1970: 100)
        )
        _ = try await accountStore.selectAccount(
            address: account.address,
            selectedAt: Date(timeIntervalSince1970: 200)
        )
        _ = try await accountStore.removeAccount(
            address: account.address,
            activeAddress: account.address
        )

        let receipts = try receiptStore.latest(limit: 10)

        #expect(receipts.count == 3)
        #expect(receipts.map { $0.kind } == [
            "account.removed",
            "account.selected",
            "account.added"
        ])
        #expect(receipts.allSatisfy { $0.category == "accounts" })
        #expect(receipts.map { $0.sequenceID } == [3, 2, 1])
        #expect(receipts.allSatisfy {
            if case .string(let value)? = $0.payload.values["address"] {
                return value == "<redacted-opaque-token>"
            }
            return false
        })
    }

    @Test("account activation receipts share one correlation ID across chained account events")
    @MainActor
    func accountActivationReceiptsShareCorrelationID() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let receiptStore = SwiftDataReceiptStore(
            modelContext: context,
            sequenceAllocator: ReceiptSequenceAllocator()
        )
        let recorder = ReceiptBackedAccountEventRecorder(
            receiptStore: receiptStore,
            payloadSanitizer: DefaultReceiptPayloadSanitizer()
        )
        let accountStore = SwiftDataAccountStore(modelContext: context, eventRecorder: recorder)
        let correlationID = "account-activation-correlation"

        _ = try await accountStore.activateWatchAccount(
            from: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            source: EOAccountSource.manualEntry,
            selectedAt: Date(timeIntervalSince1970: 100),
            correlationID: correlationID
        )

        let receipts = try receiptStore.receipts(forCorrelationID: correlationID, limit: 10)

        #expect(receipts.map { $0.kind } == [
            "account.selected",
            "account.added"
        ])
        #expect(receipts.allSatisfy { $0.correlationID == correlationID })
    }

    @Test("policy gate denies blocked observe actions and records a denial receipt")
    @MainActor
    func observeModePolicyGateWritesReceipt() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let receiptStore = SwiftDataReceiptStore(
            modelContext: context,
            sequenceAllocator: ReceiptSequenceAllocator()
        )
        let modeState = ModeState()

        let result = await ActionPolicyGate.attempt(
            .draftTransaction,
            modeState: modeState,
            receiptStore: receiptStore
        )

        let receipts = try receiptStore.latest(limit: 10)

        #expect(result.isAllowed == false)
        #expect(result.userMessage == "Not available in Observe mode")
        #expect(receipts.count == 1)
        #expect(receipts.first?.trigger == "policy.denied")
        #expect(receipts.first?.scope == "policy")
        #expect(receipts.first?.mode == .observe)
        #expect(receipts.first?.isSuccess == false)
        #expect(receipts.first?.details.values["action"] == ReceiptJSONValue.string("draft_transaction"))
        #expect(receipts.first?.details.values["policy_denied"] == ReceiptJSONValue.bool(true))
    }

    @Test("policy gate denies plugin actions in Observe mode and records a denial receipt")
    @MainActor
    func observeModePolicyGateDeniesPluginActions() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let receiptStore = SwiftDataReceiptStore(
            modelContext: context,
            sequenceAllocator: ReceiptSequenceAllocator()
        )
        let modeState = ModeState()

        let result = await ActionPolicyGate.attempt(
            .runPlugin,
            modeState: modeState,
            receiptStore: receiptStore
        )

        let receipts = try receiptStore.latest(limit: 10)

        #expect(result.isAllowed == false)
        #expect(result.userMessage == "Not available in Observe mode")
        #expect(receipts.count == 1)
        #expect(receipts.first?.trigger == "policy.denied")
        #expect(receipts.first?.scope == "policy")
        #expect(receipts.first?.mode == .observe)
        #expect(receipts.first?.isSuccess == false)
        #expect(receipts.first?.details.values["action"] == ReceiptJSONValue.string("run_plugin"))
        #expect(receipts.first?.details.values["policy_denied"] == ReceiptJSONValue.bool(true))
        #expect(receipts.first?.details.values["policy_approved"] == ReceiptJSONValue.bool(false))
    }

    @Test("chain-scope account events emit one receipt per real preferred and current change")
    @MainActor
    func chainScopeEventsWriteReceipts() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let receiptStore = SwiftDataReceiptStore(
            modelContext: context,
            sequenceAllocator: ReceiptSequenceAllocator()
        )
        let recorder = ReceiptBackedAccountEventRecorder(
            receiptStore: receiptStore,
            payloadSanitizer: DefaultReceiptPayloadSanitizer()
        )

        await recorder.record(
            AccountEvent.preferredChainChanged(
                address: "0x1234567890abcdef1234567890abcdef12345678",
                from: Chain.ethMainnet,
                to: Chain.baseMainnet
            )
        )
        await recorder.record(
            AccountEvent.currentChainChanged(
                address: "0x1234567890abcdef1234567890abcdef12345678",
                from: Chain.baseMainnet,
                to: Chain.baseSepoliaTestnet
            )
        )

        let receipts = try receiptStore.latest(limit: 10)

        #expect(receipts.count == 2)
        #expect(receipts.map { $0.trigger } == [
            "account.chain.current.changed",
            "account.chain.preferred.changed"
        ])
        #expect(receipts.allSatisfy { $0.scope == "accounts.chain_scope" })
        #expect(receipts.first?.details.values["from_chain"] == ReceiptJSONValue.string(Chain.baseMainnet.rawValue))
        #expect(receipts.first?.details.values["to_chain"] == ReceiptJSONValue.string(Chain.baseSepoliaTestnet.rawValue))
    }

    @Test("chain-scope account receipts preserve caller correlation IDs for follow-on refresh chaining")
    @MainActor
    func chainScopeReceiptsPreserveCorrelationID() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let receiptStore = SwiftDataReceiptStore(
            modelContext: context,
            sequenceAllocator: ReceiptSequenceAllocator()
        )
        let recorder = ReceiptBackedAccountEventRecorder(
            receiptStore: receiptStore,
            payloadSanitizer: DefaultReceiptPayloadSanitizer()
        )
        let correlationID = "chain-scope-correlation"

        await recorder.record(
            AccountEvent.currentChainChanged(
                address: "0x1234567890abcdef1234567890abcdef12345678",
                from: Chain.ethMainnet,
                to: Chain.baseMainnet
            ),
            correlationID: correlationID
        )

        let receipts = try receiptStore.receipts(forCorrelationID: correlationID, limit: 10)

        #expect(receipts.count == 1)
        #expect(receipts.first?.trigger == "account.chain.current.changed")
        #expect(receipts.first?.correlationID == correlationID)
    }

    @Test("chain-scope planner suppresses redundant writes and only refreshes the active scope")
    func chainScopePlannerAvoidsNoOpChanges() {
        let planner = ChainScopeChangePlanner()

        let unchangedPlan = planner.planCurrentChange(
            address: "0x1234567890abcdef1234567890abcdef12345678",
            from: .ethMainnet,
            to: .ethMainnet
        )
        let preferredPlan = planner.planPreferredChange(
            address: "0x1234567890abcdef1234567890abcdef12345678",
            from: .ethMainnet,
            to: .baseMainnet
        )
        let currentPlan = planner.planCurrentChange(
            address: "0x1234567890abcdef1234567890abcdef12345678",
            from: .ethMainnet,
            to: .baseMainnet
        )

        #expect(unchangedPlan.shouldApply == false)
        #expect(unchangedPlan.event == nil)
        #expect(unchangedPlan.shouldRefreshActiveScope == false)

        #expect(preferredPlan.shouldApply)
        #expect(preferredPlan.shouldRefreshActiveScope == false)
        #expect(
            preferredPlan.event == .preferredChainChanged(
                address: "0x1234567890abcdef1234567890abcdef12345678",
                from: .ethMainnet,
                to: .baseMainnet
            )
        )

        #expect(currentPlan.shouldApply)
        #expect(currentPlan.shouldRefreshActiveScope)
        #expect(
            currentPlan.event == .currentChainChanged(
                address: "0x1234567890abcdef1234567890abcdef12345678",
                from: .ethMainnet,
                to: .baseMainnet
            )
        )
    }
}
