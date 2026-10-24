import Foundation
import PerformanceCore
import RuntimeCore
import Testing

@testable import EvalCore

@Suite("Improvement recommendations")
struct ImprovementRecommendationTests {
    @Test func derivationIsDeterministicAndEvidenceLinked() {
        let result = EvalResult(
            outcomeID: UUID(),
            correlationID: "workflow-1",
            playbookID: "operator-1",
            traceObservability: TraceObservability(
                recordedStepCount: 1,
                unknownEventCount: 1,
                hasTerminalEvent: false
            ),
            results: [CriterionResult(
                criterion: .producedArtifact,
                outcome: .notMet(detail: "missing")
            )],
            grade: .failed
        )
        let card = OperatorReportCard(
            playbookID: "operator-1",
            health: PlaybookHealth(playbookID: "operator-1", events: []),
            evalResults: [result]
        )
        let engine = ImprovementRecommendationEngine()
        let first = engine.recommendations(for: card, createdAt: .distantPast)
        let second = engine.recommendations(for: card, createdAt: .distantPast)

        #expect(first == second)
        #expect(first.allSatisfy { $0.evidenceWorkflowIDs == ["workflow-1"] })
        #expect(first.contains { $0.category == .observability })
        #expect(first.contains { $0.category == .outcomeQuality })
    }

    @Test func lifecycleRequiresExplicitTransitions() async {
        let store = InMemoryImprovementRecommendationStore()
        let recommendation = ImprovementRecommendation(
            id: "stable",
            operatorID: "operator-1",
            evidenceWorkflowIDs: ["workflow-1"],
            category: .reliability,
            summary: "Review failures",
            proposedChange: .reviewOperatorInstructions,
            confidence: 0.8
        )
        await store.upsert(recommendation)
        #expect(await store.recommendation(id: "stable")?.state == .proposed)

        await store.upsert(recommendation.transitioning(to: .accepted, reviewedBy: "human"))
        #expect(await store.recommendation(id: "stable")?.state == .accepted)
    }

    /// The ID embeds the evidence so a new run re-proposes rather than rewriting a reviewed row —
    /// but the evidence set is capped, because eval results are never pruned and a row is written
    /// per refresh. Embedding every run made both the primary key and the payload grow with the
    /// operator's whole history, so durable bytes grew as the square of the run count.
    @Test func evidenceAndIDStayBoundedAsTheRunCountGrows() {
        let card = card(runs: 400)
        let recommendations = ImprovementRecommendationEngine().recommendations(for: card, createdAt: .distantPast)

        #expect(!recommendations.isEmpty)
        for recommendation in recommendations {
            #expect(recommendation.evidenceWorkflowIDs.count == ImprovementRecommendationEngine.maximumCitedWorkflows)
            // operatorID + category + a 16-character digest, whatever the history behind it.
            #expect(recommendation.id.count < 64)
            #expect(recommendation.confidence == 0.95)
        }
    }

    /// The cap must not cost the property the ID exists for: one more graded run is new evidence,
    /// so it must still produce a new recommendation rather than silently reusing the old row.
    @Test func oneMoreRunStillProducesANewRecommendation() {
        let engine = ImprovementRecommendationEngine()
        let before = engine.recommendations(for: card(runs: 40), createdAt: .distantPast)
        let after = engine.recommendations(for: card(runs: 41), createdAt: .distantPast)

        #expect(!before.isEmpty)
        #expect(before.map(\.category) == after.map(\.category))
        #expect(Set(before.map(\.id)).isDisjoint(with: Set(after.map(\.id))))
    }

    /// Identical evidence must still digest identically, or every refresh would propose afresh.
    @Test func identicalEvidenceKeepsTheSameID() {
        let engine = ImprovementRecommendationEngine()
        #expect(
            engine.recommendations(for: card(runs: 30), createdAt: .distantPast).map(\.id)
                == engine.recommendations(for: card(runs: 30), createdAt: .distantPast).map(\.id)
        )
    }

    /// A latency criterion the trace could not *decide* is not evidence of slowness. It goes
    /// inconclusive whenever a run recorded no trace at all, so proposing a latency review off the
    /// back of it would point someone at a budget when the real fault is the missing instrumentation
    /// the observability recommendation already names.
    @Test func anUndecidedLatencyCriterionProposesNoLatencyReview() {
        let undecided = EvalResult(
            outcomeID: UUID(),
            correlationID: "workflow-1",
            playbookID: "operator-1",
            traceObservability: TraceObservability(
                recordedStepCount: 0,
                unknownEventCount: 0,
                hasTerminalEvent: false
            ),
            results: [CriterionResult(
                criterion: .completedWithin(seconds: 30),
                outcome: .inconclusive(detail: "No worklog entries were recorded for this workflow.")
            )],
            grade: .inconclusive
        )
        let card = OperatorReportCard(
            playbookID: "operator-1",
            health: PlaybookHealth(playbookID: "operator-1", events: []),
            evalResults: [undecided]
        )

        let categories = ImprovementRecommendationEngine()
            .recommendations(for: card, createdAt: .distantPast)
            .map(\.category)

        // The shortfall is listed — it is worth seeing — but only as an observability finding.
        #expect(card.shortfalls.map(\.criterion) == [.completedWithin(seconds: 30)])
        #expect(card.shortfalls[0].missCount == 0)
        #expect(!categories.contains(.latency))
        #expect(categories.contains(.observability))
    }

    /// A budget that was provably exceeded still proposes the review, which is the case the branch
    /// exists for.
    @Test func aProvablyMissedLatencyBudgetStillProposesAReview() {
        let missed = EvalResult(
            outcomeID: UUID(),
            correlationID: "workflow-1",
            playbookID: "operator-1",
            results: [CriterionResult(
                criterion: .completedWithin(seconds: 30),
                outcome: .notMet(detail: "over")
            )],
            grade: .failed
        )
        let card = OperatorReportCard(
            playbookID: "operator-1",
            health: PlaybookHealth(playbookID: "operator-1", events: []),
            evalResults: [missed]
        )

        #expect(ImprovementRecommendationEngine()
            .recommendations(for: card, createdAt: .distantPast)
            .map(\.category)
            .contains(.latency))
    }

    /// A result stored before trace diagnoses existed has *no* diagnosis, not a bad one. Counting its
    /// absence as an incomplete trace would let pre-migration history alone accuse an operator of
    /// broken instrumentation.
    @Test func aResultWithNoTraceDiagnosisIsNotCountedAsIncomplete() {
        let legacy = EvalResult(
            outcomeID: UUID(),
            correlationID: "workflow-1",
            playbookID: "operator-1",
            results: [CriterionResult(criterion: .producedArtifact, outcome: .met)],
            grade: .passed
        )
        let card = OperatorReportCard(
            playbookID: "operator-1",
            health: PlaybookHealth(playbookID: "operator-1", events: []),
            evalResults: [legacy]
        )

        #expect(card.incompleteTraceCount == 0)
        #expect(ImprovementRecommendationEngine()
            .recommendations(for: card, createdAt: .distantPast)
            .isEmpty)
    }

    /// `runs` failed runs with an incomplete trace, oldest first so the report card's own sort
    /// decides which ones the engine cites.
    private func card(runs: Int) -> OperatorReportCard {
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)
        let results = (0..<runs).map { index in
            EvalResult(
                outcomeID: UUID(),
                correlationID: "workflow-\(String(format: "%04d", index))",
                playbookID: "operator-1",
                traceObservability: TraceObservability(
                    recordedStepCount: 1,
                    unknownEventCount: 1,
                    hasTerminalEvent: false
                ),
                results: [CriterionResult(criterion: .producedArtifact, outcome: .notMet(detail: "missing"))],
                grade: .failed,
                evaluatedAt: epoch.addingTimeInterval(Double(index))
            )
        }
        return OperatorReportCard(
            playbookID: "operator-1",
            health: PlaybookHealth(playbookID: "operator-1", events: []),
            evalResults: results
        )
    }
}
