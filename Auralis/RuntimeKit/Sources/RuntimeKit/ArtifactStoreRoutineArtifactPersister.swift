import ArtifactCore
import Foundation
import SchedulingCore

/// Adapts the runtime-owned routine output request to the receipts-owned durable artifact store.
public struct ArtifactStoreRoutineArtifactPersister: RoutineArtifactPersisting {
    private let store: any ArtifactStore

    public init(store: any ArtifactStore) {
        self.store = store
    }

    public func create(_ draft: RoutineArtifactDraft) async throws -> UUID {
        let artifact = try await store.create(
            ArtifactDraft(
                type: draft.type,
                title: draft.title,
                creatorPlaybookID: draft.creatorPlaybookID,
                creatorOperatorID: draft.creatorOperatorID,
                provenance: ArtifactProvenance(actor: draft.actor, inference: draft.inference),
                relatedReceiptIDs: draft.relatedReceiptIDs,
                destination: draft.destination,
                exportFormat: draft.exportFormat,
                content: draft.content
            )
        )
        return artifact.id
    }
}
