/// The complete pre-execution governance result for a registered tool call.
public struct BeforeToolCallResult: Equatable, Sendable {
    /// Which stage of this hook produced ``decision``.
    ///
    /// Reported explicitly because the pipeline treats a schema rejection differently from a
    /// governance verdict, and the two are otherwise indistinguishable: the schema gate returns no
    /// check results, but so does a Judge `.revise` for a tool that requires no deterministic
    /// checks. Inferring the stage from `checkResults.isEmpty` therefore misread the latter as the
    /// former and skipped the `.checksEvaluated` worklog entry and the capability-restriction
    /// lookup — no fail-open, since nothing executes on either path, but a restricted actor was
    /// told "revise" instead of naming the restriction.
    public enum Origin: Equatable, Sendable {
        /// The declared input schema rejected the proposal before any check or judge ran.
        case inputSchema
        /// A deterministic check, the standing policy, or the Judge produced the verdict.
        case governance
    }

    public let decision: JudgeDecision
    public let checkResults: [DeterministicCheckResult]
    public let origin: Origin

    /// - Parameter origin: Defaults to ``Origin/governance``, the safe reading for a custom hook
    ///   that does not model the schema stage separately: the pipeline then records the full
    ///   worklog trace and restriction lookup rather than assuming it can skip them.
    public init(
        decision: JudgeDecision,
        checkResults: [DeterministicCheckResult],
        origin: Origin = .governance
    ) {
        self.decision = decision
        self.checkResults = checkResults
        self.origin = origin
    }
}

/// A replaceable, testable boundary for all checks that must happen before execution.
///
/// Registry resolution and definition/proposal integrity matching remain the pipeline's responsibility;
/// this hook validates the declared schema, runs deterministic checks, and invokes the policy judge.
public protocol BeforeToolCallHook: Sendable {
    func evaluate(
        tool: ToolDefinition,
        proposal: ActionProposal,
        approvedEscalation: ApprovalRequest?
    ) async -> BeforeToolCallResult
}

public struct StandardBeforeToolCallHook: BeforeToolCallHook {
    private let checks: DeterministicCheckRegistry
    private let policy: any ToolPolicyEvaluating
    private let judge: any Judge

    public init(
        checks: DeterministicCheckRegistry,
        policy: any ToolPolicyEvaluating,
        judge: any Judge
    ) {
        self.checks = checks
        self.policy = policy
        self.judge = judge
    }

    public func evaluate(
        tool: ToolDefinition,
        proposal: ActionProposal,
        approvedEscalation: ApprovalRequest?
    ) async -> BeforeToolCallResult {
        let inputProblems = tool.inputSchema.validationProblems(against: proposal.parameters)
        if !inputProblems.isEmpty {
            return BeforeToolCallResult(
                decision: .revise(instructions: "Revise the request: \(inputProblems.joined(separator: "; "))."),
                checkResults: [],
                origin: .inputSchema
            )
        }

        let requiredCheckIDs = orderedUnion(tool.requiredCheckIDs, proposal.requiredCheckIDs)
        let results = await checks.evaluate(ids: requiredCheckIDs, for: proposal)
        if let failure = results.firstFailure {
            let detail = failure.detail.map { ": \($0)" } ?? ""
            return BeforeToolCallResult(
                decision: .block(reason: "Check failed (\(failure.checkID))\(detail)"),
                checkResults: results
            )
        }
        let policyDecision = await policy.evaluate(proposal, checkResults: results)
        let effectivePolicyDecision = approvalAware(
            warningAnnotated(policyDecision, warnings: results.warnings),
            approvedEscalation: approvedEscalation
        )
        guard case .allow = effectivePolicyDecision else {
            return BeforeToolCallResult(decision: effectivePolicyDecision, checkResults: results)
        }

        let judgedDecision = await judge.judge(proposal, checkResults: results)
        let effectiveJudgeDecision = approvalAware(
            warningAnnotated(judgedDecision, warnings: results.warnings),
            approvedEscalation: approvedEscalation
        )
        if case .allow = effectiveJudgeDecision,
           approvedEscalation == nil,
           !proposal.requiredApprovals.isEmpty {
            return BeforeToolCallResult(
                decision: .escalate(approvalRequest: ApprovalRequest(
                    proposal: proposal,
                    prompt: escalationPrompt(for: proposal, warnings: results.warnings)
                )),
                checkResults: results
            )
        }
        return BeforeToolCallResult(decision: effectiveJudgeDecision, checkResults: results)
    }

    /// Builds the approval prompt for the `requiredApprovals` path, naming any non-blocking warnings.
    private func escalationPrompt(
        for proposal: ActionProposal,
        warnings: [DeterministicCheckResult]
    ) -> String {
        let base = "Approve “\(proposal.intent)” (\(proposal.requiredApprovals.joined(separator: ", ")))?"
        return appendingWarningNotes(to: base, warnings: warnings)
    }

    /// Carries warnings into an escalation the policy or judge raised with its own prompt.
    ///
    /// Those two paths build their prompts from the standing policy, which never sees `checkResults`
    /// — so without this the warning would reach the worklog and Mission Control but not the person
    /// actually authorizing the action. That is the path a high-risk crypto action takes, which is
    /// where an unchecksummed address matters most.
    ///
    /// Annotating *before* ``approvalAware(_:approvedEscalation:)`` is deliberate: the comparison
    /// there matches a resumed approval by prompt, so the note has to be present at raise and resume
    /// alike or a valid approval would be silently refused.
    private func warningAnnotated(
        _ decision: JudgeDecision,
        warnings: [DeterministicCheckResult]
    ) -> JudgeDecision {
        guard case let .escalate(request) = decision else { return decision }
        return .escalate(approvalRequest: ApprovalRequest(
            id: request.id,
            proposal: request.proposal,
            prompt: appendingWarningNotes(to: request.prompt, warnings: warnings)
        ))
    }

    /// Appends non-blocking warning details to an approval prompt.
    ///
    /// A warning is only worth recording if it reaches the person who authorizes the action — an
    /// address that is well-formed but unchecksummed is exactly the kind of thing an approver should
    /// see before signing.
    ///
    /// This is safe against the raise/resume prompt comparison in
    /// ``approvalAware(_:approvedEscalation:)`` only given a constraint on the checks. That
    /// comparison matches on ``ActionProposal/withoutFreshnessEvaluationStamp``, so it requires every
    /// parameter *except* `freshnessEvaluatedAt` to agree — and the boundary re-stamps that one on
    /// every run. A `.warning` detail must therefore be a pure function of the parameters **excluding**
    /// the freshness stamp. Every shipping warning is: only ``AddressFormatCheck`` emits one, from
    /// `address`/`watchlist`. Note *order* is stable for the same reason —
    /// ``DeterministicCheckRegistry/evaluate(ids:for:)`` appends in the order of a deterministic
    /// `orderedUnion`.
    ///
    /// A future check that warned off the stamp would annotate the two runs differently, the prompt
    /// comparison would miss, and a valid approval would be refused at resume — an approval loop
    /// rather than a fail-open, but a hard one to diagnose. `annotatedPromptSurvivesFreshnessRestamping`
    /// in `DeterministicCheckSeverityTests` pins it.
    private func appendingWarningNotes(
        to prompt: String,
        warnings: [DeterministicCheckResult]
    ) -> String {
        let notes = warnings.compactMap(\.detail)
        guard !notes.isEmpty else { return prompt }
        return prompt + " Note: \(notes.joined(separator: "; "))."
    }

    private func orderedUnion(_ first: [String], _ second: [String]) -> [String] {
        var seen: Set<String> = []
        return (first + second).filter { seen.insert($0).inserted }
    }

    private func approvalAware(
        _ decision: JudgeDecision,
        approvedEscalation: ApprovalRequest?
    ) -> JudgeDecision {
        guard let approvedEscalation else { return decision }
        if case let .escalate(request) = decision,
           request.proposal.withoutFreshnessEvaluationStamp
               == approvedEscalation.proposal.withoutFreshnessEvaluationStamp,
           request.prompt == approvedEscalation.prompt {
            return .allow
        }
        return decision
    }
}
