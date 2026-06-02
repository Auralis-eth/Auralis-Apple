import PolicyCore
import Testing

@Suite
struct PolicyCoreTests {
    @Test("observe mode denies execution-style actions before future execution evidence is evaluated")
    @MainActor
    func observeModeDeniesExecutionActions() async {
        let result = await ActionPolicyGate.attempt(.draftTransaction, mode: .observe)

        #expect(result == PolicyGateResult(isAllowed: false, userMessage: "Not available in Observe mode"))
    }

    @Test("future execution controls deny signing actions without signing access first")
    func executionReadinessRequiresSigningAccess() {
        let result = PolicyExecutionReadiness.evaluate(
            action: .signMessage,
            evidence: .none
        )

        #expect(result == PolicyGateResult(isAllowed: false, userMessage: "Signing-capable account access is required"))
    }

    @Test("policy actions map to canonical capability identifiers")
    func policyActionsMapToCapabilities() {
        #expect(PolicyControlledAction.signMessage.capabilityID.rawValue == "sign_message")
        #expect(PolicyControlledAction.approveSpending.capabilityID.rawValue == "approve_spending")
        #expect(PolicyControlledAction.draftTransaction.capabilityID.rawValue == "draft_transaction")
        #expect(PolicyControlledAction.runPlugin.capabilityID.rawValue == "run_plugin")
    }
}
