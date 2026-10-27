import AuralisPolicy
import AuralisRuntime

/// Adapts AuralisPolicy's standing action policy into AuralisRuntime's before-tool-call policy stage.
public struct PolicyCoreToolEvaluator: ToolPolicyEvaluating {
    private let cryptoMode: CryptoMode

    public init(cryptoMode: CryptoMode) {
        self.cryptoMode = cryptoMode
    }

    public func evaluate(
        _ proposal: ActionProposal,
        checkResults: [DeterministicCheckResult]
    ) async -> JudgeDecision {
        let action = CapabilityActionMapping.policyAction(for: proposal.capability)
        switch StandingToolPolicy.evaluate(
            action: action,
            mode: cryptoMode,
            isCryptoCapability: CapabilityDomain.isCrypto(proposal.capability),
            requiresConfirmation: proposal.impact.requiresConfirmation,
            intent: proposal.intent
        ) {
        case .allow:
            return .allow
        case let .block(reason):
            return .block(reason: reason)
        case let .requireApproval(prompt):
            return .escalate(approvalRequest: ApprovalRequest(
                proposal: proposal,
                prompt: prompt
            ))
        }
    }
}
