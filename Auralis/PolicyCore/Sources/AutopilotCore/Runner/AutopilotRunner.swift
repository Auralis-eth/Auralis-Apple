import PlannerCore
import RuntimeCore

/// A convenience that wires the whole loop end to end: plan a goal, then orchestrate it
/// under autopilot authorization. The feature layer supplies the planner (deterministic
/// or model-backed), the policy-gate-backed authorizer, and the executor that actually
/// performs cleared steps.
///
/// This is intentionally thin — it exists so a caller doesn't have to re-assemble the
/// planner/orchestrator/authorizer triangle at every call site, and so "run this goal on
/// autopilot" reads as one call.
@MainActor
public struct AutopilotRunner {
    private let planner: any GoalPlanning
    private let authorizer: any StepAuthorizing
    private let executor: any StepExecuting
    /// Optional worklog sink. When present, the planner's deliberation (what it considered and
    /// rejected) is recorded as a `considered` entry so Mission Control can show the reasoning.
    private let worklog: (any WorklogRecording)?

    public init(
        planner: any GoalPlanning,
        authorizer: any StepAuthorizing,
        executor: any StepExecuting,
        worklog: (any WorklogRecording)? = nil
    ) {
        self.planner = planner
        self.authorizer = authorizer
        self.executor = executor
        self.worklog = worklog
    }

    /// Plans the goal and runs the plan, returning both so the caller can show the plan
    /// review alongside what actually happened (and what is waiting on confirmation).
    ///
    /// `correlationID` ties the recorded deliberation to the rest of the workflow's trace.
    public func run(
        _ goal: PlanningGoal,
        correlationID: String? = nil
    ) async -> (plan: Plan, result: OrchestrationResult) {
        let plan = await planner.makePlan(for: goal)
        await recordDeliberation(plan.deliberation, correlationID: correlationID)
        // Both sides of the join are derived from the same deliberation here, which is the only
        // place that knows which planner actually wrote the steps. The authorizer was assembled
        // before the goal was planned, so until this rebind it filed proposals under the planner
        // that was *installed* while the `considered` entry above recorded the planner that *ran* —
        // and a model-backed planner that degrades to templates makes those two differ on the
        // ordinary path, not an exotic one.
        let orchestrator = SequentialPlanOrchestrator(
            authorizer: authorizer.attributing(to: plan.deliberation.plannerActor),
            executor: executor
        )
        let result = await orchestrator.run(plan)
        return (plan, result)
    }

    /// Translates the planner's `PlanDeliberation` into a planner-agnostic worklog entry.
    private func recordDeliberation(_ deliberation: PlanDeliberation, correlationID: String?) async {
        guard let worklog, !deliberation.isEmpty else { return }
        let candidates = deliberation.candidates.map { candidate in
            ConsideredCandidate(
                title: candidate.title,
                capability: candidate.capability,
                wasSelected: candidate.isSelected,
                rationale: candidate.rationale
            )
        }
        // A model-backed planner is a `.model` actor with real inference provenance; only the
        // deterministic template planner is a bare workflow (P0.5-602). Derived through
        // `PlanDeliberation.plannerActor` rather than rebuilt here, so this entry and the
        // proposals the authorizer files cannot drift apart — they are now literally the same
        // expression evaluated once each.
        let plannerActor = deliberation.plannerActor
        await worklog.record(
            WorkflowStepLog(
                correlationID: correlationID,
                toolID: plannerActor.identifier ?? "planner",
                event: .considered(candidates),
                actor: plannerActor
            )
        )
    }
}
