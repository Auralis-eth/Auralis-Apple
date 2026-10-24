import Foundation
import PerformanceCore
import RuntimeCore

/// How often one criterion came up short for an operator, across its graded runs.
///
/// The single most useful line on a report card: `PlaybookHealth` already says an operator is flaky,
/// and ``FailurePattern`` already says which errors recur, but neither says *which expectation* it
/// keeps missing. A routine at 80% success whose one recurring miss is a latency budget needs a
/// different response than one missing "produced an artifact".
public struct CriterionShortfall: Equatable, Sendable, Identifiable {
    public let criterion: SuccessCriterion
    /// Runs where the criterion was provably not met.
    public let missCount: Int
    /// Runs where the trace could not decide it. Reported alongside rather than folded in, because
    /// "missed 4 times" and "unverifiable 4 times" call for different action — the first is an
    /// operator problem, the second a logging one.
    public let inconclusiveCount: Int

    public var id: String { criterion.id }

    public init(criterion: SuccessCriterion, missCount: Int, inconclusiveCount: Int) {
        self.criterion = criterion
        self.missCount = missCount
        self.inconclusiveCount = inconclusiveCount
    }
}

/// A per-operator rollup: run health, graded outcomes, and which expectations it keeps missing.
///
/// A derived view, computed on demand from a store's data rather than persisted. Deliberately not
/// `Codable`: a stored report card would be a second copy of numbers that live in `PerformanceCore`
/// and the eval results, free to drift from them. It is also **descriptive only** — nothing here
/// grants, widens, or removes authority (Phase 2 guardrail).
public struct OperatorReportCard: Equatable, Sendable, Identifiable {
    public let playbookID: String
    /// Run-level health: success/intervention/block rates, latency, recurring failure reasons.
    public let health: PlaybookHealth
    /// Every graded run for this operator, newest first.
    public let evalResults: [EvalResult]

    public var id: String { playbookID }

    public init(playbookID: String, health: PlaybookHealth, evalResults: [EvalResult]) {
        self.playbookID = playbookID
        self.health = health
        self.evalResults = evalResults.sorted { $0.evaluatedAt > $1.evaluatedAt }
    }

    /// Runs that passed, over runs that reached a verdict either way.
    ///
    /// Inconclusive runs are excluded from the denominator for the same reason ``EvalResult/score``
    /// excludes inconclusive criteria: a trace we could not read is missing evidence, not a failure,
    /// and counting it as one would let a logging regression look like a degrading operator. `nil`
    /// when no run reached a verdict — there is no honest rate to show.
    public var passRate: Double? {
        let decided = evalResults.filter { $0.grade != .inconclusive }
        guard !decided.isEmpty else { return nil }
        return Double(decided.filter { $0.grade == .passed }.count) / Double(decided.count)
    }

    /// Runs whose trace could not support a verdict. Surfaced as a first-class number because a card
    /// with a healthy `passRate` over three decided runs and forty inconclusive ones is not a healthy
    /// operator — it is an unobservable one, and the card must not let that hide.
    public var inconclusiveRunCount: Int {
        evalResults.filter { $0.grade == .inconclusive }.count
    }

    public var gradedRunCount: Int { evalResults.count }

    /// Runs whose trace was observed to be incomplete.
    ///
    /// Counts only results that actually carry a diagnosis. A result stored before
    /// ``EvalResult/traceObservability`` existed has no diagnosis rather than a bad one, and counting
    /// its absence as a finding would let pre-migration history alone raise "repair your
    /// instrumentation" against an operator whose logging was never broken — an accusation derived
    /// from the schema's age instead of from evidence.
    public var incompleteTraceCount: Int {
        evalResults.filter { result in
            guard let observability = result.traceObservability else { return false }
            return !observability.isComplete
        }.count
    }

    public var unknownTraceEventCount: Int {
        evalResults.compactMap(\.traceObservability).reduce(0) { $0 + $1.unknownEventCount }
    }

    /// The expectations this operator misses most, worst first.
    ///
    /// Ordered by provable misses before inconclusives, so a real shortfall always outranks an
    /// unverifiable one no matter how often the latter occurs. Criteria that were always met are
    /// omitted — a report card should be a list of things to look at.
    public var shortfalls: [CriterionShortfall] {
        var misses: [SuccessCriterion: (miss: Int, inconclusive: Int)] = [:]
        for result in evalResults {
            for entry in result.results {
                switch entry.outcome {
                case .met:
                    continue
                case .notMet:
                    misses[entry.criterion, default: (0, 0)].miss += 1
                case .inconclusive:
                    misses[entry.criterion, default: (0, 0)].inconclusive += 1
                }
            }
        }
        return misses
            .map { criterion, counts in
                CriterionShortfall(
                    criterion: criterion,
                    missCount: counts.miss,
                    inconclusiveCount: counts.inconclusive
                )
            }
            .sorted { lhs, rhs in
                if lhs.missCount != rhs.missCount { return lhs.missCount > rhs.missCount }
                if lhs.inconclusiveCount != rhs.inconclusiveCount {
                    return lhs.inconclusiveCount > rhs.inconclusiveCount
                }
                // Stable tiebreak so two cards over the same data render identically.
                return lhs.criterion.id < rhs.criterion.id
            }
    }

    /// Failure reasons that have recurred, carried straight through from `PerformanceCore`.
    public var recurringFailures: [FailurePattern] {
        health.failurePatterns.filter(\.isRecurring)
    }
}
