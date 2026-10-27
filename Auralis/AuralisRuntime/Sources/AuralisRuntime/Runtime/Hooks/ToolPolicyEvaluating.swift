/// Standing policy evaluation performed independently from deterministic checks and judgment.
public protocol ToolPolicyEvaluating: Sendable {
    func evaluate(_ proposal: ActionProposal, checkResults: [DeterministicCheckResult]) async -> JudgeDecision
}

/// Neutral policy used by isolated AuralisRuntime tests. Shipping composition injects its PolicyCore adapter.
public struct AllowAllToolPolicy: ToolPolicyEvaluating {
    public init() { }

    public func evaluate(
        _ proposal: ActionProposal,
        checkResults: [DeterministicCheckResult]
    ) async -> JudgeDecision {
        .allow
    }
}
