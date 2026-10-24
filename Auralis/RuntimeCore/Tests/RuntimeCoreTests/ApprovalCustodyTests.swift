import CapabilitiesCore
import Foundation
@_spi(RuntimeTesting) @_spi(ToolRegistration) @testable import RuntimeCore
import Testing

/// Records that a tool executor was invoked.
private actor CustodyExecutor: ToolExecuting {
    private(set) var executionCount = 0

    func execute(
        _ tool: ToolDefinition,
        proposal: ActionProposal,
        authorization: ToolExecutionAuthorization
    ) async throws -> ToolCallArtifact {
        executionCount += 1
        return ToolCallArtifact(toolID: tool.id, summary: "did \(tool.title)")
    }

    func count() -> Int { executionCount }
}

/// A worklog that refuses every write, standing in for an unavailable store.
private struct UnavailableWorklog: WorklogRecording {
    func record(_ step: WorkflowStepLog) async -> WorklogRecordResult {
        .failed(WorklogFailure(operation: .save, message: "disk unavailable"))
    }
}

/// Approval custody must survive refusals the approval itself had no part in.
///
/// The grant is one-shot, so *when* it is consumed decides whether a transient machine state costs a
/// person their authorization. These pin the boundary: preconditions that precede governance leave it
/// intact, and anything from the governance evaluation onward spends it.
@Suite("Approval custody")
struct ApprovalCustodyTests {
    private func pipeline(
        gate: PauseGate? = nil,
        worklog: any WorklogRecording = InMemoryWorklog(),
        registry: ApprovalRegistry,
        executor: CustodyExecutor,
        impact: ActionImpactClass = .externalImpact
    ) async -> GovernedToolPipeline {
        let tool = ToolDefinition(
            id: "act",
            title: "Act",
            capability: .signMessage,
            impact: impact
        )
        let tools = ToolRegistry()
        await tools.register(tool)
        return GovernedToolPipeline.testing(
            registry: tools,
            checks: DeterministicCheckRegistry(),
            judge: ObserveModeJudge(isObserveMode: false),
            executor: executor,
            worklog: worklog,
            pauseGate: gate,
            approvalRegistry: registry
        )
    }

    private func proposal(impact: ActionImpactClass = .externalImpact) -> ActionProposal {
        ActionProposal(
            actor: .human,
            intent: "do the thing",
            capability: .signMessage,
            impact: impact,
            correlationID: "corr"
        )
    }

    @Test("pausing while an approval is pending does not spend it")
    func pauseDoesNotConsumeApproval() async {
        let gate = PauseGate(paused: false)
        let approvals = ApprovalRegistry()
        let executor = CustodyExecutor()
        let pipeline = await pipeline(gate: gate, registry: approvals, executor: executor)

        guard case let .needsApproval(pending) = await pipeline.run(toolID: "act", proposal: proposal()) else {
            Issue.record("expected the confirmation-class proposal to escalate")
            return
        }

        // The operator pauses activity, then clears the approval.
        await gate.setPaused(true)
        guard case let .blocked(reason) = await pipeline.resumeApproved(pending) else {
            Issue.record("expected a paused resume to block")
            return
        }
        #expect(reason.contains("Paused"))
        // The grant is untouched: the pause said nothing about whether this action was authorized.
        #expect(await approvals.toolID(for: pending) == "act")

        // Unpausing lets the *same* approval through, with no second trip past the person.
        await gate.setPaused(false)
        guard case .executed = await pipeline.resumeApproved(pending) else {
            Issue.record("the same approval must still be usable once activity resumes")
            return
        }
        #expect(await executor.count() == 1)
        #expect(await approvals.toolID(for: pending) == nil)
    }

    @Test("a refusal for an unavailable worklog does not spend a high-risk approval")
    func mandatoryWorklogFailureDoesNotConsumeApproval() async {
        let approvals = ApprovalRegistry()
        let executor = CustodyExecutor()
        // Raise the approval against a healthy worklog…
        let healthy = await pipeline(registry: approvals, executor: executor, impact: .highRisk)
        guard case let .needsApproval(pending) = await healthy.run(
            toolID: "act",
            proposal: proposal(impact: .highRisk)
        ) else {
            Issue.record("expected the high-risk proposal to escalate")
            return
        }

        // …then clear it while the worklog is refusing writes. High-risk work needs its mandatory
        // trace, so the run is refused — but the refusal is about the store, not the authorization.
        let degraded = await pipeline(
            worklog: UnavailableWorklog(),
            registry: approvals,
            executor: executor,
            impact: .highRisk
        )
        guard case let .evidenceIncomplete(original, failures) = await degraded.resumeApproved(pending) else {
            Issue.record("expected an incomplete-evidence refusal")
            return
        }
        guard case .blocked = original else {
            Issue.record("expected the underlying outcome to be blocked, got \(original)")
            return
        }
        #expect(failures.contains { $0.contains("disk unavailable") })
        #expect(await executor.count() == 0)
        #expect(await approvals.toolID(for: pending) == "act")
    }

    @Test("governance evaluating an approval spends it even when it refuses")
    func governanceRefusalStillConsumesApproval() async {
        let approvals = ApprovalRegistry()
        let executor = CustodyExecutor()
        let tool = ToolDefinition(id: "act", title: "Act", capability: .signMessage, impact: .highRisk)
        let tools = ToolRegistry()
        await tools.register(tool)
        // Observe mode blocks state-changing work outright, so the resume reaches the judge and is
        // refused there — past the point of no return.
        let pipeline = GovernedToolPipeline.testing(
            registry: tools,
            checks: DeterministicCheckRegistry(),
            judge: ObserveModeJudge(isObserveMode: false),
            executor: executor,
            approvalRegistry: approvals
        )
        guard case let .needsApproval(pending) = await pipeline.run(
            toolID: "act",
            proposal: proposal(impact: .highRisk)
        ) else {
            Issue.record("expected escalation")
            return
        }

        let observing = GovernedToolPipeline.testing(
            registry: tools,
            checks: DeterministicCheckRegistry(),
            judge: ObserveModeJudge(isObserveMode: true),
            executor: executor,
            approvalRegistry: approvals
        )
        guard case .blocked = await observing.resumeApproved(pending) else {
            Issue.record("expected Observe mode to refuse the state-changing action")
            return
        }
        // Spent: governance judged this exact grant, so it must not authorize a second attempt.
        #expect(await approvals.toolID(for: pending) == nil)
        #expect(await executor.count() == 0)
    }

    @Test("an approval is still single-use on the happy path")
    func approvalRemainsOneShot() async {
        let approvals = ApprovalRegistry()
        let executor = CustodyExecutor()
        let pipeline = await pipeline(registry: approvals, executor: executor)

        guard case let .needsApproval(pending) = await pipeline.run(toolID: "act", proposal: proposal()) else {
            Issue.record("expected escalation")
            return
        }
        guard case .executed = await pipeline.resumeApproved(pending) else {
            Issue.record("expected the approved run to execute")
            return
        }
        guard case let .blocked(reason) = await pipeline.resumeApproved(pending) else {
            Issue.record("a spent approval must not authorize a replay")
            return
        }
        #expect(reason.contains("already used"))
        #expect(await executor.count() == 1)
    }
}
