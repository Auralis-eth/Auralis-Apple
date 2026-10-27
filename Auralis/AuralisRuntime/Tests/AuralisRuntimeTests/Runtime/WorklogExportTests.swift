import AuralisFoundation
import Foundation
@testable import AuralisRuntime
import Testing

/// Pins the worklog export contract.
///
/// `allSteps()` hands live values to an in-process reader; `exportAll()` is the artifact that leaves
/// the process — what evals, operator report cards, and bug reports carry. That makes ordering and
/// byte-stability part of the contract, not incidental: a snapshot whose bytes shift between two
/// exports of the same trace turns every eval diff into noise.
@Suite("Worklog export")
struct WorklogExportTests {
    private func step(
        _ event: WorkflowWorklogEvent,
        at timestamp: Date,
        id: UUID = UUID()
    ) -> WorkflowStepLog {
        WorkflowStepLog(
            id: id,
            correlationID: "corr",
            toolID: "tool",
            event: event,
            actor: .system,
            timestamp: timestamp
        )
    }

    @Test("the export is ordered oldest-first regardless of insertion order")
    func exportIsChronological() async throws {
        let worklog = InMemoryWorklog()
        let base = Date(timeIntervalSince1970: 5_000)
        await worklog.record(step(.failed(reason: "third"), at: base + 2))
        await worklog.record(step(.blocked(reason: "first"), at: base))
        await worklog.record(step(.executed(artifactID: UUID(), durationSeconds: 1), at: base + 1))

        let decoded = try JSONDecoder().decode(
            [WorkflowStepLog].self,
            from: try await worklog.exportAll()
        )
        #expect(decoded.map(\.timestamp) == [base, base + 1, base + 2])
    }

    /// Entries sharing a timestamp are real — a routine's phases can all stamp the same `.now` — so
    /// ties break on `id` rather than on whatever order the store happened to return.
    @Test("entries with identical timestamps export in a stable order")
    func tiedTimestampsAreStable() async throws {
        let sameInstant = Date(timeIntervalSince1970: 9_000)
        let low = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let high = UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000001")!

        let forward = InMemoryWorklog()
        await forward.record(step(.blocked(reason: "a"), at: sameInstant, id: low))
        await forward.record(step(.blocked(reason: "b"), at: sameInstant, id: high))

        let reversed = InMemoryWorklog()
        await reversed.record(step(.blocked(reason: "b"), at: sameInstant, id: high))
        await reversed.record(step(.blocked(reason: "a"), at: sameInstant, id: low))

        let forwardExport = try await forward.exportAll()
        let reversedExport = try await reversed.exportAll()
        #expect(forwardExport == reversedExport)
    }

    /// The export has to survive the round trip with attribution and the richer event payloads
    /// intact, or a report card reading it back sees a different run than the one that happened.
    @Test("the export round-trips actor, authority, and considered candidates")
    func exportRoundTripsFullEntry() async throws {
        let worklog = InMemoryWorklog()
        let candidates = [
            ConsideredCandidate(
                title: "organize-library",
                capability: .autoOrganization,
                wasSelected: true,
                rationale: "Matched the goal."
            ),
            ConsideredCandidate(
                title: "make-playlist",
                capability: .playlistManagement,
                wasSelected: false,
                rationale: "No playlist intent."
            )
        ]
        await worklog.record(
            WorkflowStepLog(
                correlationID: "corr",
                toolID: "planner.deterministic",
                event: .considered(candidates),
                actor: ActorRef(kind: .workflow, identifier: "planner.deterministic"),
                timestamp: Date(timeIntervalSince1970: 1)
            )
        )
        await worklog.record(
            WorkflowStepLog(
                correlationID: "corr",
                toolID: "routine",
                event: .routinePhase(.artifactRejected, detail: "output type not allowed"),
                actor: ActorRef(kind: .scheduledRoutine, identifier: "user.cron.digest"),
                timestamp: Date(timeIntervalSince1970: 2)
            )
        )

        let decoded = try JSONDecoder().decode(
            [WorkflowStepLog].self,
            from: try await worklog.exportAll()
        )
        #expect(decoded.count == 2)
        guard case let .considered(roundTripped) = decoded[0].event else {
            Issue.record("expected a considered entry first")
            return
        }
        #expect(roundTripped == candidates)
        #expect(decoded[0].actor.identifier == "planner.deterministic")
        guard case let .routinePhase(phase, detail) = decoded[1].event else {
            Issue.record("expected a routinePhase entry second")
            return
        }
        #expect(phase == .artifactRejected)
        #expect(detail == "output type not allowed")
        #expect(decoded[1].actor.kind == .scheduledRoutine)
    }
}
