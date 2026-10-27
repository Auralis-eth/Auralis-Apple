import AuralisFoundation
import Foundation
@testable import AuralisRuntime
import Testing

/// Deterministic guardrails on the planner's instruction text and its grounding rule. These run
/// everywhere (no model required) and are the always-on counterpart to the model-gated
/// ``PlannerCapabilitySelectionEvaluation``: a wording change that drops a grounding rule, or a
/// grounding regression that lets an unknown capability through, fails here immediately.
///
/// Every assertion below is made against text the planner *sends* — ``PlannerInstructions/
/// sessionLines``, ``PlannerInstructions/responseFormatLines``, and the prompt
/// `ModelGoalPlanner.authorizedRequest` renders. They used to be made against
/// `PlannerInstructions.lines(availableCapabilities:)`, which no caller had used since the planner
/// moved capability data into the governed prompt: "never invent a capability" and the
/// observe-before-execute ordering could be deleted from the shipping instructions with all four
/// tests still green, while the dead string stayed pinned. A guardrail on unsent text is theatre.
struct PlannerInstructionsTests {
    @Test("the session instructions teach the full step-kind vocabulary")
    func sessionInstructionsCoverKindVocabulary() {
        let text = PlannerInstructions.sessionLines.joined(separator: "\n")
        for kind in PlanStepKind.allCases {
            #expect(text.contains(kind.rawValue), "instructions omit kind \(kind.rawValue)")
        }
    }

    @Test("the session instructions restrict execute to state changes and forbid inventing capabilities")
    func sessionInstructionsStateTheHardRules() {
        let text = PlannerInstructions.sessionLines
            .joined(separator: "\n")
            .lowercased()
        #expect(text.contains("execute") && text.contains("change state"))
        #expect(text.contains("never invent"))
        // The ordering rule is the one the grounding clamp cannot enforce after the fact, so it has
        // to survive in the text itself.
        #expect(text.contains("observe first"))
    }

    /// A route executed through `ModelInferring` has no schema channel, so the reply shape is only
    /// ever asked for in prose. If these keys drift from `GeneratedPlan`'s properties, every routed
    /// reply fails to decode and the planner silently degrades to templates forever.
    @Test("the routed instructions name every key the reply is decoded from")
    func routedInstructionsStateTheResponseContract() {
        let text = PlannerInstructions.routedSessionLines.joined(separator: "\n")
        for key in ["summary", "steps", "capability", "kind", "title", "rationale"] {
            #expect(text.contains("\"\(key)\""), "response contract omits \(key)")
        }
        // The routed lines are the session lines plus the contract, never a separate prompt that
        // could lose a grounding rule.
        #expect(PlannerInstructions.routedSessionLines.starts(with: PlannerInstructions.sessionLines))
    }

#if canImport(FoundationModels)
    /// The capability list lives in the *governed prompt*, not the instruction channel, so this is
    /// the only place it can be pinned. Asserting it against `PlannerInstructions` alone is what
    /// made the old guardrail vacuous.
    @Test("the governed planning prompt offers every allowed capability by its exact identifier")
    func governedPromptListsEveryCapability() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let capabilities = CapabilityID.allCases
        let planner = ModelGoalPlanner(availableCapabilities: capabilities)
        let request = try planner.authorizedRequest(
            for: PlanningGoal(text: "organize my music library"),
            instructions: PlannerInstructions.sessionLines,
            at: Date()
        )
        for capability in capabilities {
            #expect(request.prompt.contains(capability.rawValue), "prompt omits \(capability.rawValue)")
        }
    }

    /// The prompt also has to carry the goal, and the instructions it is paired with have to be the
    /// ones graded above — the two halves are only a guardrail together.
    @Test("the governed planning prompt carries the goal and ships the graded instructions")
    func governedPromptCarriesTheGoal() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let planner = ModelGoalPlanner()
        let request = try planner.authorizedRequest(
            for: PlanningGoal(text: "tip this artist some ETH"),
            instructions: PlannerInstructions.routedSessionLines,
            at: Date()
        )
        #expect(request.prompt.contains("tip this artist some ETH"))
        #expect(request.instructions == PlannerInstructions.routedSessionLines)
        #expect(request.taskKind == ModelTaskKind.autopilotPlanning)
    }
#endif

    @Test("grounding keeps only real, allowed capabilities and drops hallucinations")
    func groundingDropsUnknownCapabilities() {
        let allowed: [CapabilityID] = [.playlistManagement, .musicExport]
        let grounded = PlannerInstructions.groundedCapabilities(
            from: ["playlist_management", "delete_everything", "music_export", "sign_message"],
            allowed: allowed
        )
        #expect(grounded == [.playlistManagement, .musicExport])
    }

    /// The capability was grounded; the *kind* was not. `kind` arrives as free text from the model
    /// and it decides how much ceremony a step gets, so a step naming `sign_message` while
    /// declaring itself `observe` had a wallet signature treated as a read — and `observe` is
    /// precisely the label the policy gate was skipped on.
    ///
    /// These are exactly the capabilities with *no read-only mode*: there is no way to sign, approve,
    /// or draft a transaction that only reads, and producing an export always puts data elsewhere.
    @Test("a capability with no read-only mode cannot be grounded as an observe step", arguments: [
        CapabilityID.signMessage,
        .approveSpending,
        .draftTransaction,
        .musicExport
    ])
    func observeIsRaisedOnCapabilitiesWithNoReadOnlyMode(capability: CapabilityID) {
        #expect(CapabilityImpactMapping.minimumImpact(for: capability) != .readOnly)
        #expect(PlannerInstructions.groundedStepKind(declared: .observe, for: capability) == .execute)
    }

    /// The other half of the rule, and the one that is easy to get backwards.
    ///
    /// `groundedStepKind` must test ``CapabilityImpactMapping/minimumImpact(for:)`` — "does this
    /// capability have a read-only mode at all" — and not ``CapabilityImpactMapping/defaultImpact``,
    /// which is the impact of *executing* it. The two share a signature, so the wrong one compiles
    /// and still passes every case above. By `defaultImpact`, none of the capabilities below are
    /// read-only (`musicLibraryClassification` is `.reversibleWrite`, `runPlugin` is
    /// `.externalImpact`), so the planner rewrote the observe-first step its own instructions ask
    /// for — "Inspect library" — into `.execute`. `AutopilotAuthorizer` then refuses to clear a
    /// non-`.execute`-exempt step without the gate: a confirmation prompt for a library read in
    /// Operate, and an outright block in Observe. Approval-inbox noise on reads is what trains
    /// people to approve the one prompt that mattered.
    @Test("a capability that has a read-only mode keeps a declared observe", arguments: [
        CapabilityID.runPlugin,
        .playlistManagement,
        .autoOrganization,
        .musicLibraryClassification,
        .metadataOverride,
        .backgroundMusicTask,
        .playbackQueue,
        .audioPlayback
    ])
    func observeSurvivesOnCapabilitiesWithAReadOnlyMode(capability: CapabilityID) {
        #expect(CapabilityImpactMapping.minimumImpact(for: capability) == .readOnly)
        #expect(PlannerInstructions.groundedStepKind(declared: .observe, for: capability) == .observe)
    }

    /// Pins the rule to the floor across the *whole* capability enum, so a capability added later
    /// is covered the moment it exists rather than when someone remembers to list it above.
    @Test("grounding raises observe exactly when the capability has no read-only mode", arguments: CapabilityID.allCases)
    func groundingTracksTheImpactFloor(capability: CapabilityID) {
        let hasReadOnlyMode = CapabilityImpactMapping.minimumImpact(for: capability) == .readOnly
        let grounded = PlannerInstructions.groundedStepKind(declared: .observe, for: capability)
        #expect(grounded == (hasReadOnlyMode ? .observe : .execute))
    }

    /// A genuinely read-only capability keeps whatever the model said, so grounding does not turn
    /// the whole plan into execute steps.
    @Test("a read-only capability keeps its declared kind")
    func readOnlyCapabilityKeepsDeclaredKind() {
        for kind in PlanStepKind.allCases {
            #expect(PlannerInstructions.groundedStepKind(declared: kind, for: .audioPlayback) == kind)
        }
    }

    /// `.assist` is left alone on purpose: "produce a draft" is a coherent thing to do with a write
    /// capability, and those steps are covered at the authority boundary by `AutopilotAuthorizer`
    /// instead. Raising them here would make every model-planned music step a confirmation prompt.
    @Test("assist is not rewritten, and execute is never lowered")
    func assistAndExecuteAreLeftAlone() {
        #expect(PlannerInstructions.groundedStepKind(declared: .assist, for: .playlistManagement) == .assist)
        #expect(PlannerInstructions.groundedStepKind(declared: .assist, for: .signMessage) == .assist)
        #expect(PlannerInstructions.groundedStepKind(declared: .execute, for: .audioPlayback) == .execute)
    }
}
