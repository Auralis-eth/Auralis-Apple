import AuralisPrimaryModels
@testable import AutopilotCore
import AuralisFoundation
import PlannerCore
import PolicyCore
import RuntimeCore
import Testing

/// A gate that returns a fixed verdict, so authorizer behavior can be tested without the
/// full policy machinery.
private struct FixedGate: PolicyActionGating {
    let allowed: Bool
    var message: String = ""

    func attempt(_ action: PolicyControlledAction, actor: ActorRef) async -> PolicyGateResult {
        PolicyGateResult(isAllowed: allowed, userMessage: message)
    }
}

private func step(_ kind: PlanStepKind, _ capability: CapabilityID, title: String = "do it") -> PlanStep {
    PlanStep(capability: capability, kind: kind, title: title, rationale: "r")
}

private let goal = PlanningGoal(text: "demo")

/// Named rather than a fabricated default, so these tests exercise the same attribution a real
/// caller must supply (P0.5-602).
private let autopilotActor = ActorRef(kind: .workflow, identifier: "autopilot.test")

@MainActor
struct AutopilotAuthorizerTests {
    /// Advisory steps on a capability that cannot require confirmation still stream through without
    /// a gate call — that is what keeps the top of the ladder cheap, and why a music classification
    /// read is not stopped by the legacy whole-app gate. The gate here denies everything and is
    /// never asked.
    @Test("advisory steps below the confirmation line are cleared without consulting the gate")
    func lowImpactAdvisoryStepsAreAutopilot() async {
        let authorizer = AutopilotAuthorizer(gate: FixedGate(allowed: false, message: "blocked"), actor: autopilotActor)

        #expect(await authorizer.authorize(step(.observe, .audioPlayback), in: goal) == .autopilot)
        #expect(await authorizer.authorize(step(.assist, .audioPlayback), in: goal) == .autopilot)
        #expect(await authorizer.authorize(step(.observe, .musicLibraryClassification), in: goal) == .autopilot)
        #expect(await authorizer.authorize(step(.assist, .autoOrganization), in: goal) == .autopilot)
    }

    /// The bypass this authorizer used to have. `kind` is a claim the step makes about itself — on
    /// the model-planning path it is free text a model emitted — so clearing `.observe`/`.assist`
    /// before consulting the gate meant a step naming a wallet capability and labelling itself
    /// "read-only" ran unattended with the Observe boundary never asked. Whether the gate is
    /// consulted is now decided by the capability.
    @Test("a confirmation-class capability mislabelled as read-only is still put through the gate")
    func mislabelledHighImpactStepIsGated() async {
        let denying = AutopilotAuthorizer(
            gate: FixedGate(allowed: false, message: "Not available in Observe mode"),
            actor: autopilotActor
        )

        for kind in [PlanStepKind.observe, .assist] {
            // Wallet signing: the hole as filed.
            let signing = await denying.authorize(step(kind, .signMessage, title: "look at a signature"), in: goal)
            #expect(signing == .blocked("Not available in Observe mode"), "\(kind) on .signMessage must not skip the gate")

            // The same hole one notch down: an export reaches off the device, so relabelling it as
            // a read must not clear it either.
            let export = await denying.authorize(step(kind, .musicExport, title: "look at an export"), in: goal)
            #expect(export == .blocked("Not available in Observe mode"), "\(kind) on .musicExport must not skip the gate")
        }
    }

    /// Passing the gate is not authorization to run unattended.
    ///
    /// This used to assert `.autopilot` for `{.observe, .signMessage}`, which left the mislabelling
    /// hole half-closed: the step was correctly *gated*, and then its own `.observe` claim was taken at
    /// face value for the verdict — and `StepAuthorization.autopilot` means "run it now, unattended".
    /// In Operate mode that produced a signature nobody confirmed. A capability with no read-only floor
    /// must reach a confirmation prompt regardless of the `kind` the planner (or a model) wrote on it,
    /// which is the same floor `PlanStepProposal` applies via `max(claimed, minimumImpact(for:))`.
    @Test("an allowed capability with no read-only floor needs confirmation even when labelled advisory")
    func allowedAdvisoryStepsWithNoReadOnlyFloorStillAsk() async {
        let authorizer = AutopilotAuthorizer(gate: FixedGate(allowed: true), actor: autopilotActor)

        for kind in [PlanStepKind.observe, .assist] {
            let signing = await authorizer.authorize(step(kind, .signMessage, title: "Sign it"), in: goal)
            #expect(
                signing == .needsConfirmation("“Sign it” is ready — confirm to run it."),
                "\(kind) on .signMessage must not run unattended"
            )

            let export = await authorizer.authorize(step(kind, .musicExport, title: "Export it"), in: goal)
            #expect(
                export == .needsConfirmation("“Export it” is ready — confirm to run it."),
                "\(kind) on .musicExport must not run unattended"
            )
        }
    }

    /// The narrowing must not reach capabilities that genuinely have a read-only mode — those still
    /// stream on the advisory rungs, which is the whole-app-posture regression this guards against.
    @Test("an allowed capability with a read-only floor still streams on the advisory rungs")
    func allowedAdvisoryStepsWithReadOnlyFloorStillStream() async {
        let authorizer = AutopilotAuthorizer(gate: FixedGate(allowed: true), actor: autopilotActor)

        #expect(await authorizer.authorize(step(.observe, .audioPlayback), in: goal) == .autopilot)
        #expect(await authorizer.authorize(step(.assist, .musicLibraryClassification), in: goal) == .autopilot)
    }

    @Test("an execute step the policy denies is blocked with the policy's reason")
    func deniedExecuteIsBlocked() async {
        let authorizer = AutopilotAuthorizer(
            gate: FixedGate(allowed: false, message: "Not available in Observe mode"),
            actor: autopilotActor
        )
        let result = await authorizer.authorize(step(.execute, .musicExport), in: goal)
        #expect(result == .blocked("Not available in Observe mode"))
    }

    @Test("an allowed but untrusted execute step asks for confirmation")
    func allowedUntrustedNeedsConfirmation() async {
        let authorizer = AutopilotAuthorizer(gate: FixedGate(allowed: true), actor: autopilotActor)
        let result = await authorizer.authorize(step(.execute, .playlistManagement, title: "Create the playlist"), in: goal)
        guard case .needsConfirmation = result else {
            Issue.record("expected needsConfirmation, got \(result)")
            return
        }
    }

    @Test("an allowed execute step that is a trusted routine runs on autopilot")
    func allowedTrustedIsAutopilot() async {
        let authorizer = AutopilotAuthorizer(
            gate: FixedGate(allowed: true),
            trustedRoutines: TrustedRoutineAllowlist([.playlistManagement]),
            actor: autopilotActor
        )
        let result = await authorizer.authorize(step(.execute, .playlistManagement), in: goal)
        #expect(result == .autopilot)
    }

    @Test("trust never bypasses a policy denial")
    func trustDoesNotOverrideDenial() async {
        let authorizer = AutopilotAuthorizer(
            gate: FixedGate(allowed: false, message: "denied"),
            trustedRoutines: TrustedRoutineAllowlist([.musicExport]),
            actor: autopilotActor
        )
        let result = await authorizer.authorize(step(.execute, .musicExport), in: goal)
        #expect(result == .blocked("denied"))
    }
}
