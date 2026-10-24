import PlannerCore
import RuntimeCore

/// A ``StepAuthorizing`` that authorizes plan steps through the RuntimeCore governance kernel:
/// it turns each step into an ``ActionProposal``, runs the required deterministic checks, asks a
/// ``Judge``, and maps the ``JudgeDecision`` back onto the ``StepAuthorization`` ladder.
///
/// This is the RuntimeCore-native counterpart to ``AutopilotAuthorizer`` (which drives the legacy
/// `PolicyActionGating`). Both honor the same Observe → Assist → Confirm → Autopilot ladder; this one
/// additionally runs deterministic checks and can express `.revise`/`.escalate` verdicts. With the
/// default ``ObserveModeJudge`` in Observe mode, execute steps for high-risk capabilities resolve to
/// `.blocked`, exactly like the rest of the app.
@MainActor
public struct JudgeStepAuthorizer: StepAuthorizing {
    private let judge: any Judge
    private let checks: DeterministicCheckRegistry
    private let requiredCheckIDs: @Sendable (PlanStep) -> [String]
    private let actor: ActorRef
    /// The global kill switch, consulted before the judge on every step.
    ///
    /// Defence in depth rather than the primary enforcement: `RuntimeHost.runAutopilotGoal` refuses a
    /// paused run outright, before a planner is even built, which is what stops inference from
    /// happening at all. This exists for the caller that reaches an authorizer some other way.
    ///
    /// The gap it closes: ``RuntimeCore/PauseGate`` was wired into `GovernedToolPipeline` only, so
    /// pausing stopped `runOperator`/`runPolicyAction` and — via the scheduling engine — routines,
    /// while an autopilot goal run went through neither. A paused runtime still planned on device,
    /// still performed read-only and advisory steps, and still wrote `autopilot.step.ran` receipts
    /// with `isSuccess: true`. Only steps that happened to route to a governed operator were
    /// refused, and then by the pipeline rather than by anything autopilot itself consulted.
    ///
    /// `nil` leaves the authorizer ungated, which is right for a caller that has no runtime host and
    /// therefore no kill switch to honour.
    private let pauseGate: PauseGate?
    /// The grouping key every proposal this authorizer builds is filed under — the *run's* correlation
    /// id, supplied by whoever started the goal. `nil` falls back to the goal's surface, which is right
    /// only for a caller that has no run of its own to join.
    private let correlationID: String?

    /// - Parameter actor: Who is proposing the steps this authorizer judges (P0.5-602). Forwarded onto
    ///   every ``ActionProposal`` it builds, so the Judge evaluates — and the worklog records — a
    ///   correctly attributed proposal.
    ///
    ///   This is the attribution to use when no plan exists yet. Which planner actually wrote a
    ///   run's steps is not knowable here — a model-backed planner degrades to templates whenever
    ///   grounding fails — so ``AutopilotRunner`` replaces it via
    ///   ``attributing(to:)`` once the deliberation is in hand. Pass the installed planner's
    ///   `planner.<name>`; it is the right answer for a caller that orchestrates directly without
    ///   going through the runner.
    ///
    ///   No default: an `= ActorRef(kind: .workflow, identifier: "planner")` fallback let a second
    ///   planner compile clean and record proposals indistinguishable from the first one's, which is
    ///   the silent misattribution this ticket exists to prevent. Naming yourself is the price of
    ///   proposing an action.
    public init(
        judge: any Judge = DomainJudge(),
        checks: DeterministicCheckRegistry = DeterministicCheckRegistry(),
        // Grouped with the judge and the checks: these three are the authority inputs, and the gate
        // outranks the other two.
        pauseGate: PauseGate? = nil,
        actor: ActorRef,
        correlationID: String? = nil,
        requiredCheckIDs: @escaping @Sendable (PlanStep) -> [String] = { _ in [] }
    ) {
        self.judge = judge
        self.checks = checks
        self.actor = actor
        self.pauseGate = pauseGate
        self.correlationID = correlationID
        self.requiredCheckIDs = requiredCheckIDs
    }

    /// Rebinds the proposal attribution to the planner that actually produced the run's steps.
    ///
    /// Every other input is carried over unchanged — the judge, the checks, the kill switch, and
    /// the correlation id are all properties of the *run*, and only the actor was provisional.
    public func attributing(to actor: ActorRef) -> any StepAuthorizing {
        JudgeStepAuthorizer(
            judge: judge,
            checks: checks,
            pauseGate: pauseGate,
            actor: actor,
            correlationID: correlationID,
            requiredCheckIDs: requiredCheckIDs
        )
    }

    public func authorize(_ step: PlanStep, in goal: PlanningGoal) async -> StepAuthorization {
        // Cancellation is the caller's explicit stop, so it outranks even the pause gate.
        //
        // Nothing else in the loop honoured it: ``SequentialPlanOrchestrator`` iterates the whole plan
        // and neither it nor the executor consults `Task.isCancelled`, so cancelling the task running
        // a goal — navigating away from Mission Control, tearing down the surface — left every
        // remaining step to execute anyway, writing `autopilot.step.ran` receipts with
        // `isSuccess: true` for work the user had already called off. The authorizer is consulted
        // immediately before each step, so refusing here halts the run at the next step boundary:
        // the orchestrator stops on `.blocked` and reports the rest as skipped.
        //
        // Read-only and advisory steps are refused too, deliberately. A cancelled run must stop
        // spending inference and I/O, not just stop mutating state.
        if Task.isCancelled {
            return .blocked("The run was cancelled.")
        }
        // The kill switch outranks the judge, so it is read first. A paused runtime permits nothing,
        // and asking the judge would otherwise clear the step on its own merits. See ``pauseGate``.
        if let pauseGate, await pauseGate.isPaused() {
            return .blocked("Operator activity is paused.")
        }
        let checkIDs = requiredCheckIDs(step)
        let proposal = PlanStepProposal.makeProposal(
            for: step,
            in: goal,
            actor: actor,
            requiredCheckIDs: checkIDs,
            // The run's own grouping key, not `goal.surface`. A surface is a *screen* name shared by
            // every run launched from it ("missionControl"), so filing proposals under it collapsed
            // unrelated runs into one trace while the run's session, events, and receipts were filed
            // under the real correlation id — the split trace ``ActionProposal/resolvedCorrelationID``
            // warns about. Falls back to the surface via `makeProposal` when the caller has no run id.
            correlationID: correlationID
        )
        let results = await checks.evaluate(ids: checkIDs, for: proposal)
        let decision = await judge.judge(proposal, checkResults: results)
        return decision.asStepAuthorization
    }
}
