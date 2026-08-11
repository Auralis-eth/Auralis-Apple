import CapabilitiesCore

/// An ordered, inspectable decomposition of a ``PlanningGoal`` into capability-grounded
/// steps. A plan is a proposal: producing one changes nothing. It is meant to be shown
/// to the user ("here's how I'd approach this") and then handed to an orchestrator that
/// runs it one step at a time under authorization.
public struct Plan: Equatable, Sendable {
    public let goal: PlanningGoal
    public let steps: [PlanStep]
    /// A one-line summary of the approach, for the top of the plan review.
    public let summary: String

    public init(goal: PlanningGoal, steps: [PlanStep], summary: String) {
        self.goal = goal
        self.steps = steps
        self.summary = summary
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
