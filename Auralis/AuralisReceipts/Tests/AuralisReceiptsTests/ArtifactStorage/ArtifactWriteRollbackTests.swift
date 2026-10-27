@testable import AuralisReceipts
import Foundation
import AuralisRuntime
import SwiftData
import Testing

/// `@ModelActor` holds one long-lived `ModelContext`, so a write that fails to commit does not
/// disappear — it stays pending until *some other* call saves successfully and carries it along.
///
/// The scenario this pins: an approval is reported to the person as failed, and then lands anyway
/// the next time an unrelated artifact is created.
@Suite("Artifact write rollback")
struct ArtifactWriteRollbackTests {
    private func draft(_ title: String) -> ArtifactDraft {
        ArtifactDraft(
            type: .doc,
            title: title,
            provenance: ArtifactProvenance(actor: .human),
            content: "body of \(title)"
        )
    }

    @MainActor
    private func makeStore() throws -> ArtifactPersistenceStore {
        let container = try ModelContainer(
            for: Schema([StoredArtifact.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        return ArtifactPersistenceStore(modelContainer: container)
    }

    @Test("a failed approval is not committed by the next successful write")
    @MainActor
    func failedApprovalIsNotCommittedLater() async throws {
        let store = try makeStore()
        let created = try await store.create(draft("Approve me"))
        #expect(try await store.get(id: created.id)?.approvalState == .draft)

        await store.failNextCommitForTesting()
        await #expect(throws: ArtifactPersistenceStore.CommitProbeError.self) {
            try await store.setApprovalState(id: created.id, to: .approved)
        }

        // The write above failed and the caller was told so. An unrelated successful write must not
        // be what finally commits it.
        _ = try await store.create(draft("Something else"))

        #expect(try await store.get(id: created.id)?.approvalState == .draft)
    }

    /// The guard is per-call-site, so each write path needs its own proof. `create` is the one where
    /// a leaked pending change is an entire artifact appearing out of nowhere on someone else's save.
    @Test("a failed create does not appear on the next successful write")
    @MainActor
    func failedCreateIsNotCommittedLater() async throws {
        let store = try makeStore()
        _ = try await store.create(draft("Anchor"))

        await store.failNextCommitForTesting()
        await #expect(throws: ArtifactPersistenceStore.CommitProbeError.self) {
            _ = try await store.create(draft("Never created"))
        }

        _ = try await store.create(draft("Unrelated"))

        #expect(try await store.latest(limit: 10).map(\.title).sorted() == ["Anchor", "Unrelated"])
    }

    @Test("a failed receipt link is not committed by the next successful write")
    @MainActor
    func failedReceiptLinkIsNotCommittedLater() async throws {
        let store = try makeStore()
        let created = try await store.create(draft("Link me"))

        await store.failNextCommitForTesting()
        await #expect(throws: ArtifactPersistenceStore.CommitProbeError.self) {
            try await store.linkRelatedReceipt(id: UUID(), toArtifact: created.id)
        }

        _ = try await store.create(draft("Something else"))

        #expect(try await store.get(id: created.id)?.relatedReceiptIDs.isEmpty == true)
    }

    /// The worst one to leak: a `resetAll` reported as failed must not delete the person's artifacts
    /// the next time anything at all is saved.
    @Test("a failed resetAll does not delete anything, then or later")
    @MainActor
    func failedResetAllIsNotCommittedLater() async throws {
        let store = try makeStore()
        let kept = try await store.create(draft("Keep me"))

        await store.failNextCommitForTesting()
        await #expect(throws: ArtifactPersistenceStore.CommitProbeError.self) {
            try await store.resetAll()
        }
        #expect(try await store.get(id: kept.id) != nil)

        _ = try await store.create(draft("Something else"))

        #expect(try await store.get(id: kept.id) != nil)
    }

    /// `addVersion` is the only write path that makes **two related mutations** — it supersedes every
    /// readable prior row in the group and *then* inserts the new version — and both land on one
    /// `save()`. So it is the one path where a failed commit could leave half a state: prior versions
    /// marked `.superseded` with no successor to supersede them, which reads back as a lineage whose
    /// every version is retired and whose newest artifact does not exist.
    ///
    /// The rest of the suite proves the guard per single-mutation call site; this proves it holds
    /// across the pair.
    @Test("a failed addVersion leaves neither the supersede nor the new version behind")
    @MainActor
    func failedAddVersionLeavesNoHalfWrittenLineage() async throws {
        let store = try makeStore()
        let v1 = try await store.create(draft("Doc"))

        await store.failNextCommitForTesting()
        await #expect(throws: ArtifactPersistenceStore.CommitProbeError.self) {
            _ = try await store.addVersion(toGroup: v1.groupID, draft("Doc v2"))
        }

        // The supersede half must not have survived the failed commit.
        #expect(try await store.get(id: v1.id)?.approvalState == .draft)
        #expect(try await store.versions(ofGroup: v1.groupID).map(\.version) == [1])

        // Nor may either half be carried in by somebody else's save.
        _ = try await store.create(draft("Unrelated"))
        #expect(try await store.get(id: v1.id)?.approvalState == .draft)
        #expect(try await store.versions(ofGroup: v1.groupID).map(\.version) == [1])

        // And the lineage is still usable afterwards: the retried version takes 2, not 3.
        let v2 = try await store.addVersion(toGroup: v1.groupID, draft("Doc v2"))
        #expect(v2.version == 2)
        #expect(try await store.get(id: v1.id)?.approvalState == .superseded)
    }

    @Test("a successful write still commits through the same path")
    @MainActor
    func successfulWriteStillCommits() async throws {
        let store = try makeStore()
        let created = try await store.create(draft("Approve me"))

        try await store.setApprovalState(id: created.id, to: .approved)
        try await store.updateLifecycle(
            id: created.id,
            to: .exported,
            destination: "files",
            exportFormat: "md"
        )
        let receiptID = UUID()
        try await store.linkRelatedReceipt(id: receiptID, toArtifact: created.id)

        let reloaded = try #require(try await store.get(id: created.id))
        #expect(reloaded.approvalState == .exported)
        #expect(reloaded.destination == "files")
        #expect(reloaded.exportFormat == "md")
        #expect(reloaded.relatedReceiptIDs == [receiptID])
    }
}
