/// Decides whether a plan step may run, and how far it may go on its own.
///
/// This is the seam between planning (pure, in this package) and authority (policy, app
/// mode, trusted routines — supplied by a higher layer such as AutopilotCore). The
/// orchestrator never decides for itself whether a state change is allowed; it always
/// asks an authorizer. Marked `@MainActor` because real authorizers consult the app's
/// policy gate, which is main-actor isolated.
@MainActor
public protocol StepAuthorizing {
    func authorize(_ step: PlanStep, in goal: PlanningGoal) async -> StepAuthorization
}
