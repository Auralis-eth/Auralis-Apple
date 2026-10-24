import ArtifactCore
import ArtifactStorage
import Foundation
import OperatorRuntimeStorage
import PerformanceCore
import PlaybookCore
import ReceiptsCore
import RuntimeCore
@testable import RuntimeKit
import SchedulingCore
import SwiftData
import Testing

private actor PersistentHostReceiptStore: ReceiptStore {
    private var records: [ReceiptRecord] = []

    func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord {
        let record = ReceiptRecord(
            id: UUID(),
            sequenceID: records.count + 1,
            createdAt: receipt.createdAt,
            actor: receipt.actor,
            actorDetail: receipt.actorDetail,
            authorityDetail: receipt.authorityDetail,
            mode: receipt.mode,
            trigger: receipt.trigger,
            scope: receipt.scope,
            summary: receipt.summary,
            provenance: receipt.provenance,
            isSuccess: receipt.isSuccess,
            correlationID: receipt.correlationID,
            details: receipt.details
        )
        records.insert(record, at: 0)
        return record
    }

    func latest(limit: Int) async throws -> [ReceiptRecord] {
        Array(records.prefix(limit))
    }

    func receipts(forCorrelationID correlationID: String, limit: Int) async throws -> [ReceiptRecord] {
        Array(records.filter { $0.correlationID == correlationID }.prefix(limit))
    }

    func exportAll() async throws -> Data {
        try JSONEncoder().encode(records)
    }

    func resetAll() async throws {
        records.removeAll()
    }

    func count(ofTrigger trigger: String) -> Int {
        records.filter { $0.trigger == trigger }.count
    }
}

@MainActor
private func makePersistentRuntimeContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Schema([
            StoredPlaybookRecord.self,
            StoredPerformanceEventRecord.self,
            StoredExecutionRecordRow.self,
            StoredArtifact.self,
            StoredArtifactRecord.self,
            StoredWorkflowStepLogRow.self,
            StoredAgentSessionRow.self,
            StoredRuntimeEventRow.self,
            StoredCapabilityLeaseRow.self,
            StoredCapabilityRestrictionRow.self
        ]),
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
}

@MainActor
@Suite("Persistent RuntimeHost")
struct PersistentRuntimeHostTests {
    @Test
    func persistentHostRehydratesEventsSessionsAndLeases() async throws {
        let container = try makePersistentRuntimeContainer()
        let receiptStore = PersistentHostReceiptStore()
        let correlationID = "corr-runtime-relaunch"
        let actor = ActorRef(kind: .workflow, identifier: "planner")

        let firstHost = RuntimeHost.persistent(
            receiptStore: receiptStore,
            makeStorageContainer: { container }
        )
        await firstHost.recordMemoryTouch(
            kind: .memoryRead,
            key: "memory.localPreferences",
            dataClass: .localPreference,
            correlationID: correlationID,
            actor: RuntimeHost.shellContextActor
        )
        let lease = await firstHost.grantCapabilityLease(
            capability: .playlistManagement,
            grantedTo: actor,
            reason: "Planner may inspect the local music library while building a recommendation.",
            correlationID: correlationID
        )

        let relaunchedHost = RuntimeHost.persistent(
            receiptStore: receiptStore,
            makeStorageContainer: { container }
        )

        let events = await relaunchedHost.recentEvents(limit: 10)
        #expect(events.contains { envelope in
            if case .memoryTouched(.memoryRead, "memory.localPreferences") = envelope.event {
                return envelope.correlationID == correlationID
            }
            return false
        })
        #expect(events.contains { envelope in
            if case let .capabilityLeaseGranted(granted) = envelope.event {
                return granted.id == lease.id
            }
            return false
        })

        let session = try #require(await relaunchedHost.sessionStore.session(correlationID: correlationID))
        #expect(session.memoryTouched.map(\.key) == ["memory.localPreferences"])
        #expect(session.memoryTouched.first?.dataClass == .localPreference)

        // P0.5-602: instrumentation opens this session, so the actor it names has to survive the
        // relaunch. `.system` would decode identically to the legacy fallback, making a real context
        // touch indistinguishable from a pre-attribution row — assert we did not land back on it.
        #expect(session.actor == RuntimeHost.shellContextActor)
        #expect(session.actor != .system)

        let activeLeases = await relaunchedHost.activeCapabilityLeases()
        #expect(activeLeases.contains { activeLease in
            activeLease.id == lease.id
                && activeLease.capability == .playlistManagement
                && activeLease.grantedTo == actor
                && activeLease.sessionCorrelationID == correlationID
        })

        await relaunchedHost.revokeCapabilityLease(id: lease.id)
        #expect(await relaunchedHost.activeCapabilityLeases() == [])
    }

    /// The runtime's history lives in its own on-disk container, so the app-side privacy reset that
    /// deletes receipts and wallet rows never reached it: worklog traces, sessions, and event history
    /// all survived "delete all local data". Asserted through a *relaunched* host so this proves the
    /// rows are gone from storage, not just from one host's memory.
    @Test
    func resetAllHistoryClearsDurableRuntimeHistory() async throws {
        let container = try makePersistentRuntimeContainer()
        let receiptStore = PersistentHostReceiptStore()
        let correlationID = "corr-privacy-reset"

        let host = RuntimeHost.persistent(
            receiptStore: receiptStore,
            makeStorageContainer: { container }
        )
        await host.recordMemoryTouch(
            kind: .memoryRead,
            key: "memory.localPreferences",
            dataClass: .localPreference,
            correlationID: correlationID,
            actor: RuntimeHost.shellContextActor
        )
        await host.worklogStore.record(
            WorkflowStepLog(
                correlationID: correlationID,
                toolID: "tool.research",
                event: .proposed(ActionProposal(
                    actor: RuntimeHost.shellContextActor,
                    intent: "Summarize the local library",
                    capability: .autoOrganization,
                    impact: .readOnly
                )),
                actor: RuntimeHost.shellContextActor
            )
        )
        _ = await host.grantCapabilityLease(
            capability: .playlistManagement,
            grantedTo: RuntimeHost.shellContextActor,
            reason: "Planner may inspect the local music library while building a recommendation.",
            correlationID: correlationID
        )
        #expect(await host.worklogStore.allSteps().isEmpty == false)

        try await host.resetAllHistory()

        let relaunchedHost = RuntimeHost.persistent(
            receiptStore: receiptStore,
            makeStorageContainer: { container }
        )
        #expect(await relaunchedHost.worklogStore.allSteps().isEmpty)
        #expect(await relaunchedHost.worklogStore.steps(forCorrelationID: correlationID).isEmpty)
        #expect(await relaunchedHost.sessionStore.session(correlationID: correlationID) == nil)
        #expect(await relaunchedHost.recentEvents(limit: 50).isEmpty)
        #expect(await relaunchedHost.activeCapabilityLeases().isEmpty)
        #expect(try await relaunchedHost.artifactStore.latest(limit: 10).isEmpty)
        #expect(await relaunchedHost.performanceStore.allHealth().isEmpty)
    }

    /// One expiry earns one receipt, however many times the app is relaunched.
    ///
    /// The registry's "already reported" set is in-memory and the lease store returns every row it
    /// holds, expired or not, so each relaunch used to re-announce the entire history of expired
    /// leases as newly expired. `RuntimeReceiptObserver` receipts each announcement, and its own
    /// dedupe cannot catch these because the replayed envelope carries a fresh event ID. Standing
    /// routine authority alone mints roughly ten 24-hour leases a day, so the ledger filled with
    /// duplicate expiry entries at a rate that grew with the install's age.
    ///
    /// Asserted across *two* relaunches, because a single one cannot distinguish "reported once" from
    /// "reported once per process".
    @Test
    func anExpiredLeaseIsReceiptedOnceAcrossRelaunches() async throws {
        let container = try makePersistentRuntimeContainer()
        let receiptStore = PersistentHostReceiptStore()
        let expiryTrigger = "runtime.capability.expired"

        let firstHost = RuntimeHost.persistent(
            receiptStore: receiptStore,
            makeStorageContainer: { container }
        )
        await firstHost.bootstrap()
        // Expired on arrival, so the sweep has something to find without the test waiting out a lease.
        _ = await firstHost.grantCapabilityLease(
            capability: .playlistManagement,
            grantedTo: .human,
            reason: "Lapsed lease for the expiry sweep.",
            duration: -60
        )
        _ = await firstHost.activeCapabilityLeases()
        // A lease that lapses while the app is running is still reported — the fix suppresses the
        // re-announcement, not the announcement.
        try await settle(until: { await receiptStore.count(ofTrigger: expiryTrigger) == 1 })

        for _ in 0..<2 {
            let relaunchedHost = RuntimeHost.persistent(
                receiptStore: receiptStore,
                makeStorageContainer: { container }
            )
            await relaunchedHost.bootstrap()
            _ = await relaunchedHost.activeCapabilityLeases()
        }
        // Long enough for a re-announced expiry to have been written, had one been published.
        try await Task.sleep(for: .milliseconds(300))

        #expect(await receiptStore.count(ofTrigger: expiryTrigger) == 1)
    }

    /// Which artifact store the persistent host actually builds.
    ///
    /// Two near-identical `SwiftDataArtifactStore` types existed: the hardened one in
    /// `ArtifactStorage`, with 21 tests and zero production imports, and a weaker copy declared in
    /// `OperatorRuntimeStorage` that this host was the sole caller of. The copy's write methods
    /// `guard let … else { return }` on a missing row, so they reported success for a mutation that
    /// wrote nothing — and `MissionControlHomeModel.updateArtifactLifecycle` appends an
    /// `isSuccess: true` receipt straight after the call, so a person who approved or exported an
    /// artifact deleted from under them (another window, a `resetAll`) was told the decision had
    /// been recorded. Every defect `ArtifactStorageTests` certified as fixed was still live.
    ///
    /// Asserted through the *host* rather than the store directly, because the defect was never in
    /// either store's own tests — it was in which one got wired up.
    @Test
    func persistentHostArtifactStoreReportsAWriteToAMissingArtifact() async throws {
        let container = try makePersistentRuntimeContainer()
        let host = RuntimeHost.persistent(
            receiptStore: PersistentHostReceiptStore(),
            makeStorageContainer: { container }
        )

        let artifact = try await host.artifactStore.create(
            ArtifactDraft(
                type: .brief,
                title: "Brief",
                creatorOperatorID: "operator.research.brief",
                provenance: ArtifactProvenance(actor: .system),
                content: "body"
            )
        )
        try await host.artifactStore.resetAll()

        // The row is gone, so there is nothing to record the decision on. That has to reach the
        // caller: it is the difference between a receipt that is true and one that is not.
        await #expect(throws: ArtifactStoreWriteError.artifactNotFound(id: artifact.id)) {
            try await host.artifactStore.updateLifecycle(
                id: artifact.id,
                to: .exported,
                destination: "Share sheet",
                exportFormat: "markdown"
            )
        }
        await #expect(throws: ArtifactStoreWriteError.artifactNotFound(id: artifact.id)) {
            try await host.artifactStore.setApprovalState(id: artifact.id, to: .approved)
        }
        await #expect(throws: ArtifactStoreWriteError.artifactNotFound(id: artifact.id)) {
            try await host.artifactStore.linkRelatedReceipt(id: UUID(), toArtifact: artifact.id)
        }
    }

    /// Artifacts written before the storage change are in a different table, so without the
    /// migration the swap above would have made every existing artifact vanish from Mission
    /// Control. The host runs it on open; `LegacyArtifactMigration` covers the copy itself.
    @Test
    func persistentHostMigratesLegacyArtifactsOnOpen() async throws {
        let container = try makePersistentRuntimeContainer()
        let legacy = Artifact(
            id: UUID(),
            groupID: UUID(),
            version: 1,
            type: .report,
            title: "Written by the old store",
            creatorPlaybookID: nil,
            creatorOperatorID: "operator.onchain.watch",
            createdAt: Date(timeIntervalSince1970: 500),
            provenance: ArtifactProvenance(actor: .system),
            relatedReceiptIDs: [],
            approvalState: .draft,
            destination: nil,
            exportFormat: nil,
            content: "legacy body"
        )
        let context = ModelContext(container)
        context.insert(
            StoredArtifactRecord(
                id: legacy.id,
                groupID: legacy.groupID,
                typeRawValue: legacy.type.rawValue,
                createdAt: legacy.createdAt,
                data: try JSONEncoder().encode(legacy)
            )
        )
        try context.save()

        let host = RuntimeHost.persistent(
            receiptStore: PersistentHostReceiptStore(),
            makeStorageContainer: { container }
        )

        let migrated = try #require(try await host.artifactStore.get(id: legacy.id))
        #expect(migrated.title == "Written by the old store")
        #expect(migrated.content == "legacy body")
    }
}

/// Polls `condition` until it holds, so a test can wait on the receipt observer's asynchronous write
/// without pinning a fixed sleep to how fast the machine happens to be.
@MainActor
private func settle(
    until condition: () async -> Bool,
    timeout: Duration = .seconds(5)
) async throws {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(await condition())
}
