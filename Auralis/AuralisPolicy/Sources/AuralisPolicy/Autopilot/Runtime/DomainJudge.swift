import AuralisRuntime

/// The app's default ``Judge``, encoding the **crypto-scoped** Observe boundary (ADR-010).
///
/// - Crypto/wallet capabilities are gated by ``CryptoMode``: `.observe` blocks, `.assist` escalates for
///   approval, and `.operate` can proceed only after deterministic checks and impact confirmation rules.
/// - Every other domain (music, playback, plugin, artifacts, …) is fully operational: a failed
///   deterministic check blocks; a confirmation-class impact (`externalImpact`/`highRisk`) escalates;
///   read-only and reversible writes are allowed.
///
/// This replaces the whole-app `ObserveModeJudge` default so non-crypto CRUD runs while crypto stays
/// gated.
public struct DomainJudge: Judge {
    private let cryptoMode: CryptoMode

    public init(cryptoMode: CryptoMode = .observe) {
        self.cryptoMode = cryptoMode
    }

    public func judge(
        _ proposal: ActionProposal,
        checkResults: [DeterministicCheckResult]
    ) async -> JudgeDecision {
        if let failure = checkResults.firstFailure {
            let detail = failure.detail.map { ": \($0)" } ?? ""
            return .block(reason: "Check failed (\(failure.checkID))\(detail)")
        }

        switch StandingToolPolicy.evaluate(
            action: CapabilityActionMapping.policyAction(for: proposal.capability),
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
            return .escalate(approvalRequest: ApprovalRequest(proposal: proposal, prompt: prompt))
        }
    }
}
