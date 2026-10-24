/// Turns a ``PlanningGoal`` into a ``Plan``.
///
/// Conformances range from a deterministic, always-available template planner
/// (``DeterministicGoalPlanner``) to a FoundationModels-backed planner that decomposes
/// novel goals on device. Planning is pure: a planner reads a goal and returns a plan.
/// It has no side effects and no authority — authority lives in the authorization layer.
public protocol GoalPlanning: Sendable {
    /// Stable identifier for this planner *implementation*, for configuration and diagnostics.
    ///
    /// It is **not** the attribution identity of a run, and it does not populate
    /// ``PlanDeliberation/planner``. It used to be documented as if it did, and that claim could not
    /// hold: `name` is a constant known before planning starts, while which planner actually
    /// produces the steps is only decided during ``makePlan(for:)`` — a model-backed planner that
    /// degrades to templates returns steps its fallback wrote. So the two disagreed on exactly the
    /// common path, and a caller that named proposals from `name` filed them under `planner.model`
    /// while the worklog entry for the same run recorded `planner.deterministic`: one run, two
    /// identities, and the join between a proposal and the deliberation that considered it broken
    /// where it was most needed.
    ///
    /// ``PlanDeliberation/planner`` is the single source of truth, because it is stamped by the
    /// planner that actually wrote the steps. Attribute runs from `plan.deliberation.planner`;
    /// a planner that wrote its own steps stamps its own `name` there, so the two agree whenever
    /// agreeing is true.
    var name: String { get }

    func makePlan(for goal: PlanningGoal) async -> Plan
}
