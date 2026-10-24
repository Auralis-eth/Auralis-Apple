import CapabilitiesCore
import Foundation
import RuntimeCore
import Testing

@testable import EvalCore

// MARK: - Fixtures

private let routineActor = ActorRef(kind: .scheduledRoutine, identifier: "morning-brief")
private let correlation = "wf-1"
private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

private func step(
    _ event: WorkflowWorklogEvent,
    at offset: TimeInterval = 0
) -> WorkflowStepLog {
    WorkflowStepLog(
        correlationID: correlation,
        toolID: "tool.brief",
        event: event,
        actor: routineActor,
        timestamp: epoch.addingTimeInterval(offset)
    )
}

private func proposal() -> ActionProposal {
    ActionProposal(
        actor: routineActor,
        intent: "Draft the morning brief",
        capability: .runPlugin,
        impact: .readOnly,
        correlationID: correlation
    )
}

private func spec(_ criteria: [SuccessCriterion]) -> OutcomeSpec {
    OutcomeSpec(summary: "Morning brief", criteria: criteria)
}

private func evaluate(
    _ criteria: [SuccessCriterion],
    trace: [WorkflowStepLog]
) -> EvalResult {
    TraceEvaluator().evaluate(
        spec(criteria),
        correlationID: correlation,
        trace: trace,
        evaluatedAt: epoch
    )
}

/// A clean, fully governed run: proposed → checks passed → allowed → executed.
private func healthyTrace() -> [WorkflowStepLog] {
    [
        step(.proposed(proposal()), at: 0),
        step(.checksEvaluated([DeterministicCheckResult(checkID: "address.wellFormed", passed: true)]), at: 1),
        step(.decided(.allow), at: 2),
        step(.executed(artifactID: UUID(), durationSeconds: 3), at: 5)
    ]
}

// MARK: - Tests

@Suite("TraceEvaluator")
struct TraceEvaluatorTests {

    @Test func healthyRunPassesEveryCriterion() {
        let result = evaluate(
            [
                .producedArtifact,
                .noBlockedSteps,
                .noFailedSteps,
                .allDeterministicChecksPassed,
                .judgeDidNotEscalate,
                .completedWithin(seconds: 30),
                .traceFullyLegible
            ],
            trace: healthyTrace()
        )

        #expect(result.grade == .passed)
        #expect(result.score == 1.0)
        #expect(result.decidedCount == 7)
        #expect(result.correlationID == correlation)
        #expect(result.nextAction == .complete)
        let allMet = result.results.allSatisfy { $0.outcome.isMet }
        #expect(allMet)
    }

    /// The failure mode this evaluator exists to avoid: every `no…`/`all…` criterion is vacuously
    /// true over an empty trace, so a naive evaluator would score a run it never observed as perfect
    /// — turning a logging regression into a clean bill of health.
    @Test func emptyTraceIsInconclusiveRatherThanAVacuousPass() {
        let result = evaluate([.noBlockedSteps, .noFailedSteps, .judgeDidNotEscalate], trace: [])

        #expect(result.grade == .inconclusive)
        #expect(result.score == nil)
        #expect(result.decidedCount == 0)
        #expect(result.nextAction == .repairEvidenceAndRetry)
        let noneMet = result.results.allSatisfy { !$0.outcome.isMet }
        #expect(noneMet)
    }

    @Test func aSpecWithNoCriteriaCannotPass() {
        let result = evaluate([], trace: healthyTrace())

        #expect(result.grade == .inconclusive)
        #expect(result.score == nil)
    }

    @Test func blockedStepFailsTheRunAndNamesTheReason() {
        let result = evaluate(
            [.noBlockedSteps],
            trace: [step(.proposed(proposal())), step(.blocked(reason: "Observe mode"), at: 1)]
        )

        #expect(result.grade == .failed)
        #expect(result.nextAction == .requestHumanReview)
        guard case let .notMet(detail) = result.results[0].outcome else {
            Issue.record("Expected notMet, got \(result.results[0].outcome)")
            return
        }
        #expect(detail.contains("Observe mode"))
    }

    @Test func failedStepFailsTheRun() {
        let result = evaluate(
            [.noFailedSteps],
            trace: [step(.proposed(proposal())), step(.failed(reason: "RPC timeout"), at: 1)]
        )

        #expect(result.grade == .failed)
    }

    @Test func missingArtifactFailsWhenTheTraceIsFullyReadable() {
        let result = evaluate(
            [.producedArtifact],
            trace: [step(.proposed(proposal())), step(.decided(.allow), at: 1)]
        )

        #expect(result.grade == .failed)
    }

    @Test func aFailedDeterministicCheckIsReportedByCheckID() {
        let result = evaluate(
            [.allDeterministicChecksPassed],
            trace: [
                step(.checksEvaluated([
                    DeterministicCheckResult(checkID: "chain.allowlisted", passed: true),
                    DeterministicCheckResult(checkID: "context.fresh", passed: false)
                ]))
            ]
        )

        #expect(result.grade == .failed)
        guard case let .notMet(detail) = result.results[0].outcome else {
            Issue.record("Expected notMet, got \(result.results[0].outcome)")
            return
        }
        #expect(detail.contains("context.fresh"))
        #expect(!detail.contains("chain.allowlisted"))
    }

    /// Absence is evidence for `noBlockedSteps`, but not here: this criterion asks about the contents
    /// of a check record, so with no record at all there is nothing to inspect.
    @Test func noCheckRecordAtAllIsInconclusiveNotAPass() {
        let result = evaluate(
            [.allDeterministicChecksPassed],
            trace: [step(.proposed(proposal())), step(.executed(artifactID: UUID(), durationSeconds: 1), at: 1)]
        )

        #expect(result.grade == .inconclusive)
        #expect(result.score == nil)
    }

    @Test func escalationMeansTheRunDidNotCompleteUnattended() {
        let request = ApprovalRequest(proposal: proposal(), prompt: "Approve?")
        let result = evaluate(
            [.judgeDidNotEscalate],
            trace: [step(.proposed(proposal())), step(.decided(.escalate(approvalRequest: request)), at: 1)]
        )

        #expect(result.grade == .failed)
    }

    @Test func latencyBudgetUsesTheWallClockSpanOfTheWholeTrace() {
        let trace = [step(.proposed(proposal()), at: 0), step(.executed(artifactID: UUID(), durationSeconds: 1), at: 45)]

        #expect(evaluate([.completedWithin(seconds: 60)], trace: trace).grade == .passed)

        let overBudget = evaluate([.completedWithin(seconds: 30)], trace: trace)
        #expect(overBudget.grade == .failed)
        guard case let .notMet(detail) = overBudget.results[0].outcome else {
            Issue.record("Expected notMet, got \(overBudget.results[0].outcome)")
            return
        }
        #expect(detail.contains("45"))
    }

    /// Neither side of a latency comparison is validated — a budget rides inside a decoded
    /// `OutcomeSpec` and a span is derived from worklog timestamps that decode as bare `Double`s — so
    /// grading has to survive a nonsense number. The whole-number formatting path converts through
    /// `Int`, which traps on anything `Int` cannot hold, and losing a whole trace's verdict to an
    /// unprintable duration is far worse than printing `inf`.
    @Test func anUnrepresentableBudgetIsGradedRatherThanCrashing() {
        let trace = [step(.proposed(proposal()), at: 0), step(.executed(artifactID: UUID(), durationSeconds: 1), at: 5)]

        for budget in [-Double.infinity, -1e30, 1e30, .nan] {
            let result = evaluate([.completedWithin(seconds: budget)], trace: trace)
            // A budget nothing can be under fails; one nothing can exceed passes. Either is a verdict.
            #expect(result.grade == (budget == 1e30 ? .passed : .failed))
        }
    }

    /// A worklog timestamp decodes as an unvalidated `Double`, so a corrupt row can make the trace's
    /// wall-clock span non-finite. That must still grade.
    @Test func aNonFiniteTraceSpanIsGradedRatherThanCrashing() {
        let trace = [
            step(.proposed(proposal()), at: 0),
            step(.executed(artifactID: UUID(), durationSeconds: 1), at: .infinity)
        ]

        let result = evaluate([.completedWithin(seconds: 30)], trace: trace)

        #expect(result.grade == .failed)
        guard case let .notMet(detail) = result.results[0].outcome else {
            Issue.record("Expected notMet, got \(result.results[0].outcome)")
            return
        }
        // Reported verbatim and un-suffixed, rather than implying a unit the value does not have.
        #expect(detail.contains("inf"))
        #expect(detail.contains("30s"))
    }

    @Test func routinePhaseCriterionMatchesTheRecordedPhase() {
        let trace = [
            step(.routinePhase(.authorityResolved, detail: nil), at: 0),
            step(.routinePhase(.completed, detail: nil), at: 2)
        ]

        #expect(evaluate([.reachedRoutinePhase(.completed)], trace: trace).grade == .passed)
        #expect(evaluate([.reachedRoutinePhase(.artifactProduced)], trace: trace).grade == .failed)
    }

    @Test func producedArtifactAcceptsTheSchedulingTracePhase() {
        let trace = [
            step(.routinePhase(.contextGathered, detail: nil), at: 0),
            step(.routinePhase(.artifactProduced, detail: "brief"), at: 1),
            step(.routinePhase(.completed, detail: nil), at: 2)
        ]

        #expect(evaluate([.producedArtifact], trace: trace).grade == .passed)
    }

    // MARK: Unreadable entries (L-09 interaction)

    /// A criterion asserting an event is *absent* cannot be settled when the trace holds an entry this
    /// build cannot classify — the unreadable event could be the very thing being ruled out. Grading
    /// it `.met` would let a downgrade manufacture a clean pass.
    @Test func unreadableEntryMakesAbsenceCriteriaInconclusive() {
        let trace = healthyTrace() + [
            step(.unknown(caseName: "quarantined", payload: .object(["reason": .string("newer build")])), at: 6)
        ]
        let result = evaluate([.noBlockedSteps, .noFailedSteps, .judgeDidNotEscalate], trace: trace)

        #expect(result.grade == .inconclusive)
        #expect(result.score == nil)
        #expect(result.decidedCount == 0)
    }

    /// Presence criteria are different: evidence found elsewhere in the trace settles the question, so
    /// an unreadable entry cannot un-happen a step that was recorded.
    @Test func unreadableEntryDoesNotUndoEvidenceThatWasFound() {
        let trace = healthyTrace() + [step(.unknown(caseName: "quarantined", payload: .null), at: 6)]
        let result = evaluate([.producedArtifact], trace: trace)

        #expect(result.results[0].outcome == .met)
    }

    @Test func unreadableEntryMakesAMissingPresenceCriterionInconclusive() {
        let trace = [
            step(.proposed(proposal()), at: 0),
            step(.unknown(caseName: "quarantined", payload: .null), at: 1)
        ]
        let result = evaluate([.producedArtifact], trace: trace)

        #expect(result.grade == .inconclusive)
    }

    @Test func legibilityCriterionReportsAnUnreadableEntryAsARealFinding() {
        let trace = healthyTrace() + [step(.unknown(caseName: "quarantined", payload: .null), at: 6)]
        let result = evaluate([.traceFullyLegible], trace: trace)

        #expect(result.grade == .failed)
    }

    /// Timestamps survive on an unreadable entry — that is the whole point of `.unknown` keeping the
    /// enclosing entry — so a latency budget stays decidable.
    @Test func latencyStaysDecidableAcrossAnUnreadableEntry() {
        let trace = [
            step(.proposed(proposal()), at: 0),
            step(.unknown(caseName: "quarantined", payload: .null), at: 90)
        ]

        #expect(evaluate([.completedWithin(seconds: 30)], trace: trace).grade == .failed)
    }

    // MARK: Grade precedence & scoring

    /// A provable failure outranks an unresolved criterion, so a partly unreadable trace still
    /// surfaces what it *could* prove instead of hiding a known-bad run behind "we're not sure".
    @Test func provenFailureOutranksInconclusive() {
        let trace = [
            step(.proposed(proposal()), at: 0),
            step(.unknown(caseName: "quarantined", payload: .null), at: 1)
        ]
        // `traceFullyLegible` is provably notMet; `noBlockedSteps` is inconclusive.
        let result = evaluate([.noBlockedSteps, .traceFullyLegible], trace: trace)

        #expect(result.grade == .failed)
        #expect(result.decidedCount == 1)
        #expect(result.score == 0.0)
    }

    /// Inconclusive criteria leave the denominator rather than counting as failures: a partly
    /// unreadable trace should lower confidence in the score, not the score itself.
    @Test func scoreIgnoresInconclusiveCriteriaInsteadOfPenalizingThem() {
        let trace = healthyTrace() + [step(.unknown(caseName: "quarantined", payload: .null), at: 6)]
        // producedArtifact: met · noBlockedSteps: inconclusive · traceFullyLegible: notMet
        let result = evaluate([.producedArtifact, .noBlockedSteps, .traceFullyLegible], trace: trace)

        #expect(result.decidedCount == 2)
        #expect(result.score == 0.5)
    }
}

// MARK: - Spec round trip

@Suite("OutcomeSpec serialization")
struct OutcomeSpecSerializationTests {

    /// A spec is only useful if it can be re-run against a later trace and the results compared,
    /// which means it has to survive a round trip to disk — including its parameterised criteria.
    @Test func specRoundTripsThroughJSONIncludingParameterisedCriteria() throws {
        let original = OutcomeSpec(
            summary: "Morning brief",
            criteria: [
                .producedArtifact,
                .completedWithin(seconds: 42.5),
                .reachedRoutinePhase(.completed),
                .traceFullyLegible
            ],
            proseCriteria: ["Reads like something a person would want at 7am."]
        )

        let decoded = try JSONDecoder().decode(
            OutcomeSpec.self,
            from: JSONEncoder().encode(original)
        )

        #expect(decoded == original)
    }

    /// A spec written before criteria were structured must still decode, keeping its prose. Its
    /// sentences are deliberately *not* converted into criteria: inferring an expectation from a
    /// sentence would invent a rule the author never declared and then grade real runs against it.
    @Test func legacyProseOnlySpecDecodesWithNoCriteria() throws {
        let legacy = Data(#"""
        {
          "id": "5E7B1F2A-0000-4000-8000-000000000001",
          "summary": "Morning brief",
          "successCriteria": ["The brief covers every watched account."]
        }
        """#.utf8)

        let decoded = try JSONDecoder().decode(OutcomeSpec.self, from: legacy)

        #expect(decoded.criteria.isEmpty)
        #expect(decoded.proseCriteria == ["The brief covers every watched account."])

        // And so grading against it is inconclusive, never a pass.
        let graded = TraceEvaluator().evaluate(decoded, correlationID: correlation, trace: healthyTrace())
        #expect(graded.grade == .inconclusive)
    }

    /// Prose is written back under its original key, so a spec survives a round trip through a build
    /// on either side of the structured-criteria migration.
    @Test func proseIsReEncodedUnderTheLegacyKey() throws {
        let spec = OutcomeSpec(summary: "x", criteria: [.producedArtifact], proseCriteria: ["human intent"])

        let json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(spec)
        ) as? [String: Any]

        #expect(json?["successCriteria"] as? [String] == ["human intent"])
        #expect((json?["criteria"] as? [Any])?.count == 1)
    }

    @Test func resultRoundTripsThroughJSON() throws {
        let result = evaluate([.producedArtifact, .noBlockedSteps], trace: healthyTrace())

        let decoded = try JSONDecoder().decode(
            EvalResult.self,
            from: JSONEncoder().encode(result)
        )

        #expect(decoded == result)
    }

    /// A result stored before next-action decisions existed decodes with no `nextAction`, because
    /// synthesized decoding bypasses the initializer that would otherwise derive one from the grade.
    /// ``EvalResult/resolvedNextAction`` is the accessor that stays answerable across that gap, so a
    /// pre-migration run still tells an operator what to do about it.
    @Test func aLegacyResultWithNoNextActionStillResolvesOne() throws {
        let legacy = Data(#"""
        {
          "id": "5E7B1F2A-0000-4000-8000-000000000002",
          "outcomeID": "5E7B1F2A-0000-4000-8000-000000000003",
          "correlationID": "wf-legacy",
          "results": [],
          "grade": "failed",
          "evaluatedAt": 0
        }
        """#.utf8)

        let decoded = try JSONDecoder().decode(EvalResult.self, from: legacy)

        #expect(decoded.nextAction == nil)
        #expect(decoded.resolvedNextAction == .requestHumanReview)
    }

    /// Parameterised cases must not collide under one key, or a report card grouping by criterion
    /// would merge a 30s budget with a 60s one.
    @Test func parameterisedCriteriaHaveDistinctStableIDs() {
        #expect(SuccessCriterion.completedWithin(seconds: 30).id != SuccessCriterion.completedWithin(seconds: 60).id)
        #expect(SuccessCriterion.reachedRoutinePhase(.completed).id != SuccessCriterion.reachedRoutinePhase(.blocked).id)
        #expect(SuccessCriterion.producedArtifact.id == "producedArtifact")
    }

    /// A budget that cannot be rendered as a whole number must not crash the surfaces that render it:
    /// `displayTitle` goes on a trust surface and `id` is the key a report card groups by.
    @Test func anUnrepresentableBudgetStillRendersAnIDAndTitle() {
        for budget in [-Double.infinity, -1e30, .nan] {
            let criterion = SuccessCriterion.completedWithin(seconds: budget)
            #expect(!criterion.id.isEmpty)
            #expect(criterion.displayTitle.hasPrefix("Completed within"))
        }
    }
}

// MARK: - Rubric opinions

@Suite("RubricOpinion")
struct RubricOpinionTests {

    /// `min`/`max` do not clamp NaN — every comparison against it is false, so it survives both. A
    /// NaN score would make the enclosing result unequal to itself and throw on any JSON encode, so
    /// an unrepresentable model opinion has to floor rather than propagate.
    @Test func aNonFiniteScoreFloorsInsteadOfPassingThroughTheClamp() throws {
        for score in [Double.nan, .infinity, -.infinity] {
            let opinion = RubricOpinion(score: score, rationale: "x", provenance: .local())
            #expect(opinion.score == 0)
        }

        // Equality and encodability are the two properties a NaN would have quietly broken.
        let opinion = RubricOpinion(score: .nan, rationale: "x", provenance: .local())
        #expect(opinion == opinion)
        #expect(throws: Never.self) { try JSONEncoder().encode(opinion) }
    }

    @Test func anInRangeScoreSurvivesUnchanged() {
        #expect(RubricOpinion(score: 0.75, rationale: "x", provenance: .local()).score == 0.75)
        #expect(RubricOpinion(score: 1.5, rationale: "x", provenance: .local()).score == 1)
        #expect(RubricOpinion(score: -0.5, rationale: "x", provenance: .local()).score == 0)
    }

    /// Decoding routes through the clamping initializer, so a row written by a build whose judge
    /// emitted an out-of-range score reads back inside the documented 0…1 contract rather than
    /// carrying the violation forward.
    @Test func decodingClampsAnOutOfRangeStoredScore() throws {
        let stored = Data(#"""
        {
          "score": 4.2,
          "rationale": "written by a build with a looser judge",
          "provenance": { "locality": "local" }
        }
        """#.utf8)

        #expect(try JSONDecoder().decode(RubricOpinion.self, from: stored).score == 1)
    }

    /// The shipping default attaches no opinion at all, so the grade stays a pure function of
    /// recorded evidence and the async path is the synchronous one plus a `nil`.
    @Test func theDefaultJudgeAttachesNoOpinionAndCannotMoveTheGrade() async {
        let deterministic = evaluate([.producedArtifact], trace: healthyTrace())
        let judged = await TraceEvaluator().evaluate(
            spec([.producedArtifact]),
            correlationID: correlation,
            trace: healthyTrace(),
            evaluatedAt: epoch,
            judge: NoRubricJudge()
        )

        #expect(judged.rubricOpinion == nil)
        #expect(judged.grade == deterministic.grade)
    }
}
