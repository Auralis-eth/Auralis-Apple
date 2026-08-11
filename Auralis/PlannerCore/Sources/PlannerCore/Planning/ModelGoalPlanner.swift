import CapabilitiesCore

#if canImport(FoundationModels)
import FoundationModels

/// A planner that decomposes novel goals on device with the system language model.
///
/// The model only *routes*: it proposes steps drawn from the offered capabilities and
/// the fixed kind vocabulary, and everything it returns is re-grounded against the
/// allow-list (``PlannerInstructions/groundedCapabilities(from:allowed:)``) so a
/// hallucinated capability is dropped, never executed. If the model is unavailable, or it
/// returns nothing usable, planning falls back to the deterministic planner — the feature
/// degrades to templates rather than failing.
@available(iOS 26.0, macOS 26.0, *)
public struct ModelGoalPlanner: GoalPlanning {
    private let availableCapabilities: [CapabilityID]
    private let fallback: any GoalPlanning

    public init(
        availableCapabilities: [CapabilityID] = CapabilityID.allCases,
        fallback: any GoalPlanning = DeterministicGoalPlanner()
    ) {
        self.availableCapabilities = availableCapabilities
        self.fallback = fallback
    }

    @Generable
    struct GeneratedPlan {
        @Guide(description: "A one-line summary of the overall approach.")
        let summary: String
        @Guide(description: "The ordered steps of the plan.")
        let steps: [GeneratedStep]
    }

    @Generable
    struct GeneratedStep {
        @Guide(description: "The capability identifier for this step, copied verbatim from the allowed list.")
        let capability: String
        @Guide(description: "The step kind: observe, assist, or execute.")
        let kind: String
        @Guide(description: "A short user-facing title for the step.")
        let title: String
        @Guide(description: "One sentence explaining why this step is in the plan.")
        let rationale: String
    }

    public func makePlan(for goal: PlanningGoal) async -> Plan {
        guard case .available = SystemLanguageModel.default.availability else {
            return await fallback.makePlan(for: goal)
        }

        let session = LanguageModelSession(
            instructions: Instructions {
                for line in PlannerInstructions.lines(availableCapabilities: availableCapabilities) {
                    line
                }
            }
        )

        guard let generated = try? await session.respond(
            to: goal.text,
            generating: GeneratedPlan.self
        ).content else {
            return await fallback.makePlan(for: goal)
        }

        let steps = groundedSteps(from: generated.steps)
        guard !steps.isEmpty else {
            return await fallback.makePlan(for: goal)
        }

        return Plan(
            goal: goal,
            steps: steps,
            summary: generated.summary.isEmpty ? "Plan for “\(goal.text)”." : generated.summary
        )
    }

    /// Keeps only steps whose capability is real and allowed and whose kind is valid.
    private func groundedSteps(from generated: [GeneratedStep]) -> [PlanStep] {
        let allowed = Set(availableCapabilities)
        return generated.compactMap { step -> PlanStep? in
            guard
                let capability = CapabilityID(rawValue: step.capability),
                allowed.contains(capability),
                let kind = PlanStepKind(rawValue: step.kind.lowercased())
            else {
                return nil
            }
            let descriptor = CapabilityRegistry.descriptor(for: capability)
            let title = step.title.isEmpty ? descriptor.title : step.title
            return PlanStep(
                capability: capability,
                kind: kind,
                title: title,
                rationale: step.rationale
            )
        }
    }
}
#endif
