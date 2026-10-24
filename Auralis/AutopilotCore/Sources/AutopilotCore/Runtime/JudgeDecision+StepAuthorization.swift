import PlannerCore
import RuntimeCore

/// Bridges a RuntimeCore ``JudgeDecision`` onto the PlannerCore ``StepAuthorization`` ladder.
///
/// The two vocabularies line up cleanly except that the ladder has no separate "revise" rung — a
/// proposal the Judge wants revised is surfaced to the user as a confirmation carrying the revision
/// instructions, same as an escalation carries its approval prompt.
public extension JudgeDecision {
    var asStepAuthorization: StepAuthorization {
        switch self {
        case .allow:
            return .autopilot
        case let .block(reason):
            return .blocked(reason)
        case let .revise(instructions):
            return .needsConfirmation(instructions)
        case let .escalate(request):
            return .needsConfirmation(request.prompt)
        }
    }
}
