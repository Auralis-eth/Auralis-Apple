@testable import AuralisReceipts
import Foundation
import AuralisRuntime
import SwiftData
import Testing

@Suite("StoredArtifact schema version")
struct StoredArtifactSchemaVersionTests {
    private func artifact(schemaVersion: Int = ArtifactSchema.currentVersion) -> Artifact {
        Artifact(
            id: UUID(),
            groupID: UUID(),
            version: 1,
            schemaVersion: schemaVersion,
            type: .doc,
            title: "Doc",
            creatorPlaybookID: nil,
            creatorOperatorID: nil,
            createdAt: Date(timeIntervalSince1970: 100),
            provenance: ArtifactProvenance(actor: .human),
            relatedReceiptIDs: [],
            approvalState: .draft,
            destination: nil,
            exportFormat: nil,
            content: "body"
        )
    }

    @Test("the column round-trips through the stored model")
    func schemaVersionRoundTripsThroughStorage() throws {
        let stored = try StoredArtifact(artifact: artifact())

        #expect(stored.schemaVersion == ArtifactSchema.currentVersion)
        #expect(try stored.asArtifact().schemaVersion == ArtifactSchema.currentVersion)
    }

    /// The reason the column is optional: adding it has to be a SwiftData lightweight migration, so
    /// rows written before it exists read back as `nil` — and must be interpreted as the shape they
    /// were actually written under, not as unknown.
    @Test("a row predating the column reads back as the legacy version")
    func legacyRowReadsAsLegacyVersion() throws {
        let stored = try StoredArtifact(artifact: artifact())
        stored.schemaVersion = nil

        #expect(try stored.asArtifact().schemaVersion == ArtifactSchema.legacyVersion)
    }

    @Test("the store stamps the current version on a created artifact")
    @MainActor
    func storeStampsCurrentVersion() async throws {
        let container = try ModelContainer(
            for: Schema([StoredArtifact.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let store = SwiftDataArtifactStore(modelContainer: container)

        let created = try await store.create(
            ArtifactDraft(
                type: .report,
                title: "Report",
                provenance: ArtifactProvenance(actor: .human),
                content: "body"
            )
        )

        #expect(created.schemaVersion == ArtifactSchema.currentVersion)
        #expect(try await store.get(id: created.id)?.schemaVersion == ArtifactSchema.currentVersion)
    }
}
