@testable import AuralisReceipts
import Foundation
import AuralisRuntime
import Testing

@Suite("Artifact model")
struct ArtifactModelTests {
    @Test
    func roundTripsThroughJSON() throws {
        let artifact = Artifact(
            id: UUID(),
            groupID: UUID(),
            version: 1,
            type: .brief,
            title: "Weekly brief",
            creatorPlaybookID: "pb.research",
            creatorOperatorID: nil,
            createdAt: Date(timeIntervalSince1970: 1_000),
            provenance: ArtifactProvenance(
                actor: .model(identifier: "afm", inference: .local(modelClass: "foundation")),
                inference: .local(modelClass: "foundation")
            ),
            relatedReceiptIDs: [UUID()],
            approvalState: .draft,
            destination: nil,
            exportFormat: "md",
            content: "# Brief"
        )
        let data = try JSONEncoder().encode(artifact)
        let decoded = try JSONDecoder().decode(Artifact.self, from: data)
        #expect(decoded == artifact)
        #expect(decoded.provenance.inference?.locality == .local)
    }
}

@Suite("InMemoryArtifactStore")
struct InMemoryArtifactStoreTests {
    private func draft(_ title: String, type: ArtifactType = .doc) -> ArtifactDraft {
        ArtifactDraft(
            type: type,
            title: title,
            provenance: ArtifactProvenance(actor: .human),
            content: "body of \(title)"
        )
    }

    @Test
    func createStartsAtVersionOneDraft() async {
        let store = InMemoryArtifactStore()
        let a = await store.create(draft("First"))
        #expect(a.version == 1)
        #expect(a.approvalState == .draft)
        #expect(await store.get(id: a.id) == a)
    }

    @Test
    func addVersionIncrementsAndSupersedesPrior() async {
        let store = InMemoryArtifactStore()
        let v1 = await store.create(draft("Doc"))
        let v2 = await store.addVersion(toGroup: v1.groupID, draft("Doc v2"))

        #expect(v2.version == 2)
        #expect(v2.groupID == v1.groupID)

        let versions = await store.versions(ofGroup: v1.groupID)
        #expect(versions.map(\.version) == [1, 2])
        // Prior version superseded; only the newest is returned by latest().
        #expect(await store.get(id: v1.id)?.approvalState == .superseded)
        let latest = await store.latest(limit: 10)
        #expect(latest.count == 1)
        #expect(latest.first?.version == 2)
    }

    @Test
    func filtersByTypeAndExports() async throws {
        let store = InMemoryArtifactStore()
        _ = await store.create(draft("A", type: .brief))
        _ = await store.create(draft("B", type: .report))
        let briefs = await store.all(ofType: .brief, limit: 10)
        #expect(briefs.count == 1)

        let data = try await store.exportAll()
        #expect(data.isEmpty == false)

        await store.resetAll()
        #expect(await store.latest(limit: 10).isEmpty)
    }

    @Test
    func approvalStateTransitions() async throws {
        let store = InMemoryArtifactStore()
        let a = await store.create(draft("Approve me"))
        try await store.setApprovalState(id: a.id, to: .approved)
        #expect(await store.get(id: a.id)?.approvalState == .approved)
    }

    @Test
    func relatedReceiptLinksAreStoredAndDeduplicated() async throws {
        let store = InMemoryArtifactStore()
        let artifact = await store.create(draft("Receipt linked"))
        let receiptID = UUID()

        try await store.linkRelatedReceipt(id: receiptID, toArtifact: artifact.id)
        try await store.linkRelatedReceipt(id: receiptID, toArtifact: artifact.id)

        #expect(await store.get(id: artifact.id)?.relatedReceiptIDs == [receiptID])
    }

    @Test
    func lifecycleTransitionPersistsExportMetadata() async throws {
        let store = InMemoryArtifactStore()
        let artifact = await store.create(draft("Export me", type: .brief))

        try await store.updateLifecycle(
            id: artifact.id,
            to: .exported,
            destination: "Share sheet",
            exportFormat: "markdown"
        )

        let exported = await store.get(id: artifact.id)
        #expect(exported?.approvalState == .exported)
        #expect(exported?.destination == "Share sheet")
        #expect(exported?.exportFormat == "markdown")
    }
}

/// `InMemoryArtifactStore` is documented as implementing "the full contract", and it is the double
/// every other package's tests run against. It used to `guard … else { return }` on a write to a
/// missing id while `SwiftDataArtifactStore` threw — so the one input that distinguishes them,
/// an artifact deleted concurrently, passed in tests and failed in the shipping build.
@Suite("In-memory store honours the not-found write contract")
struct InMemoryArtifactStoreWriteContractTests {
    private func store() async -> InMemoryArtifactStore { InMemoryArtifactStore() }

    @Test
    func setApprovalStateOnAMissingArtifactThrowsNotFound() async throws {
        let store = await store()
        let missing = UUID()
        await #expect(throws: ArtifactStoreWriteError.artifactNotFound(id: missing)) {
            try await store.setApprovalState(id: missing, to: .approved)
        }
    }

    @Test
    func linkRelatedReceiptOnAMissingArtifactThrowsNotFound() async throws {
        let store = await store()
        let missing = UUID()
        await #expect(throws: ArtifactStoreWriteError.artifactNotFound(id: missing)) {
            try await store.linkRelatedReceipt(id: UUID(), toArtifact: missing)
        }
    }

    @Test
    func updateLifecycleOnAMissingArtifactThrowsNotFound() async throws {
        let store = await store()
        let missing = UUID()
        await #expect(throws: ArtifactStoreWriteError.artifactNotFound(id: missing)) {
            try await store.updateLifecycle(
                id: missing,
                to: .exported,
                destination: "Share sheet",
                exportFormat: "markdown"
            )
        }
    }

    /// The present-artifact path still applies the change, so the new throw is scoped to absence
    /// rather than having turned every write into a failure.
    @Test
    func writesToAPresentArtifactStillApply() async throws {
        let store = await store()
        let created = await store.create(
            ArtifactDraft(
                type: .report,
                title: "Report",
                provenance: ArtifactProvenance(actor: .human),
                content: "body"
            )
        )

        try await store.setApprovalState(id: created.id, to: .approved)
        #expect(try await store.get(id: created.id)?.approvalState == .approved)
    }
}
