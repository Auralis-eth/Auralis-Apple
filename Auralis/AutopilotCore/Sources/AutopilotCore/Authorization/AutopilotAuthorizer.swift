import CapabilitiesCore
import PlannerCore
import PolicyCore

/// The concrete ``StepAuthorizing`` that turns a plan step into a ladder verdict by
/// composing the app's real policy gate with a trusted-routine allowlist.
///
/// The decision tree *is* the Observe → Assist → Confirm → Autopilot ladder:
///
/// - Observe and Assist steps never change state, so they are cleared to run unattended.
/// - Execute steps are mapped to a ``PolicyControlledAction`` and put through the same
///   ``PolicyActionGating`` the rest of the app uses:
///     - denied by policy (e.g. the app is in Observe mode) → ``StepAuthorization/blocked(_:)``;
///     - allowed but not a trusted routine → ``StepAuthorization/needsConfirmation(_:)``;
///     - allowed *and* a trusted routine → ``StepAuthorization/autopilot``.
///
/// Because the shipping app pins `AppMode` to `.observe`, every execute step resolves to
/// `blocked` today — which is the honest state of the world: the machinery is real, and
/// higher autonomy switches on only when policy does.
@MainActor
public struct AutopilotAuthorizer: StepAuthorizing {
    private let gate: any PolicyActionGating
    private let trustedRoutines: TrustedRoutineAllowlist

    public init(gate: any PolicyActionGating, trustedRoutines: TrustedRoutineAllowlist = .none) {
        self.gate = gate
        self.trustedRoutines = trustedRoutines
    }

    public func authorize(_ step: PlanStep, in goal: PlanningGoal) async -> StepAuthorization {
        switch step.kind {
        case .observe, .assist:
            // Read-only and advisory work carries no policy risk.
            return .autopilot

        case .execute:
            let action = CapabilityActionMapping.policyAction(for: step.capability)
            let result = await gate.attempt(action)

            guard result.isAllowed else {
                let reason = result.userMessage.isEmpty ? action.summary : result.userMessage
                return .blocked(reason)
            }

            if trustedRoutines.trusts(step.capability) {
                return .autopilot
            }
            return .needsConfirmation("“\(step.title)” is ready — confirm to run it.")
        }
    }
}
