/// Which rung of the autonomy ladder a plan step sits on.
///
/// The ladder is Observe → Assist → Confirm → Autopilot. A step's `kind` decides how
/// far it may go on its own before a human is involved:
///
/// - ``observe``: read-only. Gather or inspect state. Always safe to run unattended.
/// - ``assist``: produce a recommendation or draft. No state changes, so also safe to
///   run unattended — the output is advice the user can accept or ignore.
/// - ``execute``: changes state (spends, signs, writes, mutates a library). Must pass
///   the policy gate, and only runs unattended when it is an explicitly trusted routine.
public enum PlanStepKind: String, Codable, CaseIterable, Equatable, Sendable {
    case observe
    case assist
    case execute

    /// Whether this rung changes state and therefore requires authorization before running.
    public var isStateChanging: Bool {
        self == .execute
    }
}
