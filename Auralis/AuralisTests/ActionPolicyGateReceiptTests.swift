import AuralisPrimaryModels
import CapabilitiesCore
import Foundation
import PolicyCore
import ReceiptsCore
import Testing

@MainActor
@Suite
struct ActionPolicyGateReceiptTests {
    @Test(
        "Observe mode blocks every high-risk policy action",
        arguments: PolicyControlledAction.allCases
    )
    func observeModeBlocksHighRiskAction(_ action: PolicyControlledAction) async {
        let result = await ActionPolicyGate.attempt(action, mode: .observe)

        #expect(result.isAllowed == false)
        #expect(result.userMessage == "Not available in Observe mode")
        #expect(action.isBlockedInObserveMode)
        #expect(action.requiresHighRiskReceipt)
    }

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

    @Test("every high-risk action has a future capability contract")
    func highRiskActionsHaveFutureCapabilityContracts() throws {
        let contracts = FutureHighRiskActionContract.byAction

        #expect(Set(contracts.keys) == Set(PolicyControlledAction.allCases))

        for action in PolicyControlledAction.allCases {
            let contract = contracts[action]
            #expect(try #require(contract).capabilityID == action.capabilityID)
            #expect(try #require(contract).requiredControls == action.futureExecutionControls)
            #expect(action.isBlockedInObserveMode)
            #expect(action.requiresHighRiskReceipt)
        }
    }

    @Test("future approval modes require signing-capable account access")
    func futureApprovalModesRequireSigningCapableAccountAccess() {
        #expect(EthereumAddressAccess.readonly.canSign == false)
        #expect(EthereumAddressAccess.wallet.canSign == true)
        #expect(PolicyControlledAction.draftTransaction.futureExecutionControls.contains(.signingAccess))
    }

    @Test("draft transaction readiness requires preview evidence")
    func draftTransactionReadinessRequiresPreviewEvidence() {
        let result = PolicyExecutionReadiness.evaluate(
            action: .draftTransaction,
            evidence: completeDraftTransactionEvidence(draftTransactionPreview: nil),
            signingChainAllowlist: SigningChainAllowlist(allowedChains: [Chain.ethMainnet])
        )

        #expect(result.isAllowed == false)
        #expect(result.userMessage == "Transaction preview is required")
    }

    @Test("draft transaction readiness rejects chains outside the signing allowlist")
    func draftTransactionReadinessRejectsDisallowedChain() {
        let result = PolicyExecutionReadiness.evaluate(
            action: .draftTransaction,
            evidence: completeDraftTransactionEvidence(
                draftTransactionPreview: draftTransactionPreview(targetChain: .baseMainnet)
            ),
            signingChainAllowlist: SigningChainAllowlist(allowedChains: [Chain.ethMainnet])
        )

        #expect(result.isAllowed == false)
        #expect(result.userMessage == "Target chain is not allowed for signing")
    }

    @Test("draft transaction readiness requires chain allowlist, preview, confirmation, and receipt")
    func draftTransactionReadinessAllowsOnlyCompleteEvidence() {
        let result = PolicyExecutionReadiness.evaluate(
            action: .draftTransaction,
            evidence: completeDraftTransactionEvidence(
                draftTransactionPreview: draftTransactionPreview(targetChain: .baseMainnet)
            ),
            signingChainAllowlist: SigningChainAllowlist(allowedChains: [Chain.baseMainnet])
        )

        #expect(result.isAllowed)
        #expect(result.userMessage.isEmpty)
        #expect(PolicyControlledAction.draftTransaction.futureExecutionControls.contains(.chainAllowlist))
        #expect(PolicyControlledAction.draftTransaction.futureExecutionControls.contains(.transactionPreview))
        #expect(PolicyControlledAction.draftTransaction.futureExecutionControls.contains(.userConfirmation))
        #expect(PolicyControlledAction.draftTransaction.futureExecutionControls.contains(.approvedReceipt))
    }
}

private struct FutureHighRiskActionContract: Sendable {
    let capabilityID: CapabilityID
    let requiredControls: Set<PolicyExecutionControl>

    static let byAction: [PolicyControlledAction: FutureHighRiskActionContract] = [
        .signMessage: FutureHighRiskActionContract(
            capabilityID: .signMessage,
            requiredControls: PolicyControlledAction.signMessage.futureExecutionControls
        ),
        .approveSpending: FutureHighRiskActionContract(
            capabilityID: .approveSpending,
            requiredControls: PolicyControlledAction.approveSpending.futureExecutionControls
        ),
        .draftTransaction: FutureHighRiskActionContract(
            capabilityID: .draftTransaction,
            requiredControls: PolicyControlledAction.draftTransaction.futureExecutionControls
        ),
        .runPlugin: FutureHighRiskActionContract(
            capabilityID: .runPlugin,
            requiredControls: PolicyControlledAction.runPlugin.futureExecutionControls
        )
    ]
}

private func completeDraftTransactionEvidence(
    draftTransactionPreview: DraftTransactionPreviewEvidence?
) -> PolicyExecutionEvidence {
    PolicyExecutionEvidence(
        signingAccessAvailable: true,
        capabilityGrant: PolicyCapabilityGrant(
            capabilityID: PolicyControlledAction.draftTransaction.capabilityID.rawValue
        ),
        requesterProvenance: PolicyRequesterProvenance(
            requesterID: "auralis.test",
            displayName: "Auralis Test"
        ),
        userConfirmation: PolicyUserConfirmation(
            confirmedSummary: "Draft transaction preview confirmed",
            confirmationReceiptID: "confirmation-receipt"
        ),
        approvedReceiptID: "approved-receipt",
        draftTransactionPreview: draftTransactionPreview
    )
}

private func draftTransactionPreview(targetChain: Chain) -> DraftTransactionPreviewEvidence {
    DraftTransactionPreviewEvidence(
        targetChain: targetChain,
        gasEstimate: "21000",
        contractInfo: "Native transfer",
        verifiedDestination: "0x0000000000000000000000000000000000000000",
        simulationSummary: "No token approval side effects"
    )
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
