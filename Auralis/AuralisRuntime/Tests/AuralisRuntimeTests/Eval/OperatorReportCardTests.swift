import Foundation
import Testing

@testable import AuralisRuntime

private let playbook = "morning-brief"
private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

private func result(
    _ grade: EvalGrade,
    _ criterionOutcomes: [(SuccessCriterion, CriterionOutcome)] = [],
    at offset: TimeInterval = 0
) -> EvalResult {
    EvalResult(
        outcomeID: UUID(),
        correlationID: "wf-\(offset)",
        results: criterionOutcomes.map { CriterionResult(criterion: $0.0, outcome: $0.1) },
        grade: grade,
        evaluatedAt: epoch.addingTimeInterval(offset)
    )
}

private func card(
    _ results: [EvalResult],
    events: [PerformanceEvent] = []
) -> OperatorReportCard {
    OperatorReportCard(
        playbookID: playbook,
        health: PlaybookHealth(playbookID: playbook, events: events),
        evalResults: results
    )
}

@Suite("OperatorReportCard")
struct OperatorReportCardTests {

    @Test func passRateCountsOnlyRunsThatReachedAVerdict() {
        let subject = card([result(.passed), result(.passed), result(.failed), result(.inconclusive)])

        // 2 passed of 3 decided — the inconclusive run leaves the denominator entirely.
        #expect(subject.passRate == 2.0 / 3.0)
        #expect(subject.inconclusiveRunCount == 1)
        #expect(subject.gradedRunCount == 4)
    }

    /// An operator whose traces are all unreadable must not read as healthy *or* as failing. Folding
    /// inconclusive runs into either bucket would misreport a logging problem as an operator verdict.
    @Test func allInconclusiveRunsYieldNoPassRateRatherThanZero() {
        let subject = card([result(.inconclusive), result(.inconclusive)])

        #expect(subject.passRate == nil)
        #expect(subject.inconclusiveRunCount == 2)
    }

    @Test func noGradedRunsYieldsNoPassRate() {
        #expect(card([]).passRate == nil)
        #expect(card([]).shortfalls.isEmpty)
    }

    @Test func shortfallsRankTheMostMissedExpectationFirst() {
        let subject = card([
            result(.failed, [
                (.completedWithin(seconds: 30), .notMet(detail: "over")),
                (.producedArtifact, .met)
            ], at: 0),
            result(.failed, [
                (.completedWithin(seconds: 30), .notMet(detail: "over")),
                (.producedArtifact, .notMet(detail: "none"))
            ], at: 1)
        ])

        #expect(subject.shortfalls.count == 2)
        #expect(subject.shortfalls[0].criterion == .completedWithin(seconds: 30))
        #expect(subject.shortfalls[0].missCount == 2)
        #expect(subject.shortfalls[1].criterion == .producedArtifact)
        #expect(subject.shortfalls[1].missCount == 1)
    }

    @Test func criteriaThatAlwaysPassAreOmittedFromShortfalls() {
        let subject = card([
            result(.passed, [(.producedArtifact, .met), (.noBlockedSteps, .met)])
        ])

        #expect(subject.shortfalls.isEmpty)
    }

    /// A provable miss outranks an unverifiable one however often the latter occurs: the first is an
    /// operator problem, the second a logging problem, and the card should lead with the former.
    @Test func aProvableMissOutranksManyInconclusives() {
        let inconclusiveRuns = (0..<5).map { offset in
            result(.inconclusive, [(.noBlockedSteps, .inconclusive(detail: "unreadable"))], at: TimeInterval(offset))
        }
        let subject = card(inconclusiveRuns + [
            result(.failed, [(.producedArtifact, .notMet(detail: "none"))], at: 10)
        ])

        #expect(subject.shortfalls[0].criterion == .producedArtifact)
        #expect(subject.shortfalls[0].missCount == 1)
        #expect(subject.shortfalls[1].criterion == .noBlockedSteps)
        #expect(subject.shortfalls[1].inconclusiveCount == 5)
        #expect(subject.shortfalls[1].missCount == 0)
    }

    @Test func gradedRunsAreOrderedNewestFirst() {
        let subject = card([result(.passed, at: 0), result(.failed, at: 100), result(.passed, at: 50)])

        #expect(subject.evalResults.map(\.evaluatedAt) == [
            epoch.addingTimeInterval(100),
            epoch.addingTimeInterval(50),
            epoch
        ])
    }

    // MARK: AuralisRuntime passthrough

    @Test func recurringFailuresCarryThroughFromPerformanceHealthAndExcludeOneOffs() {
        let events = [
            PerformanceEvent(playbookID: playbook, outcome: .failed, durationSeconds: 1, failureReason: "RPC timeout"),
            PerformanceEvent(playbookID: playbook, outcome: .failed, durationSeconds: 1, failureReason: "RPC timeout"),
            PerformanceEvent(playbookID: playbook, outcome: .failed, durationSeconds: 1, failureReason: "bad address"),
            PerformanceEvent(playbookID: playbook, outcome: .success, durationSeconds: 1)
        ]
        let subject = card([result(.passed)], events: events)

        // "bad address" happened once — history, not a pattern.
        #expect(subject.recurringFailures.map(\.key) == ["RPC timeout"])
        #expect(subject.health.totalRuns == 4)
        #expect(subject.health.failureCount == 3)
    }

    /// Run health and eval grades measure different things and must not be conflated: a run can
    /// complete successfully (health) and still miss its declared expectations (eval).
    @Test func runHealthAndEvalGradeAreIndependent() {
        let events = [
            PerformanceEvent(playbookID: playbook, outcome: .success, durationSeconds: 1),
            PerformanceEvent(playbookID: playbook, outcome: .success, durationSeconds: 1)
        ]
        let subject = card([
            result(.failed, [(.completedWithin(seconds: 5), .notMet(detail: "over"))])
        ], events: events)

        #expect(subject.health.successRate == 1.0)
        #expect(subject.passRate == 0.0)
    }
}
