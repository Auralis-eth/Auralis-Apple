import Foundation

/// One mechanically checkable statement about what a successful run looks like.
///
/// The executable counterpart to ``OutcomeSpec/proseCriteria``, which is prose: prose states intent
/// for a person to read, a criterion is something the evaluator can actually decide from a worklog
/// trace. A closed enum rather than a predicate closure so specs are `Codable` — an eval is only
/// useful if the same spec can be re-run against a later trace and the two results compared, which
/// means the spec has to survive a round trip to disk.
///
/// Every case is decidable from ``WorkflowStepLog`` alone. That is a deliberate constraint for this
/// first slice: no criterion may need the model, the network, or a human, so an eval is reproducible
/// in CI and its verdict is reproducible from the same evidence a receipt already carries.
public enum SuccessCriterion: Equatable, Sendable, Codable, Hashable {
    /// The run executed something and produced an artifact.
    case producedArtifact
    /// The whole trace, first entry to last, fits inside a wall-clock budget.
    case completedWithin(seconds: Double)
    /// Nothing in the run was refused by governance.
    case noBlockedSteps
    /// Nothing in the run failed.
    case noFailedSteps
    /// Every deterministic check that ran passed.
    case allDeterministicChecksPassed
    /// The Judge never had to hand the run up for approval — i.e. it completed unattended.
    case judgeDidNotEscalate
    /// A scheduled routine reached a specific phase.
    case reachedRoutinePhase(RoutinePhase)
    /// Every entry in the trace is one this build can interpret.
    ///
    /// Worth stating as a criterion in its own right because an illegible trace is a real finding: it
    /// means the evidence was written by a build this one cannot fully read, and any eval over it is
    /// weaker than it looks. See ``WorkflowWorklogEvent/unknown(caseName:payload:)``.
    case traceFullyLegible

    /// A stable identifier, safe to persist and to group report cards by.
    ///
    /// Parameterised cases fold their parameter into the id so `completedWithin(30)` and
    /// `completedWithin(60)` are distinct rows rather than colliding under one key.
    public var id: String {
        switch self {
        case .producedArtifact: return "producedArtifact"
        case let .completedWithin(seconds): return "completedWithin:\(seconds)"
        case .noBlockedSteps: return "noBlockedSteps"
        case .noFailedSteps: return "noFailedSteps"
        case .allDeterministicChecksPassed: return "allDeterministicChecksPassed"
        case .judgeDidNotEscalate: return "judgeDidNotEscalate"
        case let .reachedRoutinePhase(phase): return "reachedRoutinePhase:\(phase.rawValue)"
        case .traceFullyLegible: return "traceFullyLegible"
        }
    }

    /// A user-facing label for trust surfaces and report cards.
    public var displayTitle: String {
        switch self {
        case .producedArtifact: return "Produced an artifact"
        case let .completedWithin(seconds): return "Completed within \(Self.format(seconds))s"
        case .noBlockedSteps: return "Nothing was blocked"
        case .noFailedSteps: return "Nothing failed"
        case .allDeterministicChecksPassed: return "All checks passed"
        case .judgeDidNotEscalate: return "Ran without escalation"
        case let .reachedRoutinePhase(phase): return "Reached \(phase.displayTitle.lowercased())"
        case .traceFullyLegible: return "Trace fully legible"
        }
    }

    /// How the criterion relates to the evidence, which decides what an unreadable entry does to it.
    ///
    /// The distinction matters because ``WorkflowWorklogEvent/unknown(caseName:payload:)`` means "an
    /// event happened that this build cannot classify". For a criterion asserting something is
    /// *absent*, that is fatal — the unknown event could be the very thing being ruled out, so the
    /// trace cannot support a clean verdict. For a criterion asserting something is *present*, it is
    /// fatal only when the thing was not otherwise found: evidence located elsewhere in the trace
    /// still settles the question.
    public enum Evidence: Equatable, Sendable {
        /// Asserts an event is present. Unknown entries only matter if it was not found.
        case existential
        /// Asserts an event is absent. Any unknown entry makes the verdict unsafe.
        case universal
        /// Decidable from entry metadata (timestamps, event legibility) regardless of payloads.
        case structural
    }

    public var evidence: Evidence {
        switch self {
        case .producedArtifact, .reachedRoutinePhase:
            return .existential
        case .noBlockedSteps, .noFailedSteps, .allDeterministicChecksPassed, .judgeDidNotEscalate:
            return .universal
        case .completedWithin, .traceFullyLegible:
            return .structural
        }
    }

    /// Renders a budget for ``id`` and ``displayTitle``.
    ///
    /// The finiteness guard is load-bearing, not defensive: the whole-number path converts through
    /// `Int`, which *traps* on a value `Int` cannot represent, and nothing validates a budget. This
    /// enum is `Codable` precisely so specs can be persisted and re-read, so `seconds` can arrive
    /// from disk as anything a JSON number holds — and both callers are on paths that must not crash.
    /// `displayTitle` renders on a trust surface, and `id` is the key a report card groups by.
    private static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds.magnitude < 1e15 else { return String(seconds) }
        return seconds.rounded() == seconds
            ? String(Int(seconds))
            : String(format: "%.1f", seconds)
    }
}
