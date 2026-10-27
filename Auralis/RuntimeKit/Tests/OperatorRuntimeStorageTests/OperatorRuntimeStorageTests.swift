import ArtifactCore
import ArtifactStorage
import AuralisRuntime
import Foundation
@testable import OperatorRuntimeStorage
import SwiftData
import Testing

@MainActor
private func makeContainer() throws -> ModelContainer {
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
            StoredCapabilityRestrictionRow.self,
            StoredEvalResultRow.self,
            StoredImprovementRecommendationRow.self
        ]),
        // `cloudKitDatabase: .none` explicitly, matching `OperatorRuntimeStorage.makeContainer()`.
        // The default is `.automatic`, which reads the host's iCloud entitlement as instruction to
        // mirror — and several rows here carry `@Attribute(.unique)`, which CloudKit does not
        // support, so a container that ever picked up an entitlement would fail to load outright
        // rather than fail a test. Stated here so the test container cannot drift from the real one.
        configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    )
}

// There is deliberately no "container whose saves fail" helper here, and the rollback guards on
// `SwiftDataRuntimeEventHistoryStore.append` and `SwiftDataPlaybookStore.upsert` are therefore
// unpinned by a test. Three injections were tried and none produces a throwing `save()`:
// `allowsSave: false` resolves an in-memory store to `/dev/null` so the *container* fails to load
// instead; inserting a model the container's schema does not know about is silently discarded at
// commit; and fetching an unregistered type returns empty rather than throwing. The real trigger is
// disk pressure or a corrupt store file, neither reachable from here. Reaching it would need a
// file-backed store opened a second time read-only, which is a temp-file dependency this suite does
// not otherwise carry.

private func playbook(_ id: String, state: PlaybookInstallState = .available) -> Playbook {
    Playbook(
        id: id, name: id, summary: "s",
        trigger: .manual,
        authority: PlaybookAuthority(capabilities: [.autoOrganization], allowedOutputs: [.brief]),
        completionCondition: "done",
        contextContract: .noContext(identifier: "test.\(id)"),
        installState: state
    )
}

/// One legacy row carrying a readable artifact, for the batching tests.
private func legacyArtifactRow(title: String) throws -> StoredArtifactRecord {
    let artifact = Artifact(
        id: UUID(),
        groupID: UUID(),
        version: 1,
        type: .brief,
        title: title,
        creatorPlaybookID: nil,
        creatorOperatorID: "operator.research.brief",
        createdAt: Date(timeIntervalSince1970: 1_000),
        provenance: ArtifactProvenance(actor: .system),
        relatedReceiptIDs: [],
        approvalState: .approved,
        destination: nil,
        exportFormat: nil,
        content: "body of \(title)"
    )
    return StoredArtifactRecord(
        id: artifact.id,
        groupID: artifact.groupID,
        typeRawValue: artifact.type.rawValue,
        createdAt: artifact.createdAt,
        data: try JSONEncoder().encode(artifact)
    )
}

private func proposal() -> ActionProposal {
    ActionProposal(actor: .system, intent: "Read", capability: .audioPlayback, impact: .readOnly)
}

private func worklogStep(
    _ correlationID: String?,
    event: WorkflowWorklogEvent,
    at timestamp: Date
) -> WorkflowStepLog {
    WorkflowStepLog(
        correlationID: correlationID,
        toolID: "tool",
        event: event,
        actor: .system,
        timestamp: timestamp
    )
}

@Suite("OperatorRuntimeStorage")
struct OperatorRuntimeStorageTests {
    @Test
    func playbookStoreSeedsUpsertsAndFilters() async throws {
        let container = try await makeContainer()
        let store = SwiftDataPlaybookStore(modelContainer: container)
        try await store.seedIfEmpty([playbook("a", state: .installed), playbook("b")])
        try await store.seedIfEmpty([playbook("c")]) // no-op, already seeded

        #expect(try await store.all().map(\.id) == ["a", "b"])
        try await store.setInstallState(id: "b", to: .installed)
        #expect(try await store.playbooks(inState: .installed).map(\.id) == ["a", "b"])
        try await store.setInstallState(id: "a", to: .paused)

        let relaunchedStore = SwiftDataPlaybookStore(modelContainer: container)
        #expect(try await relaunchedStore.playbook(id: "a")?.installState == .paused)
        #expect(try await relaunchedStore.playbook(id: "b")?.installState == .installed)
    }

    /// Matches `InMemoryPlaybookStore`: install/pause on an ID the library does not hold has to be
    /// reportable, not a silent success the Routine Manager renders as a completed flip.
    @Test
    func setInstallStateThrowsForAnUnknownID() async throws {
        let container = try await makeContainer()
        let store = SwiftDataPlaybookStore(modelContainer: container)
        try await store.seedIfEmpty([playbook("a")])

        await #expect(throws: PlaybookStoreError.notFound(id: "ghost")) {
            try await store.setInstallState(id: "ghost", to: .installed)
        }
        #expect(try await store.all().map(\.id) == ["a"])
    }

    @Test
    func performanceStorePersistsAndAggregates() async throws {
        let container = try await makeContainer()
        let store = SwiftDataPerformanceStore(modelContainer: container)
        await store.record(PerformanceEvent(playbookID: "pb", outcome: .success, durationSeconds: 1))
        await store.record(PerformanceEvent(playbookID: "pb", outcome: .failed, durationSeconds: 3))

        let health = await store.health(forPlaybook: "pb")
        #expect(health.totalRuns == 2)
        #expect(health.failureCount == 1)
    }

    @Test
    func performanceStorePersistsApprovalDecisionAndPolicyBlockCategory() async throws {
        let container = try await makeContainer()
        let store = SwiftDataPerformanceStore(modelContainer: container)
        let runID = UUID()
        await store.record(PerformanceEvent(
            playbookID: "pb",
            outcome: .needsApproval,
            durationSeconds: 1,
            runID: runID
        ))
        await store.record(PerformanceEvent(
            playbookID: "pb",
            outcome: .blocked,
            durationSeconds: 0,
            blockCategory: .policy
        ))
        await store.recordApprovalDecision(runID: runID, decision: .approved)

        let relaunched = SwiftDataPerformanceStore(modelContainer: container)
        let health = await relaunched.health(forPlaybook: "pb")
        #expect(health.approvalRate == 1)
        #expect(health.resolvedApprovalCount == 1)
        #expect(health.policyBlockRate == 0.5)
    }

    @Test
    func executionRecordStorePersists() async throws {
        let container = try await makeContainer()
        let store = SwiftDataExecutionRecordStore(modelContainer: container)
        await store.store(ExecutionRecord(
            playbookID: "pb", triggerSource: .manual, actor: .human, outcome: .success,
            artifactID: nil, startedAt: .now, durationSeconds: 0.1
        ))
        #expect(await store.all().count == 1)
        let latest = await store.latest(forPlaybookID: "pb")
        #expect(latest?.playbookID == "pb")
    }

    /// The durable store must resolve a `startedAt` tie the way the in-memory one does — **last
    /// recorded wins** — because both implement one protocol method and
    /// `latestPrefersTheMostRecentlyRecordedRunOnATie` pins that contract on the in-memory side.
    ///
    /// Before `sequence` existed this store fetched with no sort descriptor at all and filtered a
    /// full decode of the table, so the answer on a tie was whatever order SwiftData happened to
    /// return. Sorting on `id` would have been no better: a random UUID is not insertion order.
    ///
    /// **The ids are pinned deliberately, and the test is worthless without them.** Written with
    /// random ids this assertion passed against an `id`-ordered implementation on every run, so it
    /// guarded nothing. Here the *first* run carries the higher id, which means any implementation
    /// ranking by `id` returns `.manual` and fails — the only way to return `.schedule` is to know
    /// which row was recorded last.
    @Test
    func executionRecordLatestPrefersTheLastRecordedRunOnATie() async throws {
        let container = try await makeContainer()
        let store = SwiftDataExecutionRecordStore(modelContainer: container)
        let sameInstant = Date(timeIntervalSince1970: 1_700_000_000)
        let highID = try #require(UUID(uuidString: "FFFFFFFF-FFFF-4FFF-8FFF-FFFFFFFFFFFF"))
        let lowID = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000001"))

        await store.store(ExecutionRecord(
            id: highID,
            playbookID: "pb", triggerSource: .manual, actor: .human, outcome: .success,
            artifactID: nil, startedAt: sameInstant, durationSeconds: 0.1
        ))
        await store.store(ExecutionRecord(
            id: lowID,
            playbookID: "pb", triggerSource: .schedule, actor: .human, outcome: .success,
            artifactID: nil, startedAt: sameInstant, durationSeconds: 0.1
        ))

        #expect(await store.latest(forPlaybookID: "pb")?.triggerSource == .schedule)

        // And the ordinary case still wins on `startedAt` regardless of insertion order.
        await store.store(ExecutionRecord(
            playbookID: "pb", triggerSource: .maintenance, actor: .human, outcome: .success,
            artifactID: nil, startedAt: sameInstant.addingTimeInterval(-60), durationSeconds: 0.1
        ))
        #expect(await store.latest(forPlaybookID: "pb")?.triggerSource == .schedule)
    }

    /// Run history is capped, and the sweep keeps the newest — the row a lookup would return.
    ///
    /// This table had no retention at all while being appended to once per routine run by a
    /// background scan that fires on a cadence, which is F-24's shape exactly. Every other durable
    /// table in the file caps itself or argues in writing for not doing so.
    @Test
    func executionRecordRetentionKeepsTheNewestRunsAndDropsTheOldest() async throws {
        let container = try await makeContainer()
        let store = SwiftDataExecutionRecordStore(modelContainer: container)
        await store.setRetentionCap(3)
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        for index in 0..<10 {
            await store.store(ExecutionRecord(
                playbookID: "pb", triggerSource: .schedule, actor: .human, outcome: .success,
                artifactID: nil, startedAt: base.addingTimeInterval(Double(index)), durationSeconds: 0.1
            ))
        }

        let remaining = await store.all()
        #expect(remaining.count == 3, "retention cap should bound the table")
        // The survivors are the three newest, not an arbitrary three.
        #expect(
            Set(remaining.map(\.startedAt)) == Set([7, 8, 9].map { base.addingTimeInterval(Double($0)) })
        )
        // And the sweep never removes the row `latest` would hand back.
        #expect(await store.latest(forPlaybookID: "pb")?.startedAt == base.addingTimeInterval(9))
    }

    /// `latest` must not be shadowed by an unreadable row, which is F-32's listing-vs-`get` rule
    /// applied to the one query that now uses a bounded fetch rather than a full decode.
    @Test
    func executionRecordLatestSkipsAnUnreadableRow() async throws {
        let container = try await makeContainer()
        let store = SwiftDataExecutionRecordStore(modelContainer: container)
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        await store.store(ExecutionRecord(
            playbookID: "pb", triggerSource: .manual, actor: .human, outcome: .success,
            artifactID: nil, startedAt: base, durationSeconds: 0.1
        ))
        await store.store(ExecutionRecord(
            playbookID: "pb", triggerSource: .schedule, actor: .human, outcome: .success,
            artifactID: nil, startedAt: base.addingTimeInterval(60), durationSeconds: 0.1
        ))

        // Corrupt the newest row's blob, leaving its query columns intact — a lost or partially
        // written payload, not an edit anyone made on purpose.
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<StoredExecutionRecordRow>(
            sortBy: [SortDescriptor(\StoredExecutionRecordRow.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        let newest = try #require(try context.fetch(descriptor).first)
        newest.data = Data("not json".utf8)
        try context.save()

        let latest = await SwiftDataExecutionRecordStore(modelContainer: container)
            .latest(forPlaybookID: "pb")
        #expect(latest?.triggerSource == .manual, "an unreadable row must not hide the one behind it")
    }

    @Test
    func executionRecordPersistsActorAttribution() async throws {
        let container = try await makeContainer()
        let store = SwiftDataExecutionRecordStore(modelContainer: container)
        let scheduled = ExecutionRecord(
            playbookID: "cron", triggerSource: .schedule,
            actor: ActorRef(kind: .scheduledRoutine, identifier: "cron"),
            outcome: .success, artifactID: nil, startedAt: .now, durationSeconds: 0.1
        )
        let manual = ExecutionRecord(
            playbookID: "manual", triggerSource: .manual,
            actor: .human,
            outcome: .success, artifactID: nil, startedAt: .now, durationSeconds: 0.1
        )
        await store.store(scheduled)
        await store.store(manual)

        // Reopen the store so the assertions read back from persistence, not memory.
        let recreated = SwiftDataExecutionRecordStore(modelContainer: container)
        let persistedScheduled = try #require(await recreated.latest(forPlaybookID: "cron"))
        #expect(persistedScheduled.actor.kind == .scheduledRoutine)
        #expect(persistedScheduled.actor.identifier == "cron")
        let persistedManual = try #require(await recreated.latest(forPlaybookID: "manual"))
        #expect(persistedManual.actor.kind == .human)
    }

    /// Artifacts written before the storage change live in ``StoredArtifactRecord``, and production
    /// now reads `ArtifactStorage`'s `StoredArtifact`. Without the migration they would simply stop
    /// appearing in Mission Control, so this pins that they survive the move.
    ///
    /// The store behaviour itself is covered by `ArtifactStorageTests` — 21 tests against the
    /// hardened store, which replaced the near-copy this package used to declare. The copy's write
    /// methods returned normally when the named row was missing, which is why a lifecycle decision
    /// could be reported as recorded without having been.
    @Test
    func legacyArtifactRowsMigrateIntoTheHardenedStore() async throws {
        let container = try await makeContainer()
        let legacy = Artifact(
            id: UUID(),
            groupID: UUID(),
            version: 2,
            type: .brief,
            title: "Pre-migration brief",
            creatorPlaybookID: nil,
            creatorOperatorID: "operator.research.brief",
            createdAt: Date(timeIntervalSince1970: 1_000),
            provenance: ArtifactProvenance(actor: .system),
            relatedReceiptIDs: [UUID()],
            approvalState: .approved,
            destination: "Mission Control",
            exportFormat: "markdown",
            content: "body written by the old store"
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

        let result = LegacyArtifactMigration.run(in: container)

        #expect(result.migratedCount == 1)
        #expect(result.unreadableCount == 0)

        // Readable through the store production actually uses, with every field intact — including
        // the ones the legacy row only held inside its JSON blob.
        let store = SwiftDataArtifactStore(modelContainer: container)
        let migrated = try #require(try await store.get(id: legacy.id))
        #expect(migrated.title == "Pre-migration brief")
        #expect(migrated.content == "body written by the old store")
        #expect(migrated.version == 2)
        #expect(migrated.approvalState == .approved)
        #expect(migrated.relatedReceiptIDs == legacy.relatedReceiptIDs)
        #expect(migrated.destination == "Mission Control")

        // The legacy row is gone, and a second pass is a no-op — so this is safe to run on every
        // launch without a separate "has migrated" flag that could drift from the data.
        #expect(try context.fetch(FetchDescriptor<StoredArtifactRecord>()).isEmpty)
        #expect(LegacyArtifactMigration.run(in: container) == .noLegacyRows)
    }

    /// A legacy row this build cannot decode is left in place rather than deleted: it is the only
    /// copy of a durable work product, and "this build cannot read it" is not the same as "it should
    /// not exist". A build that understands it can still migrate it.
    @Test
    func undecodableLegacyArtifactRowIsLeftInPlace() async throws {
        let container = try await makeContainer()
        let context = ModelContext(container)
        context.insert(
            StoredArtifactRecord(
                id: UUID(),
                groupID: UUID(),
                typeRawValue: "brief",
                createdAt: Date(timeIntervalSince1970: 1_000),
                data: Data("not an artifact".utf8)
            )
        )
        try context.save()

        let result = LegacyArtifactMigration.run(in: container)

        #expect(result.migratedCount == 0)
        #expect(result.unreadableCount == 1)
        #expect(try context.fetch(FetchDescriptor<StoredArtifactRecord>()).count == 1)
    }

    /// The whole table used to move in one transaction, holding every artifact live three times
    /// over — blob, decoded value, new row's body — before anything committed. That runs on
    /// container open, including a `BGTaskScheduler` launch under a tight memory limit, so a corpus
    /// of a few hundred large artifacts is a jetsam that commits nothing and repeats forever.
    /// Several batches must still add up to the same answer, and an unreadable row (deliberately
    /// left in place) must not make the window re-read the page it is on.
    @Test
    func legacyArtifactRowsMigrateAcrossSeveralBatches() async throws {
        let container = try await makeContainer()
        let context = ModelContext(container)
        for index in 0..<7 {
            context.insert(try legacyArtifactRow(title: "artifact-\(index)"))
        }
        context.insert(
            StoredArtifactRecord(
                id: UUID(),
                groupID: UUID(),
                typeRawValue: "brief",
                createdAt: Date(timeIntervalSince1970: 1_000),
                data: Data("not an artifact".utf8)
            )
        )
        try context.save()

        let result = LegacyArtifactMigration.run(in: container, batchSize: 3)

        #expect(result.migratedCount == 7)
        #expect(result.unreadableCount == 1)
        #expect(result.didFail == false)
        #expect(try context.fetchCount(FetchDescriptor<StoredArtifact>()) == 7)
        // Only the row this build cannot read is left behind — the window stepped over it instead
        // of fetching its page again, which is also what stops the loop spinning.
        #expect(try context.fetchCount(FetchDescriptor<StoredArtifactRecord>()) == 1)
    }

    /// Batching is only worth anything if progress survives the interruption it exists for. A pass
    /// cut short keeps everything it committed, and leaves every row it did not reach exactly where
    /// the next pass looks for it — no artifact half-copied, none present in both tables.
    @Test
    func anInterruptedMigrationPassKeepsItsCommittedRowsAndLeavesTheRest() async throws {
        let container = try await makeContainer()
        let context = ModelContext(container)
        for index in 0..<7 {
            context.insert(try legacyArtifactRow(title: "artifact-\(index)"))
        }
        try context.save()

        let interrupted = LegacyArtifactMigration.run(in: container, batchSize: 3, stoppingAfterBatches: 2)

        #expect(interrupted.migratedCount == 6)
        #expect(try context.fetchCount(FetchDescriptor<StoredArtifact>()) == 6)
        #expect(try context.fetchCount(FetchDescriptor<StoredArtifactRecord>()) == 1)

        // The next pass picks the remainder up verbatim and does not re-copy what already moved.
        let resumed = LegacyArtifactMigration.run(in: container, batchSize: 3)

        #expect(resumed.migratedCount == 1)
        #expect(resumed.skippedExistingCount == 0)
        #expect(try context.fetchCount(FetchDescriptor<StoredArtifact>()) == 7)
        #expect(try context.fetchCount(FetchDescriptor<StoredArtifactRecord>()) == 0)
        #expect(LegacyArtifactMigration.run(in: container) == .noLegacyRows)
    }

    /// A healthy pass with nothing to do must stay distinguishable from a failed one.
    ///
    /// All three hard-failure paths used to return ``LegacyArtifactMigration/Result/noLegacyRows``,
    /// which is also this value, so a caller could not tell "nothing to migrate" from "the
    /// migration failed and every pre-upgrade artifact is still invisible". The failing side of
    /// that pair is unpinned: a read or a commit this package can make fail is not reachable
    /// in-memory — see the note above ``makeContainer()``.
    @Test
    func anEmptyMigrationPassReportsNoLegacyRowsAndNotAFailure() async throws {
        let container = try await makeContainer()

        let result = LegacyArtifactMigration.run(in: container)

        #expect(result == .noLegacyRows)
        #expect(result.didFail == false)
        #expect(LegacyArtifactMigration.Result.failure != .noLegacyRows)
    }

    @Test
    func worklogStorePersistsCorrelatedSteps() async throws {
        let container = try await makeContainer()
        let store = SwiftDataWorklogStore(modelContainer: container)
        let step = WorkflowStepLog(
            correlationID: "corr",
            toolID: "tool",
            event: .proposed(ActionProposal(actor: .system, intent: "Read", capability: .audioPlayback, impact: .readOnly)),
            actor: .system
        )
        await store.record(step)

        let recreated = SwiftDataWorklogStore(modelContainer: container)
        #expect(await recreated.allSteps().count == 1)
        #expect(await recreated.steps(forCorrelationID: "corr").first?.toolID == "tool")
        await recreated.resetAll()
        #expect(await recreated.allSteps().isEmpty)
    }

    /// The export is what evals and report cards carry off-device, so it has to be complete, ordered
    /// oldest-first, and byte-identical for the same trace — not just "some JSON".
    @Test
    func worklogExportIsCompleteOrderedAndByteStable() async throws {
        let container = try await makeContainer()
        let store = SwiftDataWorklogStore(modelContainer: container)
        let base = Date(timeIntervalSince1970: 1_000)
        // Recorded newest-first, so an export that merely echoed store order would come out reversed.
        await store.record(worklogStep("corr", event: .blocked(reason: "late"), at: base + 2))
        await store.record(worklogStep("corr", event: .proposed(proposal()), at: base))

        let data = try await store.exportAll()
        let decoded = try JSONDecoder().decode([WorkflowStepLog].self, from: data)
        #expect(decoded.count == 2)
        #expect(decoded.map(\.timestamp) == [base, base + 2])

        // Same trace, fresh store handle: the bytes must match, or diffing two eval runs is noise.
        let again = try await SwiftDataWorklogStore(modelContainer: container).exportAll()
        #expect(again == data)
    }

    /// Retention drops whole *completed* workflows, oldest first, and never touches a trace that has
    /// not finished — pruning by row would decapitate a live trace and make `steps(forCorrelationID:)`
    /// read as though the workflow started midway.
    @Test
    func worklogRetentionDropsOldestCompletedWorkflowsAndKeepsUnfinishedOnes() async throws {
        let container = try await makeContainer()
        let store = SwiftDataWorklogStore(modelContainer: container)
        let base = Date(timeIntervalSince1970: 1_000)

        // Oldest: completed. Then: still running. Newest: completed.
        await store.record(worklogStep("old", event: .proposed(proposal()), at: base))
        await store.record(worklogStep("old", event: .executed(artifactID: UUID(), durationSeconds: 1), at: base + 1))
        await store.record(worklogStep("running", event: .proposed(proposal()), at: base + 2))
        await store.record(worklogStep("running", event: .checksEvaluated([]), at: base + 3))
        await store.record(worklogStep("new", event: .proposed(proposal()), at: base + 4))
        await store.record(worklogStep("new", event: .executed(artifactID: UUID(), durationSeconds: 1), at: base + 5))
        #expect(await store.allSteps().count == 6)

        await store.pruneCompletedWorkflows(keepingAtMost: 5)

        // Only the oldest completed workflow goes, and it goes whole.
        #expect(await store.steps(forCorrelationID: "old").isEmpty)
        #expect(await store.steps(forCorrelationID: "running").count == 2)
        #expect(await store.steps(forCorrelationID: "new").count == 2)

        // Below the cap the newest completed workflow survives; the unfinished one is never eligible,
        // so the cap is deliberately soft rather than deleting evidence of stalled work.
        await store.pruneCompletedWorkflows(keepingAtMost: 1)
        #expect(await store.steps(forCorrelationID: "new").isEmpty)
        #expect(await store.steps(forCorrelationID: "running").count == 2)
    }

    /// A blocked or failed trace is exactly what debugging needs, so retention must not treat
    /// "terminal" as "droppable".
    @Test
    func worklogRetentionKeepsBlockedAndFailedWorkflows() async throws {
        let container = try await makeContainer()
        let store = SwiftDataWorklogStore(modelContainer: container)
        let base = Date(timeIntervalSince1970: 2_000)

        await store.record(worklogStep("blocked", event: .blocked(reason: "policy"), at: base))
        await store.record(worklogStep("failed", event: .failed(reason: "network"), at: base + 1))
        await store.record(worklogStep("routine", event: .routinePhase(.failed, detail: nil), at: base + 2))

        await store.pruneCompletedWorkflows(keepingAtMost: 0)

        #expect(await store.allSteps().count == 3)
    }

    /// The retention sweep is O(rows) — it fetches the whole table and decodes candidate groups.
    /// Because the cap is deliberately soft, "over the cap with nothing droppable" is a steady state
    /// the design intends to reach, so sweeping on every subsequent write would make every worklog
    /// write O(rows) for as long as the device stayed there. This pins the backoff that prevents it.
    @Test
    func worklogWritesDoNotResweepWhenNothingCanBeDropped() async throws {
        let container = try await makeContainer()
        let store = SwiftDataWorklogStore(modelContainer: container)
        await store.setRetentionCap(4)
        let base = Date(timeIntervalSince1970: 3_000)

        // Five unfinished workflows: over the cap, and not one of them is eligible to drop.
        for offset in 0..<5 {
            await store.record(worklogStep("stalled-\(offset)", event: .blocked(reason: "policy"), at: base + Double(offset)))
        }
        // The sweep ran, found nothing, and recorded the size it gave up at.
        #expect(await store.unprunableFloor == 5)

        // The next write must skip the sweep entirely. Had it swept, it would have re-measured and
        // moved the floor to 6.
        await store.record(worklogStep("stalled-5", event: .blocked(reason: "policy"), at: base + 5))
        #expect(await store.unprunableFloor == 5)
        #expect(await store.allSteps().count == 6)
    }

    /// The backoff must not outlast its own premise: a step that completes a workflow is precisely
    /// what makes a group droppable, so it has to re-arm the sweep on that write rather than leave
    /// the store sitting over the cap for another `pruneRetryGrowth` entries.
    @Test
    func aCompletingStepClearsTheBackoffImmediately() async throws {
        let container = try await makeContainer()
        let store = SwiftDataWorklogStore(modelContainer: container)
        await store.setRetentionCap(4)
        let base = Date(timeIntervalSince1970: 4_000)

        await store.record(worklogStep("finishes", event: .proposed(proposal()), at: base))
        for offset in 1..<5 {
            await store.record(worklogStep("stalled-\(offset)", event: .blocked(reason: "policy"), at: base + Double(offset)))
        }
        #expect(await store.unprunableFloor == 5)

        // Completing "finishes" makes its group eligible, so this write sweeps despite the backoff.
        await store.record(
            worklogStep("finishes", event: .executed(artifactID: UUID(), durationSeconds: 1), at: base + 5)
        )

        #expect(await store.steps(forCorrelationID: "finishes").isEmpty)
        #expect(await store.allSteps().count == 4)
        // Back under the cap, so the backoff is disarmed rather than left pointing at a stale size.
        #expect(await store.unprunableFloor == nil)
    }

    /// Pruning is deletion, and a step this build cannot interpret is exactly the evidence worth
    /// keeping. A downgrade must not be able to delete the trace of work it never understood.
    @Test
    func retentionNeverDropsAWorkflowWhoseTraceIsUnrecognized() async throws {
        let container = try await makeContainer()
        let store = SwiftDataWorklogStore(modelContainer: container)
        let base = Date(timeIntervalSince1970: 5_000)

        // An event kind from a newer build, which now decodes as `.unknown` rather than being lost.
        let future = try JSONDecoder().decode(
            WorkflowStepLog.self,
            from: Data(#"""
            {
              "id": "C0FFEE00-1111-4222-8333-444455556666",
              "correlationID": "future",
              "toolID": "tool.future",
              "event": { "delegated": { "to": "peer-agent" } },
              "actor": { "kind": "operator", "identifier": "future.operator" },
              "timestamp": 1000
            }
            """#.utf8)
        )
        await store.record(future)
        await store.record(worklogStep("done", event: .executed(artifactID: UUID(), durationSeconds: 1), at: base))

        await store.pruneCompletedWorkflows(keepingAtMost: 0)

        // The completed workflow goes; the unrecognized one stays.
        #expect(await store.steps(forCorrelationID: "done").isEmpty)
        #expect(await store.steps(forCorrelationID: "future").count == 1)
    }

    @Test
    func performanceAndExecutionRecordStoresReset() async throws {
        let container = try await makeContainer()
        let performance = SwiftDataPerformanceStore(modelContainer: container)
        let executions = SwiftDataExecutionRecordStore(modelContainer: container)

        await performance.record(PerformanceEvent(playbookID: "p", outcome: .success, durationSeconds: 1))
        await executions.store(ExecutionRecord(
            playbookID: "p", triggerSource: .manual, actor: .human, outcome: .success,
            artifactID: nil, startedAt: .now, durationSeconds: 0.1
        ))
        #expect(await performance.events(forPlaybook: "p").isEmpty == false)
        #expect(await executions.all().isEmpty == false)

        await performance.resetAll()
        await executions.resetAll()

        let recreatedPerformance = SwiftDataPerformanceStore(modelContainer: container)
        let recreatedExecutions = SwiftDataExecutionRecordStore(modelContainer: container)
        #expect(await recreatedPerformance.allHealth().isEmpty)
        #expect(await recreatedExecutions.all().isEmpty)
    }

    /// The durable half of the guarantee `RuntimePerformanceObserver` leans on for cross-process
    /// replay: it reuses the runtime event envelope's ID as the performance event ID and checkpoints
    /// only *after* recording, so a crash in between replays that event on the next launch. Recording
    /// it again must update the run rather than inflate the planner bucket's run count.
    @Test
    func performanceStoreRecordingIsIdempotentByEventID() async throws {
        let container = try await makeContainer()
        let store = SwiftDataPerformanceStore(modelContainer: container)
        let id = UUID()

        await store.record(PerformanceEvent(id: id, playbookID: "planner", outcome: .success, durationSeconds: 1))
        await store.record(PerformanceEvent(playbookID: "planner", outcome: .success, durationSeconds: 1))
        await store.record(
            PerformanceEvent(
                id: id,
                playbookID: "planner",
                outcome: .failed,
                durationSeconds: 2,
                failureReason: "no candidate cleared"
            )
        )

        // Re-read through a fresh store so the assertion is about what actually landed on disk.
        let reopened = SwiftDataPerformanceStore(modelContainer: container)
        let health = await reopened.health(forPlaybook: "planner")
        #expect(health.totalRuns == 2)
        #expect(health.failureCount == 1)
        let replayed = await reopened.events(forPlaybook: "planner").first { $0.id == id }
        #expect(replayed?.failureReason == "no candidate cleared")
    }

    /// The other half of the replay contract, and the half that only this store can honour.
    ///
    /// `RuntimePerformanceObserver` checkpoints *after* recording, so a crash in between replays the
    /// event on the next launch — and a replay is rebuilt from the runtime envelope, so it always
    /// arrives with `requiredIntervention == false` and `approvalDecision == nil`. The in-memory
    /// `PerformanceStore` folds the stored annotations back in (pinned by its own
    /// `replayDoesNotEraseHumanAnnotations`), but its state dies with the process, so the
    /// cross-launch replay it guards against can only actually happen *here*. Overwriting wholesale
    /// erased the person's approval from `approvalRate` and their intervention from
    /// `interventionRate`.
    @Test
    func performanceReplayPreservesHumanAnnotations() async throws {
        let container = try await makeContainer()
        let store = SwiftDataPerformanceStore(modelContainer: container)
        let id = UUID()
        let runID = UUID()
        let event = PerformanceEvent(
            id: id, playbookID: "planner", outcome: .needsApproval, durationSeconds: 1, runID: runID
        )

        await store.record(event)
        await store.recordIntervention(runID: runID)
        await store.recordApprovalDecision(runID: runID, decision: .approved)

        // The replay: same envelope ID, reconstructed, so unannotated.
        await store.record(event)

        // Read back through a fresh handle, so the assertion is about what landed on disk.
        let reopened = SwiftDataPerformanceStore(modelContainer: container)
        let replayed = await reopened.events(forPlaybook: "planner")
        #expect(replayed.count == 1, "the replay must update the run, not add one")
        #expect(replayed.first?.requiredIntervention == true)
        #expect(replayed.first?.approvalDecision == .approved)
        let health = await reopened.health(forPlaybook: "planner")
        #expect(health.interventionRate == 1)
        #expect(health.resolvedApprovalCount == 1)
    }

    /// An incoming decision must still win, or a replay would pin the first answer forever. Matches
    /// `PerformanceStore`'s `reRecordedDecisionWins`.
    @Test
    func performanceReRecordedDecisionOverridesTheStoredOne() async throws {
        let container = try await makeContainer()
        let store = SwiftDataPerformanceStore(modelContainer: container)
        let id = UUID()
        let runID = UUID()

        await store.record(PerformanceEvent(
            id: id, playbookID: "pb", outcome: .needsApproval, durationSeconds: 1, runID: runID
        ))
        await store.recordApprovalDecision(runID: runID, decision: .rejected)
        await store.record(PerformanceEvent(
            id: id, playbookID: "pb", outcome: .needsApproval, durationSeconds: 1, runID: runID,
            approvalDecision: .approved
        ))

        #expect(await store.events(forPlaybook: "pb").first?.approvalDecision == .approved)
    }

    /// Intervention is a property of the *run*, and one run makes several governed tool calls, so
    /// every event belonging to it carries the flag. Marking only one understates `interventionRate`
    /// by however many calls the run made — the divergence `PerformanceStore` cites this store for.
    @Test
    func performanceInterventionMarksEveryEventOfTheRun() async throws {
        let container = try await makeContainer()
        let store = SwiftDataPerformanceStore(modelContainer: container)
        let runID = UUID()
        for _ in 0..<3 {
            await store.record(PerformanceEvent(
                playbookID: "pb", outcome: .success, durationSeconds: 1, runID: runID
            ))
        }
        await store.record(PerformanceEvent(
            playbookID: "pb", outcome: .success, durationSeconds: 1, runID: UUID()
        ))

        await store.recordIntervention(runID: runID)

        let reopened = SwiftDataPerformanceStore(modelContainer: container)
        #expect(await reopened.events(forPlaybook: "pb").filter(\.requiredIntervention).count == 3)
        #expect(await reopened.health(forPlaybook: "pb").interventionRate == 0.75)
    }

    /// A person makes one decision per run, so it lands on the run's **last** event — and "last"
    /// has to mean last *recorded*, the way `PerformanceStore` resolves it by insertion position.
    ///
    /// **The ids are pinned deliberately.** The first-recorded event carries the higher id, so an
    /// implementation ranking by `id` marks the wrong row and fails here. Note what this test can
    /// and cannot catch: the previous implementation sorted on *nothing* and took the last row of
    /// the fetch, which SQLite will often hand back in insertion order, so it would likely have
    /// passed by luck. The point of `sequence` is that the answer is now ordered by construction
    /// rather than by what the storage engine happened to do.
    @Test
    func performanceApprovalDecisionLandsOnTheLastRecordedEventOfTheRun() async throws {
        let container = try await makeContainer()
        let store = SwiftDataPerformanceStore(modelContainer: container)
        let runID = UUID()
        let sameInstant = Date(timeIntervalSince1970: 1_700_000_000)
        let highID = try #require(UUID(uuidString: "FFFFFFFF-FFFF-4FFF-8FFF-FFFFFFFFFFFF"))
        let lowID = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000001"))

        await store.record(PerformanceEvent(
            id: highID, playbookID: "pb", outcome: .needsApproval, durationSeconds: 1,
            recordedAt: sameInstant, runID: runID
        ))
        await store.record(PerformanceEvent(
            id: lowID, playbookID: "pb", outcome: .needsApproval, durationSeconds: 1,
            recordedAt: sameInstant, runID: runID
        ))

        await store.recordApprovalDecision(runID: runID, decision: .approved)

        let reopened = SwiftDataPerformanceStore(modelContainer: container)
        let decided = await reopened.events(forPlaybook: "pb").filter { $0.approvalDecision != nil }
        #expect(decided.map(\.id) == [lowID], "the decision belongs to the last recorded event")
        // Exactly one, or one person's single decision would be weighted N times in `approvalRate`.
        #expect(await reopened.health(forPlaybook: "pb").resolvedApprovalCount == 1)
    }

    /// A replay must not re-rank the run's events: `sequence` **is** the recorded insertion position,
    /// so it is what reproduces `PerformanceStore`'s `lastIndex(where:)`, and `recordedAt` as the
    /// primary key can only disagree with it.
    ///
    /// The trigger is the merge branch of ``SwiftDataPerformanceStore/record(_:)``, which writes
    /// `existing.recordedAt` from the incoming event while deliberately leaving `sequence` alone so a
    /// re-recorded run keeps its position in history. Replaying the run's *first* event therefore
    /// leaves row A holding the newest `recordedAt` and the oldest `sequence`. Ranking by
    /// `recordedAt` first made the durable store annotate A while the in-memory store annotated B —
    /// one protocol method with two answers, and `PlaybookHealth.approvalRate` then averaged over
    /// different events on a device with a SwiftData container than on one without. That is the
    /// F-26/F-59 class, and the same divergence follows from any caller passing a non-monotonic
    /// explicit `recordedAt`, which the public parameter allows.
    ///
    /// Both implementations are driven from one script here, so their agreement is asserted rather
    /// than assumed — the previous test pins the tie-break, this one pins the disagreement.
    @Test
    func performanceApprovalDecisionFollowsInsertionOrderAcrossAReplay() async throws {
        let container = try await makeContainer()
        let durable = SwiftDataPerformanceStore(modelContainer: container)
        let inMemory = PerformanceStore()
        let runID = UUID()
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)

        let eventA = PerformanceEvent(
            playbookID: "pb", outcome: .needsApproval, durationSeconds: 1,
            recordedAt: epoch, runID: runID
        )
        let eventB = PerformanceEvent(
            playbookID: "pb", outcome: .needsApproval, durationSeconds: 1,
            recordedAt: epoch.addingTimeInterval(1), runID: runID
        )
        // The replay: A's envelope, rebuilt on the next launch, so it arrives under A's id carrying a
        // later clock reading than B. Both stores fold it in place rather than appending.
        let replayedA = PerformanceEvent(
            id: eventA.id, playbookID: "pb", outcome: .needsApproval, durationSeconds: 1,
            recordedAt: epoch.addingTimeInterval(2), runID: runID
        )

        for event in [eventA, eventB, replayedA] {
            await durable.record(event)
            await inMemory.record(event)
        }
        await durable.recordApprovalDecision(runID: runID, decision: .approved)
        await inMemory.recordApprovalDecision(runID: runID, decision: .approved)

        // Read back through a fresh handle, so the assertion is about what landed on disk.
        let reopened = SwiftDataPerformanceStore(modelContainer: container)
        let durableDecided = await reopened.events(forPlaybook: "pb")
            .filter { $0.approvalDecision != nil }.map(\.id)
        let inMemoryDecided = await inMemory.events(forPlaybook: "pb")
            .filter { $0.approvalDecision != nil }.map(\.id)

        #expect(durableDecided == [eventB.id], "the decision belongs to the last *recorded* event")
        #expect(durableDecided == inMemoryDecided, "one protocol method must not have two answers")
        #expect(await reopened.health(forPlaybook: "pb").resolvedApprovalCount == 1)
    }

    /// This table had no retention at all while being the highest-volume durable table in the file:
    /// `PerformancePipelineSink` writes a row for every terminal governed tool call. The in-memory
    /// `PerformanceStore` already caps itself; this one grew for the life of the install.
    @Test
    func performanceRetentionKeepsTheNewestEventsAndDropsTheOldest() async throws {
        let container = try await makeContainer()
        let store = SwiftDataPerformanceStore(modelContainer: container)
        await store.setRetentionCap(3)
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        for index in 0..<10 {
            await store.record(PerformanceEvent(
                playbookID: "pb", outcome: .success, durationSeconds: 1,
                recordedAt: base.addingTimeInterval(Double(index))
            ))
        }

        let remaining = await SwiftDataPerformanceStore(modelContainer: container)
            .events(forPlaybook: "pb")
        #expect(remaining.count == 3, "retention cap should bound the table")
        #expect(remaining.map(\.recordedAt) == [7, 8, 9].map { base.addingTimeInterval(Double($0)) })
    }

    /// A burst recorded in one instant must still be prunable.
    ///
    /// Guards the failure mode `PerformanceStore.trimToCapacity` calls out for its own in-memory
    /// trim: a *date-cutoff* sweep cannot separate ties, so a burst sharing one timestamp — or a
    /// caller backdating everything to one `Date` — leaves nothing droppable and quietly restores
    /// the unbounded growth the cap exists to stop. The implementation here ranks and limits rather
    /// than cutting off by date, so this pins that choice against a future rewrite.
    @Test
    func performanceRetentionStillPrunesEventsSharingOneInstant() async throws {
        let container = try await makeContainer()
        let store = SwiftDataPerformanceStore(modelContainer: container)
        await store.setRetentionCap(3)
        let sameInstant = Date(timeIntervalSince1970: 1_700_000_000)

        for _ in 0..<10 {
            await store.record(PerformanceEvent(
                playbookID: "pb", outcome: .success, durationSeconds: 1, recordedAt: sameInstant
            ))
        }

        #expect(await store.events(forPlaybook: "pb").count == 3)
    }

    /// A row written before the query columns existed carries the `.distantPast` sentinel and a nil
    /// `runID`, so a predicate cannot match it. Until the backfill fills it in, a person's
    /// intervention on a pre-upgrade run would silently find nothing to mark.
    @Test
    func performanceBackfillMakesPreColumnRowsReachableByRun() async throws {
        let container = try await makeContainer()
        let runID = UUID()
        let event = PerformanceEvent(
            playbookID: "pb", outcome: .success, durationSeconds: 1,
            recordedAt: Date(timeIntervalSince1970: 1_700_000_000), runID: runID
        )
        // Written the way the pre-column build wrote it: blob populated, query columns at defaults.
        let context = ModelContext(container)
        context.insert(StoredPerformanceEventRecord(
            id: event.id,
            playbookID: event.playbookID,
            runID: nil,
            sequence: 0,
            recordedAt: .distantPast,
            data: try JSONEncoder().encode(event)
        ))
        try context.save()

        let store = SwiftDataPerformanceStore(modelContainer: container)
        await store.recordIntervention(runID: runID)

        let marked = await SwiftDataPerformanceStore(modelContainer: container)
            .events(forPlaybook: "pb")
        #expect(marked.count == 1)
        #expect(marked.first?.requiredIntervention == true, "a pre-column row must still be markable")
    }

    /// The same backfill invariant for run history: `latest(forPlaybookID:)` matches on the
    /// `playbookID` column, so a row written before that column existed is invisible to the trigger
    /// evaluator — it would read as "this routine has never run" and re-fire a due routine.
    @Test
    func executionRecordBackfillMakesPreColumnRowsReachableByPlaybook() async throws {
        let container = try await makeContainer()
        let record = ExecutionRecord(
            playbookID: "pb", triggerSource: .schedule, actor: .human, outcome: .success,
            artifactID: nil, startedAt: Date(timeIntervalSince1970: 1_700_000_000), durationSeconds: 0.1
        )
        let context = ModelContext(container)
        context.insert(StoredExecutionRecordRow(
            id: record.id,
            playbookID: "",
            startedAt: .distantPast,
            sequence: 0,
            data: try JSONEncoder().encode(record)
        ))
        try context.save()

        let store = SwiftDataExecutionRecordStore(modelContainer: container)
        #expect(await store.latest(forPlaybookID: "pb")?.id == record.id)
    }

    /// Actor attribution on a worklog entry has to survive the JSON blob round-trip (P0.5-602).
    /// The store decodes with `try?` and `compactMap`s the failures away, so an attribution that
    /// fails to decode silently deletes the entry rather than surfacing an error.
    @Test
    func worklogStorePersistsActorAttribution() async throws {
        let container = try await makeContainer()
        let store = SwiftDataWorklogStore(modelContainer: container)
        let routine = ActorRef(
            kind: .scheduledRoutine,
            identifier: "morning.brief",
            displayName: "Morning Brief"
        )
        let model = ActorRef.model(
            identifier: "planner.model",
            inference: InferenceProvenance(locality: .remote, provider: "anthropic", modelClass: "opus")
        )
        await store.record(
            WorkflowStepLog(
                correlationID: "corr-actor",
                toolID: "routine.tool",
                event: .executed(artifactID: UUID(), durationSeconds: 1.5),
                actor: routine
            )
        )
        await store.record(
            WorkflowStepLog(
                correlationID: "corr-actor",
                toolID: "planner.tool",
                event: .blocked(reason: "policy"),
                actor: model
            )
        )

        let recreated = SwiftDataWorklogStore(modelContainer: container)
        let steps = await recreated.steps(forCorrelationID: "corr-actor")
        // Both entries survive: a dropped attribution would show up here as a missing step.
        #expect(steps.count == 2)

        let reloadedRoutine = try #require(steps.first { $0.toolID == "routine.tool" }).actor
        #expect(reloadedRoutine == routine)
        #expect(reloadedRoutine.kind == .scheduledRoutine)
        #expect(reloadedRoutine.identifier == "morning.brief")
        #expect(reloadedRoutine.displayName == "Morning Brief")

        let reloadedModel = try #require(steps.first { $0.toolID == "planner.tool" }).actor
        #expect(reloadedModel == model)
        #expect(reloadedModel.inference?.locality == .remote)
        #expect(reloadedModel.inference?.provider == "anthropic")
        #expect(reloadedModel.inference?.modelClass == "opus")
    }

    /// The authority a worklog entry happened under has to survive the JSON blob round-trip too, and
    /// entries written before the column existed must still decode rather than being dropped by the
    /// store's `try?` (P0.5-601/602).
    @Test
    func worklogStorePersistsAuthorityAttribution() async throws {
        let container = try await makeContainer()
        let store = SwiftDataWorklogStore(modelContainer: container)
        let expiry = Date(timeIntervalSince1970: 1_800_000_000)
        let lease = CapabilityLease(
            capability: .playbackQueue,
            reason: "Planner may queue playback.",
            grantedTo: ActorRef(kind: .workflow, identifier: "planner"),
            expiresAt: expiry
        )
        await store.record(
            WorkflowStepLog(
                correlationID: "corr-authority",
                toolID: "authorized.tool",
                event: .executed(artifactID: UUID(), durationSeconds: 0.5),
                actor: ActorRef(kind: .workflow, identifier: "planner"),
                authority: AuthorityRef(lease: lease)
            )
        )
        // A pre-authority entry: recorded before any grant is consulted, so it carries none.
        await store.record(
            WorkflowStepLog(
                correlationID: "corr-authority",
                toolID: "unauthorized.tool",
                event: .blocked(reason: "no lease"),
                actor: ActorRef(kind: .workflow, identifier: "planner")
            )
        )

        let recreated = SwiftDataWorklogStore(modelContainer: container)
        let steps = await recreated.steps(forCorrelationID: "corr-authority")
        #expect(steps.count == 2)

        let authority = try #require(steps.first { $0.toolID == "authorized.tool" }?.authority)
        #expect(authority.source == .lease)
        #expect(authority.leaseID == lease.id)
        #expect(authority.capability == .playbackQueue)
        #expect(authority.scope == .execution)
        #expect(authority.reason == "Planner may queue playback.")
        #expect(authority.expiresAt == expiry)

        #expect(try #require(steps.first { $0.toolID == "unauthorized.tool" }).authority == nil)
    }

    /// A worklog row persisted before the authority column existed has no `authority` key at all.
    /// The tolerant decoder must read it back rather than throwing, because the store `compactMap`s
    /// decode failures away — a throw here would silently erase history.
    @Test
    func legacyWorklogPayloadWithoutAuthorityStillDecodes() throws {
        let json = Data(#"""
        {
          "id": "1E1B4E52-9C7B-4B2F-9E4A-8D3C5F7A1B20",
          "correlationID": "corr-legacy",
          "toolID": "legacy.tool",
          "event": { "blocked": { "reason": "old" } },
          "actor": { "kind": "workflow", "identifier": "planner" },
          "timestamp": 750000000
        }
        """#.utf8)

        let decoded = try JSONDecoder().decode(WorkflowStepLog.self, from: json)
        #expect(decoded.correlationID == "corr-legacy")
        #expect(decoded.actor.kind == .workflow)
        #expect(decoded.authority == nil)
    }

    @Test
    func agentSessionStorePersistsAndResetsSessions() async throws {
        let container = try await makeContainer()
        let store = SwiftDataAgentSessionStore(modelContainer: container)
        let sessionActor = ActorRef(
            kind: .workflow,
            identifier: "runtime.report",
            displayName: "Runtime Report"
        )
        var session = AgentSession(
            correlationID: "corr-session",
            goal: "Prepare runtime report",
            actor: sessionActor
        )
        session.note(capability: .runPlugin)
        session.note(model: "Apple Foundation Models - local-language-model", cost: 0, promptTokens: 12, completionTokens: 4)
        session.note(memoryTouch: AgentSessionMemoryTouch(kind: .memoryRead, key: "memory.playbackQueue"))
        await store.upsert(session)

        let recreated = SwiftDataAgentSessionStore(modelContainer: container)
        let loaded = try #require(await recreated.session(correlationID: "corr-session"))
        #expect(loaded.goal == "Prepare runtime report")
        // A session is the other "run" concept alongside ExecutionRecord, so its attribution has to
        // survive the JSON blob round-trip too (P0.5-602). Asserted against the whole ref, not just
        // the kind, so a decode that silently degrades to the `.system` legacy fallback fails here.
        #expect(loaded.actor == sessionActor)
        #expect(loaded.actor.kind == .workflow)
        #expect(loaded.actor.identifier == "runtime.report")
        #expect(loaded.capabilities == [.runPlugin])
        #expect(loaded.modelsUsed == ["Apple Foundation Models - local-language-model"])
        #expect(loaded.totalTokens == 16)
        #expect(loaded.memoryTouched.map(\.key) == ["memory.playbackQueue"])
        #expect(await recreated.allSessions().map(\.correlationID) == ["corr-session"])

        await recreated.resetAll()
        #expect(await recreated.allSessions().isEmpty)
    }

    /// Sessions were written one per correlation ID for every governed session and never removed.
    /// Retention drops the oldest *completed* ones only: `.failed` and `.blocked` are the sessions
    /// worth keeping, and `.active` / `.waitingForApproval` are live work — dropping the latter
    /// would discard a person's pending approval rather than a record of one.
    @Test
    func agentSessionRetentionDropsOldestCompletedSessionsAndKeepsTheRest() async throws {
        let container = try await makeContainer()
        let store = SwiftDataAgentSessionStore(modelContainer: container)
        await store.setRetentionCap(1)
        let base = Date(timeIntervalSince1970: 6_000)

        func session(
            _ correlationID: String,
            at startedAt: Date,
            _ terminate: (inout AgentSession) -> Void = { _ in }
        ) -> AgentSession {
            var session = AgentSession(
                correlationID: correlationID,
                goal: "goal",
                actor: ActorRef(kind: .workflow, identifier: "planner"),
                startedAt: startedAt
            )
            terminate(&session)
            return session
        }

        await store.upsert(session("done-old", at: base) { $0.complete() })
        await store.upsert(session("done-new", at: base + 1) { $0.complete() })
        await store.upsert(session("failed", at: base + 2) { $0.fail() })
        await store.upsert(session("waiting", at: base + 3) { $0.markWaitingForApproval() })
        // One more write, so the row that crossed the cap is not the spared one.
        await store.upsert(session("active", at: base + 4))

        let ids = Set(await SwiftDataAgentSessionStore(modelContainer: container)
            .allSessions().map(\.correlationID))
        #expect(ids == ["done-new", "failed", "waiting", "active"])
    }

    @Test
    func runtimeEventHistoryPersistsAndResetsEvents() async throws {
        let container = try await makeContainer()
        let store = SwiftDataRuntimeEventHistoryStore(modelContainer: container)
        let start = Date(timeIntervalSince1970: 1_000)
        let first = WorkflowEventEnvelope(event: .workflowStarted, correlationID: "corr-history", timestamp: start)
        let second = WorkflowEventEnvelope(
            event: .executionUpdate("done"),
            correlationID: "corr-history",
            timestamp: start.addingTimeInterval(1)
        )
        try await store.append(first)
        try await store.append(second)

        let recreated = SwiftDataRuntimeEventHistoryStore(modelContainer: container)
        #expect(await recreated.recentEvents(limit: 1) == [second])
        #expect(await recreated.recentEvents(limit: 10) == [second, first])

        await recreated.resetAll()
        #expect(await recreated.recentEvents(limit: 10).isEmpty)
    }

    @Test
    func runtimeEventHistoryPreservesAppendOrderWhenTimestampsMatch() async throws {
        let container = try await makeContainer()
        let store = SwiftDataRuntimeEventHistoryStore(modelContainer: container)
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let first = WorkflowEventEnvelope(event: .executionUpdate("first"), timestamp: timestamp)
        let second = WorkflowEventEnvelope(event: .executionUpdate("second"), timestamp: timestamp)

        try await store.append(first)
        try await store.append(second)

        #expect(await store.recentEvents(limit: 10) == [second, first])
    }

    @Test(arguments: [0, -1, Int.min])
    func runtimeEventHistoryRejectsNonPositiveReadLimits(limit: Int) async throws {
        let container = try await makeContainer()
        let store = SwiftDataRuntimeEventHistoryStore(modelContainer: container)
        try await store.append(WorkflowEventEnvelope(event: .workflowStarted))

        #expect(await store.recentEvents(limit: limit).isEmpty)
    }

    @Test
    func runtimeEventHistoryPrunesOnlyAfterExpandedRetentionLimit() async throws {
        let container = try await makeContainer()
        let store = SwiftDataRuntimeEventHistoryStore(modelContainer: container)
        let start = Date(timeIntervalSince1970: 3_000)
        let eventCount = SwiftDataRuntimeEventHistoryStore.maximumStoredEvents + 5

        for offset in 0..<eventCount {
            try await store.append(WorkflowEventEnvelope(
                event: .executionUpdate("event-\(offset)"),
                correlationID: "corr-pruned",
                timestamp: start.addingTimeInterval(TimeInterval(offset))
            ))
        }

        let recreated = SwiftDataRuntimeEventHistoryStore(modelContainer: container)
        let events = await recreated.recentEvents(limit: eventCount)
        #expect(events.count == SwiftDataRuntimeEventHistoryStore.maximumStoredEvents)
        #expect(events.first?.timestamp == start.addingTimeInterval(TimeInterval(eventCount - 1)))
        #expect(events.last?.timestamp == start.addingTimeInterval(5))
        #expect(!events.contains { envelope in
            if case .executionUpdate("event-0") = envelope.event { return true }
            return false
        })
    }

    @Test
    func capabilityLeaseStorePersistsRevocationsAndRestrictions() async throws {
        let container = try await makeContainer()
        let store = SwiftDataCapabilityLeaseStore(modelContainer: container)
        let start = Date(timeIntervalSince1970: 2_000)
        var lease = CapabilityLease(
            capability: .playbackQueue,
            reason: "Planner may read the queue while preparing a recommendation.",
            grantedTo: ActorRef(kind: .workflow, identifier: "planner"),
            sessionCorrelationID: "corr-lease",
            grantedAt: start,
            expiresAt: start.addingTimeInterval(1_200)
        )
        lease.revoke(at: start.addingTimeInterval(60))
        let restriction = CapabilityRestriction(
            kind: .walletAccess,
            reason: "No wallet access during planning.",
            appliesTo: ActorRef(kind: .workflow, identifier: "planner"),
            sessionCorrelationID: "corr-lease",
            createdAt: start,
            expiresAt: start.addingTimeInterval(600)
        )

        await store.upsert(lease)
        await store.upsert(restriction)

        let recreated = SwiftDataCapabilityLeaseStore(modelContainer: container)
        let persistedLease = try #require(await recreated.allLeases().first)
        let persistedRestriction = try #require(await recreated.allRestrictions().first)
        #expect(persistedLease.revokedAt == start.addingTimeInterval(60))
        #expect(persistedRestriction.kind == .walletAccess)
        #expect(persistedRestriction.sessionCorrelationID == "corr-lease")

        await recreated.resetAll()
        #expect(await recreated.allLeases().isEmpty)
        #expect(await recreated.allRestrictions().isEmpty)
    }

    /// Lease rows were the one durable runtime table with no retention, and they are minted on a
    /// schedule rather than on demand — standing routine authority alone re-grants roughly ten
    /// 24-hour leases a day, and `CapabilityLeaseRegistry` decodes the whole table on first use. This
    /// pins the age sweep, and the two rows it must never take: a live lease, and the one the calling
    /// `upsert` just wrote.
    @Test
    func agedOutLeaseRowsAreSweptWhileLiveAndJustWrittenRowsSurvive() async throws {
        let container = try await makeContainer()
        let store = SwiftDataCapabilityLeaseStore(modelContainer: container)
        // Anything already expired is past the window, so the sweep is maximally aggressive and the
        // survivors below are survivors on their own merits.
        await store.setRetentionPolicy(deadLeaseRetention: 0, maximumDeadLeases: .max)
        let now = Date()

        let dead = lease(reason: "lapsed", expiresAt: now.addingTimeInterval(-10))
        let live = lease(reason: "still good", expiresAt: now.addingTimeInterval(3_600))
        await store.upsert(dead)
        // `dead` is spared by its own write, so it is still here — a caller has to be able to read
        // back what it just persisted.
        #expect(await store.allLeases().count == 1)

        await store.upsert(live)

        let remaining = await store.allLeases()
        #expect(remaining.map(\.reason) == ["still good"])
        // The live grant is intact, not merely present: the registry fails closed, so a swept-away
        // live lease would turn a working routine into a blocked run.
        #expect(remaining.first?.isActive(at: now) == true)
    }

    /// The age window bounds a steady rate; this bounds a spike. A burst of short-lived operator
    /// grants can put thousands of rows inside the window, so the cap has to hold independently.
    @Test
    func deadLeaseRowsAreCappedEvenWhenAllAreInsideTheRetentionWindow() async throws {
        let container = try await makeContainer()
        let store = SwiftDataCapabilityLeaseStore(modelContainer: container)
        // A decade of retention, so nothing below is old enough for the age sweep and only the cap
        // can be what drops a row.
        await store.setRetentionPolicy(deadLeaseRetention: 10 * 365 * 24 * 60 * 60, maximumDeadLeases: 2)
        let now = Date()

        for age in [500.0, 400.0, 300.0, 200.0, 100.0] {
            await store.upsert(lease(reason: "lapsed-\(Int(age))", expiresAt: now.addingTimeInterval(-age)))
        }
        // One more write, so the last of the five is no longer the spared row.
        await store.upsert(lease(reason: "still good", expiresAt: now.addingTimeInterval(3_600)))

        let remaining = await store.allLeases()
        // Oldest-expiring go first, so the survivors are the two most recently lapsed.
        #expect(Set(remaining.map(\.reason)) == ["lapsed-200", "lapsed-100", "still good"])
    }

    /// Restriction rows were the *other* durable authority table with no retention at all, and they
    /// grow the same way leases do — `RuntimeHost.restrictCapability` mints a fresh UUID every time
    /// rather than updating in place, nothing but `resetAll()` ever removed one, and
    /// `allRestrictions()` JSON-decodes the whole table on the launch path. This pins the age sweep
    /// and the two rows it must never take.
    @Test
    func agedOutRestrictionRowsAreSweptWhileIndefiniteAndActiveOnesSurvive() async throws {
        let container = try await makeContainer()
        let store = SwiftDataCapabilityLeaseStore(modelContainer: container)
        // Anything already expired is past the window, so the sweep is maximally aggressive and the
        // survivors below are survivors on their own merits.
        await store.setRestrictionRetentionPolicy(deadRestrictionRetention: 0, maximumDeadRestrictions: .max)
        let now = Date()

        await store.upsert(restriction(reason: "lapsed", expiresAt: now.addingTimeInterval(-10)))
        // `lapsed` is spared by its own write; this one is what sweeps it.
        await store.upsert(restriction(reason: "standing", expiresAt: nil))
        await store.upsert(restriction(reason: "still denying", expiresAt: now.addingTimeInterval(3_600)))

        let remaining = await store.allRestrictions()
        #expect(Set(remaining.map(\.reason)) == ["standing", "still denying"])
        // A restriction *denies*, so losing one fails open. Both survivors are checked as still
        // enforcing, not merely as still present.
        #expect(remaining.allSatisfy { $0.isActive(at: now) })
    }

    /// The backstop, and the one case where a restriction differs from a lease: an indefinite row
    /// has no expiry to rank, so it must be excluded from the dead-row count outright rather than
    /// sorted to one end of it. A nil sorted first would be the first thing a cap sweep took.
    @Test
    func theRestrictionCapNeverCountsOrCollectsAnIndefiniteRow() async throws {
        let container = try await makeContainer()
        let store = SwiftDataCapabilityLeaseStore(modelContainer: container)
        // A decade of retention, so nothing below is old enough for the age sweep and only the cap
        // can be what drops a row.
        await store.setRestrictionRetentionPolicy(
            deadRestrictionRetention: 10 * 365 * 24 * 60 * 60,
            maximumDeadRestrictions: 2
        )
        let now = Date()

        await store.upsert(restriction(reason: "standing", expiresAt: nil))
        for age in [500.0, 400.0, 300.0, 200.0, 100.0] {
            await store.upsert(restriction(reason: "lapsed-\(Int(age))", expiresAt: now.addingTimeInterval(-age)))
        }
        // One more write, so the last of the five is no longer the spared row.
        await store.upsert(restriction(reason: "still denying", expiresAt: now.addingTimeInterval(3_600)))

        let remaining = await store.allRestrictions()
        // Oldest-expiring go first among the dead; the indefinite row is not among them at all.
        #expect(Set(remaining.map(\.reason)) == ["standing", "lapsed-200", "lapsed-100", "still denying"])
    }
}

/// `grantedAt` is derived from `expiresAt` but pinned into the past, because `isActive(at:)` checks
/// both ends of the window — a lease granted in the future is not yet live, which would make the
/// live-lease assertion pass for the wrong reason.
private func lease(reason: String, expiresAt: Date, grantedAt: Date? = nil) -> CapabilityLease {
    CapabilityLease(
        capability: .playbackQueue,
        reason: reason,
        grantedTo: ActorRef(kind: .workflow, identifier: "planner"),
        grantedAt: grantedAt ?? min(expiresAt, Date()).addingTimeInterval(-1_200),
        expiresAt: expiresAt
    )
}

/// `createdAt` is pinned into the past for the reason ``lease(reason:expiresAt:grantedAt:)`` pins
/// `grantedAt`: `CapabilityRestriction.isActive(at:)` checks both ends, so a restriction created in
/// the future is not yet denying anything and would satisfy the survivor assertions for the wrong
/// reason.
private func restriction(reason: String, expiresAt: Date?) -> CapabilityRestriction {
    CapabilityRestriction(
        kind: .walletAccess,
        reason: reason,
        appliesTo: ActorRef(kind: .workflow, identifier: "planner"),
        createdAt: min(expiresAt ?? .distantFuture, Date()).addingTimeInterval(-1_200),
        expiresAt: expiresAt
    )
}

// MARK: - Eval result store

@Suite("SwiftDataEvalResultStore")
struct SwiftDataEvalResultStoreTests {

    private func result(
        _ grade: EvalGrade,
        correlationID: String,
        at evaluatedAt: Date,
        criteria: [CriterionResult] = []
    ) -> EvalResult {
        EvalResult(
            outcomeID: UUID(),
            correlationID: correlationID,
            results: criteria,
            grade: grade,
            evaluatedAt: evaluatedAt
        )
    }

    @MainActor
    @Test func resultsPersistAndReadBackNewestFirst() async throws {
        let store = SwiftDataEvalResultStore(modelContainer: try makeContainer())
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)

        await store.record(result(.passed, correlationID: "wf-1", at: epoch))
        await store.record(result(.failed, correlationID: "wf-2", at: epoch.addingTimeInterval(60)))

        let all = await store.allResults()
        #expect(all.count == 2)
        #expect(all.map(\.correlationID) == ["wf-2", "wf-1"])
        #expect(all[0].grade == .failed)
    }

    @MainActor
    @Test func resultsAreRetrievableByCorrelationID() async throws {
        let store = SwiftDataEvalResultStore(modelContainer: try makeContainer())
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)

        await store.record(result(.passed, correlationID: "wf-1", at: epoch))
        await store.record(result(.failed, correlationID: "wf-2", at: epoch))

        let scoped = await store.results(forCorrelationID: "wf-1")
        #expect(scoped.count == 1)
        #expect(scoped[0].grade == .passed)
        #expect(await store.results(forCorrelationID: "absent").isEmpty)
    }

    /// A spec can be re-run against a retained trace, so one workflow can carry several grades.
    @MainActor
    @Test func aWorkflowCanCarryMoreThanOneGrade() async throws {
        let store = SwiftDataEvalResultStore(modelContainer: try makeContainer())
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)

        await store.record(result(.inconclusive, correlationID: "wf-1", at: epoch))
        await store.record(result(.passed, correlationID: "wf-1", at: epoch.addingTimeInterval(30)))

        let scoped = await store.results(forCorrelationID: "wf-1")
        #expect(scoped.count == 2)
        #expect(scoped.map(\.grade) == [.passed, .inconclusive])
    }

    /// Recording the same result id twice updates the row instead of duplicating it, so a re-grade
    /// cannot inflate an operator's run count.
    @MainActor
    @Test func recordingTheSameResultTwiceUpdatesInPlace() async throws {
        let store = SwiftDataEvalResultStore(modelContainer: try makeContainer())
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)
        let id = UUID()
        let outcomeID = UUID()

        await store.record(EvalResult(
            id: id, outcomeID: outcomeID, correlationID: "wf-1", results: [], grade: .inconclusive, evaluatedAt: epoch
        ))
        await store.record(EvalResult(
            id: id, outcomeID: outcomeID, correlationID: "wf-1", results: [], grade: .passed, evaluatedAt: epoch
        ))

        let all = await store.allResults()
        #expect(all.count == 1)
        #expect(all[0].grade == .passed)
        #expect(all[0].nextAction == .complete)
    }

    /// Criterion detail survives the blob round trip — a report card's shortfall ranking depends on
    /// per-criterion outcomes, not just the overall grade.
    @MainActor
    @Test func perCriterionOutcomesSurvivePersistence() async throws {
        let store = SwiftDataEvalResultStore(modelContainer: try makeContainer())
        let stored = result(
            .failed,
            correlationID: "wf-1",
            at: Date(timeIntervalSince1970: 1_700_000_000),
            criteria: [
                CriterionResult(criterion: .producedArtifact, outcome: .met),
                CriterionResult(criterion: .completedWithin(seconds: 30), outcome: .notMet(detail: "over budget")),
                CriterionResult(criterion: .noBlockedSteps, outcome: .inconclusive(detail: "unreadable"))
            ]
        )

        await store.record(stored)

        let decoded = try #require(await store.allResults().first)
        #expect(decoded == stored)
        #expect(decoded.decidedCount == 2)
        #expect(decoded.score == 0.5)
    }

    @MainActor
    @Test func resetAllClearsGradedRuns() async throws {
        let store = SwiftDataEvalResultStore(modelContainer: try makeContainer())
        await store.record(result(.passed, correlationID: "wf-1", at: .now))

        await store.resetAll()

        #expect(await store.allResults().isEmpty)
    }
}

// MARK: - Improvement recommendation store

@Suite("SwiftDataImprovementRecommendationStore")
struct SwiftDataImprovementRecommendationStoreTests {

    private func recommendation(
        _ id: String,
        state: ImprovementRecommendationState = .proposed,
        createdAt: Date
    ) -> ImprovementRecommendation {
        ImprovementRecommendation(
            id: id,
            operatorID: "operator-1",
            evidenceWorkflowIDs: ["wf-\(id)"],
            category: .observability,
            summary: "s",
            proposedChange: .repairWorklogInstrumentation,
            confidence: 0.8,
            state: state,
            createdAt: createdAt
        )
    }

    @MainActor
    @Test func retiredRecommendationsArePrunedOldestFirst() async throws {
        let store = SwiftDataImprovementRecommendationStore(modelContainer: try makeContainer())
        await store.setRetentionCap(2)
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)

        for index in 0..<4 {
            await store.upsert(recommendation(
                "r\(index)",
                state: .superseded,
                createdAt: epoch.addingTimeInterval(Double(index))
            ))
        }
        // One more write, so the row that finally crossed the cap is not the spared one.
        await store.upsert(recommendation("keeper", state: .proposed, createdAt: epoch.addingTimeInterval(9)))

        let ids = Set(await store.allRecommendations().map(\.id))
        #expect(ids == ["r2", "r3", "keeper"])
    }

    @MainActor
    @Test func pendingAndAcceptedRecommendationsSurviveAnySweep() async throws {
        let store = SwiftDataImprovementRecommendationStore(modelContainer: try makeContainer())
        await store.setRetentionCap(0)
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)

        await store.upsert(recommendation("proposed", state: .proposed, createdAt: epoch))
        await store.upsert(recommendation("accepted", state: .accepted, createdAt: epoch.addingTimeInterval(1)))
        await store.upsert(recommendation("rejected", state: .rejected, createdAt: epoch.addingTimeInterval(2)))
        await store.upsert(recommendation("applied", state: .applied, createdAt: epoch.addingTimeInterval(3)))
        await store.upsert(recommendation("last", state: .proposed, createdAt: epoch.addingTimeInterval(4)))

        let ids = Set(await store.allRecommendations().map(\.id))
        #expect(ids == ["proposed", "accepted", "last"])
    }

    @MainActor
    @Test func retiringARecommendationDoesNotDropTheRowBeingRetired() async throws {
        let store = SwiftDataImprovementRecommendationStore(modelContainer: try makeContainer())
        await store.setRetentionCap(0)
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)

        let proposed = recommendation("only", state: .proposed, createdAt: epoch)
        await store.upsert(proposed)
        await store.upsert(proposed.transitioning(to: .superseded, reviewedBy: "adaptive.engine"))

        #expect(await store.recommendation(id: "only")?.state == .superseded)
    }
}

// MARK: - Playbook store decode tolerance

@Suite("SwiftDataPlaybookStore decoding")
struct SwiftDataPlaybookStoreDecodingTests {

    /// A row naming a capability this build does not know must cost that row and nothing else.
    /// `CapabilityID.init(from:)` throws on an unrecognised raw value, so before this the whole
    /// library — including the seeding that would repair it — went down with the one bad row.
    @MainActor
    @Test func anUnreadableRowIsDroppedRatherThanFailingTheWholeLibrary() async throws {
        let container = try makeContainer()
        let store = SwiftDataPlaybookStore(modelContainer: container)
        try await store.upsert(playbook("good", state: .installed))

        let context = ModelContext(container)
        context.insert(StoredPlaybookRecord(
            id: "from-a-newer-build",
            data: Data(#"{"id":"from-a-newer-build","name":"n","summary":"s","trigger":{"manual":{}},"authority":{"capabilities":["nft_transfer"],"allowedOutputs":[]},"completionCondition":"done"}"#.utf8)
        ))
        try context.save()

        let reopened = SwiftDataPlaybookStore(modelContainer: container)
        #expect(try await reopened.all().map(\.id) == ["good"])
        #expect(try await reopened.playbook(id: "good") != nil)

        // The library can still repair itself: seeding a missing system playbook must not throw.
        try await reopened.seedMissingSystemPlaybooks([playbook("seeded")])
        #expect(try await reopened.all().map(\.id).sorted() == ["good", "seeded"])
    }
}
