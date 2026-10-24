/// The authorization verdict for a single ``PlanStep``, produced by a ``StepAuthorizing``
/// implementation just before the orchestrator would run that step.
///
/// This is the ladder made concrete:
/// - ``autopilot``: run it now, unattended.
/// - ``needsConfirmation(_:)``: allowed in principle, but a human must confirm first.
/// - ``blocked(_:)``: not permitted (for example, the current app mode forbids it).
public enum StepAuthorization: Equatable, Sendable {
    case autopilot
    case needsConfirmation(String)
    case blocked(String)

    /// Whether the orchestrator may execute the step without further input.
    public var isRunnable: Bool {
        if case .autopilot = self { return true }
        return false
    }

    /// The user-facing reason, when there is one.
    public var message: String? {
        switch self {
        case .autopilot: return nil
        case let .needsConfirmation(message), let .blocked(message): return message
        }
    }
}
