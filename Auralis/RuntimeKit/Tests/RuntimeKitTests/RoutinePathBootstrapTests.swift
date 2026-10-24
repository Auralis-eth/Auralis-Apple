import ArtifactCore
import AuralisPrimaryModels
import CapabilitiesCore
import Foundation
import ReceiptsCore
import RuntimeCore
@testable import RuntimeKit
import SchedulingCore
import Testing

/// In-memory ledger whose summaries can be read back, so "was this receipted?" is observable.
private actor BootstrapGapLedger: ReceiptStore {
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

    func summaries() -> [String] { records.map(\.summary) }
}

/// The routine and ritual entry points must bootstrap, because the background refresh enters through
/// them and nothing else.
///
/// `RuntimeBackgroundScheduler.runInBackground()` builds its own host and calls
/// `runDueRoutines` / `runDueRituals` directly. Those were the only governed entry points that did
/// not `await bootstrap()`, so on a background wake the receipt observer was never subscribed and
/// the capability grants a routine mints for its own actor published `.capabilityLeaseGranted`
/// events into a bus nobody was auditing — leaving the ledger recording *that* work happened but
/// not *what authorized it*.
@Suite("Routine-path bootstrap")
@MainActor
struct RoutinePathBootstrapTests {
    /// Lets the receipt observer drain the event bus before the ledger is read.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(300))
    }

    @Test("running a routine without an explicit bootstrap still receipts its capability grant")
    func routineRunReceiptsItsGrantWithoutExplicitBootstrap() async throws {
        let ledger = BootstrapGapLedger()
        let host = RuntimeHost(receiptStore: ledger)

        // No `bootstrap()` — exactly what the background scheduler does.
        await host.runRoutine(id: "onchain.watch", trigger: .artifactStale)
        try await settle()

        let summaries = await ledger.summaries()
        #expect(
            summaries.contains { $0.hasPrefix("Routine onchain.watch") },
            "the run itself should be receipted: \(summaries)"
        )
        #expect(
            summaries.contains { $0.hasPrefix("Capability granted") },
            "the authority that permitted the run must be receipted too: \(summaries)"
        )
    }

    @Test("the due-routine scan bootstraps before it fires anything")
    func dueRoutineScanBootstraps() async throws {
        let ledger = BootstrapGapLedger()
        let host = RuntimeHost(receiptStore: ledger)

        await host.runDueRoutines(now: .now, staleSignal: true, approvalPendingSignal: true)
        try await settle()

        let summaries = await ledger.summaries()
        #expect(summaries.contains { $0.hasPrefix("Routine ") })
        #expect(
            summaries.contains { $0.hasPrefix("Capability granted") },
            "grants from a background scan must reach the ledger: \(summaries)"
        )
    }

    /// A ritual publishes events, opens a collaborative session, and notifies before its first
    /// playbook runs — and the no-installed-playbooks path reaches none of them — so it has to
    /// bootstrap itself rather than rely on the `runRoutine` calls underneath.
    @Test("the due-ritual scan bootstraps even when no ritual is due")
    func dueRitualScanBootstraps() async throws {
        let host = RuntimeHost(receiptStore: BootstrapGapLedger())

        await host.runDueRituals(now: .now)

        // Bootstrap's observable effect: the registries are populated and standing authority seeded.
        #expect(await host.registeredTools().isEmpty == false)
        #expect(await host.activeCapabilityLeases().isEmpty == false)
    }

    /// Bootstrapping from inside `runDueRoutines` must not deadlock against the `runRoutine` calls it
    /// makes per due playbook, nor against a concurrent caller entering by another door.
    @Test("nested and concurrent bootstrap from the routine path completes")
    func nestedBootstrapDoesNotDeadlock() async throws {
        let host = RuntimeHost(receiptStore: BootstrapGapLedger())

        async let scan: Void = host.runDueRoutines(now: .now, staleSignal: true)
        async let single = host.runRoutine(id: "research.brief")
        async let tools = host.registeredTools()
        async let explicit: Void = host.bootstrap()
        _ = await (scan, single, tools, explicit)

        #expect(await host.registeredTools().isEmpty == false)
    }
}
