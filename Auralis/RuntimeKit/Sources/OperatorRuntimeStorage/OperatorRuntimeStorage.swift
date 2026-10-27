import AuralisReceipts
import AuralisRuntime
import Foundation
import OSLog
import SwiftData

private let storageLogger = Logger(subsystem: "Auralis", category: "OperatorRuntimeStorage")

/// Decodes a stored blob, logging a decode failure rather than swallowing it.
///
/// Every store below reads rows through `compactMap`, so a bare `try?` returning `nil` erases the
/// entire row from history with no trace — a missing attribution column silently costs the whole
/// worklog entry, not just its actor. The drop is retained deliberately (one corrupt row must not
/// take down a listing), but it stops being invisible: schema drift now shows up as a log line
/// instead of as history that quietly reads short.
private func decodeStoredBlob<T: Decodable>(
    _ type: T.Type,
    from data: Data,
    row: String
) -> T? {
    do {
        return try JSONDecoder().decode(type, from: data)
    } catch {
        storageLogger.error(
            "Dropped \(row, privacy: .public) row: decode failed error=\(error.localizedDescription, privacy: .public)"
        )
        return nil
    }
}

// MARK: - SwiftData models (Codable blobs + queryable columns)

@Model
public final class StoredPlaybookRecord {
    @Attribute(.unique) public var id: String
    public var data: Data
    public init(id: String, data: Data) { self.id = id; self.data = data }
}

@Model
public final class StoredPerformanceEventRecord {
    @Attribute(.unique) public var id: UUID
    public var playbookID: String
    /// The run this event belongs to, projected out of ``data`` as a real column.
    ///
    /// Without it, `recordIntervention(runID:)` and `recordApprovalDecision(runID:decision:)` had to
    /// fetch and JSON-decode **every** row to find the handful belonging to one run — the same
    /// full-table-decode shape ``StoredExecutionRecordRow`` was given columns to escape, against a
    /// table that is written to far more often. Optional because ``PerformanceEvent/runID`` is:
    /// events recorded before run attribution existed genuinely have none.
    public var runID: UUID?
    /// Insertion order, so "the run's last event" means *last recorded* — full stop, not merely on a
    /// `recordedAt` tie — and so the retention sweep has a total order to prune by.
    ///
    /// Required rather than nice to have, for the two reasons `PerformanceStore` spells out on its
    /// own in-memory equivalents. `recordApprovalDecision` resolves by *last* matching position, so
    /// without a recorded insertion order the durable store's answer is whatever order SwiftData
    /// happened to return — the F-26 divergence, on a method whose two implementations
    /// `AuralisRuntime` documents as agreeing. That method therefore ranks on this column **alone**:
    /// `recordedAt` above it would override insertion position rather than be broken by it, and the
    /// replay path makes the two genuinely disagree, because merging a re-recorded event updates
    /// `recordedAt` while deliberately preserving `sequence`. And a `recordedAt`-only prune ordering
    /// "cannot separate ties, and a burst of events recorded in the same instant — or a caller
    /// backdating them all to one `Date` — would leave nothing droppable", silently defeating the cap.
    public var sequence: Int = 0
    /// Fully qualified rather than `.distantPast`: the `@Model` macro rejects an implicit-member
    /// default with "A default value requires a fully qualified domain named value".
    ///
    /// Defaulted rather than optional so adding it is a SwiftData lightweight migration, and doubles
    /// as the "this row predates the query columns" sentinel that
    /// ``SwiftDataPerformanceStore/backfillQueryColumnsIfNeeded()`` looks for — the same role
    /// `playbookID == ""` plays for ``StoredExecutionRecordRow``.
    public var recordedAt: Date = Date.distantPast
    public var data: Data

    public init(
        id: UUID,
        playbookID: String,
        runID: UUID?,
        sequence: Int,
        recordedAt: Date,
        data: Data
    ) {
        self.id = id
        self.playbookID = playbookID
        self.runID = runID
        self.sequence = sequence
        self.recordedAt = recordedAt
        self.data = data
    }
}

@Model
public final class StoredExecutionRecordRow {
    @Attribute(.unique) public var id: UUID
    /// The two query keys, projected out of ``data`` as real columns — the same thing
    /// ``StoredArtifactRecord`` and ``StoredRuntimeEventRow`` do, and this row was the one table in
    /// the file that did not.
    ///
    /// Without them `latest(forPlaybookID:)` had to fetch and JSON-decode **every** execution record
    /// to find one, and `RuntimeHost.runDueRoutines` calls it once per installed playbook on every
    /// background scan — so one due-scan decoded the whole history N times, inside a
    /// `BGTaskScheduler` budget. They also give the retention sweep something to order by.
    ///
    /// Defaulted rather than optional so adding them is a SwiftData lightweight migration. A row
    /// written before the columns existed carries `""` / `.distantPast` until
    /// ``SwiftDataExecutionRecordStore/backfillQueryColumnsIfNeeded()`` fills it in, which is the
    /// same shape as `StoredReceipt`'s `accountKey` backfill and exists for the same reason: a
    /// predicate cannot match a column the row never wrote.
    public var playbookID: String = ""
    /// Fully qualified rather than `.distantPast`: the `@Model` macro rejects an implicit-member
    /// default with "A default value requires a fully qualified domain named value".
    public var startedAt: Date = Date.distantPast
    /// Insertion order, so "latest" can mean *last recorded* on a `startedAt` tie.
    ///
    /// Required rather than nice to have: `ExecutionRecordStoring`'s contract is pinned by
    /// `latestPrefersTheMostRecentlyRecordedRunOnATie`, which stores two runs in the same instant and
    /// requires the second one back. A durable store cannot observe insertion order without
    /// recording it — sorting on `id` would pick a random UUID and sorting on nothing at all leaves
    /// it to an unspecified fetch order — so this column is what lets the two implementations of one
    /// protocol method agree. ``StoredRuntimeEventRow/sequence`` exists for the same reason.
    public var sequence: Int = 0
    public var data: Data

    public init(id: UUID, playbookID: String, startedAt: Date, sequence: Int, data: Data) {
        self.id = id
        self.playbookID = playbookID
        self.startedAt = startedAt
        self.sequence = sequence
        self.data = data
    }
}

/// The original artifact row: the whole ``Artifact`` as one JSON blob, with a few columns lifted out
/// for querying.
///
/// **Legacy, read-only.** Nothing writes this table any more. Artifacts are persisted by
/// `AuralisReceipts.StoredArtifact`, which keeps the fields as real columns, bounds the body with
/// external storage, and — the reason for the move — refuses a row it cannot interpret instead of
/// coercing an unknown approval state to `.draft`. Two same-named `SwiftDataArtifactStore` types
/// existed for a while, one here and one in `AuralisReceipts`; the hardened one had 21 passing tests
/// and zero production imports, while this file's weaker one was what `PersistentRuntimeHost`
/// actually built. Its write methods returned normally when the named row was missing, so a person
/// who approved an artifact deleted from under them was told the decision had been recorded.
///
/// Kept registered in the schema so `AuralisReceipts.LegacyArtifactMigration` can read rows written
/// before the move and copy them across. Remove the type only once no installation can still be
/// carrying one.
@Model
public final class StoredArtifactRecord {
    @Attribute(.unique) public var id: UUID
    public var groupID: UUID
    public var typeRawValue: String
    public var createdAt: Date
    public var data: Data

    public init(id: UUID, groupID: UUID, typeRawValue: String, createdAt: Date, data: Data) {
        self.id = id
        self.groupID = groupID
        self.typeRawValue = typeRawValue
        self.createdAt = createdAt
        self.data = data
    }
}

@Model
public final class StoredWorkflowStepLogRow {
    @Attribute(.unique) public var id: UUID
    public var correlationID: String?
    public var timestamp: Date
    public var data: Data

    public init(id: UUID, correlationID: String?, timestamp: Date, data: Data) {
        self.id = id
        self.correlationID = correlationID
        self.timestamp = timestamp
        self.data = data
    }
}

@Model
public final class StoredAgentSessionRow {
    @Attribute(.unique) public var correlationID: String
    public var startedAt: Date
    public var statusRawValue: String
    public var data: Data

    public init(correlationID: String, startedAt: Date, statusRawValue: String, data: Data) {
        self.correlationID = correlationID
        self.startedAt = startedAt
        self.statusRawValue = statusRawValue
        self.data = data
    }
}

@Model
public final class StoredRuntimeEventRow {
    @Attribute(.unique) public var id: UUID
    public var timestamp: Date
    public var sequence: Int64 = 0
    public var correlationID: String?
    public var data: Data

    public init(id: UUID, timestamp: Date, sequence: Int64, correlationID: String?, data: Data) {
        self.id = id
        self.timestamp = timestamp
        self.sequence = sequence
        self.correlationID = correlationID
        self.data = data
    }
}

@Model
public final class StoredCapabilityLeaseRow {
    @Attribute(.unique) public var id: UUID
    public var grantedAt: Date
    public var expiresAt: Date
    public var revokedAt: Date?
    public var data: Data

    public init(id: UUID, grantedAt: Date, expiresAt: Date, revokedAt: Date?, data: Data) {
        self.id = id
        self.grantedAt = grantedAt
        self.expiresAt = expiresAt
        self.revokedAt = revokedAt
        self.data = data
    }
}

@Model
public final class StoredCapabilityRestrictionRow {
    @Attribute(.unique) public var id: UUID
    public var createdAt: Date
    public var expiresAt: Date?
    public var revokedAt: Date?
    public var data: Data

    public init(id: UUID, createdAt: Date, expiresAt: Date?, revokedAt: Date?, data: Data) {
        self.id = id
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.revokedAt = revokedAt
        self.data = data
    }
}

/// A graded run. `correlationID` and `evaluatedAt` are projected out of ``data`` because both have
/// readers — `results(forCorrelationID:)` predicates on the first and every listing sorts by the
/// second.
///
/// **There is deliberately no `gradeRawValue` column, and no projection of the grade would help.**
/// It carried the claim "so a report card can count grades without decoding every blob", and that is
/// not achievable by a column on this table: a report card's tallies are needed *per playbook*,
/// ``EvalResult/playbookID`` is optional, and the owning operator is normally recovered by joining
/// through the execution records — which live in another table and age out. So a global `fetchCount`
/// over a grade column cannot answer the question the card actually asks, and a per-playbook one has
/// nothing reliable to group by. The single consumer
/// (`MissionControlHomeModel.loadReportCards()`) needs the **whole** table for the same reason its
/// own comment gives: a graded run whose execution record has aged out "must not silently drop its
/// grades". A read that must be complete cannot be narrowed, so the honest shape here is one full
/// fetch that decodes each blob once, and a duplicated grade column would only be a second copy of
/// a value already inside `data`, free to disagree with it.
@Model
public final class StoredEvalResultRow {
    @Attribute(.unique) public var id: UUID
    public var correlationID: String
    public var evaluatedAt: Date
    public var data: Data

    public init(
        id: UUID,
        correlationID: String,
        evaluatedAt: Date,
        data: Data
    ) {
        self.id = id
        self.correlationID = correlationID
        self.evaluatedAt = evaluatedAt
        self.data = data
    }
}

/// An advisory recommendation. Only the columns with readers are projected out of ``data``:
/// `createdAt` orders every listing and the retention sweep, and `stateRawValue` is what lets that
/// sweep select retired rows without decoding a blob (see
/// ``SwiftDataImprovementRecommendationStore/retiredStates``).
///
/// **There is deliberately no `operatorID` column, even though a recommendation is about exactly one
/// operator.** A per-operator predicate would be the obvious projection and it is the wrong one
/// here: Mission Control fetches `allRecommendations()` **once** per refresh and then filters by
/// operator in memory while rendering each card, so narrowing in the store would turn one query
/// into one per card — strictly more work, not less, for the only access pattern that exists.
/// `ImprovementRecommendationStoring` records the same decision on `allRecommendations()` itself.
/// The operator id stays where it belongs, inside the encoded ``ImprovementRecommendation``, with no
/// second copy on the row free to disagree with it.
@Model
public final class StoredImprovementRecommendationRow {
    @Attribute(.unique) public var id: String
    public var createdAt: Date
    public var stateRawValue: String
    public var data: Data

    public init(id: String, createdAt: Date, stateRawValue: String, data: Data) {
        self.id = id
        self.createdAt = createdAt
        self.stateRawValue = stateRawValue
        self.data = data
    }
}

/// Builds the on-disk container for the operator-runtime stores. Kept separate from the app's main
/// SwiftData container so these can persist without touching the app schema.
public enum OperatorRuntimeStorage {
    public static func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            StoredPlaybookRecord.self,
            StoredPerformanceEventRecord.self,
            StoredExecutionRecordRow.self,
            // The current artifact table, owned by `AuralisReceipts` along with the store that
            // writes it. Registered here because this package owns the container.
            StoredArtifact.self,
            // Legacy, read-only, still registered so `LegacyArtifactMigration` can find rows
            // written before the move. See ``StoredArtifactRecord``.
            StoredArtifactRecord.self,
            StoredWorkflowStepLogRow.self,
            StoredAgentSessionRow.self,
            StoredRuntimeEventRow.self,
            StoredCapabilityLeaseRow.self,
            StoredCapabilityRestrictionRow.self,
            StoredEvalResultRow.self,
            StoredImprovementRecommendationRow.self
        ])
        return try ModelContainer(
            for: schema,
            // Explicit, because the default is `.automatic` and that reads the *host app's* iCloud
            // entitlement as instruction to mirror this schema to CloudKit. Auralis carries such an
            // entitlement for the receipt-ledger witness — which uses `CKContainer` directly and
            // never wanted SwiftData mirroring — and these rows are operator-runtime history that
            // is deliberately device-local: a worklog trace and capability grants are not content
            // to sync. `StoredImprovementRecommendationRow.id` is also `@Attribute(.unique)`, which
            // CloudKit does not support, so mirroring would fail the container outright.
            configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        )
    }
}

// MARK: - Playbook store

@ModelActor
public actor SwiftDataPlaybookStore: PlaybookStore {
    /// Every stored playbook, dropping any row this build cannot read.
    ///
    /// Drops rather than throws, matching every other store in this file. `Playbook.init(from:)` is
    /// tolerant by design, but `CapabilityID.init(from:)` is deliberately *not* — it throws on a raw
    /// value it does not recognise. So a library that has seen a newer build (a TestFlight install
    /// followed by an App Store one, say) can hold a playbook naming a capability this build has
    /// never heard of, and a throwing `all()` let that one row take down the whole operator library:
    /// the listing, `playbook(id:)`, and `seedMissingSystemPlaybooks` — which would then be unable
    /// to restore even the built-in playbooks.
    public func all() throws -> [Playbook] {
        try modelContext.fetch(FetchDescriptor<StoredPlaybookRecord>())
            .compactMap { decodeStoredBlob(Playbook.self, from: $0.data, row: "playbook") }
            .sorted { $0.name < $1.name }
    }

    public func playbook(id: String) throws -> Playbook? {
        try all().first { $0.id == id }
    }

    public func playbooks(inState state: PlaybookInstallState) throws -> [Playbook] {
        try all().filter { $0.installState == state }
    }

    /// - Throws: whatever the encode, the fetch, or the commit threw. **The context is rolled back
    ///   first, so a throw means nothing was left pending** — matching
    ///   ``SwiftDataPerformanceStore/record(_:)``. This actor keeps one long-lived `modelContext`,
    ///   so an uncommitted insert or an uncommitted `row.data = data` survives the failed call and
    ///   is committed by the next successful write. That is worse here than a lost write: every
    ///   mutating path in this store funnels through `upsert`, so `setInstallState` reporting a
    ///   failure and then having the install silently take effect on the next unrelated save is a
    ///   playbook running that the person was told had not been installed.
    public func upsert(_ playbook: Playbook) throws {
        do {
            let data = try JSONEncoder().encode(playbook)
            let id = playbook.id
            if let row = try modelContext.fetch(FetchDescriptor<StoredPlaybookRecord>(
                predicate: #Predicate { $0.id == id }
            )).first {
                row.data = data
            } else {
                modelContext.insert(StoredPlaybookRecord(id: id, data: data))
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// - Throws: ``PlaybookStoreError/notFound(id:)`` when no row is stored under `id`, including
    ///   when a row exists but this build cannot decode it — ``all()`` drops those, so from every
    ///   caller's point of view the playbook is not in the library and reporting it installed or
    ///   paused would be a lie.
    public func setInstallState(id: String, to state: PlaybookInstallState) throws {
        guard var playbook = try playbook(id: id) else { throw PlaybookStoreError.notFound(id: id) }
        playbook.installState = state
        try upsert(playbook)
    }

    /// Seeds the given playbooks only if the store is empty (first launch).
    public func seedIfEmpty(_ playbooks: [Playbook]) throws {
        let isEmpty = try modelContext.fetchCount(FetchDescriptor<StoredPlaybookRecord>()) == 0
        guard isEmpty else { return }
        for playbook in playbooks { try upsert(playbook) }
    }

    /// Adds newly shipped system playbooks without overwriting existing install/edit state.
    public func seedMissingSystemPlaybooks(_ playbooks: [Playbook]) throws {
        for playbook in playbooks where try self.playbook(id: playbook.id) == nil {
            try upsert(playbook)
        }
    }
}

// MARK: - Performance store

@ModelActor
public actor SwiftDataPerformanceStore: PerformanceStoring {
    /// Retention for durable run history.
    ///
    /// This was the last durable table in the file with no cap and no written argument for not
    /// having one, and it is the highest-volume of them all: `PerformancePipelineSink` records an
    /// event for **every terminal governed tool call**, so it grows faster than the execution-record
    /// table (one row per routine run, capped at 2,000) and at least as fast as the worklog. The
    /// in-memory ``PerformanceStore`` already caps itself at 4,096 with the argument that
    /// "an uncapped array grows for the entire life of the process"; this one grew for the entire
    /// life of the *install*, which is strictly worse, and `allHealth()` decodes every row of it on
    /// each Mission Control refresh.
    ///
    /// 10,000 matches the other two high-volume durable tables
    /// (``SwiftDataWorklogStore/maximumStoredSteps`` and
    /// ``SwiftDataRuntimeEventHistoryStore/maximumStoredEvents``) and is far beyond the sample any
    /// aggregate needs — `classification` reasons over a 5-run floor.
    ///
    /// Pruned oldest-first by `(recordedAt, sequence)`, the same total order the in-memory store
    /// trims by. Unlike the worklog there is no multi-row group to split: health is averaged over
    /// whatever events remain, and a run's events are contiguous in `recordedAt`, so the only run a
    /// sweep can divide is the one straddling the cap boundary.
    public static let maximumStoredEvents = 10_000

    private var retentionCap = SwiftDataPerformanceStore.maximumStoredEvents
    private var didBackfillQueryColumns = false

    /// Test seam, for the reason ``SwiftDataWorklogStore/setRetentionCap(_:)`` is one: so tests can
    /// drive the retention *policy* without writing ten thousand rows.
    func setRetentionCap(_ cap: Int) {
        retentionCap = cap
    }

    /// Records a run, replacing any row already stored under the same event ID.
    ///
    /// **Idempotent by `event.id`, and depended upon as such.** ``RuntimePerformanceObserver`` reuses
    /// the runtime event envelope's ID as the performance event's ID precisely so that recording a
    /// replayed event cannot double-count it: the observer checkpoints *after* it records, so a crash
    /// in between replays that event on the next launch. Its in-process cache cannot help there —
    /// the cache dies with the process — so this store is what makes the de-duplication hold across
    /// process lifetimes.
    ///
    /// **A replacement folds in the human annotations already on the row — see ``merging(_:into:)``.**
    /// That is the other half of the same replay contract, and it matters *here* more than anywhere:
    /// a replay is reconstructed from the runtime envelope and so always arrives with
    /// `requiredIntervention == false` and `approvalDecision == nil`, and this is the only
    /// `PerformanceStoring` implementation whose state outlives the process, so it is the only one
    /// where "the next launch replays that event" can actually happen. Overwriting wholesale erased
    /// a person's approval from `approvalRate` and their intervention from `interventionRate`.
    public func record(_ event: PerformanceEvent) {
        backfillQueryColumnsIfNeeded()
        let id = event.id
        do {
            if let existing = try modelContext.fetch(FetchDescriptor<StoredPerformanceEventRecord>(
                predicate: #Predicate { $0.id == id }
            )).first {
                let merged = Self.merging(event, into: existing)
                existing.playbookID = merged.playbookID
                existing.runID = merged.runID
                existing.recordedAt = merged.recordedAt
                // `sequence` is deliberately left alone, matching the in-memory store: "the
                // replacement keeps the original position so a re-recorded run does not jump to the
                // end of the history".
                existing.data = try JSONEncoder().encode(merged)
            } else {
                // Allocated the way ``SwiftDataExecutionRecordStore/store(_:)`` allocates its own:
                // read the current maximum and add one, inside this actor so two writes cannot
                // interleave.
                var latestDescriptor = FetchDescriptor<StoredPerformanceEventRecord>(
                    sortBy: [SortDescriptor(\StoredPerformanceEventRecord.sequence, order: .reverse)]
                )
                latestDescriptor.fetchLimit = 1
                let nextSequence = ((try modelContext.fetch(latestDescriptor).first?.sequence) ?? 0) + 1
                modelContext.insert(
                    StoredPerformanceEventRecord(
                        id: id,
                        playbookID: event.playbookID,
                        runID: event.runID,
                        sequence: nextSequence,
                        recordedAt: event.recordedAt,
                        data: try JSONEncoder().encode(event)
                    )
                )
                // Only an insert grows the table, so only an insert has to sweep.
                try pruneStoredEvents(keepingNewest: retentionCap)
            }
            try modelContext.save()
        } catch {
            // Rolled back, so a write that failed is not left pending in the context for an
            // unrelated later `save()` to commit — which would resurrect a run that this call
            // already reported as unrecorded, including one erased by `resetAll()` in between.
            modelContext.rollback()
            storageLogger.error("Performance event persistence failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Folds the human annotations already held for this row into an incoming re-record.
    ///
    /// Mirrors `PerformanceStore.merging(_:)` exactly, because the two are one protocol method: the
    /// intervention flag is sticky once set, and an incoming decision still wins so a replay cannot
    /// pin the first answer forever. An undecodable existing row has nothing to contribute, so the
    /// incoming event stands as written.
    private static func merging(
        _ event: PerformanceEvent,
        into row: StoredPerformanceEventRecord
    ) -> PerformanceEvent {
        guard let existing = decodeStoredBlob(
            PerformanceEvent.self,
            from: row.data,
            row: "performanceEvent"
        ) else { return event }
        var merged = event
        if existing.requiredIntervention {
            merged = merged.markingIntervention()
        }
        if let decision = event.approvalDecision ?? existing.approvalDecision {
            merged = merged.recordingApprovalDecision(decision)
        }
        return merged
    }

    /// Marks **every** event belonging to the run, because intervention is a property of the run and
    /// one run can make several governed tool calls. Matches `PerformanceStore.recordIntervention`.
    public func recordIntervention(runID: UUID) {
        let rows: [StoredPerformanceEventRecord]
        do {
            rows = try fetchRows(forRunID: runID)
        } catch {
            storageLogger.error("Performance intervention lookup failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        do {
            for row in rows {
                guard let event = decodeStoredBlob(PerformanceEvent.self, from: row.data, row: "performanceEvent"),
                      !event.requiredIntervention else { continue }
                row.data = try JSONEncoder().encode(event.markingIntervention())
            }
            try modelContext.save()
        } catch {
            // Rolled back rather than returned from: the loop may already have rewritten some of the
            // run's rows, and leaving those pending would commit a half-marked run on a later save.
            modelContext.rollback()
            storageLogger.error("Performance intervention persistence failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Records the person's decision on the run's **last** event, deliberately unlike
    /// ``recordIntervention(runID:)`` which marks every one: a person makes a single decision per
    /// run, and `PlaybookHealth.approvalRate` averages over the events carrying one, so annotating
    /// all N events of a multi-tool-call run would weight that one decision N times.
    ///
    /// "Last" is resolved by `sequence` **alone**, rather than by the order the fetch happened to
    /// return or by `recordedAt`. `PerformanceStore` resolves it with
    /// `events.lastIndex(where: { $0.runID == runID })` — purely insertion position — and
    /// `AuralisRuntime` documents the two as agreeing, so an unordered fetch here made that written
    /// claim rest on whatever SwiftData returned (the F-26 divergence). Ranking by `recordedAt`
    /// first did not fix it but moved it: `sequence` *is* the recorded insertion position, so a
    /// clock reading placed above it can only ever **override** the order it is supposed to
    /// reproduce. The replay path above is the live trigger — its merge branch writes
    /// `existing.recordedAt` while deliberately leaving `sequence` alone, so re-recording a run's
    /// first event leaves that row newest by clock and oldest by position, and the two
    /// implementations then annotate different events of the same run. A caller passing a
    /// non-monotonic explicit `recordedAt` reaches the same place; the parameter is public.
    ///
    /// Taking the first row that *decodes* keeps an unreadable row from shadowing the readable one
    /// behind it, as `latest(forPlaybookID:)` does.
    public func recordApprovalDecision(runID: UUID, decision: PerformanceApprovalDecision) {
        let rows: [StoredPerformanceEventRecord]
        do {
            rows = try fetchRows(forRunID: runID, newestFirst: true)
        } catch {
            storageLogger.error("Approval decision lookup failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        let resolved = rows.lazy.compactMap { row -> (StoredPerformanceEventRecord, PerformanceEvent)? in
            decodeStoredBlob(PerformanceEvent.self, from: row.data, row: "performanceEvent").map { (row, $0) }
        }.first
        guard let (row, event) = resolved else {
            storageLogger.error("Approval decision had no matching performance run: \(runID.uuidString, privacy: .public)")
            return
        }
        do {
            row.data = try JSONEncoder().encode(event.recordingApprovalDecision(decision))
            try modelContext.save()
        } catch {
            modelContext.rollback()
            storageLogger.error("Approval decision persistence failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The rows belonging to one run, resolved by the `runID` column instead of by decoding the
    /// table. Optional-typed target so the comparison stays `UUID? == UUID?` for the predicate.
    ///
    /// - Parameter newestFirst: Orders by `sequence` descending — *last recorded first*, and nothing
    ///   else. Only ``recordApprovalDecision(runID:decision:)`` asks for it, and it has to reproduce
    ///   `PerformanceStore.lastIndex(where:)` exactly; `sequence` is the recorded insertion position,
    ///   so it is the only column that can. `recordedAt` is deliberately *not* in this sort: as a
    ///   primary key it overrides insertion position instead of being broken by it, which is the
    ///   divergence documented on that method. The default forward order keeps
    ///   `(recordedAt, sequence)` because ``recordIntervention(runID:)`` is its only other caller and
    ///   marks every row of the run, so its order is immaterial either way.
    private func fetchRows(
        forRunID runID: UUID,
        newestFirst: Bool = false
    ) throws -> [StoredPerformanceEventRecord] {
        backfillQueryColumnsIfNeeded()
        let target: UUID? = runID
        let sortBy: [SortDescriptor<StoredPerformanceEventRecord>] = newestFirst
            ? [SortDescriptor(\StoredPerformanceEventRecord.sequence, order: .reverse)]
            : [
                SortDescriptor(\StoredPerformanceEventRecord.recordedAt, order: .forward),
                SortDescriptor(\StoredPerformanceEventRecord.sequence, order: .forward)
            ]
        return try modelContext.fetch(FetchDescriptor<StoredPerformanceEventRecord>(
            predicate: #Predicate { $0.runID == target },
            sortBy: sortBy
        ))
    }

    /// Fills the query columns on rows written before they existed, so a predicate can match them.
    ///
    /// One-shot per store instance and scoped by predicate to the rows that need it, so the ordinary
    /// case costs one empty-result query and nothing else. Same shape and same reason as
    /// ``SwiftDataExecutionRecordStore/backfillQueryColumnsIfNeeded()``.
    private func backfillQueryColumnsIfNeeded() {
        guard !didBackfillQueryColumns else { return }
        didBackfillQueryColumns = true
        do {
            // Hoisted out of the macro: `#Predicate` cannot resolve a static member reference, so
            // `Date.distantPast` has to arrive as a captured value.
            let sentinel = Date.distantPast
            let stale = try modelContext.fetch(
                FetchDescriptor<StoredPerformanceEventRecord>(
                    predicate: #Predicate { $0.recordedAt == sentinel }
                )
            )
            guard !stale.isEmpty else { return }
            let decoded = stale.compactMap { row -> (StoredPerformanceEventRecord, PerformanceEvent)? in
                guard let event = decodeStoredBlob(
                    PerformanceEvent.self,
                    from: row.data,
                    row: "performanceEvent"
                ) else { return nil }
                return (row, event)
            }
            // Sequences assigned in `recordedAt` order rather than fetch order, and *below* every
            // sequence a post-column write could hold, so legacy rows rank beneath new ones on a tie.
            // Pre-column rows have no recorded insertion order to recover; this is the only
            // deterministic answer available from the data.
            for (offset, pair) in decoded.sorted(by: { $0.1.recordedAt < $1.1.recordedAt }).enumerated() {
                pair.0.runID = pair.1.runID
                pair.0.recordedAt = pair.1.recordedAt
                pair.0.sequence = -decoded.count + offset
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            // Latched anyway, for the reason the execution-record backfill latches: a backfill that
            // cannot commit will not commit on the next call either, and retrying it on every read
            // would put a failing write in front of every lookup.
            storageLogger.error("Performance event backfill failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func pruneStoredEvents(keepingNewest maximumCount: Int) throws {
        guard maximumCount > 0 else {
            for row in try modelContext.fetch(FetchDescriptor<StoredPerformanceEventRecord>()) {
                modelContext.delete(row)
            }
            return
        }
        let storedCount = try modelContext.fetchCount(FetchDescriptor<StoredPerformanceEventRecord>())
        guard storedCount > maximumCount else { return }

        var descriptor = FetchDescriptor<StoredPerformanceEventRecord>(
            sortBy: [
                SortDescriptor(\StoredPerformanceEventRecord.recordedAt, order: .forward),
                SortDescriptor(\StoredPerformanceEventRecord.sequence, order: .forward)
            ]
        )
        descriptor.fetchLimit = storedCount - maximumCount
        for row in try modelContext.fetch(descriptor) {
            modelContext.delete(row)
        }
    }

    public func events(forPlaybook playbookID: String) -> [PerformanceEvent] {
        let target = playbookID
        let rows: [StoredPerformanceEventRecord]
        do {
            rows = try modelContext.fetch(FetchDescriptor<StoredPerformanceEventRecord>(
                predicate: #Predicate { $0.playbookID == target }
            ))
        } catch {
            storageLogger.error("Performance event lookup failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
        return rows.compactMap { decodeStoredBlob(PerformanceEvent.self, from: $0.data, row: "performanceEvent") }
            .sorted { $0.recordedAt < $1.recordedAt }
    }

    public func health(forPlaybook playbookID: String) -> PlaybookHealth {
        PlaybookHealth(playbookID: playbookID, events: events(forPlaybook: playbookID))
    }

    public func allHealth() -> [PlaybookHealth] {
        let rows: [StoredPerformanceEventRecord]
        do {
            rows = try modelContext.fetch(FetchDescriptor<StoredPerformanceEventRecord>())
        } catch {
            storageLogger.error("Performance health lookup failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
        let all = rows
            .compactMap { decodeStoredBlob(PerformanceEvent.self, from: $0.data, row: "performanceEvent") }
        return Dictionary(grouping: all, by: \.playbookID)
            .map { PlaybookHealth(playbookID: $0.key, events: $0.value) }
            .sorted { $0.playbookID < $1.playbookID }
    }

    public func resetAll() {
        do {
            for row in try modelContext.fetch(FetchDescriptor<StoredPerformanceEventRecord>()) {
                modelContext.delete(row)
            }
            try modelContext.save()
            // Cleared with the rows, matching ``SwiftDataExecutionRecordStore/resetAll()``: the
            // columns it would have filled are gone, and leaving it set would skip the backfill for
            // pre-column rows a later restore brings back.
            didBackfillQueryColumns = false
        } catch {
            modelContext.rollback()
            storageLogger.error("Performance reset persistence failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Execution record store

@ModelActor
public actor SwiftDataExecutionRecordStore: ExecutionRecordStoring {
    /// Retention for run history, stated rather than omitted.
    ///
    /// Every other durable table in this file carries a cap with a written argument, and
    /// `SwiftDataEvalResultStore` carries a written argument for deliberately having *none* (dropping
    /// old grades would flatter an improving operator). This table had neither: it grew by one row
    /// per routine run, forever, fed by a background scan that fires on a cadence. That is F-24's
    /// shape — the one table that got no retention while being the one a generator appends to.
    ///
    /// Run history does not have `SwiftDataEvalResultStore`'s reason to be unbounded. Nothing grades
    /// an operator on its oldest runs: the trigger evaluator reads only the *latest* record per
    /// playbook, and Mission Control shows a recent list. 2,000 rows is a few months of a busy
    /// install and keeps the whole table cheap to sweep.
    ///
    /// Pruned by `startedAt` — the newest are kept — and never partially: a record is one row, so
    /// unlike the worklog there is no multi-row trace to split.
    static let maximumStoredRecords = 2_000

    private var retentionCap = SwiftDataExecutionRecordStore.maximumStoredRecords
    private var didBackfillQueryColumns = false

    /// Test seam, for the reason ``SwiftDataWorklogStore/setRetentionCap(_:)`` is one: so tests can
    /// drive the retention *policy* without writing thousands of rows.
    func setRetentionCap(_ cap: Int) {
        retentionCap = cap
    }

    public func store(_ record: ExecutionRecord) {
        do {
            let data = try JSONEncoder().encode(record)
            // Allocated the way ``SwiftDataRuntimeEventStore`` allocates its own: read the current
            // maximum and add one, inside this actor so two stores cannot interleave.
            var latestDescriptor = FetchDescriptor<StoredExecutionRecordRow>(
                sortBy: [SortDescriptor(\StoredExecutionRecordRow.sequence, order: .reverse)]
            )
            latestDescriptor.fetchLimit = 1
            let nextSequence = ((try modelContext.fetch(latestDescriptor).first?.sequence) ?? 0) + 1
            modelContext.insert(
                StoredExecutionRecordRow(
                    id: record.id,
                    playbookID: record.playbookID,
                    startedAt: record.startedAt,
                    sequence: nextSequence,
                    data: data
                )
            )
            try pruneStoredRecords(keepingNewest: retentionCap)
            try modelContext.save()
        } catch {
            // Rolled back, so a failed prune cannot leave the insert half-applied in the context and
            // be committed by an unrelated later save.
            modelContext.rollback()
            storageLogger.error("Execution record persistence failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func all() -> [ExecutionRecord] {
        backfillQueryColumnsIfNeeded()
        do {
            return try modelContext.fetch(FetchDescriptor<StoredExecutionRecordRow>())
                .compactMap { decodeStoredBlob(ExecutionRecord.self, from: $0.data, row: "executionRecord") }
        } catch {
            storageLogger.error("Execution record lookup failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// The newest record for one playbook, resolved by the store rather than by decoding the table.
    ///
    /// This used to be `all().filter { }.max { }`, which decoded every execution record ever written
    /// to return one — and `RuntimeHost.runDueRoutines` calls it once per installed playbook, so a
    /// background scan over N playbooks paid N full-table decodes against an unbounded table.
    ///
    /// **The tie-break matches ``InMemoryExecutionRecordStore/latest(forPlaybookID:)`` — last
    /// recorded wins.** Two implementations of one protocol method disagreeing about which of two
    /// records sharing a `startedAt` is "latest" is the divergence F-26 was raised for, and that
    /// contract is pinned by `latestPrefersTheMostRecentlyRecordedRunOnATie`. The in-memory store
    /// gets it by reversing before `max(by:)` (which keeps the *first* of equally-ranked elements);
    /// this one gets it from ``StoredExecutionRecordRow/sequence``, because a durable store cannot
    /// observe insertion order without recording it. Sorting on `id` would have picked an arbitrary
    /// UUID, and the previous version sorted on nothing at all.
    public func latest(forPlaybookID playbookID: String) -> ExecutionRecord? {
        backfillQueryColumnsIfNeeded()
        let target = playbookID
        var descriptor = FetchDescriptor<StoredExecutionRecordRow>(
            predicate: #Predicate { $0.playbookID == target },
            sortBy: [
                SortDescriptor(\StoredExecutionRecordRow.startedAt, order: .reverse),
                SortDescriptor(\StoredExecutionRecordRow.sequence, order: .reverse)
            ]
        )
        // Not 1: a row whose blob will not decode must not shadow the readable record behind it,
        // which is the listing-vs-`get` rule F-32 established for the artifact store. A small window
        // bounds the cost while still tolerating a corrupt row.
        descriptor.fetchLimit = 8
        do {
            return try modelContext.fetch(descriptor)
                .lazy
                .compactMap { decodeStoredBlob(ExecutionRecord.self, from: $0.data, row: "executionRecord") }
                .first
        } catch {
            storageLogger.error("Execution record lookup failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    public func resetAll() {
        do {
            for row in try modelContext.fetch(FetchDescriptor<StoredExecutionRecordRow>()) {
                modelContext.delete(row)
            }
            try modelContext.save()
            // Cleared with the rows: the columns it would have filled are gone, and leaving it set
            // would skip the backfill for pre-column rows a later restore brings back.
            didBackfillQueryColumns = false
        } catch {
            modelContext.rollback()
            storageLogger.error("Execution record reset persistence failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Fills ``StoredExecutionRecordRow/playbookID`` and `startedAt` on rows written before those
    /// columns existed, so a predicate can match them.
    ///
    /// One-shot per store instance and scoped by predicate to the rows that need it, so the ordinary
    /// case costs one `fetchCount`-shaped query and nothing else. Same shape and same reason as
    /// `ReceiptPersistenceStore.backfillAccountKeysIfNeeded()`.
    private func backfillQueryColumnsIfNeeded() {
        guard !didBackfillQueryColumns else { return }
        didBackfillQueryColumns = true
        do {
            let stale = try modelContext.fetch(
                FetchDescriptor<StoredExecutionRecordRow>(predicate: #Predicate { $0.playbookID == "" })
            )
            guard !stale.isEmpty else { return }
            let decoded = stale.compactMap { row -> (StoredExecutionRecordRow, ExecutionRecord)? in
                guard let record = decodeStoredBlob(ExecutionRecord.self, from: row.data, row: "executionRecord") else {
                    return nil
                }
                return (row, record)
            }
            // Sequences assigned in `startedAt` order rather than fetch order, and *below* every
            // sequence a post-column write could hold. Pre-column rows have no recorded insertion
            // order to recover, so this picks the only deterministic answer available from the data
            // and keeps legacy rows ranked beneath new ones on a tie.
            for (offset, pair) in decoded.sorted(by: { $0.1.startedAt < $1.1.startedAt }).enumerated() {
                pair.0.playbookID = pair.1.playbookID
                pair.0.startedAt = pair.1.startedAt
                pair.0.sequence = -decoded.count + offset
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            // Latched anyway: a backfill that cannot commit will not commit on the next call either,
            // and retrying it on every read would put a failing write in front of every lookup.
            storageLogger.error("Execution record backfill failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func pruneStoredRecords(keepingNewest maximumCount: Int) throws {
        guard maximumCount > 0 else {
            for row in try modelContext.fetch(FetchDescriptor<StoredExecutionRecordRow>()) {
                modelContext.delete(row)
            }
            return
        }
        let storedCount = try modelContext.fetchCount(FetchDescriptor<StoredExecutionRecordRow>())
        guard storedCount > maximumCount else { return }

        // Oldest first, on the same two keys `latest` ranks by, so the row the sweep removes is never
        // the row a lookup would have returned.
        var descriptor = FetchDescriptor<StoredExecutionRecordRow>(
            sortBy: [
                SortDescriptor(\StoredExecutionRecordRow.startedAt, order: .forward),
                SortDescriptor(\StoredExecutionRecordRow.sequence, order: .forward)
            ]
        )
        descriptor.fetchLimit = storedCount - maximumCount
        for row in try modelContext.fetch(descriptor) {
            modelContext.delete(row)
        }
    }
}

// MARK: - Worklog store

@ModelActor
public actor SwiftDataWorklogStore: WorklogStoring {
    /// Soft cap on retained trace entries, above which completed workflows are dropped.
    ///
    /// Matches ``SwiftDataRuntimeEventHistoryStore/maximumStoredEvents``: the worklog is the
    /// highest-volume runtime table now that scheduled routines write a phase per run, so it needs
    /// the same order-of-magnitude bound. Soft rather than hard by design — see ``record(_:)``.
    public static let maximumStoredSteps = 10_000

    /// How many new entries must accumulate before an unproductive sweep is retried.
    ///
    /// ``pruneCompletedWorkflows(keepingAtMost:)`` is O(rows): it fetches the whole table and decodes
    /// candidate groups. Paying that once on crossing the cap is fine, but the cap is deliberately
    /// *soft* — blocked, failed, and still-running traces are never dropped — so "over the cap with
    /// nothing droppable" is a steady state the design intends to reach, not an anomaly. Sweeping on
    /// every write would then make every worklog write O(rows) for as long as the device stayed
    /// there, which is exactly when the table is largest. Retrying only after this many new entries
    /// bounds the amortized cost to O(rows / pruneRetryGrowth) per write; the price is sitting up to
    /// this many entries above a cap that is already advisory.
    static let pruneRetryGrowth = 256

    /// The cap the write path enforces.
    private var retentionCap = SwiftDataWorklogStore.maximumStoredSteps

    /// Lowers the cap the write path enforces. Internal for the same reason
    /// ``pruneCompletedWorkflows(keepingAtMost:)`` is: so tests can drive the retention *policy*,
    /// including its backoff, at a small cap instead of inserting ten thousand rows to reach the
    /// real one.
    func setRetentionCap(_ cap: Int) {
        retentionCap = cap
    }

    /// The row count left by the last sweep that could not get under the cap, or `nil` when a sweep
    /// is due. Internal so tests can observe that an unproductive sweep is not repeated.
    /// See ``pruneRetryGrowth``.
    private(set) var unprunableFloor: Int?
    private var storeHealth = WorklogStoreHealth()

    /// - Note: `@discardableResult` has to be restated here. The attribute is not inherited from the
    ///   ``WorklogRecording/record(_:)`` requirement, and both of AuralisRuntime's own conformances
    ///   carry it, so omitting it on the one durable implementation made every caller that ignores
    ///   the result warn against *this* store and not against the in-memory ones.
    @discardableResult
    public func record(_ step: WorkflowStepLog) -> WorklogRecordResult {
        let validated: WorkflowStepLog
        let data: Data
        do {
            validated = try step.validated()
            data = try JSONEncoder().encode(validated)
        } catch {
            return noteFailure(.init(operation: .encode, message: error.localizedDescription))
        }
        let existing: StoredWorkflowStepLogRow?
        do {
            existing = try modelContext.fetch(FetchDescriptor<StoredWorkflowStepLogRow>(
                predicate: #Predicate { $0.id == step.id }
            )).first
        } catch {
            return noteFailure(.init(operation: .fetch, message: error.localizedDescription))
        }
        if let row = existing {
            row.correlationID = step.correlationID
            row.timestamp = step.timestamp
            row.data = data
        } else {
            modelContext.insert(
                StoredWorkflowStepLogRow(
                    id: step.id,
                    correlationID: step.correlationID,
                    timestamp: step.timestamp,
                    data: data
                )
            )
        }
        pruneIfNeeded(having: step)
        do {
            try modelContext.save()
            storeHealth = WorklogStoreHealth(lastSuccessfulWriteAt: .now)
            return .recorded
        } catch {
            modelContext.rollback()
            return noteFailure(.init(operation: .save, message: error.localizedDescription))
        }
    }

    private func noteFailure(_ failure: WorklogFailure) -> WorklogRecordResult {
        storageLogger.error("\(failure.localizedDescription, privacy: .public)")
        storeHealth = WorklogStoreHealth(
            lastSuccessfulWriteAt: storeHealth.lastSuccessfulWriteAt,
            lastFailureAt: .now,
            lastFailure: failure,
            failedOperationCount: storeHealth.failedOperationCount + 1
        )
        return .failed(failure)
    }

    public func health() -> WorklogStoreHealth { storeHealth }

    /// Runs the retention sweep only when it is both needed and likely to accomplish something.
    ///
    /// The count check is a `fetchCount`, so the common under-cap case stays a single aggregate
    /// query per write and never materializes a row.
    private func pruneIfNeeded(having step: WorkflowStepLog) {
        let storedCount = (try? modelContext.fetchCount(FetchDescriptor<StoredWorkflowStepLogRow>())) ?? 0
        guard storedCount > retentionCap else {
            unprunableFloor = nil
            return
        }
        // A step that completes a workflow is precisely what turns an undroppable group droppable,
        // so it clears the backoff at once instead of waiting out the growth window.
        if Self.completesWorkflow(step.event) { unprunableFloor = nil }
        if let floor = unprunableFloor, storedCount < floor + Self.pruneRetryGrowth { return }

        let remaining = pruneCompletedWorkflows(keepingAtMost: retentionCap)
        unprunableFloor = remaining > retentionCap ? remaining : nil
    }

    public func allSteps() -> [WorkflowStepLog] {
        do {
            return try modelContext.fetch(FetchDescriptor<StoredWorkflowStepLogRow>(
                sortBy: [SortDescriptor(\StoredWorkflowStepLogRow.timestamp, order: .reverse)]
            )).compactMap(Self.decode)
        } catch {
            _ = noteFailure(.init(operation: .fetch, message: error.localizedDescription))
            return []
        }
    }

    public func steps(forCorrelationID correlationID: String) -> [WorkflowStepLog] {
        let target = correlationID
        do {
            return try modelContext.fetch(FetchDescriptor<StoredWorkflowStepLogRow>(
                predicate: #Predicate { $0.correlationID == target },
                sortBy: [SortDescriptor(\StoredWorkflowStepLogRow.timestamp, order: .reverse)]
            )).compactMap(Self.decode)
        } catch {
            _ = noteFailure(.init(operation: .fetch, message: error.localizedDescription))
            return []
        }
    }

    public func exportAll() throws -> Data {
        try WorklogExport.encode(allSteps())
    }

    public func resetAll() {
        do {
            for row in try modelContext.fetch(FetchDescriptor<StoredWorkflowStepLogRow>()) {
                modelContext.delete(row)
            }
            try modelContext.save()
            storeHealth = WorklogStoreHealth()
        } catch {
            modelContext.rollback()
            _ = noteFailure(.init(operation: .reset, message: error.localizedDescription))
        }
    }

    private static func decode(_ row: StoredWorkflowStepLogRow) -> WorkflowStepLog? {
        decodeStoredBlob(WorkflowStepLog.self, from: row.data, row: "worklogStep")
    }

    /// Drops the oldest *completed* workflows once the trace exceeds `maximum`.
    ///
    /// Retention is by whole workflow, not by row. Pruning the oldest N rows would decapitate a long
    /// trace and leave `steps(forCorrelationID:)` returning a partial history that reads as though the
    /// workflow began midway — worse than not having it. So a correlation group is deleted all at
    /// once, and only after it reached a terminal *completed* state (`.executed`, or
    /// `.routinePhase(.completed, _)` for a scheduled run).
    ///
    /// Blocked, failed, escalated, and still-running traces are never dropped: those are the ones
    /// worth keeping, and an old unresolved workflow is more valuable than a recent successful one.
    /// That makes the cap deliberately soft — a device carrying more than `maximum` entries of
    /// unfinished work stays above it rather than deleting the evidence of why work stalled.
    /// - Note: Internal rather than private so tests can exercise the policy at a small cap instead of
    ///   inserting ten thousand rows to reach the real one.
    /// - Returns: The number of entries left behind, which ``pruneIfNeeded(having:)`` uses to decide
    ///   whether another sweep at this size could achieve anything.
    @discardableResult
    func pruneCompletedWorkflows(keepingAtMost maximum: Int) -> Int {
        let storedCount = (try? modelContext.fetchCount(FetchDescriptor<StoredWorkflowStepLogRow>())) ?? 0
        guard storedCount > maximum else { return storedCount }

        let rows = (try? modelContext.fetch(FetchDescriptor<StoredWorkflowStepLogRow>(
            sortBy: [SortDescriptor(\StoredWorkflowStepLogRow.timestamp, order: .forward)]
        ))) ?? []

        // Group by workflow. An uncorrelated entry becomes its own single-entry group: it has no
        // workflow to have completed, so it is only ever eligible on the strength of its own event.
        var groups: [String: [StoredWorkflowStepLogRow]] = [:]
        var oldestFirst: [String] = []
        for row in rows {
            let key = row.correlationID ?? "entry:\(row.id.uuidString)"
            if groups[key] == nil { oldestFirst.append(key) }
            groups[key, default: []].append(row)
        }

        // `oldestFirst` is ordered by each group's earliest entry, so completed workflows are dropped
        // oldest-first and pruning stops as soon as the store is back under the cap.
        var remaining = storedCount
        for key in oldestFirst {
            guard remaining > maximum else { break }
            guard let group = groups[key], Self.reachedCompletion(group) else { continue }
            for row in group {
                modelContext.delete(row)
            }
            remaining -= group.count
        }

        if remaining > maximum {
            storageLogger.notice(
                "Worklog above retention cap with no completed workflows left to drop: \(remaining, privacy: .public) entries"
            )
        }
        return remaining
    }

    /// Whether a workflow's entries show it reaching a terminal *completed* state.
    private static func reachedCompletion(_ group: [StoredWorkflowStepLogRow]) -> Bool {
        var decodableCount = 0
        for row in group {
            guard let step = decode(row) else { continue }
            decodableCount += 1
            // One completion settles the group, so a long trace is not decoded in full just to
            // re-confirm what its first executed step already established.
            if completesWorkflow(step.event) { return true }
        }
        // A group no reader can decode is already absent from every listing, so retaining it forever
        // would let corrupt rows pin the store above its cap. Note this is now a narrow escape
        // hatch: since `WorkflowWorklogEvent` decodes unfamiliar events as `.unknown`, a row only
        // fails outright when the entry's own required columns are unreadable.
        return decodableCount == 0
    }

    /// Whether an event marks its workflow as having finished successfully, and its trace therefore
    /// as eligible for retention pruning.
    static func completesWorkflow(_ event: WorkflowWorklogEvent) -> Bool {
        switch event {
        case .executed, .routinePhase(.completed, _):
            return true
        case .considered, .proposed, .checksEvaluated, .decided, .blocked, .failed, .routinePhase:
            return false
        case .unknown:
            // Pruning is deletion, and a step this build cannot interpret is exactly the evidence
            // worth keeping — treating it as a completion would let a downgrade delete the trace of
            // work it never understood.
            return false
        }
    }
}

// MARK: - Agent session store

@ModelActor
public actor SwiftDataAgentSessionStore: AgentSessionStoring {
    /// How many *completed* sessions are retained, oldest dropped first.
    ///
    /// One row per correlation ID, written by `ReceiptStoreSink` and `RuntimeHost` for every governed
    /// session, and nothing removed them — so this grew at roughly the execution-record cadence with
    /// none of its cap, and `allSessions()` decodes the whole table on each Mission Control read.
    ///
    /// Only `.completed` is eligible, following the rule
    /// ``SwiftDataWorklogStore/pruneCompletedWorkflows(keepingAtMost:)`` sets: `.failed` and
    /// `.blocked` are the sessions worth keeping, and `.active` / `.waitingForApproval` are live work
    /// — one of them is a person's pending approval, and dropping it would discard the request
    /// rather than a record of one. A session's evidence outlives its row regardless: the receipts
    /// it indexes are append-only and recoverable through `receipts(forCorrelationID:)`.
    public static let maximumStoredCompletedSessions = 1_000

    /// Compared against the denormalised `statusRawValue` column so the sweep never decodes a blob.
    private static let retiredStatus = AgentSessionStatus.completed.rawValue

    private var maximumCompletedSessions = SwiftDataAgentSessionStore.maximumStoredCompletedSessions

    /// Test seam, for the same reason ``SwiftDataWorklogStore/setRetentionCap(_:)`` is one: so tests
    /// can drive the retention *policy* without writing a thousand sessions.
    func setRetentionCap(_ cap: Int) {
        maximumCompletedSessions = cap
    }

    public func upsert(_ session: AgentSession) {
        do {
            let data = try JSONEncoder().encode(session)
            let target = session.correlationID
            if let row = try modelContext.fetch(FetchDescriptor<StoredAgentSessionRow>(
                predicate: #Predicate { $0.correlationID == target }
            )).first {
                row.startedAt = session.startedAt
                row.statusRawValue = session.status.rawValue
                row.data = data
            } else {
                modelContext.insert(
                    StoredAgentSessionRow(
                        correlationID: session.correlationID,
                        startedAt: session.startedAt,
                        statusRawValue: session.status.rawValue,
                        data: data
                    )
                )
            }
            pruneCompletedSessions(sparing: target)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            storageLogger.error("Agent session persistence failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Drops the oldest completed sessions once more than ``maximumStoredCompletedSessions`` have
    /// accumulated.
    ///
    /// On the write path, matching ``SwiftDataCapabilityLeaseStore/pruneDeadLeases(at:sparing:)`` — a
    /// read should not mutate, and the write path is where growth happens.
    ///
    /// - Parameter spared: The row the calling ``upsert(_:)`` just wrote, never collected here. A
    ///   caller has to be able to read back what it persisted, and a session is *completed* by
    ///   upserting it into that status, so the row being retired is frequently also a candidate.
    private func pruneCompletedSessions(sparing spared: String) {
        let retired = Self.retiredStatus
        var descriptor = FetchDescriptor<StoredAgentSessionRow>(
            predicate: #Predicate { $0.statusRawValue == retired && $0.correlationID != spared },
            sortBy: [SortDescriptor(\StoredAgentSessionRow.startedAt, order: .forward)]
        )
        guard let retiredCount = try? modelContext.fetchCount(descriptor),
              retiredCount > maximumCompletedSessions else { return }
        descriptor.fetchLimit = retiredCount - maximumCompletedSessions
        for row in (try? modelContext.fetch(descriptor)) ?? [] {
            modelContext.delete(row)
        }
    }

    public func session(correlationID: String) -> AgentSession? {
        let target = correlationID
        return ((try? modelContext.fetch(FetchDescriptor<StoredAgentSessionRow>(
            predicate: #Predicate { $0.correlationID == target }
        ))) ?? [])
        .compactMap(Self.decode)
        .first
    }

    public func allSessions() -> [AgentSession] {
        ((try? modelContext.fetch(FetchDescriptor<StoredAgentSessionRow>(
            sortBy: [SortDescriptor(\StoredAgentSessionRow.startedAt, order: .reverse)]
        ))) ?? [])
        .compactMap(Self.decode)
    }

    public func resetAll() {
        do {
            for row in try modelContext.fetch(FetchDescriptor<StoredAgentSessionRow>()) {
                modelContext.delete(row)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            storageLogger.error("Agent session reset failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func decode(_ row: StoredAgentSessionRow) -> AgentSession? {
        decodeStoredBlob(AgentSession.self, from: row.data, row: "agentSession")
    }
}

// MARK: - Runtime event history store

@ModelActor
public actor SwiftDataRuntimeEventHistoryStore: RuntimeEventHistoryStoring {
    /// Local retention guard for durable runtime history.
    ///
    /// UI callers should still request smaller read limits. This cap prevents a
    /// long-running device from accumulating an unbounded local archive while
    /// retaining substantially more context than the original 500-event guess.
    public static let maximumStoredEvents = 10_000

    /// - Throws: whatever the encode, the fetch, the sweep, or the commit threw. **The context is
    ///   rolled back first, so a throw means nothing was left pending** — the same guarantee
    ///   ``SwiftDataPerformanceStore/record(_:)`` and ``SwiftDataExecutionRecordStore/store(_:)``
    ///   give, and it is load-bearing here because this actor holds one long-lived `modelContext`
    ///   across every call. Without the rollback, an `append` that threw left its insert *and* the
    ///   sweep's deletions staged, and the next `append` committed the lot: an event the caller was
    ///   told had not been recorded would appear in the history, alongside rows the failed sweep had
    ///   marked for deletion. This one rethrows rather than swallowing because
    ///   `RuntimeEventHistoryStoring.append` is a throwing requirement and its callers act on it.
    public func append(_ event: WorkflowEventEnvelope) throws {
        do {
            let data = try JSONEncoder().encode(event)
            let target = event.id
            if let row = try modelContext.fetch(FetchDescriptor<StoredRuntimeEventRow>(
                predicate: #Predicate { $0.id == target }
            )).first {
                row.timestamp = event.timestamp
                row.correlationID = event.correlationID
                row.data = data
            } else {
                var latestDescriptor = FetchDescriptor<StoredRuntimeEventRow>(
                    sortBy: [SortDescriptor(\StoredRuntimeEventRow.sequence, order: .reverse)]
                )
                latestDescriptor.fetchLimit = 1
                let nextSequence = ((try modelContext.fetch(latestDescriptor).first?.sequence) ?? 0) + 1
                modelContext.insert(
                    StoredRuntimeEventRow(
                        id: event.id,
                        timestamp: event.timestamp,
                        sequence: nextSequence,
                        correlationID: event.correlationID,
                        data: data
                    )
                )
            }
            try pruneStoredEvents(keepingNewest: Self.maximumStoredEvents)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    public func recentEvents(limit: Int) -> [WorkflowEventEnvelope] {
        guard limit > 0 else { return [] }
        var descriptor = FetchDescriptor<StoredRuntimeEventRow>(
            sortBy: [
                SortDescriptor(\StoredRuntimeEventRow.sequence, order: .reverse),
                SortDescriptor(\StoredRuntimeEventRow.timestamp, order: .reverse),
                SortDescriptor(\StoredRuntimeEventRow.id, order: .reverse)
            ]
        )
        descriptor.fetchLimit = limit
        return ((try? modelContext.fetch(descriptor)) ?? [])
            .compactMap(Self.decode)
    }

    public func resetAll() {
        do {
            for row in try modelContext.fetch(FetchDescriptor<StoredRuntimeEventRow>()) {
                modelContext.delete(row)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            storageLogger.error("Runtime event history reset failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func decode(_ row: StoredRuntimeEventRow) -> WorkflowEventEnvelope? {
        decodeStoredBlob(WorkflowEventEnvelope.self, from: row.data, row: "runtimeEvent")
    }

    private func pruneStoredEvents(keepingNewest maximumCount: Int) throws {
        guard maximumCount > 0 else {
            for row in try modelContext.fetch(FetchDescriptor<StoredRuntimeEventRow>()) {
                modelContext.delete(row)
            }
            return
        }

        let storedCount = try modelContext.fetchCount(FetchDescriptor<StoredRuntimeEventRow>())
        guard storedCount > maximumCount else { return }

        var descriptor = FetchDescriptor<StoredRuntimeEventRow>(
            sortBy: [
                SortDescriptor(\StoredRuntimeEventRow.sequence, order: .forward),
                SortDescriptor(\StoredRuntimeEventRow.timestamp, order: .forward),
                SortDescriptor(\StoredRuntimeEventRow.id, order: .forward)
            ]
        )
        descriptor.fetchLimit = storedCount - maximumCount

        for row in try modelContext.fetch(descriptor) {
            modelContext.delete(row)
        }
    }
}

// MARK: - Capability lease store

@ModelActor
public actor SwiftDataCapabilityLeaseStore: CapabilityLeaseStoring {
    /// How long a lease row outlives its own expiry before the sweep drops it.
    ///
    /// Leases were one of the two durable tables this actor owns that had no retention at all — the
    /// other is the restriction table swept by ``pruneDeadRestrictions(at:sparing:)``, and an earlier
    /// version of this comment wrongly claimed leases were the only one. They are minted steadily
    /// rather than on demand: ``RuntimeHost/seedRoutineAuthority(duration:renewalMargin:at:)``
    /// grants standing authority for every installed playbook capability to both the routine and the
    /// person, on a 24-hour lease, at every bootstrap. That is roughly ten new rows a day for the
    /// built-in catalog alone, none of which was ever removed, and `CapabilityLeaseRegistry` decodes
    /// the whole table on first use — so launch cost grew linearly for the life of the install.
    ///
    /// A month is chosen to comfortably outlast any live lease while still bounding the table. It is
    /// not an audit window and does not need to be: dropping a row erases no history, because the
    /// *ledger* is where authority history lives. ``RuntimeReceiptObserver`` receipts every grant,
    /// revocation, and expiry, and receipts are append-only. These rows are enforcement state, and a
    /// lease this far past its expiry can no longer permit anything.
    public static let deadLeaseRetention: TimeInterval = 30 * 24 * 60 * 60

    /// Backstop for the age window, in case something mints leases far faster than the standing
    /// seed does — a burst of operator runs, each of which takes a short-lived grant. The window
    /// alone bounds a steady rate; this bounds a spike.
    public static let maximumStoredDeadLeases = 2_000

    /// How long a *restriction* row outlives its own expiry before the sweep drops it.
    ///
    /// The same window as ``deadLeaseRetention``, and for the same reason: restrictions are the
    /// other half of the authority state this actor persists, they are minted with a fresh UUID on
    /// every `RuntimeHost.restrictCapability` rather than updated in place, and nothing but
    /// ``resetAll()`` ever removed one. ``allRestrictions()`` JSON-decodes the whole table, and that
    /// read is what `CapabilityLeaseRegistry` performs on first use — i.e. on the launch path, the
    /// same cost ``deadLeaseRetention`` was introduced to bound for leases.
    ///
    /// Dropping a row erases no history here either: ``RuntimeReceiptObserver`` receipts every
    /// restriction and revocation, and receipts are append-only. A restriction this far past its
    /// expiry can no longer deny anything.
    public static let deadRestrictionRetention: TimeInterval = 30 * 24 * 60 * 60

    /// Backstop for the restriction age window, matching ``maximumStoredDeadLeases``: the window
    /// alone bounds a steady rate, this bounds a burst of short-lived session restrictions.
    public static let maximumStoredDeadRestrictions = 2_000

    private var deadLeaseRetention = SwiftDataCapabilityLeaseStore.deadLeaseRetention
    private var maximumDeadLeases = SwiftDataCapabilityLeaseStore.maximumStoredDeadLeases
    private var deadRestrictionRetention = SwiftDataCapabilityLeaseStore.deadRestrictionRetention
    private var maximumDeadRestrictions = SwiftDataCapabilityLeaseStore.maximumStoredDeadRestrictions

    /// Test seam, for the same reason ``SwiftDataWorklogStore/setRetentionCap(_:)`` is one: so tests
    /// can drive the retention *policy* without materialising a month of leases.
    func setRetentionPolicy(deadLeaseRetention: TimeInterval, maximumDeadLeases: Int) {
        self.deadLeaseRetention = deadLeaseRetention
        self.maximumDeadLeases = maximumDeadLeases
    }

    /// Test seam for the restriction sweep, kept separate from ``setRetentionPolicy(deadLeaseRetention:maximumDeadLeases:)``
    /// so a test that drives one table's policy cannot silently change the other's.
    func setRestrictionRetentionPolicy(deadRestrictionRetention: TimeInterval, maximumDeadRestrictions: Int) {
        self.deadRestrictionRetention = deadRestrictionRetention
        self.maximumDeadRestrictions = maximumDeadRestrictions
    }

    public func upsert(_ lease: CapabilityLease) {
        do {
            let data = try JSONEncoder().encode(lease)
            let target = lease.id
            if let row = try modelContext.fetch(FetchDescriptor<StoredCapabilityLeaseRow>(
                predicate: #Predicate { $0.id == target }
            )).first {
                row.grantedAt = lease.grantedAt
                row.expiresAt = lease.expiresAt
                row.revokedAt = lease.revokedAt
                row.data = data
            } else {
                modelContext.insert(
                    StoredCapabilityLeaseRow(
                        id: lease.id,
                        grantedAt: lease.grantedAt,
                        expiresAt: lease.expiresAt,
                        revokedAt: lease.revokedAt,
                        data: data
                    )
                )
            }
            pruneDeadLeases(at: Date(), sparing: target)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            storageLogger.error("Capability lease persistence failed: \(error.localizedDescription, privacy: .public)")
        }
        // On the write path, matching ``SwiftDataRuntimeEventHistoryStore/append(_:)``, rather than
        // on `allLeases()`: a read should not mutate. Standing authority is re-seeded during every
        // bootstrap, so the sweep still runs early in each launch.
    }

    /// Drops lease rows that expired long enough ago to be useless, and caps how many such rows may
    /// survive regardless.
    ///
    /// **A live lease can never be dropped by either sweep, by construction.** Both select only rows
    /// whose `expiresAt` is strictly in the past — the age sweep against `now - deadLeaseRetention`,
    /// the backstop against `now` — while "live" requires `now < expiresAt`. That matters more than
    /// the retention numbers do: `CapabilityLeaseRegistry` fails closed, so deleting a grant that was
    /// still good would silently turn a working routine into a `.blocked` run.
    ///
    /// Keyed on `expiresAt` alone, deliberately, rather than on "revoked or expired". Revocation only
    /// ever *shortens* a lease's usefulness, so a revoked row is certainly dead by the time its own
    /// expiry clears the window — it is collected slightly later than it strictly could be, and in
    /// exchange the predicate stays a single-column comparison that cannot misclassify a live row.
    ///
    /// - Parameter spared: The row the calling ``upsert(_:)`` just wrote, which is never collected
    ///   here however long ago it expired. A caller has to be able to read back what it persisted —
    ///   `revoke` re-upserts a lease that is often already dead — and one exempt row cannot unbound
    ///   the table, because the next write sweeps it like any other.
    private func pruneDeadLeases(at now: Date, sparing spared: UUID) {
        let cutoff = now.addingTimeInterval(-deadLeaseRetention)
        let agedOut = FetchDescriptor<StoredCapabilityLeaseRow>(
            predicate: #Predicate { $0.expiresAt < cutoff && $0.id != spared }
        )
        for row in (try? modelContext.fetch(agedOut)) ?? [] {
            modelContext.delete(row)
        }

        var deadDescriptor = FetchDescriptor<StoredCapabilityLeaseRow>(
            predicate: #Predicate { $0.expiresAt < now && $0.id != spared },
            sortBy: [SortDescriptor(\StoredCapabilityLeaseRow.expiresAt, order: .forward)]
        )
        guard let deadCount = try? modelContext.fetchCount(deadDescriptor),
              deadCount > maximumDeadLeases else { return }
        // Oldest-expiring first, so the survivors are the most recently lapsed.
        deadDescriptor.fetchLimit = deadCount - maximumDeadLeases
        for row in (try? modelContext.fetch(deadDescriptor)) ?? [] {
            modelContext.delete(row)
        }
    }

    public func upsert(_ restriction: CapabilityRestriction) {
        do {
            let data = try JSONEncoder().encode(restriction)
            let target = restriction.id
            if let row = try modelContext.fetch(FetchDescriptor<StoredCapabilityRestrictionRow>(
                predicate: #Predicate { $0.id == target }
            )).first {
                row.createdAt = restriction.createdAt
                row.expiresAt = restriction.expiresAt
                row.revokedAt = restriction.revokedAt
                row.data = data
            } else {
                modelContext.insert(
                    StoredCapabilityRestrictionRow(
                        id: restriction.id,
                        createdAt: restriction.createdAt,
                        expiresAt: restriction.expiresAt,
                        revokedAt: restriction.revokedAt,
                        data: data
                    )
                )
            }
            pruneDeadRestrictions(at: Date(), sparing: target)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            storageLogger.error("Capability restriction persistence failed: \(error.localizedDescription, privacy: .public)")
        }
        // On the write path for the same reason ``upsert(_ lease:)`` sweeps there: a read should not
        // mutate, and `allRestrictions()` is the launch-path read this sweep exists to keep cheap.
    }

    /// Drops restriction rows that expired long enough ago to be useless, and caps how many such
    /// rows may survive regardless. The lease sweep's shape, applied to the other authority table.
    ///
    /// **An indefinite restriction — `expiresAt == nil` — can never be collected by either sweep.**
    /// That is the one way this differs from ``pruneDeadLeases(at:sparing:)``, where `expiresAt` is
    /// non-optional, and it is the difference that matters: a lease *grants*, so losing one fails
    /// closed, but a restriction *denies*, so losing one fails **open** — a standing "no wallet
    /// access" rule swept away silently re-permits the thing it was written to forbid. Both
    /// predicates therefore coalesce a missing expiry to `never`, which no cutoff can precede, so a
    /// nil row is not merely ranked last in the backstop sweep but excluded from its count.
    ///
    /// Keyed on `expiresAt` alone rather than "revoked or expired", exactly as the lease sweep is:
    /// revocation only ever shortens a restriction's reach, so a revoked row is certainly dead once
    /// its own expiry clears the window, and the predicate stays a comparison that cannot
    /// misclassify a row that is still denying something.
    ///
    /// - Parameter spared: The row the calling ``upsert(_:)`` just wrote, never collected here
    ///   however long ago it expired — a caller has to be able to read back what it persisted, and
    ///   `revoke` re-upserts a restriction that is often already lapsed. One exempt row cannot
    ///   unbound the table, because the next write sweeps it like any other.
    private func pruneDeadRestrictions(at now: Date, sparing spared: UUID) {
        // Captured as a local so the predicate compares two plain `Date` values; a restriction with
        // no expiry is treated as expiring at the end of time, which is never before any cutoff.
        let never = Date.distantFuture
        let cutoff = now.addingTimeInterval(-deadRestrictionRetention)
        let agedOut = FetchDescriptor<StoredCapabilityRestrictionRow>(
            predicate: #Predicate { ($0.expiresAt ?? never) < cutoff && $0.id != spared }
        )
        for row in (try? modelContext.fetch(agedOut)) ?? [] {
            modelContext.delete(row)
        }

        var deadDescriptor = FetchDescriptor<StoredCapabilityRestrictionRow>(
            predicate: #Predicate { ($0.expiresAt ?? never) < now && $0.id != spared },
            sortBy: [SortDescriptor(\StoredCapabilityRestrictionRow.expiresAt, order: .forward)]
        )
        guard let deadCount = try? modelContext.fetchCount(deadDescriptor),
              deadCount > maximumDeadRestrictions else { return }
        // Oldest-expiring first, so the survivors are the most recently lapsed.
        deadDescriptor.fetchLimit = deadCount - maximumDeadRestrictions
        for row in (try? modelContext.fetch(deadDescriptor)) ?? [] {
            modelContext.delete(row)
        }
    }

    public func allLeases() -> [CapabilityLease] {
        ((try? modelContext.fetch(FetchDescriptor<StoredCapabilityLeaseRow>(
            sortBy: [SortDescriptor(\StoredCapabilityLeaseRow.grantedAt, order: .reverse)]
        ))) ?? [])
        .compactMap(Self.decode)
    }

    public func allRestrictions() -> [CapabilityRestriction] {
        ((try? modelContext.fetch(FetchDescriptor<StoredCapabilityRestrictionRow>(
            sortBy: [SortDescriptor(\StoredCapabilityRestrictionRow.createdAt, order: .reverse)]
        ))) ?? [])
        .compactMap(Self.decode)
    }

    public func resetAll() {
        do {
            for row in try modelContext.fetch(FetchDescriptor<StoredCapabilityLeaseRow>()) {
                modelContext.delete(row)
            }
            for row in try modelContext.fetch(FetchDescriptor<StoredCapabilityRestrictionRow>()) {
                modelContext.delete(row)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            storageLogger.error("Capability authority reset failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func decode(_ row: StoredCapabilityLeaseRow) -> CapabilityLease? {
        decodeStoredBlob(CapabilityLease.self, from: row.data, row: "capabilityLease")
    }

    private static func decode(_ row: StoredCapabilityRestrictionRow) -> CapabilityRestriction? {
        decodeStoredBlob(CapabilityRestriction.self, from: row.data, row: "capabilityRestriction")
    }
}

// MARK: - Eval result store

/// Durable graded runs, backing the operator report cards.
///
/// Retention is deliberately absent here, unlike ``SwiftDataWorklogStore``. One result per completed
/// workflow is orders of magnitude smaller than that workflow's trace, and a report card is only
/// meaningful over a long history — dropping the oldest grades would quietly flatter an operator
/// whose track record was improving, or hide one whose was decaying. If this ever needs a cap, it
/// must drop by *whole spec history* and never mid-series, for the same reason worklog retention
/// drops whole correlation groups.
@ModelActor
public actor SwiftDataEvalResultStore: EvalResultStoring {
    public func record(_ result: EvalResult) {
        do {
            let data = try JSONEncoder().encode(result)
            let id = result.id
            if let row = try modelContext.fetch(FetchDescriptor<StoredEvalResultRow>(
                predicate: #Predicate { $0.id == id }
            )).first {
                row.correlationID = result.correlationID
                row.evaluatedAt = result.evaluatedAt
                row.data = data
            } else {
                modelContext.insert(
                    StoredEvalResultRow(
                        id: result.id,
                        correlationID: result.correlationID,
                        evaluatedAt: result.evaluatedAt,
                        data: data
                    )
                )
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            storageLogger.error("Evaluation result persistence failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Every graded run, newest first — the whole table, deliberately, and with no bounded variant.
    ///
    /// The one consumer (`MissionControlHomeModel.loadReportCards()`) groups these by the playbook
    /// that owned each workflow and requires completeness to do it: the grouping falls back to a
    /// join through execution records, which are capped and age out, and that read must not drop the
    /// grades of a run whose record has already gone. A `limit:` overload would have no caller that
    /// could correctly use it, so the full decode is the honest cost of the only question asked.
    public func allResults() -> [EvalResult] {
        ((try? modelContext.fetch(FetchDescriptor<StoredEvalResultRow>(
            sortBy: [SortDescriptor(\StoredEvalResultRow.evaluatedAt, order: .reverse)]
        ))) ?? [])
        .compactMap(Self.decode)
    }

    public func results(forCorrelationID correlationID: String) -> [EvalResult] {
        let target = correlationID
        return ((try? modelContext.fetch(FetchDescriptor<StoredEvalResultRow>(
            predicate: #Predicate { $0.correlationID == target },
            sortBy: [SortDescriptor(\StoredEvalResultRow.evaluatedAt, order: .reverse)]
        ))) ?? [])
        .compactMap(Self.decode)
    }

    public func resetAll() {
        do {
            for row in try modelContext.fetch(FetchDescriptor<StoredEvalResultRow>()) {
                modelContext.delete(row)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            storageLogger.error("Evaluation result reset failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func decode(_ row: StoredEvalResultRow) -> EvalResult? {
        decodeStoredBlob(EvalResult.self, from: row.data, row: "evalResult")
    }
}

/// Durable advisory recommendations, with retention on the ones nobody is waiting on.
///
/// Unlike ``SwiftDataEvalResultStore``, this table *does* need a cap. Recommendations are
/// regenerated from report cards on every Mission Control refresh, and a new graded run changes the
/// evidence set — so a new row is written and the previous one is marked `.superseded` rather than
/// replaced, deliberately, so a person's review survives. Nothing removed them, so the table grew
/// for the life of the install and `allRecommendations()` decoded every row on each refresh.
@ModelActor
public actor SwiftDataImprovementRecommendationStore: ImprovementRecommendationStoring {
    /// How many *retired* recommendations are retained, oldest dropped first.
    ///
    /// Only `.superseded`, `.rejected`, and `.applied` rows are eligible: each one has already
    /// reached its terminal state, so dropping it removes a historical note and no pending work.
    /// `.proposed` and `.accepted` rows are never collected — the first is awaiting a person, the
    /// second is awaiting the change that person agreed to, and losing either would silently drop a
    /// decision rather than a record of one.
    ///
    /// These are advisory suggestions derived from evidence that is itself retained: the grades in
    /// ``SwiftDataEvalResultStore`` and the receipts written by `recordRecommendationDecision` both
    /// outlive the row, so a dropped recommendation erases no audit history.
    public static let maximumStoredRetiredRecommendations = 200

    /// The retired states eligible for collection. Compared against the denormalised
    /// `stateRawValue` column so the sweep never has to decode a blob.
    private static let retiredStates: [String] = [
        ImprovementRecommendationState.superseded.rawValue,
        ImprovementRecommendationState.rejected.rawValue,
        ImprovementRecommendationState.applied.rawValue
    ]

    private var maximumRetiredRecommendations =
        SwiftDataImprovementRecommendationStore.maximumStoredRetiredRecommendations

    /// Test seam, for the same reason ``SwiftDataWorklogStore/setRetentionCap(_:)`` is one: so tests
    /// can drive the retention *policy* without writing two hundred rows to reach the real cap.
    func setRetentionCap(_ cap: Int) {
        maximumRetiredRecommendations = cap
    }

    public func upsert(_ recommendation: ImprovementRecommendation) {
        do {
            let data = try JSONEncoder().encode(recommendation)
            let id = recommendation.id
            if let row = try modelContext.fetch(FetchDescriptor<StoredImprovementRecommendationRow>(
                predicate: #Predicate { $0.id == id }
            )).first {
                row.createdAt = recommendation.createdAt
                row.stateRawValue = recommendation.state.rawValue
                row.data = data
            } else {
                modelContext.insert(StoredImprovementRecommendationRow(
                    id: id,
                    createdAt: recommendation.createdAt,
                    stateRawValue: recommendation.state.rawValue,
                    data: data
                ))
            }
            pruneRetiredRecommendations(sparing: id)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            storageLogger.error("Improvement recommendation persistence failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Drops the oldest retired recommendations once more than ``maximumStoredRetiredRecommendations``
    /// of them have accumulated.
    ///
    /// On the write path, matching ``SwiftDataCapabilityLeaseStore/pruneDeadLeases(at:sparing:)`` —
    /// a read should not mutate, and the write path is where growth happens.
    ///
    /// - Parameter spared: The row the calling ``upsert(_:)`` just wrote, never collected here. A
    ///   caller has to be able to read back what it persisted, and `refreshImprovementRecommendations`
    ///   retires rows by upserting them into `.superseded`, so the row being retired is frequently
    ///   also the oldest candidate.
    private func pruneRetiredRecommendations(sparing spared: String) {
        let retired = Self.retiredStates
        var descriptor = FetchDescriptor<StoredImprovementRecommendationRow>(
            predicate: #Predicate { retired.contains($0.stateRawValue) && $0.id != spared },
            sortBy: [SortDescriptor(\StoredImprovementRecommendationRow.createdAt, order: .forward)]
        )
        guard let retiredCount = try? modelContext.fetchCount(descriptor),
              retiredCount > maximumRetiredRecommendations else { return }
        descriptor.fetchLimit = retiredCount - maximumRetiredRecommendations
        for row in (try? modelContext.fetch(descriptor)) ?? [] {
            modelContext.delete(row)
        }
    }

    /// Every recommendation, newest first — the whole table, and narrowing it would cost more.
    ///
    /// Mission Control fetches this **once** per refresh and then filters by operator in memory as it
    /// renders each card, so a `recommendations(forOperatorID:)` predicate would replace one query
    /// with one per card. `ImprovementRecommendationStoring` records the same decision on its own
    /// declaration of this method. Growth is bounded by the retention sweep rather than by the read.
    public func allRecommendations() -> [ImprovementRecommendation] {
        ((try? modelContext.fetch(FetchDescriptor<StoredImprovementRecommendationRow>(
            sortBy: [SortDescriptor(\StoredImprovementRecommendationRow.createdAt, order: .reverse)]
        ))) ?? []).compactMap(Self.decode)
    }

    /// One recommendation by id.
    ///
    /// `fetchLimit = 1` because `id` is `@Attribute(.unique)`, so at most one row can ever match: the
    /// limit cannot change the answer, only the work done reaching it. Worth setting because
    /// `refreshImprovementRecommendations` calls this once per generated candidate, per refresh.
    public func recommendation(id: String) -> ImprovementRecommendation? {
        let target = id
        var descriptor = FetchDescriptor<StoredImprovementRecommendationRow>(
            predicate: #Predicate { $0.id == target }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor).first).flatMap(Self.decode)
    }

    public func resetAll() {
        do {
            for row in try modelContext.fetch(FetchDescriptor<StoredImprovementRecommendationRow>()) {
                modelContext.delete(row)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            storageLogger.error("Improvement recommendation reset failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func decode(_ row: StoredImprovementRecommendationRow) -> ImprovementRecommendation? {
        decodeStoredBlob(ImprovementRecommendation.self, from: row.data, row: "improvementRecommendation")
    }
}
