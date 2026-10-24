/// Decides what happens to a proposal, given the objective check results.
///
/// The Judge is the *subjective* half of governance (checks are the objective half). It returns a
/// ``JudgeDecision`` — allow, block, revise, or escalate — and never executes anything itself.
public protocol Judge: Sendable {
    func judge(
        _ proposal: ActionProposal,
        checkResults: [DeterministicCheckResult]
    ) async -> JudgeDecision
}

/// A reusable judge for callers that need a strict Observe-mode boundary.
///
/// Rules, in order:
/// 1. Any failed deterministic check → `.block`.
/// 2. In Observe mode, **any state-changing action** (impact other than `.readOnly`) → `.block`.
///    ADR-004 makes Observe read-only: it blocks all execution-style behavior, not just high risk.
/// 3. An action whose impact `requiresConfirmation` → `.escalate` for human approval.
/// 4. Otherwise → `.allow`.
///
/// The shipping app uses the crypto-scoped `DomainJudge`; this type remains available for stricter
/// callers that intentionally want a whole-surface read-only posture.
public struct ObserveModeJudge: Judge {
    public let isObserveMode: Bool

    public init(isObserveMode: Bool = true) {
        self.isObserveMode = isObserveMode
    }

    public func judge(
        _ proposal: ActionProposal,
        checkResults: [DeterministicCheckResult]
    ) async -> JudgeDecision {
        if let failure = checkResults.firstFailure {
            let detail = failure.detail.map { ": \($0)" } ?? ""
            return .block(reason: "Check failed (\(failure.checkID))\(detail)")
        }

        if isObserveMode, proposal.impact != .readOnly {
            return .block(reason: "State-changing actions are not available in Observe mode.")
        }

        if proposal.impact.requiresConfirmation {
            let request = ApprovalRequest(
                proposal: proposal,
                prompt: "Approve “\(proposal.intent)”?"
            )
            return .escalate(approvalRequest: request)
        }

        return .allow
    }
}
