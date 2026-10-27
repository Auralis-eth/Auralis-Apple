import AuralisFoundation

/// An ordered, inspectable decomposition of a ``PlanningGoal`` into capability-grounded
/// steps. A plan is a proposal: producing one changes nothing. It is meant to be shown
/// to the user ("here's how I'd approach this") and then handed to an orchestrator that
/// runs it one step at a time under authorization.
public struct Plan: Equatable, Sendable {
    public let goal: PlanningGoal
    public let steps: [PlanStep]
    /// A one-line summary of the approach, for the top of the plan review.
    public let summary: String
    /// The options the planner considered and rejected on the way to this plan. Empty when the
    /// planner didn't record its reasoning. See ``PlanDeliberation``.
    public let deliberation: PlanDeliberation

    public init(
        goal: PlanningGoal,
        steps: [PlanStep],
        summary: String,
        deliberation: PlanDeliberation = .none
    ) {
        self.goal = goal
        self.steps = steps
        self.summary = summary
        self.deliberation = deliberation
    }

    public var isEmpty: Bool {
        steps.isEmpty
    }

    /// The capabilities the plan touches, in order (may repeat across steps).
    public var capabilities: [CapabilityID] {
        steps.map(\.capability)
    }

    /// Whether any step changes state and will therefore need authorization.
    public var containsStateChange: Bool {
        steps.contains { $0.kind.isStateChanging }
    }
}
