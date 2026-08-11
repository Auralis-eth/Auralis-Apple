/// Turns a ``PlanningGoal`` into a ``Plan``.
///
/// Conformances range from a deterministic, always-available template planner
/// (``DeterministicGoalPlanner``) to a FoundationModels-backed planner that decomposes
/// novel goals on device. Planning is pure: a planner reads a goal and returns a plan.
/// It has no side effects and no authority — authority lives in the authorization layer.
public protocol GoalPlanning: Sendable {
    func makePlan(for goal: PlanningGoal) async -> Plan
}
