@testable import AutopilotCore
import AuralisFoundation
import AuralisRuntime
import Testing

/// Named rather than a fabricated default, so these tests carry the same attribution a real caller
/// must supply (P0.5-602). File scope: every suite below builds proposals.
private let plannerActor = ActorRef(kind: .workflow, identifier: "planner.test")

/// Records the proposal it was asked to judge, so a test can assert what the authorizer *built*
/// rather than only what verdict came back. Allows everything — the proposal is the subject here.
private actor CapturedProposalJudge: Judge {
    private var proposal: ActionProposal?

    func judge(_ proposal: ActionProposal, checkResults: [DeterministicCheckResult]) async -> JudgeDecision {
        self.proposal = proposal
        return .allow
    }

    func correlationID() -> String? { proposal?.correlationID }

    func capturedProposal() -> ActionProposal? { proposal }
}

@Suite("JudgeStepAuthorizer")
@MainActor
struct JudgeStepAuthorizerTests {
    private let goal = PlanningGoal(text: "organize my music", surface: "music")

    private func step(_ capability: CapabilityID, _ kind: PlanStepKind) -> PlanStep {
        PlanStep(capability: capability, kind: kind, title: "step", rationale: "because")
    }

    @Test
    func observeAndAssistStepsRunUnattended() async {
        let authorizer = JudgeStepAuthorizer(actor: plannerActor)
        #expect(await authorizer.authorize(step(.audioPlayback, .observe), in: goal) == .autopilot)
        #expect(await authorizer.authorize(step(.autoOrganization, .assist), in: goal) == .autopilot)
    }

    /// The authorizer is built before the goal is planned, so the actor it starts with names the
    /// *installed* planner. A model-backed planner that fails to ground its output writes template
    /// steps, so the planner that ran is routinely not the one installed — `AutopilotRunner`
    /// rebinds through this seam, and without it a proposal cannot be joined to the `considered`
    /// entry recording the reasoning that produced it.
    @Test
    func rebindingAttributionRetargetsTheProposalWithoutDisturbingAuthority() async {
        let judge = CapturedProposalJudge()
        let installed = JudgeStepAuthorizer(
            judge: judge,
            actor: ActorRef(kind: .workflow, identifier: "planner.model"),
            correlationID: "run-1"
        )

        let ranInstead = PlanDeliberation(planner: "deterministic", candidates: [])
        let rebound = installed.attributing(to: ranInstead.plannerActor)

        #expect(await rebound.authorize(step(.audioPlayback, .observe), in: goal) == .autopilot)

        let proposal = await judge.capturedProposal()
        #expect(proposal?.actor.identifier == "planner.deterministic")
        #expect(proposal?.actor.kind == .workflow)
        // The correlation id is a property of the run, not of the attribution, so the rebind must
        // carry it through — losing it would file the proposal outside the trace that made it.
        #expect(proposal?.correlationID == "run-1")
    }

    @Test
    func executeStepsAreBlockedInObserveMode() async {
        let authorizer = JudgeStepAuthorizer(judge: ObserveModeJudge(isObserveMode: true), actor: plannerActor)
        // Both a reversible music write and a high-risk wallet action are blocked in Observe.
        guard case .blocked = await authorizer.authorize(step(.playlistManagement, .execute), in: goal) else {
            Issue.record("expected reversible-write execute step to be blocked in Observe mode")
            return
        }
        guard case .blocked = await authorizer.authorize(step(.signMessage, .execute), in: goal) else {
            Issue.record("expected high-risk execute step to be blocked in Observe mode")
            return
        }
    }

    @Test
    func outsideObserveConfirmationClassEscalatesToConfirmation() async {
        let authorizer = JudgeStepAuthorizer(judge: ObserveModeJudge(isObserveMode: false), actor: plannerActor)
        // High-risk requires confirmation → maps to needsConfirmation on the ladder.
        guard case .needsConfirmation = await authorizer.authorize(step(.signMessage, .execute), in: goal) else {
            Issue.record("expected high-risk step to need confirmation outside Observe mode")
            return
        }
        // Reversible write does not require confirmation → runs unattended outside Observe.
        #expect(await authorizer.authorize(step(.playlistManagement, .execute), in: goal) == .autopilot)
    }

    /// Cancelling the task running a goal must stop the loop. Nothing downstream honours cancellation
    /// — the orchestrator iterates the whole plan and the executor never checks — so the authorizer is
    /// what has to refuse, or a cancelled run executes every remaining step.
    ///
    /// The cancellation is observed deterministically rather than racily: the suite is `@MainActor` and
    /// the child task inherits that isolation, so its body cannot begin until this method suspends at
    /// the `await` below — by which time `cancel()` has already landed.
    @Test
    func aCancelledRunIsBlockedEvenWhenThePolicyWouldAllowIt() async {
        // Outside Observe, and a reversible write: this step authorizes to `.autopilot` when the run is
        // live (pinned by `outsideObserveConfirmationClassEscalatesToConfirmation`), so a `.blocked`
        // here can only be the cancellation.
        let authorizer = JudgeStepAuthorizer(judge: ObserveModeJudge(isObserveMode: false), actor: plannerActor)
        let pending = step(.playlistManagement, .execute)
        let goal = goal

        let task = Task { @MainActor in
            await authorizer.authorize(pending, in: goal)
        }
        task.cancel()

        guard case let .blocked(reason) = await task.value else {
            Issue.record("expected a cancelled run to block the step")
            return
        }
        #expect(reason.contains("cancelled"))
    }

    /// The run's correlation id is what proposals are filed under, so the trace joins the session,
    /// events, and receipts the host writes under that same id. Passing the goal's *surface* instead
    /// filed every run launched from one screen under a single shared key.
    @Test
    func proposalsAreFiledUnderTheRunsCorrelationIDRatherThanTheSurface() async {
        let captured = CapturedProposalJudge()
        let authorizer = JudgeStepAuthorizer(
            judge: captured,
            actor: plannerActor,
            correlationID: "run-42"
        )

        _ = await authorizer.authorize(step(.audioPlayback, .observe), in: goal)

        // `goal.surface` is "music"; the run id must win.
        #expect(await captured.correlationID() == "run-42")
    }

    /// With no run id supplied the surface remains the fallback — right for a caller that has no run
    /// of its own to join, and the behaviour `PlanStepProposal` documents.
    @Test
    func withoutARunCorrelationIDTheSurfaceRemainsTheFallback() async {
        let captured = CapturedProposalJudge()
        let authorizer = JudgeStepAuthorizer(judge: captured, actor: plannerActor)

        _ = await authorizer.authorize(step(.audioPlayback, .observe), in: goal)

        #expect(await captured.correlationID() == "music")
    }

    @Test
    func failedCheckBlocksTheStep() async {
        let checks = DeterministicCheckRegistry()
        await checks.register(ClosureCheck(id: "must.fail") { _ in
            DeterministicCheckResult(checkID: "must.fail", passed: false, detail: "nope")
        })
        let authorizer = JudgeStepAuthorizer(
            judge: ObserveModeJudge(isObserveMode: false),
            checks: checks,
            actor: plannerActor,
            requiredCheckIDs: { _ in ["must.fail"] }
        )
        guard case .blocked = await authorizer.authorize(step(.audioPlayback, .observe), in: goal) else {
            Issue.record("expected a failed check to block the step")
            return
        }
    }
}

@Suite("DomainJudge — crypto-scoped boundary")
struct DomainJudgeTests {
    private func proposal(_ capability: CapabilityID, _ impact: ActionImpactClass) -> ActionProposal {
        ActionProposal(actor: .system, intent: "x", capability: capability, impact: impact)
    }

    @Test
    func cryptoActionsAreBlockedInObserve() async {
        let judge = DomainJudge(cryptoMode: .observe)
        let decision = await judge.judge(proposal(.signMessage, .highRisk), checkResults: [])
        guard case let .block(reason) = decision else {
            Issue.record("expected crypto action blocked, got \(decision)")
            return
        }
        #expect(reason.contains("Observe"))
    }

    @Test
    func cryptoActionsEscalateInAssist() async {
        let judge = DomainJudge(cryptoMode: .assist)
        guard case .escalate = await judge.judge(proposal(.signMessage, .highRisk), checkResults: []) else {
            Issue.record("expected crypto action escalated in Assist")
            return
        }
    }

    @Test
    func cryptoReadOnlyActionsCanRunInOperate() async {
        let judge = DomainJudge(cryptoMode: .operate)
        #expect(await judge.judge(proposal(.draftTransaction, .readOnly), checkResults: []) == .allow)
    }

    @Test
    func nonCryptoWritesAreAllowed() async {
        let judge = DomainJudge()
        // A reversible music-library write runs — full CRUD outside crypto.
        #expect(await judge.judge(proposal(.playlistManagement, .reversibleWrite), checkResults: []) == .allow)
        #expect(await judge.judge(proposal(.metadataOverride, .reversibleWrite), checkResults: []) == .allow)
        #expect(await judge.judge(proposal(.audioPlayback, .readOnly), checkResults: []) == .allow)
    }

    @Test
    func nonCryptoExternalImpactEscalates() async {
        let judge = DomainJudge()
        guard case .escalate = await judge.judge(proposal(.musicExport, .externalImpact), checkResults: []) else {
            Issue.record("expected external-impact non-crypto action to escalate")
            return
        }
    }

    @Test
    func failedCheckBlocksAnyDomain() async {
        let judge = DomainJudge()
        let failed = [DeterministicCheckResult(checkID: "c", passed: false)]
        guard case .block = await judge.judge(proposal(.playlistManagement, .reversibleWrite), checkResults: failed) else {
            Issue.record("expected a failed check to block even a non-crypto action")
            return
        }
    }
}

@Suite("JudgeStepAuthorizer default (DomainJudge)")
@MainActor
struct JudgeStepAuthorizerDomainDefaultTests {
    private let goal = PlanningGoal(text: "organize", surface: "music")

    private func step(_ capability: CapabilityID, _ kind: PlanStepKind) -> PlanStep {
        PlanStep(capability: capability, kind: kind, title: "step", rationale: "r")
    }

    @Test
    func nonCryptoExecuteRunsUnattended() async {
        let authorizer = JudgeStepAuthorizer(actor: plannerActor) // default DomainJudge
        #expect(await authorizer.authorize(step(.playlistManagement, .execute), in: goal) == .autopilot)
    }

    @Test
    func cryptoExecuteIsBlocked() async {
        let authorizer = JudgeStepAuthorizer(actor: plannerActor) // default DomainJudge
        guard case .blocked = await authorizer.authorize(step(.signMessage, .execute), in: goal) else {
            Issue.record("expected crypto execute step blocked under DomainJudge default")
            return
        }
    }
}

@Suite("JudgeDecision ↔ StepAuthorization bridge")
struct JudgeDecisionBridgeTests {
    @Test
    func mapsEachVerdict() {
        #expect(JudgeDecision.allow.asStepAuthorization == .autopilot)
        #expect(JudgeDecision.block(reason: "no").asStepAuthorization == .blocked("no"))
        #expect(JudgeDecision.revise(instructions: "fix").asStepAuthorization == .needsConfirmation("fix"))

        let proposal = ActionProposal(actor: .system, intent: "x", capability: .runPlugin, impact: .externalImpact)
        let request = ApprovalRequest(proposal: proposal, prompt: "approve?")
        #expect(JudgeDecision.escalate(approvalRequest: request).asStepAuthorization == .needsConfirmation("approve?"))
    }
}

@Suite("PlanStepProposal")
struct PlanStepProposalTests {
    /// The impact class comes from the capability, whatever the step's `kind` claims.
    ///
    /// This assertion used to require `.readOnly` here — the test was named
    /// `observeStepsAreReadOnlyRegardlessOfCapability`, which states the defect exactly. A
    /// `.readOnly` proposal has `requiresConfirmation == false`, and that is what
    /// `StandingToolPolicy` reads: in Observe mode the crypto branch still blocked this step (it
    /// keys on the capability), but in **Operate** mode it returned `.allow` — an irreversible
    /// signature authorized unattended because the step called itself a read.
    @Test
    func stepImpactComesFromCapabilityNotDeclaredKind() {
        let goal = PlanningGoal(text: "g", surface: "s")
        let step = PlanStep(capability: .signMessage, kind: .observe, title: "peek", rationale: "r")

        let proposal = PlanStepProposal.makeProposal(for: step, in: goal, actor: plannerActor)

        #expect(proposal.impact == .highRisk)
        #expect(proposal.impact.requiresConfirmation)
        #expect(proposal.correlationID == "s")
    }

    @Test
    func executeStepsTakeCapabilityImpact() {
        let goal = PlanningGoal(text: "g")
        let step = PlanStep(capability: .signMessage, kind: .execute, title: "sign", rationale: "r")
        let proposal = PlanStepProposal.makeProposal(for: step, in: goal, actor: plannerActor)
        #expect(proposal.impact == .highRisk)
    }

    /// A capability that *has* a read-only mode keeps the step's own claim, so the floor does not
    /// make the whole ladder ceremonial.
    ///
    /// `runPlugin` is the case that matters: it is `.externalImpact` to *execute*, and it is also
    /// the capability every non-wallet agent step maps onto — `OperatorCatalog` declares the
    /// Research Brief tool it resolves to `.readOnly`. Flooring it at its execute-impact would send
    /// a library summary to the approval inbox.
    @Test("a capability with a read-only mode keeps the step's claimed impact on the advisory rungs")
    func capabilityWithReadOnlyModeKeepsClaimedImpact() {
        let goal = PlanningGoal(text: "g")

        for capability in [CapabilityID.audioPlayback, .runPlugin, .musicLibraryClassification] {
            for kind in [PlanStepKind.observe, .assist] {
                let step = PlanStep(capability: capability, kind: kind, title: "look", rationale: "r")
                let proposal = PlanStepProposal.makeProposal(for: step, in: goal, actor: plannerActor)
                #expect(proposal.impact == .readOnly, "\(kind) on \(capability.rawValue)")
                #expect(proposal.impact.requiresConfirmation == false)
            }
        }
    }

    /// An export has no read-only mode — producing one always puts data somewhere else, and
    /// inspecting what *would* be exported is a different capability — so the same mislabelling
    /// cannot clear it either.
    @Test("an export mislabelled as a read is floored at external impact")
    func exportStepIsFlooredAtExternalImpact() {
        let goal = PlanningGoal(text: "g")
        let step = PlanStep(capability: .musicExport, kind: .observe, title: "peek at export", rationale: "r")

        let proposal = PlanStepProposal.makeProposal(for: step, in: goal, actor: plannerActor)

        #expect(proposal.impact == .externalImpact)
        #expect(proposal.impact.requiresConfirmation)
    }
}
