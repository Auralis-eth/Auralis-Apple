
/// Decides whether a plan step may run, and how far it may go on its own.
///
/// This is the seam between planning (pure, in this package) and authority (policy, app
/// mode, trusted routines — supplied by a higher layer such as AuralisPolicy). The
/// orchestrator never decides for itself whether a state change is allowed; it always
/// asks an authorizer. Marked `@MainActor` because real authorizers consult the app's
/// policy gate, which is main-actor isolated.
@MainActor
public protocol StepAuthorizing {
    func authorize(_ step: PlanStep, in goal: PlanningGoal) async -> StepAuthorization

    /// Returns a copy of this authorizer that attributes the proposals it files to `actor`.
    ///
    /// Exists because the authorizer is assembled *before* the goal is planned, so at
    /// construction time nobody yet knows which planner will actually write the steps — the
    /// model-backed planner degrades to templates whenever grounding fails, and
    /// ``PlanDeliberation/planner`` is the only thing that knows which happened. An authorizer
    /// built with a fixed `planner.<name>` therefore filed every proposal under the planner that
    /// was *installed*, while the worklog `considered` entry for the same run recorded the planner
    /// that *ran* — one run, two identities, and the proposal could not be joined to the reasoning
    /// that produced it.
    ///
    /// ``AutopilotRunner`` calls this once, between planning and orchestration, so both sides of
    /// that join are derived from the same ``PlanDeliberation``.
    ///
    /// The default returns `self`: an authorizer that records no actor has nothing to rebind, and
    /// making this a requirement with no default would break every existing conformer — including
    /// the test doubles whose whole purpose is to answer `authorize` and nothing else.
    func attributing(to actor: ActorRef) -> any StepAuthorizing
}

public extension StepAuthorizing {
    func attributing(to actor: ActorRef) -> any StepAuthorizing { self }
}

public extension PlanDeliberation {
    /// The actor a run's proposals and its `considered` worklog entry should both carry.
    ///
    /// Derived from the deliberation rather than from the planner's own `name`, because `name` is
    /// an implementation identifier fixed at construction while this is run attribution: a
    /// model-backed planner whose grounding failed produced *template* steps and must be recorded
    /// as the template planner. `telemetry` is non-`nil` exactly when a model's output produced
    /// the steps, so it is also the right test for whether this is a `.model` actor at all.
    var plannerActor: ActorRef {
        let identifier = "planner.\(planner)"
        guard let route = telemetry?.route else {
            return ActorRef(kind: .workflow, identifier: identifier)
        }
        return ActorRef.model(identifier: identifier, route: route)
    }
}
