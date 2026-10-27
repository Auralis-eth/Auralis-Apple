import AuralisPrimaryModels
@testable import AutopilotCore
import AuralisFoundation
import AuralisRuntime
import PolicyCore
import Testing

/// Captures worklog entries so a test can assert the planner's deliberation was recorded.
private actor RecordingWorklog: WorklogRecording {
    private var steps: [WorkflowStepLog] = []
    func record(_ step: WorkflowStepLog) -> WorklogRecordResult {
        steps.append(step)
        return .recorded
    }
    func recorded() -> [WorkflowStepLog] { steps }
}

/// A gate backed by the *real* PolicyCore evaluation in Observe mode — the shipping app's
/// current posture. Proves the whole stack composes against actual policy, not a stub.
private struct ObserveModeGate: PolicyActionGating {
    func attempt(_ action: PolicyControlledAction, actor: ActorRef) async -> PolicyGateResult {
        await ActionPolicyGate.attempt(action, mode: .observe, actor: actor)
    }
}

/// Executes by recording the step; used to confirm which steps actually ran.
@MainActor
private final class RecordingExecutor: StepExecuting {
    private(set) var executed: [PlanStep] = []
    func execute(_ step: PlanStep) async throws -> StepExecutionOutcome {
        executed.append(step)
        return StepExecutionOutcome(summary: "ran \(step.title)")
    }
}

/// Named rather than a fabricated default, so the ladder tests carry the same attribution a real
/// caller must supply (P0.5-602).
private let ladderActor = ActorRef(kind: .workflow, identifier: "autopilot.ladder")

@MainActor
struct AutopilotLadderTests {
    @Test("in Observe mode a real goal runs its read-only steps then stops at the state change")
    func observeModeRunsReadThenBlocks() async {
        let executor = RecordingExecutor()
        let runner = AutopilotRunner(
            planner: DeterministicGoalPlanner(),
            authorizer: AutopilotAuthorizer(gate: ObserveModeGate(), actor: ladderActor),
            executor: executor
        )

        let (plan, result) = await runner.run(PlanningGoal(text: "organize my music library"))

        // The plan is observe → assist → execute.
        #expect(plan.steps.map(\.kind) == [.observe, .assist, .execute])
        // Only the read-only and advisory steps ran; the execute step was blocked by policy.
        #expect(executor.executed.map(\.kind) == [.observe, .assist])
        #expect(result.isComplete == false)

        guard case .blocked = result.reports.last?.status else {
            Issue.record("expected the execute step to be blocked in Observe mode")
            return
        }
    }

    @Test("marking a routine trusted still cannot run a state change while policy is in Observe mode")
    func trustedRoutineStillBlockedInObserveMode() async {
        let executor = RecordingExecutor()
        let runner = AutopilotRunner(
            planner: DeterministicGoalPlanner(),
            authorizer: AutopilotAuthorizer(
                gate: ObserveModeGate(),
                trustedRoutines: TrustedRoutineAllowlist([.autoOrganization]),
                actor: ladderActor
            ),
            executor: executor
        )

        let (_, result) = await runner.run(PlanningGoal(text: "organize my music library"))

        #expect(executor.executed.map(\.kind) == [.observe, .assist])
        guard case .blocked = result.reports.last?.status else {
            Issue.record("trust must not bypass the Observe-mode policy block")
            return
        }
    }

    @Test("an untrusted planner cannot escalate into wallet signing in Observe mode")
    func maliciousPlannerCannotEscalateCapabilities() async {
        let executor = RecordingExecutor()
        let runner = AutopilotRunner(
            planner: MaliciousPlanner(),
            authorizer: AutopilotAuthorizer(gate: ObserveModeGate(), actor: ladderActor),
            executor: executor
        )

        let (plan, result) = await runner.run(PlanningGoal(text: "summarize my wallet"))

        #expect(plan.steps.map(\.capability) == [.signMessage])
        #expect(executor.executed.isEmpty)
        #expect(result.isComplete == false)
        guard case .blocked = result.reports.first?.status else {
            Issue.record("expected the planner's unauthorized signing step to be blocked")
            return
        }
    }

    /// Cancelling the task running a goal must stop the plan, including its read-only steps — a
    /// cancelled run should stop spending I/O and inference, not merely stop mutating state. Neither
    /// the orchestrator nor the executor consults `Task.isCancelled`, so the authorizer is the only
    /// thing standing between a cancelled run and the rest of its plan.
    ///
    /// Deterministic, not racy: this suite is `@MainActor` and the child task inherits that isolation,
    /// so its body cannot start until this method suspends at the `await`, after `cancel()`.
    @Test("cancelling a run stops the plan instead of executing the rest of it")
    func cancellationHaltsTheRun() async {
        let executor = RecordingExecutor()
        let runner = AutopilotRunner(
            planner: DeterministicGoalPlanner(),
            authorizer: AutopilotAuthorizer(gate: ObserveModeGate(), actor: ladderActor),
            executor: executor
        )

        let task = Task { @MainActor in
            await runner.run(PlanningGoal(text: "organize my music library"))
        }
        task.cancel()
        let (_, result) = await task.value

        // Without the cancellation check the observe and assist steps run (see
        // `observeModeRunsReadThenBlocks`); cancelled, nothing executes at all.
        #expect(executor.executed.isEmpty)
        #expect(result.isComplete == false)
        guard case let .blocked(reason)? = result.reports.first?.authorization else {
            Issue.record("expected the first step of a cancelled run to be blocked")
            return
        }
        #expect(reason.contains("cancelled"))
    }

    @Test("the planner's deliberation is recorded to the worklog as a considered entry")
    func recordsPlannerDeliberationToWorklog() async {
        let worklog = RecordingWorklog()
        let runner = AutopilotRunner(
            planner: DeterministicGoalPlanner(),
            authorizer: AutopilotAuthorizer(gate: ObserveModeGate(), actor: ladderActor),
            executor: RecordingExecutor(),
            worklog: worklog
        )

        _ = await runner.run(PlanningGoal(text: "organize my music library"), correlationID: "corr-plan")

        let steps = await worklog.recorded()
        let considered = steps.first { step in
            if case .considered = step.event { return true }
            return false
        }
        #expect(considered?.correlationID == "corr-plan")
        #expect(considered?.toolID == "planner.deterministic")
        guard case let .considered(candidates)? = considered?.event else {
            Issue.record("expected a considered worklog entry")
            return
        }
        // The matched template is selected; the others are recorded as rejected.
        #expect(candidates.contains { $0.wasSelected })
        #expect(candidates.contains { !$0.wasSelected })

        // A template planner ran no model, so the deliberation is the workflow's own work.
        #expect(considered?.actor.kind == .workflow)
        #expect(considered?.actor.identifier == "planner.deterministic")
        #expect(considered?.actor.inference == nil)
    }

    /// P0.5-602 — when the plan came from a model, the deliberation entry is attributed to that model
    /// with its inference provenance, not flattened into an anonymous workflow actor.
    @Test("a model-backed planner's deliberation is attributed to the model with provenance")
    func recordsModelPlannerAttributionToWorklog() async {
        let route = ModelRoute(
            id: "test.remote.opus",
            provider: "anthropic",
            modelClass: "opus",
            locality: .remote
        )
        let worklog = RecordingWorklog()
        let runner = AutopilotRunner(
            planner: StubModelPlanner(route: route),
            authorizer: AutopilotAuthorizer(gate: ObserveModeGate(), actor: ladderActor),
            executor: RecordingExecutor(),
            worklog: worklog
        )

        _ = await runner.run(PlanningGoal(text: "inspect my library"), correlationID: "corr-model-plan")

        let considered = await worklog.recorded().first { step in
            if case .considered = step.event { return true }
            return false
        }
        let actor = considered?.actor
        #expect(actor?.kind == .model)
        #expect(actor?.identifier == "planner.model")
        #expect(actor?.inference?.locality == .remote)
        #expect(actor?.inference?.provider == "anthropic")
        #expect(actor?.inference?.modelClass == "opus")
    }
}

/// An explicitly untrusted planner double that attempts to turn a read-only request into a
/// wallet-signing operation. The authorization boundary must treat its output as data, not authority.
private struct MaliciousPlanner: GoalPlanning {
    let name = "malicious-test-planner"

    func makePlan(for goal: PlanningGoal) async -> Plan {
        Plan(
            goal: goal,
            steps: [
                PlanStep(
                    capability: .signMessage,
                    kind: .execute,
                    title: "Sign an unrelated message",
                    rationale: "Attempt a capability escalation."
                )
            ],
            summary: "Escalate a harmless request into wallet authority."
        )
    }
}

/// A planner double that reports model-backed deliberation telemetry without calling a model.
private struct StubModelPlanner: GoalPlanning {
    let name = "stub-model"

    let route: ModelRoute

    func makePlan(for goal: PlanningGoal) async -> Plan {
        Plan(
            goal: goal,
            steps: [
                PlanStep(
                    capability: .musicLibraryClassification,
                    kind: .observe,
                    title: "Inspect library",
                    rationale: "Gather context first."
                )
            ],
            summary: "Inspect the library.",
            deliberation: PlanDeliberation(
                planner: "model",
                candidates: [
                    PlanCandidate(
                        title: "Inspect library",
                        capability: .musicLibraryClassification,
                        isSelected: true,
                        rationale: "Model selected a safe read-only step."
                    )
                ],
                telemetry: InferenceTelemetry(
                    route: route,
                    promptTokens: 12,
                    completionTokens: 4,
                    durationSeconds: 0.05,
                    estimatedCost: 0,
                    tokensEstimated: false
                )
            )
        )
    }
}
