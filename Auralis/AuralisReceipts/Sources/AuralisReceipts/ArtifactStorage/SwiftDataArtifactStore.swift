import Foundation
import OSLog
import SwiftData
import AuralisFoundation

private let artifactStorageLogger = Logger(subsystem: "Auralis", category: "AuralisReceipts")

/// SwiftData-backed persistence for artifacts. *Listing* and versioning filter in-memory over
/// fetched rows, which keeps us clear of SwiftData predicate edge cases on the enum-raw fields; a
/// lookup by `id` does not, because that one is plain equality on a `@Attribute(.unique)` column and
/// scanning for it made every named read and every named write O(table) — see ``fetchRow(id:)``.
///
/// **This table has no retention cap, deliberately.** The sibling durable stores trim
/// (`SwiftDataWorklogStore` keeps 10_000 steps; `AuralisAppShell` prunes execution records
/// and performance events), so the absence here is a decision and has to be argued, not left to the
/// reader. Two halves:
///
/// *The write rate.* A `StoredArtifact` is written only when a run produces a **work product** — one
/// row per `create`, one per `addVersion`. Even under P2-EVAL/P2-IMPROVE, where improvement loops
/// author artifacts with no human in the loop, that rate is bounded by the *run* rate: a scheduled
/// routine firing minutes apart, which is why those loops stay human-approved and fully receipted.
/// The tables that need a cap are the per-step ones — the worklog writes a phase per step of every
/// run, orders of magnitude hotter — and artifacts are not one of those.
///
/// *What the rows are.* These are the person's deliverables, they are what `relatedReceiptIDs` ties
/// the receipt chain to, and ``versions(ofGroup:)`` promises **every** version of a lineage. A trim
/// on the `AuralisAppShell` shape — oldest-first on the key the lookup ranks by — cannot be
/// written here without breaking one of those: dropping old versions makes `versions` lie about a
/// lineage its newest row still anchors, and dropping whole oldest groups silently deletes approved,
/// exported work that a receipt still points at. Deleting artifacts stays a decision the person
/// makes (`exportAll`, then `resetAll`), not one a sweep makes on their behalf.
///
/// What was actually unbounded and worth fixing was *reads*: the named-row paths no longer
/// materialise the table, and the listings page lazily so a body is faulted in off external storage
/// only for the rows actually handed back.
@ModelActor
public actor ArtifactPersistenceStore {
    public func create(_ draft: ArtifactDraft) throws -> Artifact {
        try insert(draft, groupID: UUID(), version: 1)
    }

    public func addVersion(toGroup groupID: UUID, _ draft: ArtifactDraft) throws -> Artifact {
        do {
            let existing = try fetchGroup(groupID)
            // Version numbers are allocated over *every* row in the group, readable or not: a row
            // this build cannot interpret still occupies its version, and reusing the number would
            // put two artifacts on it the moment a build that understands it reads back.
            let nextVersion = (existing.map(\.version).max() ?? 0) + 1
            for row in existing where row.approvalStateRawValue != ArtifactApprovalState.superseded.rawValue {
                guard canInterpret(row) else { continue }
                row.apply(approvalState: .superseded)
            }
            return try insert(draft, groupID: groupID, version: nextVersion)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    public func get(id: UUID) throws -> Artifact? {
        guard let row = try fetchRow(id: id) else { return nil }
        return try row.asArtifact()
    }

    public func latest(limit: Int) throws -> [Artifact] {
        guard limit > 0 else { return [] }
        // One slot per group, filled by the newest **readable** version in that group.
        //
        // Choosing the newest *raw* row per group and filtering afterwards cost the listing a
        // *lineage* rather than a row: an unreadable newest version claimed its group's only slot
        // and then dropped out of it, so the readable versions underneath were never considered.
        // That is strictly worse than the bad row being hidden, because a `groupID` only ever
        // reaches a caller through this listing — with the group absent, ``versions(ofGroup:)`` is
        // unreachable and the whole lineage is unrecoverable short of `resetAll`. The F-32 rule is
        // that a listing skips a bad **row**; a `get` of that row may fail.
        //
        // Groups are ranked by their newest row's `createdAt` whether that row is readable or not:
        // what is being ordered is the recency of the lineage, and `createdAt` is a plain column, so
        // ranking the page faults no bodies in off external storage.
        //
        // Decode before taking the page, not after — the other order let an unreadable row occupy a
        // slot and then vanish from it, so a caller that asked for `limit` got fewer than that with
        // readable groups still waiting outside the window.
        //
        // `lazy` is load-bearing, not tidiness: decoding reads `content`, which is
        // `@Attribute(.externalStorage)`, so an eager `compactMap` faults every artifact body in the
        // store off disk to answer `latest(limit: 5)`. Lazily, decoding stops at the first `limit`
        // groups that yield a readable version.
        return Array(
            Dictionary(grouping: try fetchAll(), by: \.groupID).values
                .sorted { newestCreatedAt(of: $0) > newestCreatedAt(of: $1) }
                .lazy
                .compactMap(newestReadable(in:))
                .prefix(limit)
        )
    }

    public func versions(ofGroup groupID: UUID) throws -> [Artifact] {
        try fetchGroup(groupID)
            .sorted { $0.version < $1.version }
            .compactMap(readable)
    }

    public func all(ofType type: ArtifactType, limit: Int) throws -> [Artifact] {
        guard limit > 0 else { return [] }
        // Decode before taking the page, and lazily — see ``latest(limit:)`` for both halves.
        return Array(
            try fetchAll()
                .filter { $0.typeRawValue == type.rawValue }
                .sorted { $0.createdAt > $1.createdAt }
                .lazy
                .compactMap(readable)
                .prefix(limit)
        )
    }

    public func setApprovalState(id: UUID, to state: ArtifactApprovalState) throws {
        let row = try requireReadableRow(id: id)
        try saveOrRollback { row.apply(approvalState: state) }
    }

    public func linkRelatedReceipt(id receiptID: UUID, toArtifact artifactID: UUID) throws {
        let row = try requireReadableRow(id: artifactID)
        try saveOrRollback { try row.appendRelatedReceipt(id: receiptID) }
    }

    public func updateLifecycle(
        id: UUID,
        to state: ArtifactApprovalState,
        destination: String?,
        exportFormat: String?
    ) throws {
        let row = try requireReadableRow(id: id)
        try saveOrRollback {
            row.apply(approvalState: state, destination: destination, exportFormat: exportFormat)
        }
    }

    public func exportAll() throws -> Data {
        let artifacts = try fetchAll()
            .sorted { ($0.createdAt, $0.version) < ($1.createdAt, $1.version) }
            .map { try $0.asArtifact() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(artifacts)
    }

    public func resetAll() throws {
        let rows = try fetchAll()
        try saveOrRollback {
            for row in rows { modelContext.delete(row) }
        }
    }

#if DEBUG
    enum CommitProbeError: Error { case injected }

    /// Makes the next commit through ``saveOrRollback(_:)`` fail, once.
    ///
    /// This seam exists only because SwiftData offers no way to make an in-memory `save()` fail on
    /// demand — without it the rollback guard below could only be asserted by reading it, and the
    /// defect it fixes (a failed write landing later, on somebody else's save) is precisely the kind
    /// that survives review. It arms the guard rather than reimplementing any one write, so the
    /// tests drive the real `create` / `setApprovalState` / `linkRelatedReceipt` / `resetAll`: the
    /// rollback is per-call-site, and a path that forgot to route through `saveOrRollback` would not
    /// show up in a test of a near-copy. DEBUG-only so none of it reaches a release binary.
    func failNextCommitForTesting() {
        failNextCommit = true
    }

    private var failNextCommit = false

    /// Rows handed back by every fetch this actor has made since the last reset.
    ///
    /// This seam exists for the same reason as ``failNextCommitForTesting()``: "this path no longer
    /// reads the whole table" is not visible in any return value — `get(id:)` answers identically
    /// before and after — so without a count the bound could only be asserted by reading the code,
    /// and an O(table) scan behind a correct-looking answer is exactly the kind of regression that
    /// reads fine. Counting in ``fetch(_:)`` rather than per call site means a future path that
    /// reintroduces the scan is caught by the existing test.
    private(set) var rowsFetchedForTesting = 0

    func resetRowsFetchedForTesting() {
        rowsFetchedForTesting = 0
    }
#endif

    /// Applies `mutation` and commits it, discarding the change if the commit fails.
    ///
    /// `@ModelActor` holds **one** long-lived `ModelContext`, so an uncommitted mutation left behind
    /// by a failed `save()` does not disappear — it stays pending and is committed by the *next*
    /// successful save from an unrelated call. Without the rollback, a `setApprovalState` that threw
    /// (disk full, constraint violation) and was reported to the caller as failed would silently
    /// land the moment any later `create` succeeded: an artifact marked approved by a decision the
    /// app told the person had not been recorded. `addVersion` already guarded itself this way; this
    /// is the same guard for the rest of the write path.
    ///
    /// The mechanics are `AuralisFoundation.performRollbackSafeMutation`, not a private copy of it:
    /// AGENTS.md puts shared SwiftData rollback helpers in that package, and a second
    /// `do/catch { rollback() }` here is the kind of duplicate that drifts. This wrapper adds only
    /// the artifact-specific part — the DEBUG commit probe, which throws *inside* the shared helper's
    /// work closure so the rollback it triggers is the real one.
    private func saveOrRollback(_ mutation: () throws -> Void) throws {
        try modelContext.performRollbackSafeMutation {
            try mutation()
#if DEBUG
            if failNextCommit {
                failNextCommit = false
                throw CommitProbeError.injected
            }
#endif
        }
    }

    /// One row that cannot be interpreted must not take down a listing (the argument
    /// `decodeStoredBlob` makes for the same shape), but it must not vanish
    /// silently either — forward-incompatible rows show up as a log line rather than as a browser
    /// that quietly reads short.
    private func readable(_ row: StoredArtifact) -> Artifact? {
        do {
            return try row.asArtifact()
        } catch {
            artifactStorageLogger.error(
                "Dropped artifact row \(row.id, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    /// Whether this build can interpret `row`, for the write paths that must not mutate a record
    /// they cannot read.
    ///
    /// Superseding a row whose approval state has no case here would write a state we understand
    /// over one we never did — the same laundering ``StoredArtifact/asArtifact()`` refuses on the
    /// read path, and it would be permanent: a newer build's (say) rejection is gone the moment an
    /// older one versions the group. Leaving the row exactly as written costs nothing, because it is
    /// already absent from every listing.
    ///
    /// Separate from ``readable(_:)`` for the log line alone — "dropped" is the wrong story for a row
    /// that is being deliberately left alone.
    /// The newest version in `group` this build can read, or `nil` when it can read none of them.
    ///
    /// Walks versions newest-first and stops at the first that decodes, so the ordinary case decodes
    /// exactly one row and a group disappears from ``latest(limit:)`` only when *every* version in
    /// it is unreadable — at which point there is nothing to list and ``versions(ofGroup:)`` has
    /// nothing to recover either.
    private func newestReadable(in group: [StoredArtifact]) -> Artifact? {
        for row in group.sorted(by: { $0.version > $1.version }) {
            if let decoded = readable(row) { return decoded }
        }
        return nil
    }

    private func newestCreatedAt(of group: [StoredArtifact]) -> Date {
        group.map(\.createdAt).max() ?? .distantPast
    }

    private func canInterpret(_ row: StoredArtifact) -> Bool {
        do {
            _ = try row.asArtifact()
            return true
        } catch {
            artifactStorageLogger.error(
                "Left artifact row \(row.id, privacy: .public) as written: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    private func requireReadableRow(id: UUID) throws -> StoredArtifact {
        guard let row = try fetchRow(id: id) else {
            throw ArtifactStoreWriteError.artifactNotFound(id: id)
        }
        // A named write must obey the same fail-closed contract as `get(id:)`. Otherwise an older
        // build can permanently replace a newer approval state, or mutate a record whose schema it
        // does not understand, merely because it knows the row's identifier.
        _ = try row.asArtifact()
        return row
    }

    private func insert(_ draft: ArtifactDraft, groupID: UUID, version: Int) throws -> Artifact {
        let artifact = Artifact(
            id: UUID(),
            groupID: groupID,
            version: version,
            type: draft.type,
            title: draft.title,
            creatorPlaybookID: draft.creatorPlaybookID,
            creatorOperatorID: draft.creatorOperatorID,
            createdAt: .now,
            provenance: draft.provenance,
            relatedReceiptIDs: draft.relatedReceiptIDs,
            approvalState: .draft,
            destination: draft.destination,
            exportFormat: draft.exportFormat,
            content: draft.content
        )
        try saveOrRollback {
            modelContext.insert(try StoredArtifact(artifact: artifact))
        }
        return artifact
    }

    /// The one row with this `id`, fetched by predicate instead of by scanning the table.
    ///
    /// `id` is `@Attribute(.unique)`, so `fetchLimit = 1` is exactness rather than truncation, and
    /// the comparison is plain UUID equality — not one of the enum-raw fields the type comment keeps
    /// in memory. The scan this replaces was the only read primitive in the file, which made
    /// `get(id:)` and every named write O(table): approving one artifact fetched all of them, and
    /// under P2-EVAL write rates that table only grows.
    private func fetchRow(id: UUID) throws -> StoredArtifact? {
        let target = id
        var descriptor = FetchDescriptor<StoredArtifact>(
            predicate: #Predicate<StoredArtifact> { $0.id == target }
        )
        descriptor.fetchLimit = 1
        return try fetch(descriptor).first
    }

    private func fetchAll() throws -> [StoredArtifact] {
        try fetch(FetchDescriptor<StoredArtifact>())
    }

    /// Every fetch in this actor goes through here so the DEBUG row counter cannot be bypassed by a
    /// path that calls `modelContext.fetch` directly — the bound is only worth asserting if the
    /// assertion sees all of the reads.
    private func fetch<Model: PersistentModel>(_ descriptor: FetchDescriptor<Model>) throws -> [Model] {
        let rows = try modelContext.fetch(descriptor)
#if DEBUG
        rowsFetchedForTesting += rows.count
#endif
        return rows
    }

    private func fetchGroup(_ groupID: UUID) throws -> [StoredArtifact] {
        try fetchAll().filter { $0.groupID == groupID }
    }
}

/// `ArtifactStore` facade over the persistence actor.
public final class SwiftDataArtifactStore: ArtifactStore {
    private let store: ArtifactPersistenceStore

    public init(modelContainer: ModelContainer) {
        self.store = ArtifactPersistenceStore(modelContainer: modelContainer)
    }

    public func create(_ draft: ArtifactDraft) async throws -> Artifact { try await store.create(draft) }
    public func addVersion(toGroup groupID: UUID, _ draft: ArtifactDraft) async throws -> Artifact {
        try await store.addVersion(toGroup: groupID, draft)
    }
    public func get(id: UUID) async throws -> Artifact? { try await store.get(id: id) }
    public func latest(limit: Int) async throws -> [Artifact] { try await store.latest(limit: limit) }
    public func versions(ofGroup groupID: UUID) async throws -> [Artifact] {
        try await store.versions(ofGroup: groupID)
    }
    public func all(ofType type: ArtifactType, limit: Int) async throws -> [Artifact] {
        try await store.all(ofType: type, limit: limit)
    }
    public func setApprovalState(id: UUID, to state: ArtifactApprovalState) async throws {
        try await store.setApprovalState(id: id, to: state)
    }
    public func linkRelatedReceipt(id receiptID: UUID, toArtifact artifactID: UUID) async throws {
        try await store.linkRelatedReceipt(id: receiptID, toArtifact: artifactID)
    }
    public func updateLifecycle(
        id: UUID,
        to state: ArtifactApprovalState,
        destination: String?,
        exportFormat: String?
    ) async throws {
        try await store.updateLifecycle(id: id, to: state, destination: destination, exportFormat: exportFormat)
    }
    public func exportAll() async throws -> Data { try await store.exportAll() }
    public func resetAll() async throws { try await store.resetAll() }
}
