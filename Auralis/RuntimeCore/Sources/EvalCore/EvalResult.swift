import Foundation
import RuntimeCore

/// The verdict for one criterion.
///
/// Three-valued on purpose. A two-valued met/notMet would force the evaluator to answer questions the
/// evidence cannot settle, and it would answer them optimistically: a criterion asserting nothing
/// failed is *vacuously* true over a trace that recorded nothing at all. ``inconclusive`` is how the
/// evaluator says "the trace does not support a verdict" instead of quietly scoring a run it never
/// saw.
public enum CriterionOutcome: Equatable, Sendable, Codable {
    case met
    case notMet(detail: String)
    case inconclusive(detail: String)

    public var isMet: Bool {
        if case .met = self { return true }
        return false
    }
}

public struct CriterionResult: Equatable, Sendable, Codable, Identifiable {
    public let criterion: SuccessCriterion
    public let outcome: CriterionOutcome

    public var id: String { criterion.id }

    public init(criterion: SuccessCriterion, outcome: CriterionOutcome) {
        self.criterion = criterion
        self.outcome = outcome
    }
}

/// The overall grade for a run.
public enum EvalGrade: String, Equatable, Sendable, Codable, CaseIterable {
    case passed
    case failed
    /// The trace could not support a verdict — no criteria, no trace, or the deciding evidence was
    /// unreadable. Deliberately not a synonym for `failed`: "we don't know" and "it went wrong" lead
    /// to different operator action, and collapsing them would let a logging bug read as a broken
    /// routine.
    case inconclusive

    public var displayTitle: String {
        switch self {
        case .passed: return "Passed"
        case .failed: return "Failed"
        case .inconclusive: return "Inconclusive"
        }
    }
}

/// The explicit continuation chosen after a run is evaluated. These decisions are deliberately
/// advisory: none grants authority or executes work by itself.
public enum PostEvaluationAction: String, Equatable, Sendable, Codable, CaseIterable {
    case complete
    case requestHumanReview
    case repairEvidenceAndRetry
}

public extension EvalGrade {
    var postEvaluationAction: PostEvaluationAction {
        switch self {
        case .passed: return .complete
        case .failed: return .requestHumanReview
        case .inconclusive: return .repairEvidenceAndRetry
        }
    }
}

/// The graded outcome of evaluating one run against one spec.
public struct EvalResult: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    /// The ``OutcomeSpec`` this was graded against.
    public let outcomeID: UUID
    /// The workflow this graded, so a result joins back onto the worklog trace and the receipt that
    /// share its `correlationID`.
    public let correlationID: String
    /// Stable ownership captured at grading time. Optional only for results written before this
    /// field existed; report cards use it before consulting prunable execution history.
    public let playbookID: String?
    /// A compact diagnosis of the trace used for this grade.
    public let traceObservability: TraceObservability?
    public let results: [CriterionResult]
    public let grade: EvalGrade
    public let evaluatedAt: Date
    /// An optional model opinion on run *quality*, carried alongside the grade and never folded into
    /// it. `nil` whenever no judge is attached, which is the shipping default. See ``RubricJudging``.
    public let rubricOpinion: RubricOpinion?
    /// Persisted alongside the grade so history records what the system decided should happen next.
    /// Optional only for backward compatibility with results stored before next-action decisions.
    public let nextAction: PostEvaluationAction?

    public init(
        id: UUID = UUID(),
        outcomeID: UUID,
        correlationID: String,
        playbookID: String? = nil,
        traceObservability: TraceObservability? = nil,
        results: [CriterionResult],
        grade: EvalGrade,
        evaluatedAt: Date = .now,
        rubricOpinion: RubricOpinion? = nil,
        nextAction: PostEvaluationAction? = nil
    ) {
        self.id = id
        self.outcomeID = outcomeID
        self.correlationID = correlationID
        self.playbookID = playbookID
        self.traceObservability = traceObservability
        self.results = results
        self.grade = grade
        self.evaluatedAt = evaluatedAt
        self.rubricOpinion = rubricOpinion
        self.nextAction = nextAction ?? grade.postEvaluationAction
    }

    /// The same result with a model opinion attached. Returns a copy rather than mutating so the
    /// deterministic grade is computed and fixed before any model is consulted — the ordering is the
    /// guarantee that inference cannot influence it.
    public func attaching(_ opinion: RubricOpinion?) -> EvalResult {
        EvalResult(
            id: id,
            outcomeID: outcomeID,
            correlationID: correlationID,
            playbookID: playbookID,
            traceObservability: traceObservability,
            results: results,
            grade: grade,
            evaluatedAt: evaluatedAt,
            rubricOpinion: opinion,
            nextAction: nextAction
        )
    }

    /// Criteria that were met, over criteria the trace could actually decide.
    ///
    /// Inconclusive criteria are excluded from the denominator rather than counted as failures, so a
    /// partially unreadable trace lowers *confidence* (how many criteria the score rests on) instead
    /// of silently lowering the score. `nil` when nothing was decidable — there is no honest ratio to
    /// report, and returning 0 would be indistinguishable from a run that failed everything.
    public var score: Double? {
        let decided = results.filter {
            if case .inconclusive = $0.outcome { return false }
            return true
        }
        guard !decided.isEmpty else { return nil }
        return Double(decided.filter(\.outcome.isMet).count) / Double(decided.count)
    }

    /// The continuation to take for this run, always answerable.
    ///
    /// Prefer this over reading ``nextAction`` directly. The initializer derives a next action from the
    /// grade whenever one is not supplied, but synthesized decoding bypasses initializers entirely —
    /// so a result stored before this column existed decodes with `nextAction == nil` and every reader
    /// would have to remember the `?? grade.postEvaluationAction` fallback for itself. One forgotten
    /// fallback is a run that history says nothing should happen to.
    public var resolvedNextAction: PostEvaluationAction {
        nextAction ?? grade.postEvaluationAction
    }

    /// The number of criteria the trace could decide, out of how many were asked.
    public var decidedCount: Int {
        results.filter {
            if case .inconclusive = $0.outcome { return false }
            return true
        }.count
    }
}

/// What was actually observable in the worklog at grading time.
public struct TraceObservability: Equatable, Sendable, Codable {
    public let recordedStepCount: Int
    public let unknownEventCount: Int
    public let hasTerminalEvent: Bool
    public let worklogWasDegraded: Bool

    public init(
        recordedStepCount: Int,
        unknownEventCount: Int,
        hasTerminalEvent: Bool,
        worklogWasDegraded: Bool = false
    ) {
        self.recordedStepCount = recordedStepCount
        self.unknownEventCount = unknownEventCount
        self.hasTerminalEvent = hasTerminalEvent
        self.worklogWasDegraded = worklogWasDegraded
    }

    public var isComplete: Bool {
        recordedStepCount > 0 && unknownEventCount == 0 && hasTerminalEvent && !worklogWasDegraded
    }
}
