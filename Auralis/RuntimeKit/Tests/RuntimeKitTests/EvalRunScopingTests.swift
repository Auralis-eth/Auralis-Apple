import ArtifactCore
import AuralisRuntime
import Foundation
import ReceiptsCore
import Testing

@testable import RuntimeKit

/// A correlation id can hold more than one run, so a grade has to say *which* run it is about.
///
/// `RitualCoordinator.runSharedWorkflow` files every playbook a person shares into a session under
/// that session's correlation id, and a collaborative ritual runs each of its playbooks under one
/// shared id. `TraceEvaluator` grades every entry it is handed, so reading the trace by correlation
/// id alone made each run's grade a function of the runs before it — inventing failures in one
/// direction and masking them in the other. See ``RuntimeHost/trace(ofRun:in:)``.
@Suite("Eval run scoping")
@MainActor
struct EvalRunScopingTests {

    // MARK: - The trace window

    /// Pins the window semantics directly: closed at both ends, and nothing from outside it.
    @Test func theRunWindowKeepsOnlyTheRunsOwnEntries() {
        let start = Date(timeIntervalSince1970: 1_000)
        let record = Self.record(playbookID: "p", startedAt: start, durationSeconds: 10)

        let scoped = RuntimeHost.trace(
            ofRun: record,
            in: [
                Self.step(at: start.addingTimeInterval(-1), detail: "before"),
                Self.step(at: start, detail: "at-start"),
                Self.step(at: start.addingTimeInterval(5), detail: "during"),
                Self.step(at: start.addingTimeInterval(10), detail: "at-end"),
                Self.step(at: start.addingTimeInterval(11), detail: "after")
            ]
        )

        #expect(scoped.map(Self.detail) == ["at-start", "during", "at-end"])
    }

    /// A zero-length run still owns the entries stamped at its instant, so an in-memory run that
    /// completes inside a clock tick is not graded on an empty trace.
    @Test func aZeroLengthRunStillOwnsItsOwnInstant() {
        let start = Date(timeIntervalSince1970: 2_000)
        let record = Self.record(playbookID: "p", startedAt: start, durationSeconds: 0)

        let scoped = RuntimeHost.trace(
            ofRun: record,
            in: [
                Self.step(at: start.addingTimeInterval(-0.5), detail: "before"),
                Self.step(at: start, detail: "at-start"),
                Self.step(at: start.addingTimeInterval(0.5), detail: "after")
            ]
        )

        #expect(scoped.map(Self.detail) == ["at-start"])
    }

    // MARK: - The concrete failure

    /// The reported defect, end to end: share one playbook into a session, wait, then share another.
    ///
    /// `completedWithin` measures `max(timestamp) - min(timestamp)` over the trace it is given, so the
    /// second run used to be charged for the wall-clock gap since the first — failing a run that took
    /// milliseconds. The budget here is well above what an in-memory run can take and well below the
    /// gap, so the assertion distinguishes the two rather than racing them.
    @Test func theSecondRunInASessionIsNotChargedForTheFirstRunsElapsedTime() async throws {
        let evalStore = InMemoryEvalResultStore()
        let subject = Self.host(
            playbooks: [
                Self.playbook("first", outcome: nil),
                Self.playbook("second", outcome: OutcomeSpec(
                    summary: "Prompt, because someone is waiting on it.",
                    criteria: [.completedWithin(seconds: 0.5)]
                ))
            ],
            evalStore: evalStore
        )
        await subject.bootstrap()

        await subject.runRoutine(id: "first", correlationID: "session-1")
        try await Task.sleep(for: .seconds(1))
        await subject.runRoutine(id: "second", correlationID: "session-1")

        let graded = try #require(await evalStore.allResults().first { $0.playbookID == "second" })
        #expect(graded.grade == .passed)
        // Passed on real evidence rather than on an empty window, which would grade `.inconclusive`
        // and quietly satisfy the assertion above for the wrong reason.
        #expect((graded.traceObservability?.recordedStepCount ?? 0) > 0)
    }

    /// The masking direction, which matters at least as much: a run that produced nothing must not be
    /// credited with the artifact an earlier playbook in the same session produced.
    @Test func aRunIsNotCreditedWithAnArtifactAnotherPlaybookProduced() async throws {
        let evalStore = InMemoryEvalResultStore()
        let subject = Self.host(
            playbooks: [
                Self.playbook("producer", outcome: nil),
                Self.playbook("barren", outcome: OutcomeSpec(
                    summary: "Produces a reviewable artifact.",
                    criteria: [.producedArtifact]
                ))
            ],
            evalStore: evalStore,
            // `producer` keeps the default operator (which drafts a brief); `barren` produces nothing.
            routineOperators: ["barren": ArtifactlessRoutineOperator()]
        )
        await subject.bootstrap()

        await subject.runRoutine(id: "producer", correlationID: "session-2")
        await subject.runRoutine(id: "barren", correlationID: "session-2")

        let graded = try #require(await evalStore.allResults().first { $0.playbookID == "barren" })
        #expect(graded.grade == .failed)
    }

    /// A failed run must not be passed off as completed because an earlier playbook in the same
    /// session reached that phase.
    ///
    /// `reachedRoutinePhase` is existential, so it is satisfied by *any* matching entry in the trace
    /// it is handed — which is what let a run that recorded `.failed` inherit a `.completed` it never
    /// reached. Ordered healthy-then-faulty deliberately: the borrowed evidence has to already be in
    /// the trace for the masking to be possible.
    @Test func aFailedRunDoesNotInheritAnEarlierRunsCompletion() async throws {
        let evalStore = InMemoryEvalResultStore()
        let subject = Self.host(
            playbooks: [
                Self.playbook("healthy", outcome: nil),
                Self.playbook("faulty", outcome: OutcomeSpec(
                    summary: "Runs to completion.",
                    criteria: [.reachedRoutinePhase(.completed)]
                ))
            ],
            evalStore: evalStore,
            routineOperators: ["faulty": FailingRoutineOperator()]
        )
        await subject.bootstrap()

        await subject.runRoutine(id: "healthy", correlationID: "session-3")
        let faulty = await subject.runRoutine(id: "faulty", correlationID: "session-3")
        #expect(faulty.outcome == .failed)

        let graded = try #require(await evalStore.allResults().first { $0.playbookID == "faulty" })
        #expect(graded.grade == .failed)
    }

    /// The guarantee the fix must not cost: a run under its own correlation id is graded on its whole
    /// trace, exactly as before.
    @Test func aStandaloneRunIsStillGradedOnItsFullTrace() async throws {
        let evalStore = InMemoryEvalResultStore()
        let subject = Self.host(
            playbooks: [Self.playbook("solo", outcome: OutcomeSpec(
                summary: "Produces something legibly.",
                criteria: [.producedArtifact, .traceFullyLegible, .reachedRoutinePhase(.completed)]
            ))],
            evalStore: evalStore
        )
        await subject.bootstrap()

        let record = await subject.runRoutine(id: "solo")

        let graded = try #require(await evalStore.allResults().first { $0.playbookID == "solo" })
        #expect(graded.grade == .passed)
        #expect(graded.correlationID == record.correlationID)
    }

    // MARK: - Fixtures

    private static func host(
        playbooks: [Playbook],
        evalStore: any EvalResultStoring,
        routineOperators: [String: any RoutineOperator] = [:]
    ) -> RuntimeHost {
        RuntimeHost(
            receiptStore: EvalRunScopingReceiptStore(),
            stores: RuntimeHostStores(
                playbookStore: InMemoryPlaybookStore(seed: playbooks),
                evalResultStore: evalStore
            ),
            operators: RuntimeOperatorStack(routineOperators: routineOperators)
        )
    }

    private static func playbook(_ id: String, outcome: OutcomeSpec?) -> Playbook {
        Playbook(
            id: id,
            name: id,
            summary: "s",
            trigger: .manual,
            authority: PlaybookAuthority(capabilities: [.runPlugin], allowedOutputs: [.brief]),
            completionCondition: "done",
            contextContract: SystemPlaybookContracts.contract(for: id, identifier: "test.\(id)"),
            outcome: outcome,
            installState: .installed
        )
    }

    private static func record(
        playbookID: String,
        startedAt: Date,
        durationSeconds: Double
    ) -> ExecutionRecord {
        ExecutionRecord(
            playbookID: playbookID,
            triggerSource: .manual,
            actor: .human,
            correlationID: "session",
            outcome: .success,
            artifactID: nil,
            startedAt: startedAt,
            durationSeconds: durationSeconds
        )
    }

    private static func step(at timestamp: Date, detail: String) -> WorkflowStepLog {
        WorkflowStepLog(
            correlationID: "session",
            toolID: nil,
            event: .routinePhase(.completed, detail: detail),
            actor: .human,
            timestamp: timestamp
        )
    }

    private static func detail(_ step: WorkflowStepLog) -> String {
        guard case let .routinePhase(_, detail) = step.event else { return "" }
        return detail ?? ""
    }
}

/// Succeeds while producing no work product, so `producedArtifact` has nothing of its own to find.
private struct ArtifactlessRoutineOperator: RoutineOperator {
    func run(playbook: Playbook, context: GovernedContext) async -> RoutineRunResult {
        RoutineRunResult(outcome: .success)
    }
}

/// Fails, so the run records a `.failed` routine phase in the shared trace.
private struct FailingRoutineOperator: RoutineOperator {
    func run(playbook: Playbook, context: GovernedContext) async -> RoutineRunResult {
        RoutineRunResult(outcome: .failed, failureReason: "operator fault")
    }
}

/// Minimal receipt store; this suite only needs receipt filing to succeed so `runRoutine` reaches
/// the evaluation step.
private actor EvalRunScopingReceiptStore: ReceiptStore {
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
    func receipts(forCorrelationID correlationID: String, limit: Int) async throws -> [ReceiptRecord] {
        Array(records.filter { $0.correlationID == correlationID }.prefix(limit))
    }
    func exportAll() async throws -> Data { Data() }
    func resetAll() async throws { records.removeAll() }
}
