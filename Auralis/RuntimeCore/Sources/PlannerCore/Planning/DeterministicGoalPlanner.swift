import AuralisFoundation

/// A planner that maps a goal to a plan using a keyword-triggered template catalog.
///
/// It is always available (no model, no network), fully deterministic, and therefore the
/// dependable fallback whenever the on-device model is unavailable, as well as the
/// baseline the evaluation suite scores against. When no template matches, it produces a
/// single safe observe step rather than guessing at a state change.
public struct DeterministicGoalPlanner: GoalPlanning {
    /// This planner writes every step it returns, so it stamps `name` straight onto the
    /// deliberation below rather than repeating the literal — the identity is decided once.
    public let name = "deterministic"

    private let templates: [PlanTemplate]

    public init(templates: [PlanTemplate] = PlanTemplateCatalog.builtIn) {
        self.templates = templates
    }

    public func makePlan(for goal: PlanningGoal) async -> Plan {
        let normalized = goal.normalizedText
        // Evaluated once per template and keyed by *position*, not by id. Selecting on `template.id
        // == matched?.id` marked every template sharing an id as selected, and `templates` is an
        // injectable parameter, so a caller passing two variants of one id got a deliberation
        // claiming the planner chose both while only the first template's steps were used.
        let matchedIndices = templates.indices.filter { templates[$0].matches(normalized) }
        let selectedIndex = matchedIndices.first

        // Every template is a candidate: the chosen one is selected, the rest are rejected with the
        // reason they didn't fire. This is what makes the deterministic planner's choice legible.
        //
        // Two different reasons to reject, and they must not be conflated. Matching is
        // `first(where:)`, so a template can match the goal and still lose on catalog precedence —
        // "organize my playlist" matches both `organize-library` and `make-playlist`. Reporting that
        // as "Goal did not mention any of: playlist, mix, …" states a falsehood about a goal that
        // says "playlist", on the one surface whose entire job is explaining why an option was
        // dropped. A deliberation a reader can catch lying is worse than no deliberation.
        let templateCandidates = templates.indices.map { index -> PlanCandidate in
            let template = templates[index]
            let rationale: String
            if index == selectedIndex {
                rationale = "Goal keywords matched this template."
            } else if matchedIndices.contains(index), let winner = selectedIndex {
                rationale = """
                    Goal also matched this template, but “\(templates[winner].id)” comes first in the \
                    catalog and took precedence.
                    """
            } else {
                rationale = "Goal did not mention any of: \(template.keywords.joined(separator: ", "))."
            }
            return PlanCandidate(
                title: template.id,
                capability: template.steps.first?.capability,
                isSelected: index == selectedIndex,
                rationale: rationale
            )
        }

        if let selectedIndex {
            let template = templates[selectedIndex]
            return Plan(
                goal: goal,
                steps: template.steps,
                summary: template.summary,
                deliberation: PlanDeliberation(planner: name, candidates: templateCandidates)
            )
        }

        // No template matched: fall back to a read-only step. Never invent a state change
        // for a goal we don't recognize.
        let fallbackStep = PlanStep(
            capability: .musicLibraryClassification,
            kind: .observe,
            title: "Gather context",
            rationale: "Look at what's available before suggesting any action."
        )
        let fallbackCandidate = PlanCandidate(
            title: "gather-context-fallback",
            capability: .musicLibraryClassification,
            isSelected: true,
            rationale: "No template matched the goal, so fall back to a safe read-only step."
        )
        return Plan(
            goal: goal,
            steps: [fallbackStep],
            summary: "Gather context for “\(goal.text)”.",
            deliberation: PlanDeliberation(
                planner: name,
                candidates: templateCandidates + [fallbackCandidate]
            )
        )
    }
}
