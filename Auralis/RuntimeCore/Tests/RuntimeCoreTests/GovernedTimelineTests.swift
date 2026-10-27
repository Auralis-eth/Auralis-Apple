import AuralisFoundation
import Foundation
@_spi(RuntimeTesting) @_spi(ToolRegistration) @testable import RuntimeCore
import Testing

private actor TimelineEventRecorder: RuntimeEventPublishing {
    private var envelopes: [WorkflowEventEnvelope] = []

    func publish(_ event: WorkflowEventEnvelope) { envelopes.append(event) }
    func allEvents() -> [WorkflowEvent] { envelopes.map(\.event) }
}

private struct TimelineExecutor: ToolExecuting {
    func execute(
        _ tool: ToolDefinition,
        proposal: ActionProposal,
        authorization: ToolExecutionAuthorization
    ) async throws -> ToolCallArtifact {
        ToolCallArtifact(toolID: tool.id, summary: "ran")
    }
}

private struct TimelineUnavailableWorklog: WorklogRecording {
    func record(_ step: WorkflowStepLog) async -> WorklogRecordResult {
        .failed(WorklogFailure(operation: .save, message: "disk unavailable"))
    }
}

/// What the runtime *says happened* has to match what happened.
///
/// Every refused run reads the same way to an operator, so the announcements a run publishes and the
/// evidence it emits are part of its contract, not incidental logging.
@Suite("Governed timeline")
struct GovernedTimelineTests {
    private func tool(impact: ActionImpactClass = .readOnly) -> ToolDefinition {
        ToolDefinition(id: "read", title: "Read", capability: .audioPlayback, impact: impact)
    }

    private func proposal(impact: ActionImpactClass = .readOnly) -> ActionProposal {
        ActionProposal(
            actor: .human,
            intent: "read the thing",
            capability: .audioPlayback,
            impact: impact,
            correlationID: "corr"
        )
    }

    /// A run refused for want of authority must never have been announced as allowed.
    ///
    /// `.allow` is the judge's verdict, not permission: authority resolution can still refuse it.
    /// Publishing the verdict before that check left "Policy allowed X" and "blocked" side by side in
    /// the timeline, which reads as the runtime contradicting itself.
    @Test("an authority refusal is never preceded by a policy-allowed announcement")
    func authorityRefusalIsNotAnnouncedAsAllowed() async {
        let tools = ToolRegistry()
        await tools.register(tool())
        let events = TimelineEventRecorder()
        // A lease registry with no matching grant: the judge allows, authority refuses.
        let pipeline = GovernedToolPipeline.testing(
            registry: tools,
            checks: DeterministicCheckRegistry(),
            judge: ObserveModeJudge(isObserveMode: false),
            executor: TimelineExecutor(),
            eventBus: events,
            leaseRegistry: CapabilityLeaseRegistry()
        )

        guard case let .blocked(reason) = await pipeline.run(toolID: "read", proposal: proposal()) else {
            Issue.record("expected the missing lease to refuse the run")
            return
        }
        #expect(reason.contains("Missing active capability lease"))

        let published = await events.allEvents()
        let policyDecisions = published.compactMap { event -> String? in
            guard case let .policyDecision(message) = event else { return nil }
            return message
        }
        #expect(policyDecisions.isEmpty)
        #expect(published.contains { if case .workflowBlocked = $0 { true } else { false } })
    }

    @Test("a permitted run is still announced as allowed")
    func permittedRunIsAnnounced() async {
        let tools = ToolRegistry()
        await tools.register(tool())
        let events = TimelineEventRecorder()
        let pipeline = GovernedToolPipeline.testing(
            registry: tools,
            checks: DeterministicCheckRegistry(),
            judge: ObserveModeJudge(isObserveMode: false),
            executor: TimelineExecutor(),
            eventBus: events
        )

        guard case .executed = await pipeline.run(toolID: "read", proposal: proposal()) else {
            Issue.record("expected the read-only run to execute")
            return
        }
        let published = await events.allEvents()
        #expect(published.contains { event in
            guard case let .policyDecision(message) = event else { return false }
            return message.contains("Policy allowed")
        })
    }

    @Test("a judge refusal is still announced")
    func judgeRefusalIsAnnounced() async {
        let tools = ToolRegistry()
        await tools.register(tool(impact: .highRisk))
        let events = TimelineEventRecorder()
        let pipeline = GovernedToolPipeline.testing(
            registry: tools,
            checks: DeterministicCheckRegistry(),
            judge: ObserveModeJudge(isObserveMode: true),
            executor: TimelineExecutor(),
            eventBus: events
        )

        guard case .blocked = await pipeline.run(
            toolID: "read",
            proposal: proposal(impact: .highRisk)
        ) else {
            Issue.record("expected Observe mode to refuse the high-risk run")
            return
        }
        let published = await events.allEvents()
        #expect(published.contains { event in
            guard case let .policyDecision(message) = event else { return false }
            return message.contains("Policy blocked")
        })
    }

    /// The mandatory-worklog refusal used to be the one terminal outcome that published a bare
    /// `workflowBlocked` and returned — no receipt, no session end, no performance signal — so a
    /// high-risk action refused for a degraded store left almost no trace of having been attempted.
    @Test("a high-risk run refused for an unavailable worklog still emits full evidence")
    func mandatoryWorklogRefusalEmitsEvidence() async {
        let tools = ToolRegistry()
        await tools.register(tool(impact: .highRisk))
        let events = TimelineEventRecorder()
        let receipts = InMemoryReceiptEmitter()
        let performance = InMemoryPerformanceSignalEmitter()
        let sessions = InMemoryAgentSessionStore()
        let pipeline = GovernedToolPipeline.testing(
            registry: tools,
            checks: DeterministicCheckRegistry(),
            judge: ObserveModeJudge(isObserveMode: false),
            executor: TimelineExecutor(),
            eventBus: events,
            worklog: TimelineUnavailableWorklog(),
            receiptSink: receipts,
            performanceSink: performance,
            sessionStore: sessions
        )

        guard case let .evidenceIncomplete(original, failures) = await pipeline.run(
            toolID: "read",
            proposal: proposal(impact: .highRisk)
        ) else {
            Issue.record("expected an incomplete-evidence refusal")
            return
        }
        guard case .blocked = original else {
            Issue.record("expected the underlying outcome to be blocked, got \(original)")
            return
        }
        #expect(failures.contains { $0.contains("disk unavailable") })

        // A receipt records the attempt and why it was refused.
        let emitted = await receipts.allReceipts()
        #expect(emitted.count == 1)
        #expect(emitted.first?.outcome == .blocked)
        #expect(emitted.first?.reason?.contains("mandatory worklog is unavailable") == true)

        // The refusal is attributed to infrastructure, not to policy or a missing authority.
        let signals = await performance.allSignals()
        #expect(signals.count == 1)
        #expect(signals.first?.outcome == .blocked)
        #expect(signals.first?.blockSource == .infrastructure)

        // The session is closed rather than left open forever.
        let session = await sessions.session(correlationID: "corr")
        #expect(session?.status == .blocked)
        #expect(session?.endedAt != nil)

        let published = await events.allEvents()
        #expect(published.contains { event in
            guard case let .sessionEnded(_, status) = event else { return false }
            return status == .blocked
        })
    }
}
