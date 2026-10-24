import EvalCore
import Foundation
import OperatorRuntimeStorage
import PerformanceCore
import SwiftData
import Testing

struct WorklogAdaptiveImprovementTests {
    @Test("recommendations are deterministic, evidence-linked, and advisory")
    func recommendationsRemainDeterministicAndProposed() {
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
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let first = engine.recommendations(for: card, createdAt: timestamp)
        let second = engine.recommendations(for: card, createdAt: timestamp)

        #expect(first == second)
        #expect(first.allSatisfy { $0.state == .proposed })
        #expect(first.allSatisfy { $0.evidenceWorkflowIDs == ["workflow-1"] })
        #expect(first.contains { $0.category == .observability })
        #expect(first.contains { $0.category == .outcomeQuality })
    }

    @Test("recommendation lifecycle survives durable storage and privacy reset")
    func recommendationPersistenceAndReset() async throws {
        let container = try ModelContainer(
            for: StoredImprovementRecommendationRow.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let store = SwiftDataImprovementRecommendationStore(modelContainer: container)
        let value = ImprovementRecommendation(
            id: "stable-id",
            operatorID: "operator-1",
            evidenceWorkflowIDs: ["workflow-1"],
            category: .reliability,
            summary: "Review failures",
            proposedChange: .reviewOperatorInstructions,
            confidence: 0.8
        )

        await store.upsert(value)
        #expect(await store.recommendation(id: value.id) == value)
        await store.resetAll()
        #expect(await store.allRecommendations().isEmpty)
    }
}
