import CapabilitiesCore
import Testing
@testable import PlannerCore

/// Deterministic guardrails on the FoundationModels session's instruction text and its
/// grounding rule. These run everywhere (no model required) and are the always-on
/// counterpart to the model-gated ``PlannerCapabilitySelectionEvaluation``: a wording
/// change that drops a capability from the catalog, or a grounding regression that lets an
/// unknown capability through, fails here immediately.
struct PlannerInstructionsTests {
    @Test("instructions offer every allowed capability by its exact identifier")
    func instructionsListEveryCapability() {
        let capabilities = CapabilityID.allCases
        let text = PlannerInstructions.lines(availableCapabilities: capabilities).joined(separator: "\n")
        for capability in capabilities {
            #expect(text.contains(capability.rawValue), "instructions omit \(capability.rawValue)")
        }
    }

    @Test("instructions teach the full step-kind vocabulary")
    func instructionsCoverKindVocabulary() {
        let text = PlannerInstructions.lines(availableCapabilities: CapabilityID.allCases).joined(separator: "\n")
        for kind in PlanStepKind.allCases {
            #expect(text.contains(kind.rawValue), "instructions omit kind \(kind.rawValue)")
        }
    }

    @Test("instructions restrict execute to state changes and forbid inventing capabilities")
    func instructionsStateTheHardRules() {
        let text = PlannerInstructions.lines(availableCapabilities: CapabilityID.allCases)
            .joined(separator: "\n")
            .lowercased()
        #expect(text.contains("execute") && text.contains("change state"))
        #expect(text.contains("never invent"))
    }

    @Test("grounding keeps only real, allowed capabilities and drops hallucinations")
    func groundingDropsUnknownCapabilities() {
        let allowed: [CapabilityID] = [.playlistManagement, .musicExport]
        let grounded = PlannerInstructions.groundedCapabilities(
            from: ["playlist_management", "delete_everything", "music_export", "sign_message"],
            allowed: allowed
        )
        #expect(grounded == [.playlistManagement, .musicExport])
    }
}
