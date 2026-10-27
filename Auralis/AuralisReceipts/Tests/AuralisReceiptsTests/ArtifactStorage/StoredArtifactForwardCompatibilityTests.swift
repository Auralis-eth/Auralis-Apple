@testable import AuralisReceipts
import Foundation
import AuralisRuntime
import SwiftData
import Testing

/// What happens to a row this build cannot interpret — the downgrade / staged-rollout case
/// (TestFlight then App Store), where the store holds records written by a build that knew more
/// enum cases or a later ``ArtifactSchema`` version than the one reading them.
///
/// The contract these pin: **fail closed on the single-record path, drop-and-log on listings.**
/// Before this suite, `asArtifact()` coerced an unknown type to `.doc` and an unknown approval state
/// to `.draft`, so an unreadable row came back looking like ordinary unreviewed work.
@Suite("StoredArtifact forward compatibility")
struct StoredArtifactForwardCompatibilityTests {
    private func artifact(
        id: UUID = UUID(),
        groupID: UUID = UUID(),
        version: Int = 1,
        type: ArtifactType = .doc,
        approvalState: ArtifactApprovalState = .draft,
        createdAt: Date = Date(timeIntervalSince1970: 100)
    ) -> Artifact {
        Artifact(
            id: id,
            groupID: groupID,
            version: version,
            type: type,
            title: "Doc",
            creatorPlaybookID: nil,
            creatorOperatorID: nil,
            createdAt: createdAt,
            provenance: ArtifactProvenance(actor: .human),
            relatedReceiptIDs: [],
            approvalState: approvalState,
            destination: nil,
            exportFormat: nil,
            content: "body"
        )
    }

    @MainActor
    private func makeStore() throws -> (SwiftDataArtifactStore, ModelContainer) {
        let container = try ModelContainer(
            for: Schema([StoredArtifact.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        return (SwiftDataArtifactStore(modelContainer: container), container)
    }

    // MARK: - Fail closed rather than guess

    /// Pre-fix this returned `.draft` — the most permissive state — so a record a newer build had
    /// put into a state this one has never heard of was presented as approvable, exportable,
    /// re-versionable work.
    @Test("an unrecognized approval state throws instead of reading as .draft")
    func unrecognizedApprovalStateThrows() throws {
        let stored = try StoredArtifact(artifact: artifact(approvalState: .approved))
        stored.approvalStateRawValue = "rejected"

        #expect(throws: StoredArtifactDecodingError.unrecognizedApprovalState(id: stored.id, rawValue: "rejected")) {
            try stored.asArtifact()
        }
    }

    /// Pre-fix this returned `.doc`, which also made the row inconsistent with itself:
    /// `all(ofType:)` filters on the raw string, so the same record was both "not a doc" (excluded
    /// from the doc listing) and "a doc" (when fetched directly).
    @Test("an unrecognized artifact type throws instead of reading as .doc")
    func unrecognizedTypeThrows() throws {
        let stored = try StoredArtifact(artifact: artifact(type: .report))
        stored.typeRawValue = "spreadsheet"

        #expect(throws: StoredArtifactDecodingError.unrecognizedType(id: stored.id, rawValue: "spreadsheet")) {
            try stored.asArtifact()
        }
    }

    /// `ArtifactSchema.supportedVersions` documents that a version outside the set "cannot be
    /// interpreted, so the check fails closed rather than guessing". That was enforced on the
    /// proposal path (`AuralisAppShell.SchemaChecks`) and nowhere on the read path.
    @Test("a row written under an unsupported schema version throws")
    func unsupportedSchemaVersionThrows() throws {
        let unsupported = (ArtifactSchema.supportedVersions.max() ?? 0) + 1
        let stored = try StoredArtifact(artifact: artifact())
        stored.schemaVersion = unsupported

        #expect(throws: StoredArtifactDecodingError.unsupportedSchemaVersion(id: stored.id, version: unsupported)) {
            try stored.asArtifact()
        }
    }

    @Test("a readable row is unaffected by the guards")
    func readableRowStillRoundTrips() throws {
        let original = artifact(type: .brief, approvalState: .exported)
        let decoded = try StoredArtifact(artifact: original).asArtifact()

        #expect(decoded == original)
    }

    // MARK: - One bad row must not take down a listing

    /// The F-25 contract, applied here: a single forward-incompatible row must not remove the
    /// artifact browser (and with it any path that would let a person deal with the row).
    @Test("an unreadable row is skipped by the listings rather than failing them")
    @MainActor
    func unreadableRowIsSkippedByListings() async throws {
        let (store, container) = try makeStore()
        let groupID = UUID()
        let good = try await store.create(
            ArtifactDraft(type: .doc, title: "Readable", provenance: ArtifactProvenance(actor: .human), content: "ok")
        )

        let poisoned = try StoredArtifact(artifact: artifact(groupID: groupID, type: .report))
        poisoned.typeRawValue = "spreadsheet"
        container.mainContext.insert(poisoned)
        try container.mainContext.save()

        let latest = try await store.latest(limit: 10)
        #expect(latest.map(\.id) == [good.id])
        #expect(try await store.all(ofType: .doc, limit: 10).map(\.id) == [good.id])
        #expect(try await store.versions(ofGroup: groupID).isEmpty)
    }

    /// Dropping the row must cost the listing a *row*, not a *slot*. Pre-fix the page was taken
    /// before the rows were decoded, so an unreadable row inside the window was counted against the
    /// limit and then removed from it — the caller asked for 2, got 1, and the readable row sitting
    /// just outside the window was never reached.
    @Test("an unreadable row does not consume a slot in a limited page")
    @MainActor
    func unreadableRowDoesNotConsumeAPageSlot() async throws {
        let (store, container) = try makeStore()
        // Explicit `createdAt`s rather than three `create` calls: the ordering *is* the assertion.
        let newest = try StoredArtifact(artifact: artifact(createdAt: Date(timeIntervalSince1970: 300)))
        // Poisoned by schema version, not by type, so it still passes the `.doc` filter and this one
        // row exercises both listings.
        newest.schemaVersion = (ArtifactSchema.supportedVersions.max() ?? 0) + 1
        let middle = try StoredArtifact(artifact: artifact(createdAt: Date(timeIntervalSince1970: 200)))
        let oldest = try StoredArtifact(artifact: artifact(createdAt: Date(timeIntervalSince1970: 100)))
        for row in [newest, middle, oldest] { container.mainContext.insert(row) }
        try container.mainContext.save()

        #expect(try await store.latest(limit: 2).map(\.id) == [middle.id, oldest.id])
        #expect(try await store.all(ofType: .doc, limit: 2).map(\.id) == [middle.id, oldest.id])
    }

    /// Dropping the row must cost the listing a *row*, not a *lineage*.
    ///
    /// The slot test above cannot reach this: `artifact(...)` defaults `groupID` to a fresh `UUID`,
    /// so its three rows are three groups of one and the newest-*within*-a-group case never runs.
    /// Pre-fix, `latest` chose the newest raw row per group and decoded afterwards, so a poisoned v2
    /// claimed the group's only slot and then vanished from it — the group was absent from the
    /// listing entirely, and since a `groupID` only ever reaches a caller through `latest`/`all`, the
    /// readable v1 that `versions(ofGroup:)` would happily return was unreachable and the lineage
    /// unrecoverable short of `resetAll`.
    @Test("an unreadable newest version does not hide the readable versions beneath it")
    @MainActor
    func unreadableNewestVersionDoesNotHideItsLineage() async throws {
        let (store, container) = try makeStore()
        let groupID = UUID()
        let readableV1 = try StoredArtifact(
            artifact: artifact(
                groupID: groupID,
                version: 1,
                approvalState: .approved,
                createdAt: Date(timeIntervalSince1970: 100)
            )
        )
        let poisonedV2 = try StoredArtifact(
            artifact: artifact(
                groupID: groupID,
                version: 2,
                approvalState: .approved,
                createdAt: Date(timeIntervalSince1970: 200)
            )
        )
        poisonedV2.approvalStateRawValue = "rejected"
        for row in [readableV1, poisonedV2] { container.mainContext.insert(row) }
        try container.mainContext.save()

        // The group keeps its slot, filled by the newest version this build *can* read.
        #expect(try await store.latest(limit: 10).map(\.id) == [readableV1.id])
        #expect(try await store.all(ofType: .doc, limit: 10).map(\.id) == [readableV1.id])
        // And what the listing hands back is a lineage `versions` can still open — the two agree.
        #expect(try await store.versions(ofGroup: groupID).map(\.id) == [readableV1.id])
    }

    /// The limit still counts groups, not rows: a group whose newest version fell back to an older
    /// one occupies exactly one slot, and a group with no readable version at all occupies none.
    @Test("fallback within a group costs the page neither a slot nor an extra one")
    @MainActor
    func groupFallbackDoesNotDisturbThePage() async throws {
        let (store, container) = try makeStore()
        let recentGroup = UUID()
        let olderGroup = UUID()
        let unreadableGroup = UUID()

        let recentV1 = try StoredArtifact(
            artifact: artifact(groupID: recentGroup, version: 1, createdAt: Date(timeIntervalSince1970: 300))
        )
        let recentV2 = try StoredArtifact(
            artifact: artifact(groupID: recentGroup, version: 2, createdAt: Date(timeIntervalSince1970: 400))
        )
        recentV2.typeRawValue = "spreadsheet"
        let older = try StoredArtifact(
            artifact: artifact(groupID: olderGroup, version: 1, createdAt: Date(timeIntervalSince1970: 200))
        )
        let unreadable = try StoredArtifact(
            artifact: artifact(groupID: unreadableGroup, version: 1, createdAt: Date(timeIntervalSince1970: 500))
        )
        unreadable.schemaVersion = (ArtifactSchema.supportedVersions.max() ?? 0) + 1
        for row in [recentV1, recentV2, older, unreadable] { container.mainContext.insert(row) }
        try container.mainContext.save()

        // The wholly unreadable group is skipped rather than consuming the first slot, and the
        // fallback group is ranked by its lineage's recency (400), ahead of the older group (200).
        #expect(try await store.latest(limit: 2).map(\.id) == [recentV1.id, older.id])
    }

    // MARK: - Nor may a write path launder a row it cannot read

    /// `asArtifact()` closed the read path, but `addVersion` still mutated raw rows: it wrote
    /// `.superseded` over every non-superseded row in the group without decoding any of them, which
    /// is the exact laundering the guards refuse — and permanent, since the original state is gone.
    @Test("addVersion leaves a row it cannot interpret exactly as written")
    @MainActor
    func addVersionDoesNotLaunderAnUnreadableRow() async throws {
        let (store, container) = try makeStore()
        let groupID = UUID()
        let readable = try StoredArtifact(
            artifact: artifact(groupID: groupID, version: 1, approvalState: .approved)
        )
        let poisoned = try StoredArtifact(
            artifact: artifact(groupID: groupID, version: 2, approvalState: .approved)
        )
        poisoned.approvalStateRawValue = "rejected"
        container.mainContext.insert(readable)
        container.mainContext.insert(poisoned)
        try container.mainContext.save()

        let added = try await store.addVersion(
            toGroup: groupID,
            ArtifactDraft(type: .doc, title: "v3", provenance: ArtifactProvenance(actor: .human), content: "ok")
        )

        // Versions are still allocated over every row, readable or not — reusing 2 would collide
        // with the row this build cannot read.
        #expect(added.version == 3)
        // The readable prior version supersedes as usual.
        #expect(try await store.get(id: readable.id)?.approvalState == .superseded)
        // Had the supersede landed on the other row it would now decode cleanly as `.superseded`.
        // Still refusing to decode is the proof its state was left alone.
        await #expect(
            throws: StoredArtifactDecodingError.unrecognizedApprovalState(id: poisoned.id, rawValue: "rejected")
        ) {
            try await store.get(id: poisoned.id)
        }
    }

    @Test("direct writes refuse to mutate a row they cannot interpret")
    @MainActor
    func directWritesDoNotLaunderAnUnreadableRow() async throws {
        let (store, container) = try makeStore()
        let poisoned = try StoredArtifact(artifact: artifact(approvalState: .approved))
        poisoned.approvalStateRawValue = "rejected"
        container.mainContext.insert(poisoned)
        try container.mainContext.save()

        await #expect(throws: StoredArtifactDecodingError.self) {
            try await store.setApprovalState(id: poisoned.id, to: .draft)
        }
        await #expect(throws: StoredArtifactDecodingError.self) {
            try await store.updateLifecycle(
                id: poisoned.id,
                to: .exported,
                destination: "files",
                exportFormat: "md"
            )
        }
        await #expect(throws: StoredArtifactDecodingError.self) {
            try await store.linkRelatedReceipt(id: UUID(), toArtifact: poisoned.id)
        }

        await #expect(
            throws: StoredArtifactDecodingError.unrecognizedApprovalState(id: poisoned.id, rawValue: "rejected")
        ) {
            try await store.get(id: poisoned.id)
        }
    }

    /// The other half of the contract. A caller that named one artifact, or asked for the whole
    /// export, is told the truth: "does not exist" and "silently one record short" are both worse
    /// answers than an error.
    @Test("get and exportAll propagate rather than hiding the row")
    @MainActor
    func singleRecordAndExportPropagate() async throws {
        let (store, container) = try makeStore()
        let poisoned = try StoredArtifact(artifact: artifact())
        poisoned.approvalStateRawValue = "rejected"
        container.mainContext.insert(poisoned)
        try container.mainContext.save()

        await #expect(throws: StoredArtifactDecodingError.self) { try await store.get(id: poisoned.id) }
        await #expect(throws: StoredArtifactDecodingError.self) { try await store.exportAll() }
    }
}
