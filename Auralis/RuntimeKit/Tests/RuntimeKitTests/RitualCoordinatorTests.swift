import Foundation
import PlaybookCore
import ReceiptsCore
import RuntimeCore
@testable import RuntimeKit
import SchedulingCore
import SocialCore
import Testing

/// A ``RoutineRunning`` double, so a ritual can be driven without composing a whole `RuntimeHost` —
/// which is the testability the `RitualCoordinator` extraction was for.
@MainActor
private final class RecordingRoutineRunner: RoutineRunning {
    private(set) var startedPlaybookIDs: [String] = []

    func runRoutine(
        id: String,
        trigger: TriggerSource,
        actor: ActorRef?,
        correlationID: String?
    ) async -> ExecutionRecord {
        startedPlaybookIDs.append(id)
        return ExecutionRecord(
            playbookID: id,
            triggerSource: trigger,
            actor: actor ?? .human,
            correlationID: correlationID,
            outcome: .success,
            artifactID: nil,
            startedAt: .now,
            durationSeconds: 0.01
        )
    }
}

@MainActor
private final class RecordingDegradationReporter: RuntimeDegradationReporting {
    private(set) var playbookErrors: [String] = []
    private(set) var receiptFailures: [String] = []

    func reportPlaybookPersistenceError(_ error: Error) {
        playbookErrors.append(error.localizedDescription)
    }

    func noteReceiptPersistenceFailure(correlationID: String?, goal: String, actor: ActorRef) async {
        receiptFailures.append(correlationID ?? "<none>")
    }
}

private actor StubReceiptStore: ReceiptStore {
    func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord {
        ReceiptRecord(
            id: UUID(), sequenceID: 1, createdAt: receipt.createdAt,
            actor: receipt.actor, actorDetail: receipt.actorDetail,
            authorityDetail: receipt.authorityDetail, mode: receipt.mode, trigger: receipt.trigger,
            scope: receipt.scope, summary: receipt.summary, provenance: receipt.provenance,
            isSuccess: receipt.isSuccess, correlationID: receipt.correlationID, details: receipt.details
        )
    }
    func latest(limit: Int) async throws -> [ReceiptRecord] { [] }
    func receipts(forCorrelationID correlationID: String, limit: Int) async throws -> [ReceiptRecord] { [] }
    func exportAll() async throws -> Data { Data() }
    func resetAll() async throws { }
}

@MainActor
@Suite("Ritual coordinator")
struct RitualCoordinatorTests {
    private static let ritualID = "ritual.coordinator-test"
    private static let playbookID = "research.brief"

    private func makeRitual() -> RitualDefinition {
        RitualDefinition(
            id: Self.ritualID,
            kind: .weeklyReflection,
            name: "Coordinator Test",
            summary: "",
            trigger: .schedule(intervalSeconds: 100),
            playbookIDs: [Self.playbookID],
            isEnabled: true
        )
    }

    private func makeCoordinator(
        rituals: RitualStore,
        routines: any RoutineRunning,
        degradation: any RuntimeDegradationReporting
    ) -> RitualCoordinator {
        RitualCoordinator(
            rituals: rituals,
            sharedSessions: SharedSessionStore(),
            socialEventLog: SocialEventLogStore(),
            playbooks: InMemoryPlaybookStore(seed: SystemPlaybooks.all),
            receipts: StubReceiptStore(),
            events: RuntimeEventBus(),
            notifier: NoOpRitualRunNotifier(),
            cryptoMode: { .observe },
            routines: routines,
            degradation: degradation
        )
    }

    /// A ritual whose playbook loop ran nothing must not report success.
    ///
    /// `runRitualReport` aggregates by comparing `successfulCount == records.count`, which holds
    /// trivially at 0 == 0 — so an empty run with every playbook installed used to fall through to
    /// `.completed`, notify as completed, and call `recordRun`, advancing the schedule past an
    /// occurrence where nothing happened. Reaching it requires the weak `routines` collaborator to be
    /// gone, which cannot happen while the owning host is alive; dropping the double here is what
    /// makes the branch observable at all.
    @Test("a ritual that executed no playbooks is failed, not completed")
    func emptyRunIsNotReportedAsCompleted() async {
        let rituals = RitualStore(seed: [makeRitual()])
        let reporter = RecordingDegradationReporter()
        var runner: RecordingRoutineRunner? = RecordingRoutineRunner()
        let coordinator = makeCoordinator(rituals: rituals, routines: runner!, degradation: reporter)

        // The coordinator holds `routines` weakly, so releasing the only strong reference is what
        // puts the loop in the state this test is about.
        runner = nil

        let report = await coordinator.runRitualReport(
            id: Self.ritualID,
            trigger: .schedule,
            actor: nil,
            scheduledOccurrence: nil
        )

        #expect(report.status == .failed)
        #expect(report.records.isEmpty)
        #expect(report.didExecute == false)
        // The schedule must not advance for an occurrence that produced nothing.
        #expect(await rituals.lastRun(id: Self.ritualID) == nil)
        // And the claim is released, so a later attempt is not refused as `.alreadyRunning`.
        #expect(await rituals.beginRun(id: Self.ritualID) == true)
    }

    /// The ordinary path, so the guard above is pinned as specific to the empty case rather than
    /// having quietly broken success reporting.
    @Test("a ritual whose playbooks all run is completed and advances its schedule")
    func successfulRunIsCompleted() async {
        let rituals = RitualStore(seed: [makeRitual()])
        let reporter = RecordingDegradationReporter()
        let runner = RecordingRoutineRunner()
        let coordinator = makeCoordinator(rituals: rituals, routines: runner, degradation: reporter)

        let occurrence = Date(timeIntervalSince1970: 1_700_000_000)
        let report = await coordinator.runRitualReport(
            id: Self.ritualID,
            trigger: .schedule,
            actor: nil,
            scheduledOccurrence: occurrence
        )

        #expect(report.status == .completed)
        #expect(report.records.count == 1)
        #expect(report.didExecute)
        #expect(runner.startedPlaybookIDs == [Self.playbookID])
        #expect(await rituals.lastRun(id: Self.ritualID) == occurrence)
    }
}
