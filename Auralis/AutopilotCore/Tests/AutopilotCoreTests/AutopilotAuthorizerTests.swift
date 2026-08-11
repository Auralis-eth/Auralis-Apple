import CapabilitiesCore
import PlannerCore
import PolicyCore
import Testing
@testable import AutopilotCore

/// A gate that returns a fixed verdict, so authorizer behavior can be tested without the
/// full policy machinery.
private struct FixedGate: PolicyActionGating {
    let allowed: Bool
    var message: String = ""

    func attempt(_ action: PolicyControlledAction) async -> PolicyGateResult {
        PolicyGateResult(isAllowed: allowed, userMessage: message)
    }
}

private func step(_ kind: PlanStepKind, _ capability: CapabilityID, title: String = "do it") -> PlanStep {
    PlanStep(capability: capability, kind: kind, title: title, rationale: "r")
}

private let goal = PlanningGoal(text: "demo")

@MainActor
struct AutopilotAuthorizerTests {
    @Test("observe and assist steps are always cleared to run unattended")
    func readOnlyStepsAreAutopilot() async {
        let authorizer = AutopilotAuthorizer(gate: FixedGate(allowed: false, message: "blocked"))
        let observe = await authorizer.authorize(step(.observe, .musicLibraryClassification), in: goal)
        let assist = await authorizer.authorize(step(.assist, .autoOrganization), in: goal)
        #expect(observe == .autopilot)
        #expect(assist == .autopilot)
    }

    @Test("an execute step the policy denies is blocked with the policy's reason")
    func deniedExecuteIsBlocked() async {
        let authorizer = AutopilotAuthorizer(gate: FixedGate(allowed: false, message: "Not available in Observe mode"))
        let result = await authorizer.authorize(step(.execute, .musicExport), in: goal)
        #expect(result == .blocked("Not available in Observe mode"))
    }

    @Test("an allowed but untrusted execute step asks for confirmation")
    func allowedUntrustedNeedsConfirmation() async {
        let authorizer = AutopilotAuthorizer(gate: FixedGate(allowed: true))
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
            trustedRoutines: TrustedRoutineAllowlist([.playlistManagement])
        )
        let result = await authorizer.authorize(step(.execute, .playlistManagement), in: goal)
        #expect(result == .autopilot)
    }

    @Test("trust never bypasses a policy denial")
    func trustDoesNotOverrideDenial() async {
        let authorizer = AutopilotAuthorizer(
            gate: FixedGate(allowed: false, message: "denied"),
            trustedRoutines: TrustedRoutineAllowlist([.musicExport])
        )
        let result = await authorizer.authorize(step(.execute, .musicExport), in: goal)
        #expect(result == .blocked("denied"))
    }
}
