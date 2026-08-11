import PlannerCore

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

    public init(
        planner: any GoalPlanning,
        authorizer: any StepAuthorizing,
        executor: any StepExecuting
    ) {
        self.planner = planner
        self.authorizer = authorizer
        self.executor = executor
    }

    /// Plans the goal and runs the plan, returning both so the caller can show the plan
    /// review alongside what actually happened (and what is waiting on confirmation).
    public func run(_ goal: PlanningGoal) async -> (plan: Plan, result: OrchestrationResult) {
        let plan = await planner.makePlan(for: goal)
        let orchestrator = SequentialPlanOrchestrator(authorizer: authorizer, executor: executor)
        let result = await orchestrator.run(plan)
        return (plan, result)
    }
}
