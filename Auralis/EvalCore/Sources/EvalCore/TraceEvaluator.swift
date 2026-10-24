import Foundation
import RuntimeCore

/// Grades a workflow's worklog trace against an ``OutcomeSpec``.
///
/// Pure and synchronous: the trace is the entire input, so the same trace always grades the same way.
/// That is the property that makes an eval worth storing — a result can be re-derived from evidence
/// the receipt chain already carries, and two runs of one spec are comparable.
///
/// Descriptive only. An ``EvalResult`` never grants, widens, or removes authority; it is an
/// observation about a run that already happened under whatever authority governance allowed at the
/// time (Phase 2 guardrail: "performance becomes decision-informing … never authority-granting").
public struct TraceEvaluator: Sendable {
    public init() { }

    public func evaluate(
        _ spec: OutcomeSpec,
        correlationID: String,
        trace: [WorkflowStepLog],
        playbookID: String? = nil,
        worklogWasDegraded: Bool = false,
        evaluatedAt: Date = .now
    ) -> EvalResult {
        // An unreadable entry is not a missing entry: its event payload cannot be classified, but the
        // entry itself — and crucially its timestamp — survived (see `WorkflowWorklogEvent.unknown`).
        // So it blocks verdicts that depend on classifying every event, and not the ones that only
        // need entry metadata.
        let hasUnreadableEntry = trace.contains {
            if case .unknown = $0.event { return true }
            return false
        }

        let results = spec.criteria.map { criterion in
            CriterionResult(
                criterion: criterion,
                outcome: outcome(
                    for: criterion,
                    trace: trace,
                    hasUnreadableEntry: hasUnreadableEntry
                )
            )
        }

        return EvalResult(
            outcomeID: spec.id,
            correlationID: correlationID,
            playbookID: playbookID,
            traceObservability: TraceObservability(
                recordedStepCount: trace.count,
                unknownEventCount: trace.filter { if case .unknown = $0.event { true } else { false } }.count,
                hasTerminalEvent: trace.contains {
                    switch $0.event {
                    case .executed, .blocked, .failed, .routinePhase(.completed, _),
                         .routinePhase(.blocked, _), .routinePhase(.failed, _): true
                    default: false
                    }
                },
                worklogWasDegraded: worklogWasDegraded
            ),
            results: results,
            grade: Self.grade(results, criteriaCount: spec.criteria.count),
            evaluatedAt: evaluatedAt
        )
    }

    /// Grades deterministically, then optionally attaches a model's advisory opinion.
    ///
    /// The grade is computed *before* the judge is consulted and is not revisited afterwards, so a
    /// model — or a model failure — cannot move it. With the default ``NoRubricJudge`` this is exactly
    /// the synchronous path plus one `nil`.
    public func evaluate(
        _ spec: OutcomeSpec,
        correlationID: String,
        trace: [WorkflowStepLog],
        playbookID: String? = nil,
        worklogWasDegraded: Bool = false,
        evaluatedAt: Date = .now,
        judge: any RubricJudging
    ) async -> EvalResult {
        let result = evaluate(
            spec,
            correlationID: correlationID,
            trace: trace,
            playbookID: playbookID,
            worklogWasDegraded: worklogWasDegraded,
            evaluatedAt: evaluatedAt
        )
        return result.attaching(await judge.score(spec, trace: trace))
    }

    /// A definite failure outranks an unresolved one.
    ///
    /// `notMet` is positive evidence that the run fell short; `inconclusive` is only the absence of
    /// evidence. Checking `notMet` first means a trace that is partly unreadable still reports the
    /// failures it *could* prove, rather than hiding a known-bad run behind "we're not sure".
    private static func grade(_ results: [CriterionResult], criteriaCount: Int) -> EvalGrade {
        // A spec asserting nothing cannot be passed. Grading it `.passed` would manufacture a clean
        // result out of an empty question, which is exactly the number that would then get averaged
        // into a report card.
        guard criteriaCount > 0 else { return .inconclusive }
        if results.contains(where: { if case .notMet = $0.outcome { return true }; return false }) {
            return .failed
        }
        if results.contains(where: { if case .inconclusive = $0.outcome { return true }; return false }) {
            return .inconclusive
        }
        return .passed
    }

    private func outcome(
        for criterion: SuccessCriterion,
        trace: [WorkflowStepLog],
        hasUnreadableEntry: Bool
    ) -> CriterionOutcome {
        // A run with no trace at all decides nothing. Without this guard every `no…`/`all…` criterion
        // would be vacuously true and a routine that recorded nothing would grade as a clean pass —
        // the worst possible failure mode for an eval, since a logging regression would read as
        // perfect health.
        guard !trace.isEmpty else {
            return .inconclusive(detail: "No worklog entries were recorded for this workflow.")
        }

        if criterion.evidence == .universal, hasUnreadableEntry {
            return .inconclusive(
                detail: "The trace contains an entry this build cannot interpret, which could be the event this criterion rules out."
            )
        }

        switch criterion {
        case .producedArtifact:
            return existential(
                found: trace.contains { step in
                    switch step.event {
                    case .executed:
                        return true
                    case let .routinePhase(phase, _):
                        return phase == .artifactProduced
                    default:
                        return false
                    }
                },
                hasUnreadableEntry: hasUnreadableEntry,
                missingDetail: "The run recorded neither an executed step nor an artifact-produced routine phase."
            )

        case let .completedWithin(seconds):
            // Wall-clock span across the whole trace rather than the executed step's own duration:
            // the question a budget asks is how long the workflow took end to end, including the time
            // it spent waiting on checks and approvals.
            let timestamps = trace.map(\.timestamp)
            guard let first = timestamps.min(), let last = timestamps.max() else {
                return .inconclusive(detail: "The trace carries no timestamps.")
            }
            let span = last.timeIntervalSince(first)
            return span <= seconds
                ? .met
                : .notMet(
                    detail: "The workflow spanned \(Self.duration(span)), over its \(Self.duration(seconds)) budget."
                )

        case .noBlockedSteps:
            let blocked = trace.compactMap { step -> String? in
                if case let .blocked(reason) = step.event { return reason }
                return nil
            }
            return blocked.isEmpty
                ? .met
                : .notMet(detail: "Blocked: \(blocked.joined(separator: "; "))")

        case .noFailedSteps:
            let failures = trace.compactMap { step -> String? in
                if case let .failed(reason) = step.event { return reason }
                return nil
            }
            return failures.isEmpty
                ? .met
                : .notMet(detail: "Failed: \(failures.joined(separator: "; "))")

        case .allDeterministicChecksPassed:
            // Unlike the `no…` criteria, absence is not evidence here: this asks about the contents of
            // a check record, so with no record at all there is nothing to inspect and the honest
            // answer is that we do not know whether checks ran.
            let checkResults = trace.flatMap { step -> [DeterministicCheckResult] in
                if case let .checksEvaluated(results) = step.event { return results }
                return []
            }
            guard !checkResults.isEmpty else {
                return .inconclusive(detail: "The trace records no deterministic check results.")
            }
            let failed = checkResults.filter { !$0.passed }
            return failed.isEmpty
                ? .met
                : .notMet(
                    detail: "Checks failed: \(failed.map(\.checkID).joined(separator: ", "))"
                )

        case .judgeDidNotEscalate:
            let escalated = trace.contains { step in
                if case let .decided(decision) = step.event, case .escalate = decision { return true }
                return false
            }
            return escalated
                ? .notMet(detail: "The Judge escalated this run for approval.")
                : .met

        case let .reachedRoutinePhase(phase):
            return existential(
                found: trace.contains { step in
                    if case let .routinePhase(recorded, _) = step.event { return recorded == phase }
                    return false
                },
                hasUnreadableEntry: hasUnreadableEntry,
                missingDetail: "The routine never reached \(phase.displayTitle.lowercased())."
            )

        case .traceFullyLegible:
            return hasUnreadableEntry
                ? .notMet(
                    detail: "At least one entry was written by a build this one cannot fully interpret."
                )
                : .met
        }
    }

    /// Resolves a criterion that asserts an event is *present*.
    ///
    /// Finding the evidence settles it outright — an unreadable entry elsewhere cannot un-happen a
    /// step that was recorded. Only when the evidence is absent does an unreadable entry matter,
    /// because the missing proof could be sitting inside the payload this build cannot read.
    private func existential(
        found: Bool,
        hasUnreadableEntry: Bool,
        missingDetail: String
    ) -> CriterionOutcome {
        if found { return .met }
        if hasUnreadableEntry {
            return .inconclusive(
                detail: "\(missingDetail) An entry this build cannot interpret may hold that evidence."
            )
        }
        return .notMet(detail: missingDetail)
    }

    /// The magnitude beyond which a duration is printed verbatim instead of as a whole number.
    ///
    /// Comfortably inside `Int`'s range and far above any duration a real workflow can span, so the
    /// bound only ever catches nonsense.
    private static let wholeNumberFormattingLimit: Double = 1e15

    /// Renders a duration for a verdict's detail string.
    ///
    /// The guard is load-bearing rather than defensive: the whole-number path converts through `Int`,
    /// which *traps* on a value `Int` cannot represent, and neither input to this function is
    /// validated anywhere upstream. A budget arrives inside a decoded ``OutcomeSpec`` and
    /// ``SuccessCriterion`` checks nothing, while a span is derived from worklog timestamps that
    /// decode as bare `Double`s — so one corrupt row or one nonsense spec could otherwise crash
    /// grading outright. Losing a whole trace's verdict to an unprintable number is strictly worse
    /// than printing `inf`, especially in an evaluator whose entire job is to survive bad evidence.
    ///
    /// Non-finite and absurd values therefore keep their IEEE spelling (`inf`, `-inf`, `nan`) and are
    /// deliberately left un-suffixed, so the detail reads "over its `-inf` budget" rather than
    /// implying a unit the value does not have.
    private static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds.magnitude < wholeNumberFormattingLimit else {
            return String(seconds)
        }
        return seconds.rounded() == seconds
            ? "\(Int(seconds))s"
            : "\(String(format: "%.1f", seconds))s"
    }
}
