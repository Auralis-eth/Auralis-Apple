import Foundation

/// The single governed path from an ``ActionProposal`` to an executed tool call.
///
/// This generalizes the hardcoded `ActionPolicyGate.attempt` (gate → decide → receipt) into a
/// reusable pipeline that any tool call flows through. The BeforeToolCall hook is steps 1–4
/// (resolve, integrity-match, checks, judge); the AfterToolCall hook is steps 5–6 (execute, then
/// emit worklog + events). Nothing executes outside this pipeline.
///
/// Observe-mode note: with `ObserveModeJudge`, high-risk proposals resolve to `.blocked` and
/// confirmation-class proposals resolve to `.needsApproval` — this is a governance seam, not a live
/// autonomous executor. Actual execution only happens for proposals the Judge `.allow`s.
public struct GovernedToolPipeline: Sendable {
    private let registry: ToolRegistry
    private let beforeToolCallHook: any BeforeToolCallHook
    private let executor: any ToolExecuting
    private let eventBus: any RuntimeEventPublishing
    private let worklog: any WorklogRecording
    private let receiptSink: any ReceiptEmitting
    private let performanceSink: any PerformanceSignalEmitting
    private let pauseGate: PauseGate?
    private let leaseRegistry: CapabilityLeaseRegistry?
    private let sessionStore: (any AgentSessionStoring)?
    private let contextRecorder: (any RuntimeContextRecording)?
    private let approvalRegistry: ApprovalRegistry
    private let afterToolCallHook: any AfterToolCallHook

    @_spi(RuntimeComposition)
    public init(
        registry: ToolRegistry,
        checks: DeterministicCheckRegistry,
        policy: any ToolPolicyEvaluating,
        judge: any Judge,
        executor: any ToolExecuting,
        eventBus: any RuntimeEventPublishing,
        worklog: any WorklogRecording,
        receiptSink: any ReceiptEmitting,
        performanceSink: any PerformanceSignalEmitting,
        pauseGate: PauseGate? = nil,
        leaseRegistry: CapabilityLeaseRegistry? = nil,
        sessionStore: (any AgentSessionStoring)? = nil,
        contextRecorder: (any RuntimeContextRecording)? = nil,
        approvalRegistry: ApprovalRegistry = ApprovalRegistry(),
        afterToolCallHooks: [any AfterToolCallHook] = []
    ) {
        self.registry = registry
        self.beforeToolCallHook = StandardBeforeToolCallHook(checks: checks, policy: policy, judge: judge)
        self.executor = executor
        self.eventBus = eventBus
        self.worklog = worklog
        self.receiptSink = receiptSink
        self.performanceSink = performanceSink
        self.pauseGate = pauseGate
        self.leaseRegistry = leaseRegistry
        self.sessionStore = sessionStore
        self.contextRecorder = contextRecorder
        self.approvalRegistry = approvalRegistry
        self.afterToolCallHook = StandardAfterToolCallHook(
            eventBus: eventBus,
            worklog: worklog,
            receiptSink: receiptSink,
            performanceSink: performanceSink,
            observers: afterToolCallHooks
        )
    }

    public func run(toolID: String, proposal: ActionProposal) async -> ToolCallOutcome {
        await run(toolID: toolID, proposal: proposal, approvedRequest: nil)
    }

    /// Continues the exact proposal previously escalated through this approval registry.
    /// The grant is one-shot and all mutable checks and tool contracts are evaluated again.
    public func resumeApproved(_ request: ApprovalRequest) async -> ToolCallOutcome {
        await run(toolID: "", proposal: request.proposal, approvedRequest: request)
    }

    private func run(
        toolID requestedToolID: String,
        proposal incomingProposal: ActionProposal,
        approvedRequest: ApprovalRequest?
    ) async -> ToolCallOutcome {
        let start = Date()
        // The "now" half of context freshness belongs to this boundary, not to the caller, and it is
        // stamped per *run* rather than per proposal construction. That is what makes `context.fresh`
        // enforce something on the resume path: an approval that sat in the inbox is re-evaluated
        // against the moment it was cleared, not against the frozen instant it was raised. The
        // approval's own integrity is unaffected — `approvedRequest` is consumed unmodified below.
        let proposal = incomingProposal.stampingFreshnessEvaluation(at: start)
        let correlationID = proposal.resolvedCorrelationID
        await ensureSession(for: proposal, correlationID: correlationID)
        // The approval is *inspected* here and consumed only at the point of no return below, once
        // governance is actually about to evaluate it. Custody is unchanged — `toolID(for:)` applies
        // the same exact-match test as `consume(_:)`, and the grant is still one-shot — but a run
        // refused by a precondition that has nothing to do with the approval (a paused kill switch,
        // an unavailable worklog) now leaves the grant intact. Consuming first meant pausing
        // operator activity while an approval sat in the inbox silently destroyed it, and the retry
        // after unpausing reported the grant as "altered", blaming the person for a transient
        // machine state.
        let toolID: String
        if let approvedRequest {
            guard let approvedToolID = await approvalRegistry.toolID(for: approvedRequest) else {
                return await block(
                    "Approval is invalid, stale, altered, or already used.",
                    proposal: proposal,
                    toolID: requestedToolID,
                    startedAt: start
                )
            }
            toolID = approvedToolID
        } else {
            toolID = requestedToolID
        }
        let proposalRecord = await record(proposal: proposal, toolID: toolID, event: .proposed(proposal))
        if proposal.impact == .highRisk, let failure = proposalRecord.failure {
            let reason = "High-risk execution refused because its mandatory worklog is unavailable: \(failure.localizedDescription)"
            // Routed through `block` like every other refusal, so this path emits the same receipt,
            // session end, and performance signal instead of being the one terminal outcome that
            // published a bare `workflowBlocked` and returned. The worklog is already known-degraded,
            // so the outcome stays `.evidenceIncomplete` regardless of whether the receipt landed.
            let outcome = await block(
                reason,
                proposal: proposal,
                toolID: toolID,
                startedAt: start,
                source: .infrastructure
            )
            var failures = [failure.localizedDescription]
            if case let .evidenceIncomplete(_, additional) = outcome {
                failures.append(contentsOf: additional)
            }
            return .evidenceIncomplete(original: .blocked(reason: reason), failures: failures)
        }
        await publish(.workflowStarted, correlationID: correlationID)

        // --- Kill switch: refuse to start new governed work while paused. ---
        if let pauseGate, await pauseGate.isPaused() {
            return await block("Paused — operator activity is paused.", proposal: proposal, toolID: toolID, startedAt: start)
        }

        // --- BeforeToolCall: resolve + integrity match ---
        guard let tool = await registry.tool(id: toolID) else {
            return await block(
                "Unknown tool “\(toolID)”.",
                proposal: proposal,
                toolID: toolID,
                startedAt: start
            )
        }

        guard tool.capability == proposal.capability else {
            return await block(
                "Capability mismatch: tool requires \(tool.capability.rawValue), proposal claims \(proposal.capability.rawValue).",
                proposal: proposal,
                toolID: toolID,
                startedAt: start
            )
        }

        guard tool.impact == proposal.impact else {
            return await block(
                "Impact mismatch: tool is \(tool.impact.rawValue), proposal claims \(proposal.impact.rawValue).",
                proposal: proposal,
                toolID: toolID,
                startedAt: start
            )
        }

        // --- Point of no return for approval custody ---
        // Everything above this line is a precondition the approval had no say in. From here the
        // grant is spent: governance is about to re-evaluate the proposal *as approved*, and whatever
        // it decides — allow, block, revise, or a fresh escalation — that one-shot authorization has
        // been used and must not authorize a second attempt.
        if let approvedRequest {
            guard await approvalRegistry.consume(approvedRequest) != nil else {
                return await block(
                    "Approval is invalid, stale, altered, or already used.",
                    proposal: proposal,
                    toolID: toolID,
                    startedAt: start
                )
            }
        }

        // --- BeforeToolCall: input schema validation (revisable) ---
        // A malformed/incomplete proposal isn't a policy refusal — it's a correctable request, so the
        // pipeline sends it back with field-level instructions rather than blocking it outright.
        let beforeResult = await beforeToolCallHook.evaluate(
            tool: tool,
            proposal: proposal,
            approvedEscalation: approvedRequest
        )
        // Keyed on the reported stage, not on `checkResults.isEmpty`: a Judge `.revise` for a tool
        // that requires no deterministic checks also carries no results, so the emptiness test
        // routed it down this path and skipped both the `.checksEvaluated` worklog entry and the
        // restriction lookup below.
        if case let .revise(instructions) = beforeResult.decision,
           beforeResult.origin == .inputSchema {
            await record(proposal: proposal, toolID: tool.id, event: .decided(.revise(instructions: instructions)))
            return await revise(instructions, proposal: proposal, toolID: tool.id, startedAt: start)
        }

        // --- BeforeToolCall: deterministic checks ---
        let results = beforeResult.checkResults
        await record(proposal: proposal, toolID: toolID, event: .checksEvaluated(results))
        for failure in results where !failure.passed {
            await publish(
                .checkFailed(id: failure.checkID, reason: failure.detail ?? "failed"),
                correlationID: correlationID
            )
        }
        if let restrictionReason = await explicitRestrictionReason(for: proposal, correlationID: correlationID) {
            return await block(
                restrictionReason,
                proposal: proposal,
                toolID: tool.id,
                startedAt: start,
                source: .policy
            )
        }

        // --- BeforeToolCall: judge ---
        let decision = beforeResult.decision
        await record(proposal: proposal, toolID: toolID, event: .decided(decision))
        // A refusal is final at this point, so it is announced immediately. `.allow` is not: the run
        // is only permitted once an authority backs it, and announcing "Policy allowed X" before that
        // check left a contradictory pair — allowed, then blocked — in the Mission Control timeline
        // whenever authority resolution refused the run.
        if !decision.isAllowed {
            await notePolicyDecision(decision, proposal: proposal, correlationID: correlationID)
        }

        switch decision {
        case .allow:
            // Resolving authority and enforcing it are the same step: we keep the grant that let the
            // run through so it can be recorded, instead of discarding a yes/no (P0.5-601/602).
            let authority: AuthorityRef
            switch await resolveAuthority(for: proposal, correlationID: correlationID) {
            case let .granted(resolved):
                authority = resolved
            case let .refused(reason):
                return await block(
                    reason,
                    proposal: proposal,
                    toolID: tool.id,
                    startedAt: start,
                    source: .authority
                )
            }
            await notePolicyDecision(decision, proposal: proposal, correlationID: correlationID)
            // Recorded before execution, not after: a run that fails partway still needs to show
            // what let it start.
            await updateSession(correlationID: correlationID, defaultGoal: proposal.intent, actor: proposal.actor) { session in
                session.note(authority: authority)
            }
            return await execute(tool: tool, proposal: proposal, startedAt: start, authority: authority)
        case let .block(reason):
            return await block(reason, proposal: proposal, toolID: toolID, startedAt: start, source: .policy)
        case let .revise(instructions):
            // The `.decided(.revise)` worklog entry was already recorded above, so the helper does
            // not re-record it here.
            return await revise(instructions, proposal: proposal, toolID: tool.id, startedAt: start)
        case let .escalate(request):
            guard request.proposal == proposal else {
                return await block(
                    "Judge returned an approval for a different proposal.",
                    proposal: proposal,
                    toolID: tool.id,
                    startedAt: start
                )
            }
            return await escalate(request, proposal: proposal, toolID: tool.id, startedAt: start)
        }
    }

    private func escalate(
        _ request: ApprovalRequest,
        proposal: ActionProposal,
        toolID: String,
        startedAt: Date
    ) async -> ToolCallOutcome {
        let correlationID = proposal.resolvedCorrelationID
        await approvalRegistry.register(request, toolID: toolID)
        await publish(.approvalRequired(request), correlationID: correlationID)
        await updateSession(correlationID: correlationID, defaultGoal: proposal.intent, actor: proposal.actor) { session in
            session.note(approvalID: request.id)
            session.markWaitingForApproval()
        }
        let evidence = await emit(proposal: proposal, toolID: toolID, outcome: .needsApproval, reason: request.prompt)
        await recordPerformance(
            proposal: proposal,
            toolID: toolID,
            outcome: .needsApproval,
            durationSeconds: Date().timeIntervalSince(startedAt)
        )
        guard evidence.succeeded else {
            return .evidenceIncomplete(original: .needsApproval(request), failures: evidence.failures)
        }
        return .needsApproval(request)
    }

    // --- AfterToolCall: execute + emit ---
    private func execute(
        tool: ToolDefinition,
        proposal: ActionProposal,
        startedAt: Date,
        authority: AuthorityRef
    ) async -> ToolCallOutcome {
        do {
            let artifact = try await executor.execute(
                tool,
                proposal: proposal,
                authorization: ToolExecutionAuthorization(toolID: tool.id, proposalID: proposal.id)
            )

            guard artifact.toolID == tool.id else {
                let outcome = await fail(
                    "Tool executor returned an artifact for “\(artifact.toolID)” while executing “\(tool.id)”.",
                    proposal: proposal
                )
                let evidence = await notifyAfterToolCallHooks(
                    proposal: proposal,
                    tool: tool,
                    outcome: outcome,
                    artifactID: nil,
                    durationSeconds: Date().timeIntervalSince(startedAt),
                    authority: authority
                )
                await publish(.sessionEnded(correlationID: proposal.resolvedCorrelationID, status: .failed), correlationID: proposal.resolvedCorrelationID)
                return evidence.succeeded ? outcome : .evidenceIncomplete(original: .failed(reason: outcome.failureReason), failures: evidence.failures)
            }

            // --- AfterToolCall: output schema enforcement ---
            // The tool ran, but a result that violates the declared output contract is not a valid
            // success — surface it as a failure rather than emitting a receipt for bad output.
            let outputProblems = tool.outputSchema.validationProblems(against: artifact.outputFields)
            if !outputProblems.isEmpty {
                let outcome = await fail(
                    "Tool “\(tool.id)” produced output violating its schema: \(outputProblems.joined(separator: "; ")).",
                    proposal: proposal
                )
                let evidence = await notifyAfterToolCallHooks(
                    proposal: proposal,
                    tool: tool,
                    outcome: outcome,
                    artifactID: artifact.id,
                    durationSeconds: Date().timeIntervalSince(startedAt),
                    authority: authority
                )
                await publish(.sessionEnded(correlationID: proposal.resolvedCorrelationID, status: .failed), correlationID: proposal.resolvedCorrelationID)
                return evidence.succeeded ? outcome : .evidenceIncomplete(original: .failed(reason: outcome.failureReason), failures: evidence.failures)
            }

            let duration = Date().timeIntervalSince(startedAt)
            await updateSession(correlationID: proposal.resolvedCorrelationID, defaultGoal: proposal.intent, actor: proposal.actor) { session in
                session.note(artifactID: artifact.id)
                if let telemetry = Self.inferenceTelemetry(from: artifact.outputFields) {
                    session.note(telemetry: telemetry)
                }
                session.noteExecutionUpdate("Executed \(tool.title)")
            }
            let outcome = ToolCallOutcome.executed(artifact)
            let evidenceReport = await notifyAfterToolCallHooks(
                proposal: proposal,
                tool: tool,
                outcome: outcome,
                artifactID: artifact.id,
                durationSeconds: duration,
                authority: authority
            )
            if !evidenceReport.succeeded {
                let reason = "Tool executed, but required governance evidence is incomplete: \(evidenceReport.failures.joined(separator: "; "))"
                await updateSession(correlationID: proposal.resolvedCorrelationID, defaultGoal: proposal.intent, actor: proposal.actor) {
                    $0.fail(reason: reason)
                }
                await publish(.workflowBlocked(reason: reason), correlationID: proposal.resolvedCorrelationID)
                await publish(.sessionEnded(correlationID: proposal.resolvedCorrelationID, status: .failed), correlationID: proposal.resolvedCorrelationID)
                return .evidenceIncomplete(original: .executed(artifact), failures: evidenceReport.failures)
            }
            await updateSession(correlationID: proposal.resolvedCorrelationID, defaultGoal: proposal.intent, actor: proposal.actor) { $0.complete() }
            await publish(.sessionEnded(correlationID: proposal.resolvedCorrelationID, status: .completed), correlationID: proposal.resolvedCorrelationID)
            return outcome
        } catch {
            let outcome = await fail(String(describing: error), proposal: proposal)
            let evidence = await notifyAfterToolCallHooks(
                proposal: proposal,
                tool: tool,
                outcome: outcome,
                artifactID: nil,
                durationSeconds: Date().timeIntervalSince(startedAt),
                authority: authority
            )
            await publish(.sessionEnded(correlationID: proposal.resolvedCorrelationID, status: .failed), correlationID: proposal.resolvedCorrelationID)
            return evidence.succeeded ? outcome : .evidenceIncomplete(original: .failed(reason: outcome.failureReason), failures: evidence.failures)
        }
    }

    /// Records the failure of an already-started run (executor threw, or its output violated the
    /// declared schema). Session state is finalized here; the mandatory AfterToolCall hook emits the
    /// audit trail — including the tool, timing, and authority — immediately afterward, which is why
    /// this only needs the proposal and the reason.
    private func fail(
        _ reason: String,
        proposal: ActionProposal
    ) async -> ToolCallOutcome {
        let correlationID = proposal.resolvedCorrelationID
        await updateSession(correlationID: correlationID, defaultGoal: proposal.intent, actor: proposal.actor) { session in
            session.fail(reason: reason)
        }
        return .failed(reason: reason)
    }

    private func notifyAfterToolCallHooks(
        proposal: ActionProposal,
        tool: ToolDefinition,
        outcome: ToolCallOutcome,
        artifactID: UUID?,
        durationSeconds: Double,
        authority: AuthorityRef
    ) async -> EvidenceEmissionReport {
        let context = AfterToolCallContext(
            proposal: proposal,
            tool: tool,
            outcome: outcome,
            artifactID: artifactID,
            durationSeconds: durationSeconds,
            authority: authority
        )
        return await afterToolCallHook.emit(context)
    }

    /// Sends a proposal back for correction. Shared by the deterministic input-schema gate and the
    /// Judge's `.revise` verdict, so both revision paths emit identical worklog/session/receipt/
    /// performance signals. Callers are responsible for recording the `.decided(.revise)` worklog
    /// entry if it hasn't already been recorded.
    private func revise(_ instructions: String, proposal: ActionProposal, toolID: String, startedAt: Date) async -> ToolCallOutcome {
        let correlationID = proposal.resolvedCorrelationID
        await updateSession(correlationID: correlationID, defaultGoal: proposal.intent, actor: proposal.actor) { session in
            session.block(reason: instructions)
        }
        await publish(.workflowBlocked(reason: instructions), correlationID: correlationID)
        let evidence = await emit(proposal: proposal, toolID: toolID, outcome: .needsRevision, reason: instructions)
        await recordPerformance(
            proposal: proposal,
            toolID: toolID,
            outcome: .needsRevision,
            durationSeconds: Date().timeIntervalSince(startedAt),
            failureReason: instructions
        )
        await publish(.sessionEnded(correlationID: correlationID, status: .blocked), correlationID: correlationID)
        return evidence.succeeded
            ? .needsRevision(instructions: instructions)
            : .evidenceIncomplete(original: .needsRevision(instructions: instructions), failures: evidence.failures)
    }

    private func block(
        _ reason: String,
        proposal: ActionProposal,
        toolID: String,
        startedAt: Date,
        source: PerformanceBlockSource = .other
    ) async -> ToolCallOutcome {
        await record(proposal: proposal, toolID: toolID, event: .blocked(reason: reason))
        let correlationID = proposal.resolvedCorrelationID
        await updateSession(correlationID: correlationID, defaultGoal: proposal.intent, actor: proposal.actor) { session in
            session.block(reason: reason)
        }
        await publish(.workflowBlocked(reason: reason), correlationID: correlationID)
        let evidence = await emit(proposal: proposal, toolID: toolID, outcome: .blocked, reason: reason)
        await recordPerformance(
            proposal: proposal,
            toolID: toolID,
            outcome: .blocked,
            durationSeconds: Date().timeIntervalSince(startedAt),
            failureReason: reason,
            blockSource: source
        )
        await publish(.sessionEnded(correlationID: correlationID, status: .blocked), correlationID: correlationID)
        return evidence.succeeded
            ? .blocked(reason: reason)
            : .evidenceIncomplete(original: .blocked(reason: reason), failures: evidence.failures)
    }

    /// Emits the receipt for a run refused *before* execution.
    ///
    /// Deliberately narrower than ``GovernedReceipt``: a run that never executed has no artifact and
    /// no output, and it was refused before any authority was resolved — recording one would assert
    /// that something permitted an action nothing permitted. The post-execution receipt, which does
    /// carry all three, is emitted by ``StandardAfterToolCallHook``.
    private func emit(
        proposal: ActionProposal,
        toolID: String,
        outcome: GovernedOutcomeKind,
        reason: String? = nil
    ) async -> EvidenceEmissionReport {
        do {
            try await receiptSink.emit(
                GovernedReceipt(
                    proposal: proposal,
                    toolID: toolID,
                    outcome: outcome,
                    reason: reason
                )
            )
            return EvidenceEmissionReport()
        } catch {
            let failure = "Governance receipt persistence failed: \(error.localizedDescription)"
            await publish(
                .workflowBlocked(reason: failure),
                correlationID: proposal.resolvedCorrelationID
            )
            return EvidenceEmissionReport(failures: [failure])
        }
    }

    private func recordPerformance(
        proposal: ActionProposal,
        toolID: String,
        outcome: GovernedOutcomeKind,
        durationSeconds: Double,
        failureReason: String? = nil,
        blockSource: PerformanceBlockSource? = nil
    ) async {
        await performanceSink.record(
            PerformanceSignal(
                toolID: toolID,
                capability: proposal.capability,
                outcome: outcome,
                durationSeconds: durationSeconds,
                runID: proposal.id,
                correlationID: proposal.resolvedCorrelationID,
                failureReason: failureReason,
                blockSource: blockSource
            )
        )
    }

    /// Records one worklog entry for this run.
    ///
    /// `@discardableResult` because only the high-risk mandatory-worklog gate acts on the result;
    /// every other call site records the trace as a side effect and has already committed to its
    /// outcome. The result stays typed so that gate can fail closed on it.
    @discardableResult
    private func record(
        proposal: ActionProposal,
        toolID: String,
        event: WorkflowWorklogEvent,
        authority: AuthorityRef? = nil
    ) async -> WorklogRecordResult {
        await worklog.record(
            WorkflowStepLog(
                // Resolved, not raw: the session and events for this run are filed under the
                // fallback id, so a raw nil here would strand the worklog entry where
                // `steps(forCorrelationID:)` can never find it.
                correlationID: proposal.resolvedCorrelationID,
                toolID: toolID,
                event: event,
                actor: proposal.actor,
                authority: authority,
                workflowRun: proposal.workflowRun
            )
        )
    }

    private func publish(_ event: WorkflowEvent, correlationID: String?) async {
        await eventBus.publish(WorkflowEventEnvelope(event: event, correlationID: correlationID))
    }

    private func ensureSession(for proposal: ActionProposal, correlationID: String) async {
        let memoryTouches = await contextRecorder?.touches(correlationID: correlationID)
            .map(\.sessionMemoryTouch) ?? []

        await updateSession(correlationID: correlationID, defaultGoal: proposal.intent, actor: proposal.actor) { session in
            session.note(goal: proposal.intent)
            session.note(capability: proposal.capability)
            for touch in memoryTouches {
                session.note(memoryTouch: touch)
            }
        }
        await publish(.sessionStarted(correlationID: correlationID, goal: proposal.intent), correlationID: correlationID)
        for touch in memoryTouches {
            switch touch.kind {
            case .contextRefresh:
                await publish(.contextRefreshed(key: touch.key), correlationID: correlationID)
            case .memoryRead, .memoryWrite:
                await publish(.memoryTouched(kind: touch.kind, key: touch.key), correlationID: correlationID)
            }
        }
    }

    /// The outcome of the authority check: either the grant that permits the run, or why it doesn't.
    private enum AuthorityResolution {
        case granted(AuthorityRef)
        case refused(String)
    }

    /// Resolves *which* authority permits this proposal, so the run can record it rather than just
    /// acting on a boolean. With no lease registry configured, standing policy is the authority.
    private func resolveAuthority(for proposal: ActionProposal, correlationID: String) async -> AuthorityResolution {
        guard let leaseRegistry else {
            return .granted(.policyDefault(capability: proposal.capability, reason: "No capability lease registry configured."))
        }
        await publishExpiredLeases(at: Date())
        guard let lease = await leaseRegistry.grantingLease(
            proposal.capability,
            to: proposal.actor,
            correlationID: correlationID,
            scope: CapabilityLeaseScope.defaultScope(for: proposal.capability)
        ) else {
            return .refused("Missing active capability lease for \(proposal.capability.rawValue).")
        }
        return .granted(AuthorityRef(lease: lease))
    }

    private func explicitRestrictionReason(for proposal: ActionProposal, correlationID: String) async -> String? {
        guard let leaseRegistry else { return nil }
        guard let denial = await leaseRegistry.firstDenial(
            for: proposal.capability,
            to: proposal.actor,
            correlationID: correlationID
        ) else {
            return nil
        }
        return "\(denial.kind.displayTitle): \(denial.reason)"
    }

    private func publishExpiredLeases(at now: Date) async {
        guard let leaseRegistry else { return }
        let expired = await leaseRegistry.expiredLeases(at: now)
        for lease in expired {
            await publish(.capabilityLeaseExpired(lease.capability), correlationID: lease.sessionCorrelationID)
        }
    }

    private func notePolicyDecision(_ decision: JudgeDecision, proposal: ActionProposal, correlationID: String) async {
        let message: String
        switch decision {
        case .allow:
            message = "Policy allowed \(proposal.intent)"
        case let .block(reason):
            message = "Policy blocked \(proposal.intent): \(reason)"
        case let .revise(instructions):
            message = "Policy requested revision for \(proposal.intent): \(instructions)"
        case .escalate:
            message = "Policy escalated \(proposal.intent) for approval"
        }
        await updateSession(correlationID: correlationID, defaultGoal: proposal.intent, actor: proposal.actor) { session in
            session.noteExecutionUpdate(message)
        }
        await publish(.policyDecision(message), correlationID: correlationID)
    }

    /// - Parameter actor: Who the session is attributed to when this call is the one that creates it
    ///   (P0.5-602). Always the proposal's actor at every call site, so a session opened by a governed
    ///   run records the same party the run itself is attributed to.
    private func updateSession(
        correlationID: String,
        defaultGoal: String,
        actor: ActorRef,
        _ update: (inout AgentSession) -> Void
    ) async {
        guard let sessionStore else { return }
        var session = await sessionStore.session(correlationID: correlationID)
            ?? AgentSession(correlationID: correlationID, goal: defaultGoal, actor: actor)
        update(&session)
        await sessionStore.upsert(session)
    }

    private static func inferenceTelemetry(from outputFields: [String: String]) -> InferenceTelemetry? {
        InferenceTelemetry(outputFields: outputFields)
    }
}

#if DEBUG
extension GovernedToolPipeline {
    /// Test-only composition helper. Production SPI composition must supply every evidence sink.
    ///
    /// Exposed under its own `RuntimeTesting` SPI, separate from `RuntimeComposition`, so feature
    /// packages can test their tools through the real governed path without gaining access to the
    /// production initializer that ADR-008 deliberately walls off. `#if DEBUG` keeps it out of
    /// release builds entirely, and the defaulted sinks mean a test opts into only the evidence it
    /// asserts on.
    @_spi(RuntimeTesting)
    public static func testing(
        registry: ToolRegistry,
        checks: DeterministicCheckRegistry,
        policy: any ToolPolicyEvaluating = AllowAllToolPolicy(),
        judge: any Judge,
        executor: any ToolExecuting,
        eventBus: any RuntimeEventPublishing = RuntimeEventBus(),
        worklog: any WorklogRecording = InMemoryWorklog(),
        receiptSink: any ReceiptEmitting = InMemoryReceiptEmitter(),
        performanceSink: any PerformanceSignalEmitting = InMemoryPerformanceSignalEmitter(),
        pauseGate: PauseGate? = nil,
        leaseRegistry: CapabilityLeaseRegistry? = nil,
        sessionStore: (any AgentSessionStoring)? = nil,
        contextRecorder: (any RuntimeContextRecording)? = nil,
        approvalRegistry: ApprovalRegistry = ApprovalRegistry(),
        afterToolCallHooks: [any AfterToolCallHook] = []
    ) -> GovernedToolPipeline {
        GovernedToolPipeline(
            registry: registry,
            checks: checks,
            policy: policy,
            judge: judge,
            executor: executor,
            eventBus: eventBus,
            worklog: worklog,
            receiptSink: receiptSink,
            performanceSink: performanceSink,
            pauseGate: pauseGate,
            leaseRegistry: leaseRegistry,
            sessionStore: sessionStore,
            contextRecorder: contextRecorder,
            approvalRegistry: approvalRegistry,
            afterToolCallHooks: afterToolCallHooks
        )
    }
}
#endif
