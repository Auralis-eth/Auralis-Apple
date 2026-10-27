import ArtifactCore
@testable import ArtifactStorage
import Foundation
import AuralisRuntime
import SwiftData
import Testing

@Suite("SwiftDataArtifactStore")
struct SwiftDataArtifactStoreTests {
    @MainActor
    private func makeStore() throws -> SwiftDataArtifactStore {
        let container = try ModelContainer(
            for: Schema([StoredArtifact.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        return SwiftDataArtifactStore(modelContainer: container)
    }

    private func draft(_ title: String, type: ArtifactType = .doc) -> ArtifactDraft {
        ArtifactDraft(
            type: type,
            title: title,
            provenance: ArtifactProvenance(actor: .human),
            content: "body of \(title)"
        )
    }

    @Test
    func createAndFetchRoundTrips() async throws {
        let store = try await makeStore()
        let a = try await store.create(draft("First", type: .brief))
        #expect(a.version == 1)
        let fetched = try await store.get(id: a.id)
        #expect(fetched == a)
    }

    @Test
    func versioningSupersedesPriorAndLatestReturnsNewest() async throws {
        let store = try await makeStore()
        let v1 = try await store.create(draft("Doc"))
        let v2 = try await store.addVersion(toGroup: v1.groupID, draft("Doc v2"))

        #expect(v2.version == 2)
        let versions = try await store.versions(ofGroup: v1.groupID)
        #expect(versions.map(\.version) == [1, 2])
        #expect(try await store.get(id: v1.id)?.approvalState == .superseded)

        let latest = try await store.latest(limit: 10)
        #expect(latest.count == 1)
        #expect(latest.first?.id == v2.id)
    }

    @Test
    func filterExportAndReset() async throws {
        let store = try await makeStore()
        _ = try await store.create(draft("A", type: .brief))
        _ = try await store.create(draft("B", type: .report))

        #expect(try await store.all(ofType: .brief, limit: 10).count == 1)

        let data = try await store.exportAll()
        let decoded = try JSONDecoder().decode([Artifact].self, from: data)
        #expect(decoded.count == 2)

        try await store.resetAll()
        #expect(try await store.latest(limit: 10).isEmpty)
    }

    @Test
    func approvalStatePersists() async throws {
        let store = try await makeStore()
        let a = try await store.create(draft("Approve"))
        try await store.setApprovalState(id: a.id, to: .approved)
        #expect(try await store.get(id: a.id)?.approvalState == .approved)
    }

    /// These three used to return normally when the row was absent, so approving an artifact that
    /// had been deleted from under the caller — another window, a `resetAll` — reported success and
    /// wrote nothing.
    @Test
    func writingToAMissingArtifactIsReported() async throws {
        let store = try await makeStore()
        let missing = UUID()

        await #expect(throws: ArtifactStoreWriteError.artifactNotFound(id: missing)) {
            try await store.setApprovalState(id: missing, to: .approved)
        }
        await #expect(throws: ArtifactStoreWriteError.artifactNotFound(id: missing)) {
            try await store.linkRelatedReceipt(id: UUID(), toArtifact: missing)
        }
        await #expect(throws: ArtifactStoreWriteError.artifactNotFound(id: missing)) {
            try await store.updateLifecycle(id: missing, to: .exported, destination: "files", exportFormat: "md")
        }
    }
}

/// A read must not scale with the table.
///
/// `ArtifactPersistenceStore` had exactly one read primitive — fetch every row — so naming a single
/// artifact materialised all of them: `get(id:)`, `setApprovalState`, `linkRelatedReceipt` and
/// `updateLifecycle` were each O(table). Nothing prunes `StoredArtifact` (the type comment now
/// argues that cap decision explicitly instead of asserting "volumes are small"), so the table the
/// scan walked is the one that grows under P2-EVAL write rates.
@Suite("Artifact store read bounds")
struct ArtifactStoreReadBoundsTests {
    @MainActor
    private func makeStore() throws -> ArtifactPersistenceStore {
        let container = try ModelContainer(
            for: Schema([StoredArtifact.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        return ArtifactPersistenceStore(modelContainer: container)
    }

    private func draft(_ title: String) -> ArtifactDraft {
        ArtifactDraft(
            type: .doc,
            title: title,
            provenance: ArtifactProvenance(actor: .human),
            content: "body of \(title)"
        )
    }

    @Test("naming one artifact fetches one row, not the table")
    @MainActor
    func namedReadsAndWritesFetchASingleRow() async throws {
        let store = try makeStore()
        var ids: [UUID] = []
        for index in 0..<25 {
            ids.append(try await store.create(draft("Doc \(index)")).id)
        }
        let target = ids[12]

        await store.resetRowsFetchedForTesting()
        #expect(try await store.get(id: target)?.id == target)
        #expect(await store.rowsFetchedForTesting == 1)

        // The named write paths share the primitive, so approving one artifact read all 25 too.
        await store.resetRowsFetchedForTesting()
        try await store.setApprovalState(id: target, to: .approved)
        #expect(await store.rowsFetchedForTesting == 1)

        await store.resetRowsFetchedForTesting()
        try await store.linkRelatedReceipt(id: UUID(), toArtifact: target)
        #expect(await store.rowsFetchedForTesting == 1)

        // A miss is bounded as well: proving absence used to mean walking every row.
        await store.resetRowsFetchedForTesting()
        #expect(try await store.get(id: UUID()) == nil)
        #expect(await store.rowsFetchedForTesting == 0)

        // The row the bounded fetch found is still the right one.
        #expect(try await store.get(id: target)?.approvalState == .approved)
    }
}
