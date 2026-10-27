import Foundation

/// An in-memory ``ArtifactStore`` for tests, previews, and as a fallback before the SwiftData store
/// is wired in. Implements the full contract, including versioning and supersede semantics.
public actor InMemoryArtifactStore: ArtifactStore {
    private var artifacts: [UUID: Artifact] = [:]

    public init() { }

    public func create(_ draft: ArtifactDraft) -> Artifact {
        let artifact = makeArtifact(from: draft, groupID: UUID(), version: 1)
        artifacts[artifact.id] = artifact
        return artifact
    }

    public func addVersion(toGroup groupID: UUID, _ draft: ArtifactDraft) -> Artifact {
        let existing = artifacts.values.filter { $0.groupID == groupID }
        let nextVersion = (existing.map(\.version).max() ?? 0) + 1
        for artifact in existing where artifact.approvalState != .superseded {
            artifacts[artifact.id] = artifact.with(approvalState: .superseded)
        }
        let artifact = makeArtifact(from: draft, groupID: groupID, version: nextVersion)
        artifacts[artifact.id] = artifact
        return artifact
    }

    public func get(id: UUID) -> Artifact? {
        artifacts[id]
    }

    public func latest(limit: Int) -> [Artifact] {
        guard limit > 0 else { return [] }
        var newestByGroup: [UUID: Artifact] = [:]
        for artifact in artifacts.values {
            if let current = newestByGroup[artifact.groupID], current.version >= artifact.version { continue }
            newestByGroup[artifact.groupID] = artifact
        }
        return newestByGroup.values
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }

    public func versions(ofGroup groupID: UUID) -> [Artifact] {
        artifacts.values
            .filter { $0.groupID == groupID }
            .sorted { $0.version < $1.version }
    }

    public func all(ofType type: ArtifactType, limit: Int) -> [Artifact] {
        guard limit > 0 else { return [] }
        return artifacts.values
            .filter { $0.type == type }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }

    // These three throw rather than returning silently, matching `SwiftDataArtifactStore`. They used
    // to `guard … else { return }`, which made this double disagree with the shipping store on the
    // one input that matters: `MissionControlHomeModel.updateArtifactLifecycle` propagates, so a
    // test exercising a concurrently-deleted artifact passed here and threw in production — and the
    // receipt the model writes immediately afterwards was never reached. A double whose whole job is
    // to stand in for the real store must fail where the real store fails.

    public func setApprovalState(id: UUID, to state: ArtifactApprovalState) throws {
        guard let artifact = artifacts[id] else {
            throw ArtifactStoreWriteError.artifactNotFound(id: id)
        }
        artifacts[id] = artifact.with(approvalState: state)
    }

    public func linkRelatedReceipt(id receiptID: UUID, toArtifact artifactID: UUID) throws {
        guard let artifact = artifacts[artifactID] else {
            throw ArtifactStoreWriteError.artifactNotFound(id: artifactID)
        }
        artifacts[artifactID] = artifact.withRelatedReceipt(id: receiptID)
    }

    public func updateLifecycle(
        id: UUID,
        to state: ArtifactApprovalState,
        destination: String?,
        exportFormat: String?
    ) throws {
        guard let artifact = artifacts[id] else {
            throw ArtifactStoreWriteError.artifactNotFound(id: id)
        }
        artifacts[id] = artifact.with(
            approvalState: state,
            destination: destination,
            exportFormat: exportFormat
        )
    }

    public func exportAll() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let ordered = artifacts.values.sorted { ($0.createdAt, $0.version) < ($1.createdAt, $1.version) }
        return try encoder.encode(ordered)
    }

    public func resetAll() {
        artifacts.removeAll()
    }

    private func makeArtifact(from draft: ArtifactDraft, groupID: UUID, version: Int) -> Artifact {
        Artifact(
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
    }
}

public extension Artifact {
    /// A copy with changed lifecycle metadata.
    ///
    /// ``Artifact/schemaVersion`` is carried across explicitly, not left to its default. These copy
    /// helpers call the memberwise initializer, where `schemaVersion` defaults to
    /// ``ArtifactSchema/currentVersion`` — so omitting it re-stamps the record as though *this* build
    /// had written its fields. The version is a record of the shape an artifact was written under
    /// (see ``ArtifactSchema``); approving or exporting an older artifact must not rewrite that fact,
    /// or a v1-shaped record read back through ``ArtifactStore/setApprovalState(id:to:)`` would be
    /// persisted claiming the current shape and then be read by a later build as if it had those
    /// fields.
    func with(
        approvalState newState: ArtifactApprovalState,
        destination newDestination: String? = nil,
        exportFormat newExportFormat: String? = nil
    ) -> Artifact {
        Artifact(
            id: id,
            groupID: groupID,
            version: version,
            schemaVersion: schemaVersion,
            type: type,
            title: title,
            creatorPlaybookID: creatorPlaybookID,
            creatorOperatorID: creatorOperatorID,
            createdAt: createdAt,
            provenance: provenance,
            relatedReceiptIDs: relatedReceiptIDs,
            approvalState: newState,
            destination: newDestination ?? destination,
            exportFormat: newExportFormat ?? exportFormat,
            content: content
        )
    }

    /// A copy with `receiptID` appended, or `self` when it is already linked.
    ///
    /// Preserves ``Artifact/schemaVersion`` for the reason ``with(approvalState:destination:exportFormat:)``
    /// states: linking a receipt to an older artifact says nothing about the shape it was written under.
    func withRelatedReceipt(id receiptID: UUID) -> Artifact {
        guard !relatedReceiptIDs.contains(receiptID) else { return self }
        return Artifact(
            id: id,
            groupID: groupID,
            version: version,
            schemaVersion: schemaVersion,
            type: type,
            title: title,
            creatorPlaybookID: creatorPlaybookID,
            creatorOperatorID: creatorOperatorID,
            createdAt: createdAt,
            provenance: provenance,
            relatedReceiptIDs: relatedReceiptIDs + [receiptID],
            approvalState: approvalState,
            destination: destination,
            exportFormat: exportFormat,
            content: content
        )
    }
}
