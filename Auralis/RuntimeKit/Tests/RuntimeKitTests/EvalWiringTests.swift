import EvalCore
import Foundation
import PlaybookCore
import ReceiptsCore
import RuntimeCore
import SchedulingCore
import Testing

@testable import RuntimeKit

@Suite("Eval wiring through RuntimeHost")
@MainActor
struct EvalWiringTests {

    private func host(
        playbooks: [Playbook],
        evalStore: any EvalResultStoring,
        judge: any RubricJudging = NoRubricJudge(),
        receiptStore: any ReceiptStore = EvalWiringReceiptStore()
    ) -> RuntimeHost {
        RuntimeHost(
            receiptStore: receiptStore,
            stores: RuntimeHostStores(
                playbookStore: InMemoryPlaybookStore(seed: playbooks),
                evalResultStore: evalStore
            ),
            models: RuntimeModelStack(rubricJudge: judge)
        )
    }

    private func playbook(_ id: String, outcome: OutcomeSpec?) -> Playbook {
        Playbook(
            id: id,
            name: id,
            summary: "s",
            trigger: .manual,
            authority: PlaybookAuthority(capabilities: [.runPlugin], allowedOutputs: [.brief]),
            completionCondition: "done",
            contextContract: SystemPlaybookContracts.contract(
                for: id,
                identifier: "test.\(id)"
            ),
            outcome: outcome,
            installState: .installed
        )
    }

    /// The whole point of the wiring: a real run produces a stored grade without any test calling the
    /// evaluator directly.
    @Test func aRoutineRunProducesAStoredGrade() async {
        let evalStore = InMemoryEvalResultStore()
        let subject = host(
            playbooks: [playbook("p1", outcome: OutcomeSpec(
                summary: "Produces something",
                criteria: [.producedArtifact, .traceFullyLegible]
            ))],
            evalStore: evalStore
        )
        await subject.bootstrap()

        let record = await subject.runRoutine(id: "p1")

        let results = await evalStore.allResults()
        #expect(results.count == 1)
        #expect(results[0].correlationID == record.correlationID)
        #expect(results[0].results.count == 2)
        #expect(results[0].nextAction == .complete)
    }

    @Test func routineReceiptRecordsThePostEvaluationDecision() async throws {
        let evalStore = InMemoryEvalResultStore()
        let receiptStore = EvalWiringReceiptStore()
        let subject = host(
            playbooks: [playbook("p1", outcome: OutcomeSpec(
                summary: "Must fail",
                criteria: [.reachedRoutinePhase(.failed)]
            ))],
            evalStore: evalStore,
            receiptStore: receiptStore
        )
        await subject.bootstrap()

        let record = await subject.runRoutine(id: "p1")

        let receipt = try #require(await receiptStore.allRecords().first {
            $0.correlationID == record.correlationID && $0.trigger.hasPrefix("routine.")
        })
        #expect(receipt.details.values["nextAction"] == .string("requestHumanReview"))
    }

    /// A playbook that declares no criteria is left ungraded rather than being scored against
    /// expectations nobody wrote down.
    @Test func aPlaybookWithNoOutcomeSpecIsNotGraded() async {
        let evalStore = InMemoryEvalResultStore()
        let subject = host(playbooks: [playbook("p1", outcome: nil)], evalStore: evalStore)
        await subject.bootstrap()

        await subject.runRoutine(id: "p1")

        #expect(await evalStore.allResults().isEmpty)
    }

    /// The grade is filed under the run's own correlationID, so it joins onto the same trace and
    /// receipt the run produced.
    @Test func theGradeIsFiledUnderTheRunsCorrelationID() async {
        let evalStore = InMemoryEvalResultStore()
        let subject = host(
            playbooks: [playbook("p1", outcome: OutcomeSpec(summary: "s", criteria: [.noFailedSteps]))],
            evalStore: evalStore
        )
        await subject.bootstrap()

        let record = await subject.runRoutine(id: "p1", correlationID: "wf-explicit")

        let scoped = await evalStore.results(forCorrelationID: "wf-explicit")
        #expect(scoped.count == 1)
        #expect(record.correlationID == "wf-explicit")
    }

    /// Privacy reset must reach graded runs: a grade names how well someone's operator performed.
    @Test func privacyResetClearsGradedRuns() async throws {
        let evalStore = InMemoryEvalResultStore()
        let subject = host(
            playbooks: [playbook("p1", outcome: OutcomeSpec(summary: "s", criteria: [.noFailedSteps]))],
            evalStore: evalStore
        )
        await subject.bootstrap()
        await subject.runRoutine(id: "p1")
        let before = await evalStore.allResults()
        #expect(!before.isEmpty)

        try await subject.resetAllHistory()

        #expect(await evalStore.allResults().isEmpty)
    }

    // MARK: Model judge is advisory only

    /// A judge returning a damning opinion must not move the deterministic grade. This is the
    /// guardrail that keeps a grade reproducible from evidence alone.
    @Test func aRubricOpinionIsAttachedButNeverChangesTheGrade() async {
        let evalStore = InMemoryEvalResultStore()
        let subject = host(
            playbooks: [playbook("p1", outcome: OutcomeSpec(summary: "s", criteria: [.traceFullyLegible]))],
            evalStore: evalStore,
            judge: FixedRubricJudge(
                opinion: RubricOpinion(score: 0, rationale: "worthless", provenance: .local())
            )
        )
        await subject.bootstrap()

        await subject.runRoutine(id: "p1")

        let result = await evalStore.allResults()[0]
        #expect(result.grade == .passed)
        #expect(result.rubricOpinion?.score == 0)
        #expect(result.rubricOpinion?.rationale == "worthless")
    }

    @Test func theDefaultJudgeAttachesNoOpinion() async {
        let evalStore = InMemoryEvalResultStore()
        let subject = host(
            playbooks: [playbook("p1", outcome: OutcomeSpec(summary: "s", criteria: [.traceFullyLegible]))],
            evalStore: evalStore
        )
        await subject.bootstrap()

        await subject.runRoutine(id: "p1")

        let results = await evalStore.allResults()
        #expect(results[0].rubricOpinion == nil)
    }
}

/// Minimal receipt store; this suite only cares that receipt filing succeeds so `runRoutine`
/// reaches the evaluation step.
private actor EvalWiringReceiptStore: ReceiptStore {
    private var records: [ReceiptRecord] = []

    func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord {
        let record = ReceiptRecord(
            id: UUID(), sequenceID: records.count + 1, createdAt: receipt.createdAt,
            actor: receipt.actor, actorDetail: receipt.actorDetail,
            authorityDetail: receipt.authorityDetail, mode: receipt.mode, trigger: receipt.trigger,
            scope: receipt.scope, summary: receipt.summary, provenance: receipt.provenance,
            isSuccess: receipt.isSuccess, correlationID: receipt.correlationID, details: receipt.details
        )
        records.insert(record, at: 0)
        return record
    }

    func latest(limit: Int) async throws -> [ReceiptRecord] { Array(records.prefix(limit)) }
    func allRecords() -> [ReceiptRecord] { records }
    func receipts(forCorrelationID correlationID: String, limit: Int) async throws -> [ReceiptRecord] {
        Array(records.filter { $0.correlationID == correlationID }.prefix(limit))
    }
    func exportAll() async throws -> Data { Data() }
    func resetAll() async throws { records.removeAll() }
}

private struct FixedRubricJudge: RubricJudging {
    let opinion: RubricOpinion
    func score(_ spec: OutcomeSpec, trace: [WorkflowStepLog]) async -> RubricOpinion? { opinion }
}
