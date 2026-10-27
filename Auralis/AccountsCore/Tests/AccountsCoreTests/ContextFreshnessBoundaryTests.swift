import AuralisFoundation
import Foundation
@testable import AccountsCore
@_spi(RuntimeComposition) @_spi(RuntimeTesting) @_spi(ToolRegistration) @testable import AuralisRuntime
import Testing

private actor RecordingExecutor: ToolExecuting {
    private var count = 0

    func execute(
        _ tool: ToolDefinition,
        proposal: ActionProposal,
        authorization: ToolExecutionAuthorization
    ) async throws -> ToolCallArtifact {
        count += 1
        return ToolCallArtifact(toolID: tool.id, summary: "ran \(tool.title)")
    }

    func runs() -> Int { count }
}

/// `context.fresh` only enforces anything if the "now" it measures against belongs to the governed
/// boundary. These pin the two ways it previously enforced nothing: an actor supplying its own
/// evaluation instant, and an approval whose frozen timestamps were replayed at resume.
@Suite("Context freshness boundary")
struct ContextFreshnessBoundaryTests {
    private static let capability = CapabilityID.audioPlayback

    private func proposal(
        _ parameters: [String: String],
        impact: ActionImpactClass = .readOnly
    ) -> ActionProposal {
        ActionProposal(
            actor: ActorRef(kind: .operatorAgent, identifier: "operator.test"),
            intent: "do the thing",
            capability: Self.capability,
            impact: impact,
            requiredCheckIDs: [StandardCheckID.contextFresh],
            correlationID: "corr-freshness",
            parameters: parameters
        )
    }

    private func makePipeline(
        maxAge: TimeInterval,
        impact: ActionImpactClass = .readOnly,
        executor: RecordingExecutor
    ) async -> (GovernedToolPipeline, ToolDefinition) {
        let tool = ToolDefinition(
            id: "act",
            title: "Act",
            capability: Self.capability,
            impact: impact,
            requiredCheckIDs: [StandardCheckID.contextFresh]
        )
        let registry = ToolRegistry()
        await registry.register(tool)
        let checks = DeterministicCheckRegistry()
        await checks.register(ContextFreshnessCheck(maxAge: maxAge))
        let pipeline = GovernedToolPipeline.testing(
            registry: registry,
            checks: checks,
            // Not Observe: a confirmation-class proposal escalates here rather than being blocked
            // outright, which is what gives these tests an approval to resume.
            judge: ObserveModeJudge(isObserveMode: false),
            executor: executor
        )
        return (pipeline, tool)
    }

    private func now() -> String { String(Date().timeIntervalSince1970) }

    // MARK: - The stamp itself

    @Test("the boundary stamp replaces an evaluation instant the actor supplied")
    func stampOverwritesCallerSuppliedEvaluationInstant() {
        let forged = proposal([
            StandardCheckParameterKey.contextRefreshedAt: "1000000",
            StandardCheckParameterKey.freshnessEvaluatedAt: "1000000"
        ])

        let stamped = forged.stampingFreshnessEvaluation(at: Date(timeIntervalSince1970: 1_000_500))

        #expect(stamped.parameters[StandardCheckParameterKey.freshnessEvaluatedAt] == "1000500.0")
        // The capture claim travels with the proposal and is not the boundary's to rewrite.
        #expect(stamped.parameters[StandardCheckParameterKey.contextRefreshedAt] == "1000000")
    }

    @Test("a proposal that claims no capture time gains no parameter")
    func stampLeavesProposalsWithoutACaptureTimeAlone() {
        let unstamped = proposal(["address": "0x0"])

        let stamped = unstamped.stampingFreshnessEvaluation(at: Date())

        // Adding an undeclared parameter here would make every strict input schema reject its own
        // host's proposal, so the stamp is confined to proposals the check can actually evaluate.
        #expect(stamped == unstamped)
        #expect(stamped.parameters[StandardCheckParameterKey.freshnessEvaluatedAt] == nil)
    }

    @Test("stamping preserves the identity the trace is filed under")
    func stampPreservesTraceIdentity() {
        let original = proposal([StandardCheckParameterKey.contextRefreshedAt: "1000000"])

        let stamped = original.stampingFreshnessEvaluation(at: Date(timeIntervalSince1970: 1_000_001))

        #expect(stamped.id == original.id)
        #expect(stamped.workflowRun == original.workflowRun)
        #expect(stamped.resolvedCorrelationID == original.resolvedCorrelationID)
        #expect(stamped.requiredCheckIDs == original.requiredCheckIDs)
    }

    @Test("stripping the stamp is what makes an approved proposal recognizable on resume")
    func strippingTheStampIsIdentityPreserving() {
        let original = proposal([StandardCheckParameterKey.contextRefreshedAt: "1000000"])
        let atEscalation = original.stampingFreshnessEvaluation(at: Date(timeIntervalSince1970: 1_000_001))
        let atResume = original.stampingFreshnessEvaluation(at: Date(timeIntervalSince1970: 1_000_099))

        #expect(atEscalation != atResume)
        #expect(atEscalation.withoutFreshnessEvaluationStamp == atResume.withoutFreshnessEvaluationStamp)
        // Stripping is only ever allowed to drop that one boundary-owned key.
        #expect(atResume.withoutFreshnessEvaluationStamp == original)
    }

    // MARK: - Forgery

    @Test("an actor cannot pair an ancient capture with its own convenient now")
    func forgedEvaluationInstantIsRefused() async {
        let executor = RecordingExecutor()
        let (pipeline, tool) = await makePipeline(maxAge: 300, executor: executor)

        // Age 0 by the proposal's own arithmetic, and a 1970 capture time in reality.
        let outcome = await pipeline.run(
            toolID: tool.id,
            proposal: proposal([
                StandardCheckParameterKey.contextRefreshedAt: "1000000",
                StandardCheckParameterKey.freshnessEvaluatedAt: "1000000"
            ])
        )

        guard case let .blocked(reason) = outcome else {
            Issue.record("expected a forged evaluation instant to be refused, got \(outcome)")
            return
        }
        #expect(reason.contains(StandardCheckID.contextFresh))
        #expect(reason.contains("stale"))
        #expect(await executor.runs() == 0)
    }

    @Test("a genuinely fresh capture still runs")
    func freshCaptureExecutes() async {
        let executor = RecordingExecutor()
        let (pipeline, tool) = await makePipeline(maxAge: 300, executor: executor)

        let outcome = await pipeline.run(
            toolID: tool.id,
            proposal: proposal([StandardCheckParameterKey.contextRefreshedAt: now()])
        )

        guard case .executed = outcome else {
            Issue.record("expected a fresh proposal to execute, got \(outcome)")
            return
        }
        #expect(await executor.runs() == 1)
    }

    // MARK: - Stale approvals

    @Test("an approval cleared after the freshness window is refused at resume")
    func staleApprovalIsRefusedAtResume() async throws {
        let executor = RecordingExecutor()
        let (pipeline, tool) = await makePipeline(
            maxAge: 0.05,
            impact: .externalImpact,
            executor: executor
        )

        let escalated = await pipeline.run(
            toolID: tool.id,
            proposal: proposal(
                [StandardCheckParameterKey.contextRefreshedAt: now()],
                impact: .externalImpact
            )
        )
        guard case let .needsApproval(pending) = escalated else {
            Issue.record("expected the proposal to escalate, got \(escalated)")
            return
        }

        // Time spent in the approval inbox is exactly what this check exists to measure. Comfortably
        // past a 50ms window so the assertion does not turn on scheduling.
        try await Task.sleep(for: .milliseconds(500))
        let resumed = await pipeline.resumeApproved(pending)

        guard case let .blocked(reason) = resumed else {
            Issue.record("expected a stale approval to be refused, got \(resumed)")
            return
        }
        #expect(reason.contains(StandardCheckID.contextFresh))
        #expect(reason.contains("stale"))
        #expect(await executor.runs() == 0)
    }

    @Test("an approval cleared inside the window still resumes")
    func promptApprovalStillResumes() async {
        let executor = RecordingExecutor()
        let (pipeline, tool) = await makePipeline(
            maxAge: 300,
            impact: .externalImpact,
            executor: executor
        )

        let escalated = await pipeline.run(
            toolID: tool.id,
            proposal: proposal(
                [StandardCheckParameterKey.contextRefreshedAt: now()],
                impact: .externalImpact
            )
        )
        guard case let .needsApproval(pending) = escalated else {
            Issue.record("expected the proposal to escalate, got \(escalated)")
            return
        }

        // Re-stamping the evaluation instant must not make the resumed proposal look like a *different*
        // proposal to the approval-aware judge, which would escalate it again forever.
        let resumed = await pipeline.resumeApproved(pending)

        guard case .executed = resumed else {
            Issue.record("expected a prompt approval to execute, got \(resumed)")
            return
        }
        #expect(await executor.runs() == 1)
    }

    @Test("both time inputs land on the record, so the verdict replays")
    func evaluatedInstantIsRecordedForReplay() async throws {
        let executor = RecordingExecutor()
        let (pipeline, tool) = await makePipeline(
            maxAge: 300,
            impact: .externalImpact,
            executor: executor
        )
        let capturedAt = now()

        let escalated = await pipeline.run(
            toolID: tool.id,
            proposal: proposal(
                [StandardCheckParameterKey.contextRefreshedAt: capturedAt],
                impact: .externalImpact
            )
        )

        guard case let .needsApproval(pending) = escalated else {
            Issue.record("expected the proposal to escalate, got \(escalated)")
            return
        }
        // `context.fresh` stays a pure function of what was written down rather than of when a replay
        // happens to run, so the escalated record has to carry the evaluated instant too.
        let recorded = pending.proposal.parameters
        #expect(recorded[StandardCheckParameterKey.contextRefreshedAt] == capturedAt)
        let evaluatedAt = try #require(recorded[StandardCheckParameterKey.freshnessEvaluatedAt])
        #expect(TimeInterval(evaluatedAt) != nil)
    }
}
