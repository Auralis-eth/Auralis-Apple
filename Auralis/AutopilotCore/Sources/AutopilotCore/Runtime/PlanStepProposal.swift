import PlannerCore
import RuntimeCore

/// Turns a ``PlanStep`` (in the context of its ``PlanningGoal``) into a governable
/// ``ActionProposal``.
///
/// The step's `kind` still proposes the impact class, but it cannot propose one *below* what the
/// capability makes possible. This is the seam that lets the same plan the orchestrator runs also
/// flow through the RuntimeCore Judge/checks pipeline.
///
/// `kind` used to decide alone: `.observe`/`.assist` mapped to `.readOnly` regardless of capability,
/// on the reasoning that those rungs carry no state change. But `kind` is a *claim about* the step —
/// on the model planning path it is free text the model emitted — and nothing checked it. A step
/// naming `sign_message` and declaring itself `observe` therefore proposed `.readOnly`, and
/// `ActionImpactClass.requiresConfirmation` is what `StandingToolPolicy` reads to decide whether a
/// human must confirm. In Observe mode the crypto branch still blocked it (that check keys on the
/// capability), but in **Operate** mode it returned `.allow` — an irreversible signature authorized
/// unattended because the step called itself a read.
///
/// The floor, not the execute-impact, is what is applied here. Using
/// `CapabilityImpactMapping.defaultImpact` for every rung would overstate the common case badly:
/// `runPlugin` is `.externalImpact` as a capability, yet it is the capability every non-wallet agent
/// step maps onto and `OperatorCatalog` declares the Research Brief tool it resolves to `.readOnly`.
/// Treating a library summary as externally-impactful would send a read-only operator step to the
/// approval inbox. ``CapabilityImpactMapping/minimumImpact(for:)`` instead asks whether the
/// capability has a read-only mode at all, which is the question that actually distinguishes
/// "mislabelled signature" from "plugin that only looks".
public enum PlanStepProposal {
    /// - Parameter actor: Who is proposing this step (P0.5-602). No default, matching
    ///   ``ActionProposal`` itself: a fabricated `"planner"` fallback would put an anonymous actor on
    ///   a governable proposal, and the proposal is the record the Judge and the worklog both read.
    public static func makeProposal(
        for step: PlanStep,
        in goal: PlanningGoal,
        actor: ActorRef,
        requiredCheckIDs: [String] = [],
        correlationID: String? = nil
    ) -> ActionProposal {
        let claimed: ActionImpactClass
        switch step.kind {
        case .observe, .assist:
            claimed = .readOnly
        case .execute:
            claimed = CapabilityImpactMapping.defaultImpact(for: step.capability)
        }

        return ActionProposal(
            actor: actor,
            intent: step.title,
            capability: step.capability,
            impact: max(claimed, CapabilityImpactMapping.minimumImpact(for: step.capability)),
            requiredCheckIDs: requiredCheckIDs,
            correlationID: correlationID ?? goal.surface
        )
    }
}
