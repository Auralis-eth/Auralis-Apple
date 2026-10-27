import AuralisFoundation
import Foundation
@_spi(RuntimeComposition) @_spi(RuntimeTesting) @_spi(ToolRegistration) @testable import RuntimeCore
import Testing

/// Records that a tool executor was invoked, and can be told to throw.
private actor SpyExecutor: ToolExecuting {
    private(set) var executed = false
    private let shouldThrow: Bool

    init(shouldThrow: Bool = false) { self.shouldThrow = shouldThrow }

    func execute(
        _ tool: ToolDefinition,
        proposal: ActionProposal,
        authorization: ToolExecutionAuthorization
    ) async throws -> ToolCallArtifact {
        executed = true
        if shouldThrow {
            throw NSError(domain: "test", code: 1)
        }
        return ToolCallArtifact(toolID: tool.id, summary: "did \(tool.title)")
    }

    func wasExecuted() -> Bool { executed }
}

/// A judge that always sends proposals back for revision — exercises the Judge `.revise` branch.
private struct RevisingJudge: Judge {
    let instructions: String
    func judge(_ proposal: ActionProposal, checkResults: [DeterministicCheckResult]) async -> JudgeDecision {
        .revise(instructions: instructions)
    }
}

private actor EventRecorder: RuntimeEventPublishing {
    private var envelopes: [WorkflowEventEnvelope] = []

    func publish(_ event: WorkflowEventEnvelope) {
        envelopes.append(event)
    }

    func allEvents() -> [WorkflowEventEnvelope] {
        envelopes
    }
}

private actor SequencedPolicy: ToolPolicyEvaluating {
    private var decisions: [JudgeDecision]
    private(set) var evaluationCount = 0

    init(_ decisions: [JudgeDecision]) {
        self.decisions = decisions
    }

    func evaluate(
        _ proposal: ActionProposal,
        checkResults: [DeterministicCheckResult]
    ) -> JudgeDecision {
        evaluationCount += 1
        return decisions.isEmpty ? .allow : decisions.removeFirst()
    }

    func count() -> Int { evaluationCount }
}

private struct FailingReceiptEmitter: ReceiptEmitting {
    struct Failure: LocalizedError {
        var errorDescription: String? { "receipt store unavailable" }
    }

    func emit(_ receipt: GovernedReceipt) async throws {
        throw Failure()
    }
}

private actor FailingWorklog: WorklogRecording {
    func record(_ step: WorkflowStepLog) -> WorklogRecordResult {
        .failed(WorklogFailure(operation: .save, message: "disk unavailable"))
    }
}

@Suite("GovernedToolPipeline")
struct GovernedToolPipelineTests {
    @Test("high-risk execution fails closed when its opening worklog entry cannot persist")
    func highRiskFailsClosedWhenWorklogFails() async {
        let tool = ToolDefinition(
            id: "sign",
            title: "Sign",
            capability: .signMessage,
            impact: .highRisk
        )
        let registry = ToolRegistry()
        await registry.register(tool)
        let executor = SpyExecutor()
        let pipeline = GovernedToolPipeline.testing(
            registry: registry,
            checks: DeterministicCheckRegistry(),
            judge: ObserveModeJudge(isObserveMode: false),
            executor: executor,
            worklog: FailingWorklog()
        )

        let outcome = await pipeline.run(
            toolID: tool.id,
            proposal: proposal(capability: .signMessage, impact: .highRisk)
        )

        guard case let .evidenceIncomplete(original, failures) = outcome else {
            Issue.record("expected evidenceIncomplete, got \(outcome)")
            return
        }
        #expect(original.failureReason.contains("mandatory worklog"))
        #expect(failures.contains { $0.contains("disk unavailable") })
        #expect(await executor.wasExecuted() == false)
    }

    private func makePipeline(
        tools: [ToolDefinition],
        checks: [any DeterministicCheck] = [],
        judge: any Judge = ObserveModeJudge(isObserveMode: true),
        executor: any ToolExecuting
    ) async -> (GovernedToolPipeline, InMemoryWorklog) {
        let registry = ToolRegistry()
        for tool in tools { await registry.register(tool) }
        let checkRegistry = DeterministicCheckRegistry()
        for check in checks { await checkRegistry.register(check) }
        let worklog = InMemoryWorklog()
        let pipeline = GovernedToolPipeline.testing(
            registry: registry,
            checks: checkRegistry,
            judge: judge,
            executor: executor,
            eventBus: RuntimeEventBus(),
            worklog: worklog,
            receiptSink: InMemoryReceiptEmitter(),
            performanceSink: InMemoryPerformanceSignalEmitter()
        )
        return (pipeline, worklog)
    }

    private func proposal(
        capability: CapabilityID,
        impact: ActionImpactClass,
        checkIDs: [String] = [],
        approvals: [String] = []
    ) -> ActionProposal {
        ActionProposal(
            actor: ActorRef(kind: .workflow, identifier: "planner"),
            intent: "do the thing",
            capability: capability,
            impact: impact,
            requiredApprovals: approvals,
            requiredCheckIDs: checkIDs,
            correlationID: "corr-1"
        )
    }

    @Test
    func policyStageCanBlockBeforeJudgeAndExecution() async {
        let tool = ToolDefinition(id: "read", title: "Read", capability: .audioPlayback, impact: .readOnly)
        let executor = SpyExecutor()
        let registry = ToolRegistry()
        await registry.register(tool)
        let policy = SequencedPolicy([.block(reason: "standing policy denied")])
        let pipeline = GovernedToolPipeline.testing(
            registry: registry,
            checks: DeterministicCheckRegistry(),
            policy: policy,
            judge: ObserveModeJudge(isObserveMode: false),
            executor: executor,
            eventBus: RuntimeEventBus(),
            worklog: InMemoryWorklog(),
            receiptSink: InMemoryReceiptEmitter(),
            performanceSink: InMemoryPerformanceSignalEmitter()
        )

        let outcome = await pipeline.run(
            toolID: tool.id,
            proposal: proposal(capability: tool.capability, impact: tool.impact)
        )

        guard case let .blocked(reason) = outcome else {
            Issue.record("expected policy block, got \(outcome)")
            return
        }
        #expect(reason == "standing policy denied")
        #expect(await policy.count() == 1)
        #expect(await executor.wasExecuted() == false)
    }

    @Test
    func approvedResumeRerunsPolicyAndHonorsNewBlock() async {
        let tool = ToolDefinition(id: "write", title: "Write", capability: .audioPlayback, impact: .externalImpact)
        let proposal = proposal(capability: tool.capability, impact: tool.impact)
        let approval = ApprovalRequest(proposal: proposal, prompt: "approve?")
        let policy = SequencedPolicy([
            .escalate(approvalRequest: approval),
            .block(reason: "policy changed")
        ])
        let executor = SpyExecutor()
        let registry = ToolRegistry()
        await registry.register(tool)
        let pipeline = GovernedToolPipeline.testing(
            registry: registry,
            checks: DeterministicCheckRegistry(),
            policy: policy,
            judge: ObserveModeJudge(isObserveMode: false),
            executor: executor,
            eventBus: RuntimeEventBus(),
            worklog: InMemoryWorklog(),
            receiptSink: InMemoryReceiptEmitter(),
            performanceSink: InMemoryPerformanceSignalEmitter()
        )

        guard case let .needsApproval(pending) = await pipeline.run(toolID: tool.id, proposal: proposal) else {
            Issue.record("expected approval")
            return
        }
        guard case let .blocked(reason) = await pipeline.resumeApproved(pending) else {
            Issue.record("expected fresh policy block")
            return
        }
        #expect(reason == "policy changed")
        #expect(await policy.count() == 2)
        #expect(await executor.wasExecuted() == false)
    }

    @Test
    func approvalDoesNotAuthorizeANewEscalation() async {
        let tool = ToolDefinition(id: "write", title: "Write", capability: .audioPlayback, impact: .externalImpact)
        let proposal = proposal(capability: tool.capability, impact: tool.impact)
        let first = ApprovalRequest(proposal: proposal, prompt: "Approve transfer to Alice?")
        let changed = ApprovalRequest(proposal: proposal, prompt: "Approve transfer to Bob?")
        let policy = SequencedPolicy([.escalate(approvalRequest: first), .escalate(approvalRequest: changed)])
        let executor = SpyExecutor()
        let registry = ToolRegistry()
        await registry.register(tool)
        let pipeline = GovernedToolPipeline.testing(
            registry: registry,
            checks: DeterministicCheckRegistry(),
            policy: policy,
            judge: ObserveModeJudge(isObserveMode: false),
            executor: executor,
            eventBus: RuntimeEventBus(),
            worklog: InMemoryWorklog(),
            receiptSink: InMemoryReceiptEmitter(),
            performanceSink: InMemoryPerformanceSignalEmitter()
        )

        guard case let .needsApproval(pending) = await pipeline.run(toolID: tool.id, proposal: proposal) else {
            Issue.record("expected first approval")
            return
        }
        guard case let .needsApproval(replacement) = await pipeline.resumeApproved(pending) else {
            Issue.record("a changed escalation must require its own approval")
            return
        }
        #expect(replacement.prompt == changed.prompt)
        #expect(await executor.wasExecuted() == false)
    }

    @Test
    func requiredReceiptFailureIsSurfacedAfterExecution() async {
        let tool = ToolDefinition(
            id: "write",
            title: "Write",
            capability: .audioPlayback,
            impact: .reversibleWrite,
            requiresReceipt: true
        )
        let executor = SpyExecutor()
        let registry = ToolRegistry()
        await registry.register(tool)
        let pipeline = GovernedToolPipeline.testing(
            registry: registry,
            checks: DeterministicCheckRegistry(),
            policy: AllowAllToolPolicy(),
            judge: ObserveModeJudge(isObserveMode: false),
            executor: executor,
            eventBus: RuntimeEventBus(),
            worklog: InMemoryWorklog(),
            receiptSink: FailingReceiptEmitter(),
            performanceSink: InMemoryPerformanceSignalEmitter()
        )

        let outcome = await pipeline.run(
            toolID: tool.id,
            proposal: proposal(capability: tool.capability, impact: tool.impact)
        )

        guard case let .evidenceIncomplete(original, failures) = outcome else {
            Issue.record("expected surfaced evidence failure, got \(outcome)")
            return
        }
        guard case .executed = original else {
            Issue.record("expected the original execution outcome to be preserved")
            return
        }
        #expect(failures.contains { $0.contains("receipt store unavailable") })
        #expect(await executor.wasExecuted())
    }

    @Test
    func preExecutionReceiptFailureIsSurfaced() async {
        let tool = ToolDefinition(id: "read", title: "Read", capability: .audioPlayback, impact: .readOnly)
        let registry = ToolRegistry()
        await registry.register(tool)
        let executor = SpyExecutor()
        let pipeline = GovernedToolPipeline.testing(
            registry: registry,
            checks: DeterministicCheckRegistry(),
            policy: SequencedPolicy([.block(reason: "denied")]),
            judge: ObserveModeJudge(isObserveMode: false),
            executor: executor,
            eventBus: RuntimeEventBus(),
            worklog: InMemoryWorklog(),
            receiptSink: FailingReceiptEmitter(),
            performanceSink: InMemoryPerformanceSignalEmitter()
        )

        let outcome = await pipeline.run(
            toolID: tool.id,
            proposal: proposal(capability: tool.capability, impact: tool.impact)
        )

        guard case let .evidenceIncomplete(original, failures) = outcome else {
            Issue.record("expected surfaced pre-execution evidence failure, got \(outcome)")
            return
        }
        #expect(original == .blocked(reason: "denied"))
        #expect(failures.contains { $0.contains("receipt store unavailable") })
        #expect(await executor.wasExecuted() == false)
    }

    @Test
    func allowedReadOnlyActionExecutes() async {
        let tool = ToolDefinition(id: "read", title: "Read", capability: .audioPlayback, impact: .readOnly)
        let executor = SpyExecutor()
        let (pipeline, worklog) = await makePipeline(tools: [tool], executor: executor)

        let outcome = await pipeline.run(toolID: "read", proposal: proposal(capability: .audioPlayback, impact: .readOnly))

        guard case .executed = outcome else {
            Issue.record("expected executed, got \(outcome)")
            return
        }
        #expect(await executor.wasExecuted())
        #expect(await worklog.allSteps().count >= 3) // proposed, checks, decided, executed
    }

    @Test
    func proposalWithoutCorrelationIDStillProducesRetrievableTrace() async {
        // Regression: the pipeline files sessions and events under `resolvedCorrelationID`, so the
        // worklog must use the same key. Writing the raw nil here stranded the whole trace where
        // `steps(forCorrelationID:)` could never find it.
        let tool = ToolDefinition(id: "read", title: "Read", capability: .audioPlayback, impact: .readOnly)
        let uncorrelated = ActionProposal(
            actor: ActorRef(kind: .workflow, identifier: "planner"),
            intent: "do the thing",
            capability: .audioPlayback,
            impact: .readOnly,
            correlationID: nil
        )
        let (pipeline, worklog) = await makePipeline(tools: [tool], executor: SpyExecutor())

        _ = await pipeline.run(toolID: "read", proposal: uncorrelated)

        let expectedKey = uncorrelated.id.uuidString
        #expect(uncorrelated.resolvedCorrelationID == expectedKey)
        let steps = await worklog.steps(forCorrelationID: expectedKey)
        #expect(steps.isEmpty == false)
        #expect(steps.count == (await worklog.allSteps().count))
        #expect(steps.allSatisfy { $0.correlationID == expectedKey })
    }

    @Test
    func proposalWithCorrelationIDKeepsIt() async {
        let subject = proposal(capability: .audioPlayback, impact: .readOnly)
        #expect(subject.resolvedCorrelationID == "corr-1")
    }

    // --- Adversarial: untrusted planner (N2) ---

    @Test
    func unknownToolIsBlockedAndNeverExecutes() async {
        let executor = SpyExecutor()
        let (pipeline, _) = await makePipeline(tools: [], executor: executor)

        let outcome = await pipeline.run(toolID: "ghost", proposal: proposal(capability: .runPlugin, impact: .externalImpact))

        #expect(outcome == .blocked(reason: "Unknown tool “ghost”."))
        #expect(await executor.wasExecuted() == false)
    }

    @Test
    func capabilityMismatchIsBlocked() async {
        // Tool exercises audioPlayback, but the malicious proposal claims signMessage.
        let tool = ToolDefinition(id: "play", title: "Play", capability: .audioPlayback, impact: .readOnly)
        let executor = SpyExecutor()
        let (pipeline, _) = await makePipeline(tools: [tool], executor: executor)

        let outcome = await pipeline.run(toolID: "play", proposal: proposal(capability: .signMessage, impact: .readOnly))

        guard case let .blocked(reason) = outcome else {
            Issue.record("expected blocked, got \(outcome)")
            return
        }
        #expect(reason.contains("Capability mismatch"))
        #expect(await executor.wasExecuted() == false)
    }

    @Test
    func impactEscalationIsBlocked() async {
        // Tool is declared readOnly; the proposal tries to smuggle a highRisk impact.
        let tool = ToolDefinition(id: "play", title: "Play", capability: .audioPlayback, impact: .readOnly)
        let executor = SpyExecutor()
        let (pipeline, _) = await makePipeline(tools: [tool], executor: executor)

        let outcome = await pipeline.run(toolID: "play", proposal: proposal(capability: .audioPlayback, impact: .highRisk))

        guard case let .blocked(reason) = outcome else {
            Issue.record("expected blocked, got \(outcome)")
            return
        }
        #expect(reason.contains("Impact mismatch"))
        #expect(await executor.wasExecuted() == false)
    }

    @Test
    func failedCheckBlocksExecution() async {
        let tool = ToolDefinition(
            id: "read",
            title: "Read",
            capability: .audioPlayback,
            impact: .readOnly,
            requiredCheckIDs: ["always.fails"]
        )
        let failing = ClosureCheck(id: "always.fails") { _ in
            DeterministicCheckResult(checkID: "always.fails", passed: false, detail: "nope")
        }
        let executor = SpyExecutor()
        let (pipeline, _) = await makePipeline(tools: [tool], checks: [failing], executor: executor)

        let outcome = await pipeline.run(toolID: "read", proposal: proposal(capability: .audioPlayback, impact: .readOnly))

        guard case let .blocked(reason) = outcome else {
            Issue.record("expected blocked, got \(outcome)")
            return
        }
        #expect(reason.contains("always.fails"))
        #expect(await executor.wasExecuted() == false)
    }

    @Test
    func unregisteredRequiredCheckFailsClosed() async {
        let tool = ToolDefinition(
            id: "read",
            title: "Read",
            capability: .audioPlayback,
            impact: .readOnly,
            requiredCheckIDs: ["never.registered"]
        )
        let executor = SpyExecutor()
        let (pipeline, _) = await makePipeline(tools: [tool], executor: executor)

        let outcome = await pipeline.run(toolID: "read", proposal: proposal(capability: .audioPlayback, impact: .readOnly))

        guard case .blocked = outcome else {
            Issue.record("expected blocked (fail-closed), got \(outcome)")
            return
        }
        #expect(await executor.wasExecuted() == false)
    }

    @Test
    func highRiskInObserveModeIsBlocked() async {
        let tool = ToolDefinition(id: "sign", title: "Sign", capability: .signMessage, impact: .highRisk)
        let executor = SpyExecutor()
        let (pipeline, _) = await makePipeline(tools: [tool], executor: executor)

        let outcome = await pipeline.run(toolID: "sign", proposal: proposal(capability: .signMessage, impact: .highRisk))

        guard case let .blocked(reason) = outcome else {
            Issue.record("expected blocked, got \(outcome)")
            return
        }
        #expect(reason.contains("Observe mode"))
        #expect(await executor.wasExecuted() == false)
    }

    @Test
    func externalImpactEscalatesForApproval() async {
        // Outside Observe mode, a confirmation-class action escalates rather than blocks.
        let tool = ToolDefinition(id: "open", title: "Open Link", capability: .runPlugin, impact: .externalImpact)
        let executor = SpyExecutor()
        let (pipeline, _) = await makePipeline(
            tools: [tool],
            judge: ObserveModeJudge(isObserveMode: false),
            executor: executor
        )

        let outcome = await pipeline.run(toolID: "open", proposal: proposal(capability: .runPlugin, impact: .externalImpact))

        guard case .needsApproval = outcome else {
            Issue.record("expected needsApproval, got \(outcome)")
            return
        }
        #expect(await executor.wasExecuted() == false)
    }

    @Test
    func declaredApprovalEscalatesEvenWhenJudgeAllowsAndResumesExactlyOnce() async {
        let tool = ToolDefinition(id: "read", title: "Read", capability: .audioPlayback, impact: .readOnly)
        let executor = SpyExecutor()
        let (pipeline, _) = await makePipeline(
            tools: [tool],
            judge: ObserveModeJudge(isObserveMode: false),
            executor: executor
        )
        let request = proposal(
            capability: .audioPlayback,
            impact: .readOnly,
            approvals: ["owner"]
        )

        let initial = await pipeline.run(toolID: tool.id, proposal: request)
        let approval: ApprovalRequest
        if case let .needsApproval(pending) = initial {
            approval = pending
        } else {
            Issue.record("expected needsApproval, got \(initial)")
            return
        }
        #expect(await executor.wasExecuted() == false)

        guard case .executed = await pipeline.resumeApproved(approval) else {
            Issue.record("expected the exact pending approval to execute")
            return
        }
        #expect(await executor.wasExecuted())

        guard case let .blocked(reason) = await pipeline.resumeApproved(approval) else {
            Issue.record("expected replayed approval to be blocked")
            return
        }
        #expect(reason.contains("already used"))
    }

    @Test
    func alteredOrFabricatedApprovalCannotExecute() async {
        let tool = ToolDefinition(id: "read", title: "Read", capability: .audioPlayback, impact: .readOnly)
        let executor = SpyExecutor()
        let (pipeline, _) = await makePipeline(
            tools: [tool],
            judge: ObserveModeJudge(isObserveMode: false),
            executor: executor
        )
        let proposal = proposal(
            capability: .audioPlayback,
            impact: .readOnly,
            approvals: ["owner"]
        )
        let initial = await pipeline.run(toolID: tool.id, proposal: proposal)
        guard case let .needsApproval(pending) = initial else {
            Issue.record("expected needsApproval, got \(initial)")
            return
        }
        let altered = ApprovalRequest(id: pending.id, proposal: pending.proposal, prompt: "Different prompt")

        guard case .blocked = await pipeline.resumeApproved(altered) else {
            Issue.record("expected altered approval to be blocked")
            return
        }
        #expect(await executor.wasExecuted() == false)

        guard case .executed = await pipeline.resumeApproved(pending) else {
            Issue.record("an altered attempt must not consume the genuine approval")
            return
        }
    }

    @Test
    func emitsReceiptOnExecutionAndBlock() async {
        // A reversibleWrite tool requires a receipt, so its successful run records one.
        let tool = ToolDefinition(id: "write", title: "Write", capability: .audioPlayback, impact: .reversibleWrite)
        let registry = ToolRegistry()
        await registry.register(tool)
        let sink = InMemoryReceiptEmitter()
        let pipeline = GovernedToolPipeline.testing(
            registry: registry,
            checks: DeterministicCheckRegistry(),
            judge: ObserveModeJudge(isObserveMode: false),
            executor: SpyExecutor(),
            receiptSink: sink
        )

        _ = await pipeline.run(toolID: "write", proposal: proposal(capability: .audioPlayback, impact: .reversibleWrite))
        _ = await pipeline.run(toolID: "ghost", proposal: proposal(capability: .runPlugin, impact: .readOnly))

        let receipts = await sink.allReceipts()
        #expect(receipts.count == 2)
        #expect(receipts.first?.outcome == .executed)
        #expect(receipts.last?.outcome == .blocked)
    }

    @Test
    func readOnlyExecutionSkipsReceiptWhenNotRequired() async {
        // readOnly.requiresReceipt == false, so a successful read records no durable receipt —
        // the `requiresReceipt` flag actually gates emission rather than being informational.
        let tool = ToolDefinition(id: "read", title: "Read", capability: .audioPlayback, impact: .readOnly)
        let registry = ToolRegistry()
        await registry.register(tool)
        let sink = InMemoryReceiptEmitter()
        let executor = SpyExecutor()
        let pipeline = GovernedToolPipeline.testing(
            registry: registry,
            checks: DeterministicCheckRegistry(),
            judge: ObserveModeJudge(isObserveMode: false),
            executor: executor,
            receiptSink: sink
        )

        let outcome = await pipeline.run(toolID: "read", proposal: proposal(capability: .audioPlayback, impact: .readOnly))

        guard case .executed = outcome else {
            Issue.record("expected executed, got \(outcome)")
            return
        }
        #expect(await executor.wasExecuted())
        #expect(await sink.allReceipts().isEmpty)
    }

    // --- BeforeToolCall: input schema → revise (P0.5-201 / P0.5-203) ---

    @Test
    func malformedInputIsSentBackForRevisionAndNeverExecutes() async {
        let tool = ToolDefinition(
            id: "send",
            title: "Send",
            capability: .audioPlayback,
            impact: .readOnly,
            inputSchema: ToolSchema(fields: [
                ToolSchemaField(name: "address", kind: .address),
                ToolSchemaField(name: "amount", kind: .number)
            ])
        )
        let executor = SpyExecutor()
        let (pipeline, worklog) = await makePipeline(tools: [tool], executor: executor)

        // Missing "address" and a non-numeric "amount".
        let request = ActionProposal(
            actor: ActorRef(kind: .workflow, identifier: "planner"),
            intent: "send funds",
            capability: .audioPlayback,
            impact: .readOnly,
            correlationID: "corr-1",
            parameters: ["amount": "lots"]
        )

        let outcome = await pipeline.run(toolID: "send", proposal: request)

        guard case let .needsRevision(instructions) = outcome else {
            Issue.record("expected needsRevision, got \(outcome)")
            return
        }
        #expect(instructions.contains("address"))
        #expect(instructions.contains("amount"))
        #expect(await executor.wasExecuted() == false)
        // The revision is recorded as a governance decision in the worklog.
        let decided = await worklog.allSteps().contains { step in
            if case .decided(.revise) = step.event { return true }
            return false
        }
        #expect(decided)
    }

    @Test
    func wellFormedInputPassesSchemaGateAndExecutes() async {
        let tool = ToolDefinition(
            id: "send",
            title: "Send",
            capability: .audioPlayback,
            impact: .readOnly,
            inputSchema: ToolSchema(fields: [
                ToolSchemaField(name: "address", kind: .address)
            ])
        )
        let executor = SpyExecutor()
        let (pipeline, _) = await makePipeline(tools: [tool], executor: executor)

        let request = ActionProposal(
            actor: ActorRef(kind: .workflow, identifier: "planner"),
            intent: "send funds",
            capability: .audioPlayback,
            impact: .readOnly,
            correlationID: "corr-1",
            parameters: ["address": "0x000102030405060708090a0b0c0d0e0f10111213"]
        )

        let outcome = await pipeline.run(toolID: "send", proposal: request)

        guard case .executed = outcome else {
            Issue.record("expected executed, got \(outcome)")
            return
        }
        #expect(await executor.wasExecuted())
    }

    @Test
    func revisionEmitsReceiptAndPerformanceSignal() async {
        let tool = ToolDefinition(
            id: "send",
            title: "Send",
            capability: .audioPlayback,
            impact: .readOnly,
            inputSchema: ToolSchema(fields: [ToolSchemaField(name: "address", kind: .address)])
        )
        let registry = ToolRegistry()
        await registry.register(tool)
        let sink = InMemoryReceiptEmitter()
        let performance = InMemoryPerformanceSignalEmitter()
        let pipeline = GovernedToolPipeline.testing(
            registry: registry,
            checks: DeterministicCheckRegistry(),
            judge: ObserveModeJudge(isObserveMode: false),
            executor: SpyExecutor(),
            receiptSink: sink,
            performanceSink: performance
        )

        _ = await pipeline.run(
            toolID: "send",
            proposal: ActionProposal(
                actor: ActorRef(kind: .workflow, identifier: "planner"),
                intent: "send funds",
                capability: .audioPlayback,
                impact: .readOnly,
                correlationID: "corr-1",
                parameters: [:]
            )
        )

        let receipts = await sink.allReceipts()
        #expect(receipts.count == 1)
        #expect(receipts.first?.outcome == .needsRevision)
        let signals = await performance.allSignals()
        #expect(signals.count == 1)
        #expect(signals.first?.outcome == .needsRevision)
    }

    @Test
    func judgeRevisionIsHonoredAndNeverExecutes() async {
        let tool = ToolDefinition(id: "read", title: "Read", capability: .audioPlayback, impact: .readOnly)
        let executor = SpyExecutor()
        let (pipeline, _) = await makePipeline(
            tools: [tool],
            judge: RevisingJudge(instructions: "Add a memo before resubmitting."),
            executor: executor
        )

        let outcome = await pipeline.run(toolID: "read", proposal: proposal(capability: .audioPlayback, impact: .readOnly))

        guard case let .needsRevision(instructions) = outcome else {
            Issue.record("expected needsRevision, got \(outcome)")
            return
        }
        #expect(instructions == "Add a memo before resubmitting.")
        #expect(await executor.wasExecuted() == false)
    }

    @Test
    func judgeRevisionForAChecklessToolStillRecordsTheChecksEvaluatedStep() async {
        // Regression: the pipeline told the schema gate apart from a governance verdict by testing
        // `checkResults.isEmpty`. A tool requiring no deterministic checks produces an empty result
        // set for a Judge `.revise` too, so this proposal took the schema-gate shortcut and skipped
        // both the `.checksEvaluated` worklog entry and the capability-restriction lookup.
        // `BeforeToolCallResult.origin` now reports the stage, so only a real schema rejection
        // short-circuits. Nothing executed on either path — this is about the trace being complete.
        let tool = ToolDefinition(id: "read", title: "Read", capability: .audioPlayback, impact: .readOnly)
        let executor = SpyExecutor()
        let (pipeline, worklog) = await makePipeline(
            tools: [tool],
            judge: RevisingJudge(instructions: "Add a memo before resubmitting."),
            executor: executor
        )

        let outcome = await pipeline.run(toolID: "read", proposal: proposal(capability: .audioPlayback, impact: .readOnly))

        guard case .needsRevision = outcome else {
            Issue.record("expected needsRevision, got \(outcome)")
            return
        }
        let events = await worklog.steps(forCorrelationID: "corr-1").map(\.event)
        #expect(events.contains { if case .checksEvaluated = $0 { return true } else { return false } })
        #expect(events.contains { if case .decided(.revise) = $0 { return true } else { return false } })
        #expect(await executor.wasExecuted() == false)
    }

    @Test
    func schemaRejectionShortCircuitsWithoutAChecksEvaluatedStep() async {
        // The other half of the discriminator: a genuine input-schema rejection happens before any
        // check runs, so it must *not* claim to have evaluated checks.
        let tool = ToolDefinition(
            id: "send",
            title: "Send",
            capability: .audioPlayback,
            impact: .readOnly,
            inputSchema: ToolSchema(fields: [ToolSchemaField(name: "address", kind: .address)])
        )
        let executor = SpyExecutor()
        let (pipeline, worklog) = await makePipeline(
            tools: [tool],
            judge: ObserveModeJudge(isObserveMode: false),
            executor: executor
        )

        let outcome = await pipeline.run(toolID: "send", proposal: proposal(capability: .audioPlayback, impact: .readOnly))

        guard case .needsRevision = outcome else {
            Issue.record("expected needsRevision, got \(outcome)")
            return
        }
        let events = await worklog.steps(forCorrelationID: "corr-1").map(\.event)
        #expect(events.contains { if case .checksEvaluated = $0 { return true } else { return false } } == false)
        #expect(await executor.wasExecuted() == false)
    }

    // --- AfterToolCall: output schema enforcement ---

    @Test
    func outputViolatingSchemaIsReportedAsFailure() async {
        // The executor returns an artifact with no outputFields, violating the required output schema.
        let tool = ToolDefinition(
            id: "quote",
            title: "Quote",
            capability: .audioPlayback,
            impact: .readOnly,
            outputSchema: ToolSchema(fields: [ToolSchemaField(name: "price", kind: .number)])
        )
        let executor = SpyExecutor()
        let (pipeline, _) = await makePipeline(tools: [tool], executor: executor)

        let outcome = await pipeline.run(toolID: "quote", proposal: proposal(capability: .audioPlayback, impact: .readOnly))

        guard case let .failed(reason) = outcome else {
            Issue.record("expected failed, got \(outcome)")
            return
        }
        #expect(reason.contains("price"))
        // The executor did run — enforcement happens on its output.
        #expect(await executor.wasExecuted())
    }

    @Test
    func pausedGateBlocksBeforeExecution() async {
        let tool = ToolDefinition(id: "read", title: "Read", capability: .audioPlayback, impact: .readOnly)
        let registry = ToolRegistry()
        await registry.register(tool)
        let executor = SpyExecutor()
        let pipeline = GovernedToolPipeline.testing(
            registry: registry,
            checks: DeterministicCheckRegistry(),
            judge: ObserveModeJudge(isObserveMode: false),
            executor: executor,
            pauseGate: PauseGate(paused: true)
        )

        let outcome = await pipeline.run(toolID: "read", proposal: proposal(capability: .audioPlayback, impact: .readOnly))

        guard case let .blocked(reason) = outcome else {
            Issue.record("expected paused pipeline to block, got \(outcome)")
            return
        }
        #expect(reason.contains("Paused"))
        #expect(await executor.wasExecuted() == false)
    }

    @Test
    func attachedLeaseRegistryRequiresMatchingLeaseBeforeExecution() async {
        let tool = ToolDefinition(id: "read", title: "Read", capability: .audioPlayback, impact: .readOnly)
        let toolRegistry = ToolRegistry()
        await toolRegistry.register(tool)
        let leaseRegistry = CapabilityLeaseRegistry()
        let executor = SpyExecutor()
        let pipeline = GovernedToolPipeline.testing(
            registry: toolRegistry,
            checks: DeterministicCheckRegistry(),
            judge: ObserveModeJudge(isObserveMode: false),
            executor: executor,
            leaseRegistry: leaseRegistry
        )
        let request = proposal(capability: .audioPlayback, impact: .readOnly)

        let missing = await pipeline.run(toolID: "read", proposal: request)
        guard case let .blocked(missingReason) = missing else {
            Issue.record("expected missing lease to block, got \(missing)")
            return
        }
        #expect(missingReason.contains("Missing active capability lease"))
        #expect(await executor.wasExecuted() == false)

        await leaseRegistry.grant(CapabilityLease(
            capability: .audioPlayback,
            grantedTo: ActorRef(kind: .workflow, identifier: "other-planner"),
            sessionCorrelationID: "corr-1",
            expiresAt: Date().addingTimeInterval(600)
        ))
        let wrongActor = await pipeline.run(toolID: "read", proposal: request)
        guard case .blocked = wrongActor else {
            Issue.record("expected wrong actor lease to block, got \(wrongActor)")
            return
        }

        await leaseRegistry.grant(CapabilityLease(
            capability: .audioPlayback,
            grantedTo: request.actor,
            sessionCorrelationID: "other-correlation",
            expiresAt: Date().addingTimeInterval(600)
        ))
        let wrongSession = await pipeline.run(toolID: "read", proposal: request)
        guard case .blocked = wrongSession else {
            Issue.record("expected wrong session lease to block, got \(wrongSession)")
            return
        }

        await leaseRegistry.grant(CapabilityLease(
            capability: .audioPlayback,
            grantedTo: request.actor,
            sessionCorrelationID: "corr-1",
            expiresAt: Date().addingTimeInterval(600)
        ))
        let matched = await pipeline.run(toolID: "read", proposal: request)
        guard case .executed = matched else {
            Issue.record("expected matching lease to execute, got \(matched)")
            return
        }
        #expect(await executor.wasExecuted())
    }

    @Test
    func expiredLeaseIsBlockedEvenForMatchingActor() async {
        // A lease that matches capability, actor, and session but has already lapsed must not
        // authorize execution — expiry is enforced at the pipeline boundary, not just in the registry.
        let tool = ToolDefinition(id: "read", title: "Read", capability: .audioPlayback, impact: .readOnly)
        let toolRegistry = ToolRegistry()
        await toolRegistry.register(tool)
        let leaseRegistry = CapabilityLeaseRegistry()
        let executor = SpyExecutor()
        let pipeline = GovernedToolPipeline.testing(
            registry: toolRegistry,
            checks: DeterministicCheckRegistry(),
            judge: ObserveModeJudge(isObserveMode: false),
            executor: executor,
            leaseRegistry: leaseRegistry
        )
        let request = proposal(capability: .audioPlayback, impact: .readOnly)

        await leaseRegistry.grant(CapabilityLease(
            capability: .audioPlayback,
            grantedTo: request.actor,
            sessionCorrelationID: "corr-1",
            grantedAt: Date().addingTimeInterval(-600),
            expiresAt: Date().addingTimeInterval(-1)
        ))

        let outcome = await pipeline.run(toolID: "read", proposal: request)

        guard case let .blocked(reason) = outcome else {
            Issue.record("expected expired lease to block, got \(outcome)")
            return
        }
        #expect(reason.contains("Missing active capability lease"))
        #expect(await executor.wasExecuted() == false)
    }

    @Test
    func executionCompletesSessionAndPublishesExplicitMemoryTouches() async throws {
        let tool = ToolDefinition(id: "read", title: "Read", capability: .audioPlayback, impact: .readOnly)
        let toolRegistry = ToolRegistry()
        await toolRegistry.register(tool)
        let leaseRegistry = CapabilityLeaseRegistry()
        let eventRecorder = EventRecorder()
        let sessionStore = InMemoryAgentSessionStore()
        let contextRecorder = RuntimeContextRecorder()
        let request = ActionProposal(
            actor: ActorRef(kind: .workflow, identifier: "planner"),
            intent: "read memory-backed queue",
            capability: .audioPlayback,
            impact: .readOnly,
            correlationID: "corr-memory"
        )
        await contextRecorder.recordContextRefresh(key: "context.snapshot", correlationID: "corr-memory")
        await contextRecorder.recordMemoryTouch(kind: .memoryRead, key: "memory.playbackQueue", correlationID: "corr-memory")
        await leaseRegistry.grant(CapabilityLease(
            capability: .audioPlayback,
            grantedTo: request.actor,
            sessionCorrelationID: "corr-memory",
            expiresAt: Date().addingTimeInterval(600)
        ))
        let pipeline = GovernedToolPipeline.testing(
            registry: toolRegistry,
            checks: DeterministicCheckRegistry(),
            judge: ObserveModeJudge(isObserveMode: false),
            executor: SpyExecutor(),
            eventBus: eventRecorder,
            leaseRegistry: leaseRegistry,
            sessionStore: sessionStore,
            contextRecorder: contextRecorder
        )

        let outcome = await pipeline.run(toolID: "read", proposal: request)
        guard case .executed = outcome else {
            Issue.record("expected execution, got \(outcome)")
            return
        }

        let session = try #require(await sessionStore.session(correlationID: "corr-memory"))
        #expect(session.status == .completed)
        #expect(session.artifactIDs.count == 1)
        #expect(session.memoryTouched.map(\.key).contains("context.snapshot"))
        #expect(session.memoryTouched.map(\.key).contains("memory.playbackQueue"))

        let events = await eventRecorder.allEvents().map(\.event)
        #expect(events.contains(.contextRefreshed(key: "context.snapshot")))
        #expect(events.contains(.memoryTouched(kind: .memoryRead, key: "memory.playbackQueue")))
        #expect(events.contains(.sessionEnded(correlationID: "corr-memory", status: .completed)))
    }

    @Test
    func explicitRestrictionOverridesMatchingLease() async {
        let tool = ToolDefinition(id: "draft", title: "Draft", capability: .draftTransaction, impact: .highRisk)
        let toolRegistry = ToolRegistry()
        await toolRegistry.register(tool)
        let leaseRegistry = CapabilityLeaseRegistry()
        let request = ActionProposal(
            actor: ActorRef(kind: .workflow, identifier: "planner"),
            intent: "draft transfer",
            capability: .draftTransaction,
            impact: .highRisk,
            correlationID: "corr-deny"
        )
        await leaseRegistry.grant(CapabilityLease(
            capability: .draftTransaction,
            grantedTo: request.actor,
            sessionCorrelationID: "corr-deny",
            expiresAt: Date().addingTimeInterval(600)
        ))
        await leaseRegistry.deny(CapabilityRestriction(
            kind: .walletAccess,
            reason: "Planner may inspect but not touch wallets.",
            sessionCorrelationID: "corr-deny"
        ))
        let pipeline = GovernedToolPipeline.testing(
            registry: toolRegistry,
            checks: DeterministicCheckRegistry(),
            judge: ObserveModeJudge(isObserveMode: false),
            executor: SpyExecutor(),
            leaseRegistry: leaseRegistry
        )

        let outcome = await pipeline.run(toolID: "draft", proposal: request)

        guard case let .blocked(reason) = outcome else {
            Issue.record("expected restriction to block, got \(outcome)")
            return
        }
        #expect(reason.contains("No wallet access"))
    }

    @Test
    func executorErrorIsReportedAsFailure() async {
        let tool = ToolDefinition(id: "read", title: "Read", capability: .audioPlayback, impact: .readOnly)
        let executor = SpyExecutor(shouldThrow: true)
        let (pipeline, _) = await makePipeline(tools: [tool], executor: executor)

        let outcome = await pipeline.run(toolID: "read", proposal: proposal(capability: .audioPlayback, impact: .readOnly))

        guard case .failed = outcome else {
            Issue.record("expected failed, got \(outcome)")
            return
        }
    }

    // --- AfterToolCall: performance signals (P0.5-204) ---

    /// Builds a pipeline that records performance signals into the returned emitter.
    private func makePerformancePipeline(
        tools: [ToolDefinition],
        judge: any Judge = ObserveModeJudge(isObserveMode: true),
        executor: any ToolExecuting
    ) async -> (GovernedToolPipeline, InMemoryPerformanceSignalEmitter) {
        let registry = ToolRegistry()
        for tool in tools { await registry.register(tool) }
        let performance = InMemoryPerformanceSignalEmitter()
        let pipeline = GovernedToolPipeline.testing(
            registry: registry,
            checks: DeterministicCheckRegistry(),
            judge: judge,
            executor: executor,
            performanceSink: performance
        )
        return (pipeline, performance)
    }

    @Test
    func executedActionEmitsSuccessPerformanceSignal() async {
        let tool = ToolDefinition(id: "read", title: "Read", capability: .audioPlayback, impact: .readOnly)
        let (pipeline, performance) = await makePerformancePipeline(tools: [tool], executor: SpyExecutor())

        _ = await pipeline.run(toolID: "read", proposal: proposal(capability: .audioPlayback, impact: .readOnly))

        let signals = await performance.allSignals()
        #expect(signals.count == 1)
        #expect(signals.first?.toolID == "read")
        #expect(signals.first?.outcome == .executed)
        #expect(signals.first?.failureReason == nil)
    }

    @Test
    func failedActionEmitsFailurePerformanceSignal() async {
        let tool = ToolDefinition(id: "read", title: "Read", capability: .audioPlayback, impact: .readOnly)
        let (pipeline, performance) = await makePerformancePipeline(tools: [tool], executor: SpyExecutor(shouldThrow: true))

        _ = await pipeline.run(toolID: "read", proposal: proposal(capability: .audioPlayback, impact: .readOnly))

        let signals = await performance.allSignals()
        #expect(signals.count == 1)
        #expect(signals.first?.outcome == .failed)
        #expect(signals.first?.failureReason != nil)
    }

    @Test
    func blockedActionEmitsBlockedPerformanceSignal() async {
        let (pipeline, performance) = await makePerformancePipeline(tools: [], executor: SpyExecutor())

        _ = await pipeline.run(toolID: "ghost", proposal: proposal(capability: .runPlugin, impact: .externalImpact))

        let signals = await performance.allSignals()
        #expect(signals.count == 1)
        #expect(signals.first?.outcome == .blocked)
        #expect(signals.first?.failureReason == "Unknown tool “ghost”.")
        #expect(signals.first?.blockSource == .other)
    }

    @Test
    func judgeRefusalMarksPerformanceAsPolicyBlocked() async {
        let tool = ToolDefinition(
            id: "external",
            title: "External",
            capability: .runPlugin,
            impact: .externalImpact
        )
        let (pipeline, performance) = await makePerformancePipeline(
            tools: [tool],
            judge: ObserveModeJudge(isObserveMode: true),
            executor: SpyExecutor()
        )

        _ = await pipeline.run(
            toolID: tool.id,
            proposal: proposal(capability: .runPlugin, impact: .externalImpact)
        )

        let signals = await performance.allSignals()
        #expect(signals.first?.outcome == .blocked)
        #expect(signals.first?.blockSource == .policy)
    }

    // --- Authority attribution (P0.5-601/602) ---

    /// The session is the run-level record of the work, so it must carry the grant too — not just
    /// the receipt and worklog. Recorded before execution, so a run that fails partway still shows
    /// what let it start.
    @Test
    func executedRunRecordsTheAuthorizingLeaseOnTheSession() async throws {
        let tool = ToolDefinition(id: "write", title: "Write", capability: .audioPlayback, impact: .reversibleWrite)
        let toolRegistry = ToolRegistry()
        await toolRegistry.register(tool)
        let leaseRegistry = CapabilityLeaseRegistry()
        let sessions = InMemoryAgentSessionStore()
        let pipeline = GovernedToolPipeline.testing(
            registry: toolRegistry,
            checks: DeterministicCheckRegistry(),
            judge: ObserveModeJudge(isObserveMode: false),
            executor: SpyExecutor(),
            leaseRegistry: leaseRegistry,
            sessionStore: sessions
        )
        let request = proposal(capability: .audioPlayback, impact: .reversibleWrite)
        let lease = await leaseRegistry.grant(CapabilityLease(
            capability: .audioPlayback,
            reason: "Planner may write playback state.",
            grantedTo: request.actor,
            sessionCorrelationID: "corr-1",
            expiresAt: Date().addingTimeInterval(600)
        ))

        _ = await pipeline.run(toolID: "write", proposal: request)

        let session = try #require(await sessions.session(correlationID: "corr-1"))
        #expect(session.actor == request.actor)
        let authority = try #require(session.authority)
        #expect(authority.source == .lease)
        #expect(authority.leaseID == lease.id)
    }

    @Test
    func blockedRunLeavesTheSessionWithoutAuthority() async throws {
        // Refused before any grant resolves — the session must not claim one.
        let tool = ToolDefinition(id: "write", title: "Write", capability: .audioPlayback, impact: .reversibleWrite)
        let toolRegistry = ToolRegistry()
        await toolRegistry.register(tool)
        let sessions = InMemoryAgentSessionStore()
        let pipeline = GovernedToolPipeline.testing(
            registry: toolRegistry,
            checks: DeterministicCheckRegistry(),
            judge: ObserveModeJudge(isObserveMode: false),
            executor: SpyExecutor(),
            leaseRegistry: CapabilityLeaseRegistry(),
            sessionStore: sessions
        )

        _ = await pipeline.run(toolID: "write", proposal: proposal(capability: .audioPlayback, impact: .reversibleWrite))

        let session = try #require(await sessions.session(correlationID: "corr-1"))
        #expect(session.authority == nil)
        #expect(session.actor.identifier == "planner")
    }

    /// The pipeline must record *which* grant let a run through, not just act on a yes/no. Without
    /// this, a receipt can say a routine moved money but never say what permitted it.
    @Test
    func executedRunRecordsTheAuthorizingLeaseOnReceiptAndWorklog() async throws {
        let tool = ToolDefinition(id: "write", title: "Write", capability: .audioPlayback, impact: .reversibleWrite)
        let toolRegistry = ToolRegistry()
        await toolRegistry.register(tool)
        let leaseRegistry = CapabilityLeaseRegistry()
        let worklog = InMemoryWorklog()
        let sink = InMemoryReceiptEmitter()
        let pipeline = GovernedToolPipeline.testing(
            registry: toolRegistry,
            checks: DeterministicCheckRegistry(),
            judge: ObserveModeJudge(isObserveMode: false),
            executor: SpyExecutor(),
            worklog: worklog,
            receiptSink: sink,
            leaseRegistry: leaseRegistry
        )
        let request = proposal(capability: .audioPlayback, impact: .reversibleWrite)
        let lease = await leaseRegistry.grant(CapabilityLease(
            capability: .audioPlayback,
            reason: "Planner may write playback state.",
            grantedTo: request.actor,
            sessionCorrelationID: "corr-1",
            expiresAt: Date().addingTimeInterval(600)
        ))

        _ = await pipeline.run(toolID: "write", proposal: request)

        let receipt = try #require(await sink.allReceipts().first)
        let authority = try #require(receipt.authority)
        #expect(authority.source == .lease)
        #expect(authority.leaseID == lease.id)
        #expect(authority.capability == .audioPlayback)
        #expect(authority.reason == "Planner may write playback state.")

        // The executed worklog entry carries the same authority, so the trace and the receipt agree.
        let executedStep = try #require(await worklog.allSteps().first { step in
            if case .executed = step.event { return true }
            return false
        })
        #expect(executedStep.authority?.leaseID == lease.id)

        // Pre-authority entries honestly carry none — the proposal is recorded before any grant is
        // consulted, so claiming an authority there would be a fabrication.
        let proposedStep = try #require(await worklog.allSteps().first { step in
            if case .proposed = step.event { return true }
            return false
        })
        #expect(proposedStep.authority == nil)
    }

    /// A run refused for want of a lease must not claim an authority it never had.
    @Test
    func blockedRunRecordsNoAuthority() async throws {
        let tool = ToolDefinition(id: "write", title: "Write", capability: .audioPlayback, impact: .reversibleWrite)
        let toolRegistry = ToolRegistry()
        await toolRegistry.register(tool)
        let sink = InMemoryReceiptEmitter()
        let pipeline = GovernedToolPipeline.testing(
            registry: toolRegistry,
            checks: DeterministicCheckRegistry(),
            judge: ObserveModeJudge(isObserveMode: false),
            executor: SpyExecutor(),
            receiptSink: sink,
            leaseRegistry: CapabilityLeaseRegistry()
        )

        _ = await pipeline.run(toolID: "write", proposal: proposal(capability: .audioPlayback, impact: .reversibleWrite))

        let receipt = try #require(await sink.allReceipts().first)
        #expect(receipt.outcome == .blocked)
        #expect(receipt.authority == nil)
    }

    /// With no lease registry attached, standing policy is the authority — recorded as such rather
    /// than left blank, so "why was this allowed?" always has an answer.
    @Test
    func runWithoutLeaseRegistryRecordsPolicyDefaultAuthority() async throws {
        let tool = ToolDefinition(id: "write", title: "Write", capability: .audioPlayback, impact: .reversibleWrite)
        let toolRegistry = ToolRegistry()
        await toolRegistry.register(tool)
        let sink = InMemoryReceiptEmitter()
        let pipeline = GovernedToolPipeline.testing(
            registry: toolRegistry,
            checks: DeterministicCheckRegistry(),
            judge: ObserveModeJudge(isObserveMode: false),
            executor: SpyExecutor(),
            receiptSink: sink
        )

        _ = await pipeline.run(toolID: "write", proposal: proposal(capability: .audioPlayback, impact: .reversibleWrite))

        let authority = try #require(await sink.allReceipts().first?.authority)
        #expect(authority.source == .policyDefault)
        #expect(authority.leaseID == nil)
        #expect(authority.capability == .audioPlayback)
    }
}
