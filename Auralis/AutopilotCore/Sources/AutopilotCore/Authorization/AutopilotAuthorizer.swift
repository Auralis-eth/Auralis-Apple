import CapabilitiesCore
import PlannerCore
import PolicyCore
import RuntimeCore

/// The concrete ``StepAuthorizing`` that turns a plan step into a ladder verdict by
/// composing the app's real policy gate with a trusted-routine allowlist.
///
/// The decision tree *is* the Observe → Assist → Confirm → Autopilot ladder, and whether a step may
/// skip the gate is decided by its **capability**, never by the `kind` it declares:
///
/// - Observe/Assist steps on a capability that *has* a read-only mode (a plugin run, a library
///   classification, playback) are cleared to run unattended with no gate call.
/// - Every other step is mapped to a ``PolicyControlledAction`` and put through the same
///   ``PolicyActionGating`` the rest of the app uses:
///     - denied by policy (e.g. the app is in Observe mode) → ``StepAuthorization/blocked(_:)``;
///     - allowed, and Observe/Assist → ``StepAuthorization/autopilot``;
///     - allowed, Execute, but not a trusted routine → ``StepAuthorization/needsConfirmation(_:)``;
///     - allowed, Execute, *and* a trusted routine → ``StepAuthorization/autopilot``.
///
/// Anchoring that choice to the capability is what stops a step from skipping the gate by
/// mislabelling itself as a read; see the comment in ``authorize(_:in:)``.
///
/// The active `CryptoMode` comes from the app/runtime policy gate. Observe blocks crypto execution,
/// Assist turns crypto execution into an approval request, and Operate still requires the gate to allow
/// the action before routine trust can promote it to unattended execution.
@MainActor
public struct AutopilotAuthorizer: StepAuthorizing {
    private let gate: any PolicyActionGating
    private let trustedRoutines: TrustedRoutineAllowlist
    private let actor: ActorRef

    /// - Parameter actor: Who is attempting the steps this authorizer clears (P0.5-602). The gate
    ///   writes receipts for denied and high-risk actions, so this is what those receipts are
    ///   attributed to. Pass the specific autopilot workflow, not a person — attributing unattended
    ///   work to a human is precisely the misattribution this ticket removes.
    ///
    ///   No default: a bare `"autopilot"` fallback made every autopilot surface look like the same
    ///   actor on a trust surface, and it compiled clean, so nothing flagged the loss.
    public init(
        gate: any PolicyActionGating,
        trustedRoutines: TrustedRoutineAllowlist = .none,
        actor: ActorRef
    ) {
        self.gate = gate
        self.trustedRoutines = trustedRoutines
        self.actor = actor
    }

    public func authorize(_ step: PlanStep, in goal: PlanningGoal) async -> StepAuthorization {
        // A cancelled run permits nothing, including the read-only rungs. Neither
        // ``SequentialPlanOrchestrator`` nor the executor consults `Task.isCancelled`, so without this
        // the orchestrator ran every remaining step of a plan the user had already called off. The
        // authorizer runs immediately before each step, so refusing here halts the run at the next
        // step boundary. Matches ``JudgeStepAuthorizer``, which gates the RuntimeCore-native path.
        if Task.isCancelled {
            return .blocked("The run was cancelled.")
        }

        // A step may skip the gate only when its capability *cannot* require confirmation. That is a
        // property of the capability, so a step cannot talk its way past the gate by how it labels
        // itself.
        //
        // This used to short-circuit on `kind` alone: `.observe` and `.assist` returned `.autopilot`
        // immediately, on the reasoning that those rungs carry no state change. But `kind` is a
        // claim the step makes about itself — on the ``ModelGoalPlanner`` path it is free text a
        // model emitted — and nothing checked it against the capability being named. A step
        // `{capability: .signMessage, kind: .observe}` was cleared to run unattended with the policy
        // gate never asked, in *any* mode: the whole Observe boundary skipped by mislabelling a step.
        // `musicExport` was the same hole one notch down — an export that reaches off the device,
        // relabelled as a read.
        //
        // The test is the capability's *floor* — does it have a read-only mode at all — not the
        // impact of executing it. That distinction matters here more than anywhere: this authorizer
        // drives the *legacy* whole-app ``PolicyActionGating``, where every non-wallet capability
        // collapses onto ``PolicyControlledAction/runPlugin`` and is blocked outright in Observe
        // mode. Gating the advisory rungs on the execute-impact would therefore stop a library
        // *classification read* in Observe — the whole-app posture ADR-010 replaced with a
        // crypto-scoped one. Capabilities with no read-only mode (wallet, export) are always gated;
        // the rest keep streaming on the advisory rungs and are gated on `.execute`.
        //
        // Same floor ``PlanStepProposal`` applies, so the legacy gate path and the Judge path cannot
        // disagree about which steps are allowed to skip a check.
        if !CapabilityImpactMapping.minimumImpact(for: step.capability).requiresConfirmation,
           step.kind != .execute {
            return .autopilot
        }

        let action = CapabilityActionMapping.policyAction(for: step.capability)
        let result = await gate.attempt(action, actor: actor)

        guard result.isAllowed else {
            let reason = result.userMessage.isEmpty ? action.summary : result.userMessage
            return .blocked(reason)
        }

        // The capability floor outranks the step's own `kind` here, not just at the short-circuit
        // above. Forcing a mislabelled step past the *gate* while still honouring its `.observe` claim
        // for the *verdict* left the hole half-closed: a step declaring
        // `{capability: .signMessage, kind: .observe}` was gated (correctly) and then returned
        // `.autopilot` — documented as "run it now, unattended" — producing a signature with no
        // confirmation. `PlanStepProposal` lifts the same claim to `.highRisk` via
        // `max(claimed, minimumImpact(for:))`, so without this the legacy gate path and the Judge path
        // genuinely disagreed, which is exactly what the comment above claims cannot happen.
        let requiresConfirmationFloor = CapabilityImpactMapping
            .minimumImpact(for: step.capability)
            .requiresConfirmation

        switch step.kind {
        case .observe, .assist:
            // A capability with a read-only floor and a non-execute claim is genuinely advisory. The
            // gate has confirmed it is permitted in the current mode, and it proceeds *after* the
            // gate, so a denial in Observe mode is honoured rather than skipped.
            guard requiresConfirmationFloor else { return .autopilot }
            // A wallet or export capability has no read-only floor, so the `.observe`/`.assist` claim
            // cannot be taken at face value no matter who wrote it.
            return confirmationVerdict(for: step)

        case .execute:
            return confirmationVerdict(for: step)
        }
    }

    /// The verdict for a step that must not run unattended: trusted routines still stream, everything
    /// else asks.
    private func confirmationVerdict(for step: PlanStep) -> StepAuthorization {
        if trustedRoutines.trusts(step.capability) {
            return .autopilot
        }
        return .needsConfirmation("“\(step.title)” is ready — confirm to run it.")
    }
}
