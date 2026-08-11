import CapabilitiesCore

/// A planner that maps a goal to a plan using a keyword-triggered template catalog.
///
/// It is always available (no model, no network), fully deterministic, and therefore the
/// dependable fallback whenever the on-device model is unavailable, as well as the
/// baseline the evaluation suite scores against. When no template matches, it produces a
/// single safe observe step rather than guessing at a state change.
public struct DeterministicGoalPlanner: GoalPlanning {
    private let templates: [PlanTemplate]

    public init(templates: [PlanTemplate] = PlanTemplateCatalog.builtIn) {
        self.templates = templates
    }

    public func makePlan(for goal: PlanningGoal) async -> Plan {
        let normalized = goal.normalizedText
        if let template = templates.first(where: { $0.matches(normalized) }) {
            return Plan(goal: goal, steps: template.steps, summary: template.summary)
        }
        // No template matched: fall back to a read-only step. Never invent a state change
        // for a goal we don't recognize.
        return Plan(
            goal: goal,
            steps: [
                PlanStep(
                    capability: .musicLibraryClassification,
                    kind: .observe,
                    title: "Gather context",
                    rationale: "Look at what's available before suggesting any action."
                )
            ],
            summary: "Gather context for “\(goal.text)”."
        )
    }
}
