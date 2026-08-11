import CapabilitiesCore

/// The instruction text that grounds the FoundationModels-backed planner.
///
/// These strings are the "prompt" for ``ModelGoalPlanner``. They live here, separate from
/// the model session, for two reasons: the evaluation suite references the exact same
/// text it ships with (so a wording change is measured, not silently deployed), and the
/// same criteria that grade the instructions in tests can be reused as runtime guardrails
/// — see ``groundedCapabilities(from:)``.
public enum PlannerInstructions {
    /// The kinds the model may assign to a step, matching ``PlanStepKind``.
    public static let stepKindVocabulary: [String] = PlanStepKind.allCases.map(\.rawValue)

    /// The instruction lines for a session that may plan over `capabilities`.
    ///
    /// Returned as discrete lines so a caller can feed them to an `Instructions` builder
    /// and so tests can assert on individual guarantees.
    public static func lines(availableCapabilities: [CapabilityID]) -> [String] {
        let catalog = capabilityCatalogText(for: availableCapabilities)
        return [
            "You are a planning assistant. Turn the user's goal into an ordered plan of steps.",
            "Every step must name exactly one capability from this list, using its identifier verbatim:",
            catalog,
            "Every step must have a kind, one of: \(stepKindVocabulary.joined(separator: ", ")).",
            "Use 'observe' for read-only steps that gather or inspect state.",
            "Use 'assist' for steps that produce a recommendation or draft without changing anything.",
            "Use 'execute' only for steps that change state, such as spending, signing, or writing.",
            "Order steps so you observe first, then assist, and only then execute.",
            "Never invent a capability that is not in the list. If the goal needs no action, plan a single observe step.",
            "Keep each step's title short and its rationale to one sentence.",
        ]
    }

    /// A human/model-readable catalog of `id — title: summary` lines for the allowed capabilities.
    public static func capabilityCatalogText(for capabilities: [CapabilityID]) -> String {
        capabilities
            .map { id in
                let descriptor = CapabilityRegistry.descriptor(for: id)
                return "\(id.rawValue) — \(descriptor.title): \(descriptor.summary)"
            }
            .joined(separator: "\n")
    }

    /// Filters model-proposed capability identifiers down to the ones that are real and
    /// allowed. This is the grounding guard: the model can only route to capabilities that
    /// were offered, never conjure new ones. Shared by the planner at runtime and by the
    /// evaluation suite as a format check.
    public static func groundedCapabilities(
        from proposedIdentifiers: [String],
        allowed: [CapabilityID]
    ) -> [CapabilityID] {
        let allowedSet = Set(allowed)
        return proposedIdentifiers.compactMap { raw in
            guard let id = CapabilityID(rawValue: raw), allowedSet.contains(id) else { return nil }
            return id
        }
    }
}
