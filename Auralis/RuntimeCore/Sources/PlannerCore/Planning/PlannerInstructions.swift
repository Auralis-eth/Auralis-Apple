import AuralisFoundation
import RuntimeCore

/// The instruction text that grounds the model-backed planner, on either executor.
///
/// These strings are the "prompt" for ``ModelGoalPlanner``. They live here, separate from
/// the model session, for two reasons: the evaluation suite references the exact same
/// text it ships with (so a wording change is measured, not silently deployed), and the
/// same criteria that grade the instructions in tests can be reused as runtime guardrails
/// — see ``groundedCapabilities(from:)``.
public enum PlannerInstructions {
    /// The kinds the model may assign to a step, matching ``PlanStepKind``.
    public static let stepKindVocabulary: [String] = PlanStepKind.allCases.map(\.rawValue)

    /// Developer-authored instructions safe for the higher-priority instruction channel. Runtime
    /// capability data is deliberately excluded and must arrive through governed prompt context.
    ///
    /// Returned as discrete lines so a caller can feed them to an `Instructions` builder and so
    /// tests can pin individual guarantees. These are the lines ``ModelGoalPlanner`` actually
    /// sends; there is deliberately no second, capability-inlining variant of them. One existed
    /// (`lines(availableCapabilities:)`, which spliced a descriptor catalog in at index 2) and it
    /// outlived its only caller when the planner moved capability data into the governed prompt.
    /// The instruction suite went on pinning *it*, so "never invent a capability" and the
    /// observe-before-execute ordering could be deleted from the shipping text with every
    /// instruction test still green. A guardrail that grades a string nobody sends is not a
    /// guardrail, so the dead variant is gone and the tests pin these lines and the governed
    /// prompt instead.
    public static var sessionLines: [String] {
        [
            "You are a planning assistant. Turn the user's goal into an ordered plan of steps.",
            "Every step must name exactly one capability from the governed prompt's allowed-capabilities list, using its identifier verbatim.",
            "Every step must have a kind, one of: \(stepKindVocabulary.joined(separator: ", ")).",
            "Use 'observe' for read-only steps that gather or inspect state.",
            "Use 'assist' for steps that produce a recommendation or draft without changing anything.",
            "Use 'execute' only for steps that change state, such as spending, signing, or writing.",
            "Order steps so you observe first, then assist, and only then execute.",
            "Never invent a capability that is not in the list. If the goal needs no action, plan a single observe step.",
            "Keep each step's title short and its rationale to one sentence."
        ]
    }

    /// The response contract added for a provider-routed planning request.
    ///
    /// The FoundationModels path does not need these lines: `@Generable` gives that session a real
    /// schema channel, so the shape of the reply is enforced by guided generation rather than asked
    /// for in prose. A route that runs through `ModelInferring` has no schema channel at all — the
    /// provider hands back a bare `String` — so the shape has to be stated, and stated *here*,
    /// beside the lines the instruction tests pin, rather than inlined at the call site where a
    /// silent edit would go unmeasured. Without it the routed path could only ever fail to decode
    /// and degrade to templates, which would make the routing seam decorative.
    ///
    /// The keys are the stored property names of `ModelGoalPlanner.GeneratedPlan`/`GeneratedStep`,
    /// because that is what the reply is decoded into.
    public static let responseFormatLines: [String] = [
        "Reply with a single JSON object and nothing else: no prose, no explanation, no code fences.",
        "The object has exactly two keys: \"summary\", a one-line string, and \"steps\", an array of step objects.",
        "Each step object has exactly four string keys: \"capability\", \"kind\", \"title\", and \"rationale\"."
    ]

    /// The instruction lines for a planning request executed through a ``ModelInferring`` route.
    public static var routedSessionLines: [String] { sessionLines + responseFormatLines }

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

    /// Grounds a model-declared step *kind* against the capability it names.
    ///
    /// The companion to ``groundedCapabilities(from:allowed:)``, and it exists for the same reason:
    /// everything the model returns is a claim, and a claim that decides how much ceremony a step
    /// gets has to be checked against something that is not also the model's word. The capability's
    /// impact class is that something.
    ///
    /// `.observe` asserts "reads only". On a capability that cannot be exercised without changing
    /// state, that is not a cautious description of the step but a false one — and it is the label
    /// the policy gate is skipped on, so a step naming `sign_message` and calling itself `observe`
    /// got a wallet signature treated as a read. Those are raised to `.execute` so the gate decides.
    ///
    /// `.assist` is deliberately untouched: "produce a draft or recommendation" is a coherent thing
    /// to do with a write capability — drafting a playlist really is advisory — so rewriting it would
    /// turn every model-planned music step into a confirmation prompt for no safety gain. Those
    /// steps are covered at the authority boundary instead, by `AutopilotAuthorizer`.
    ///
    /// Never lowered: a model calling a read-only capability `.execute` is merely over-cautious.
    ///
    /// The test is ``CapabilityImpactMapping/minimumImpact(for:)`` — the capability's *floor* — and
    /// **not** ``CapabilityImpactMapping/defaultImpact(for:)``, which is the impact of *executing* it.
    /// The two share a signature, so the wrong one compiles and passes every wallet case while
    /// silently inverting the common one. `defaultImpact` answers "what happens if this runs", and
    /// by that measure almost nothing is read-only: `musicLibraryClassification` is
    /// `.reversibleWrite` and `runPlugin` is `.externalImpact`. Using it here rewrote the
    /// observe-first step the instructions above explicitly ask for — "Inspect library" — into
    /// `.execute`, which `AutopilotAuthorizer` then refuses to clear without the gate: a
    /// confirmation prompt for a library read in Operate, and an outright block in Observe, where
    /// every non-wallet capability collapses onto `PolicyControlledAction.runPlugin`. `minimumImpact`
    /// asks the question this function actually means — does the capability have a read-only mode at
    /// all — so it raises exactly the wallet capabilities and `musicExport` and leaves reads alone.
    /// It is also the same floor `PlanStepProposal` and `AutopilotAuthorizer` apply, so the planner
    /// can no longer disagree with the boundary that governs it.
    public static func groundedStepKind(
        declared: PlanStepKind,
        for capability: CapabilityID
    ) -> PlanStepKind {
        guard declared == .observe,
              CapabilityImpactMapping.minimumImpact(for: capability) != .readOnly else {
            return declared
        }
        return .execute
    }
}
