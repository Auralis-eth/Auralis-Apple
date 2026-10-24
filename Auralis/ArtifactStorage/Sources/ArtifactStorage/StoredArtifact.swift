import ArtifactCore
import Foundation
import SwiftData

/// Why a persisted row could not be turned back into an ``Artifact``.
///
/// These are all "written by a build that knew more than this one" cases — a downgrade, a staged
/// rollout, or a TestFlight build followed by the App Store one. The store fails closed on them
/// rather than guessing, for the reason ``ArtifactSchema`` states about its own version set: a
/// record this build cannot interpret must not be presented as one it can.
public enum StoredArtifactDecodingError: LocalizedError, Equatable {
    case unrecognizedType(id: UUID, rawValue: String)
    case unrecognizedApprovalState(id: UUID, rawValue: String)
    case unsupportedSchemaVersion(id: UUID, version: Int)

    public var errorDescription: String? {
        switch self {
        case let .unrecognizedType(id, rawValue):
            return "Artifact \(id) has type “\(rawValue)”, which this build does not recognize."
        case let .unrecognizedApprovalState(id, rawValue):
            return "Artifact \(id) has approval state “\(rawValue)”, which this build does not recognize."
        case let .unsupportedSchemaVersion(id, version):
            let supported = ArtifactSchema.supportedVersions.sorted().map(String.init).joined(separator: ", ")
            return "Artifact \(id) was written under schema version \(version); this build reads: \(supported)."
        }
    }
}

/// SwiftData persistence model for an ``Artifact``. Complex fields (provenance, related receipt ids)
/// are JSON-encoded; the body is external-storage-backed.
@Model
public final class StoredArtifact {
    @Attribute(.unique) public var id: UUID
    public var groupID: UUID
    public var version: Int
    /// Record-shape version (P0.5-802). Optional so adding it is a SwiftData lightweight migration;
    /// rows written before the column read back as `nil`, which means `ArtifactSchema.legacyVersion`.
    public var schemaVersion: Int?
    public var typeRawValue: String
    public var title: String
    public var creatorPlaybookID: String?
    public var creatorOperatorID: String?
    public var createdAt: Date
    public var approvalStateRawValue: String
    public var destination: String?
    public var exportFormat: String?
    private var provenanceData: Data
    private var relatedReceiptIDsData: Data
    @Attribute(.externalStorage) public var content: String

    public init(artifact: Artifact) throws {
        self.id = artifact.id
        self.groupID = artifact.groupID
        self.version = artifact.version
        self.schemaVersion = artifact.schemaVersion
        self.typeRawValue = artifact.type.rawValue
        self.title = artifact.title
        self.creatorPlaybookID = artifact.creatorPlaybookID
        self.creatorOperatorID = artifact.creatorOperatorID
        self.createdAt = artifact.createdAt
        self.approvalStateRawValue = artifact.approvalState.rawValue
        self.destination = artifact.destination
        self.exportFormat = artifact.exportFormat
        self.provenanceData = try JSONEncoder().encode(artifact.provenance)
        self.relatedReceiptIDsData = try JSONEncoder().encode(artifact.relatedReceiptIDs)
        self.content = artifact.content
    }

    /// Rebuilds the domain ``Artifact``, or throws if the row was written under a shape this build
    /// cannot interpret.
    ///
    /// The three guards below replaced `?? .doc` / `?? .draft` coercions and an unread
    /// `schemaVersion`. Guessing is the wrong direction here in a way that is specific to these two
    /// fields: an unknown `approvalStateRawValue` collapsed to `.draft`, the *most permissive* state
    /// — so a record a newer build had marked (say) rejected came back as unreviewed work that this
    /// build would happily let a person approve, export, and re-version, writing a known state back
    /// over one it never understood. An unknown `typeRawValue` collapsed to `.doc`, mislabelling the
    /// work product in every surface that reads the enum while `all(ofType:)` still filtered on the
    /// raw string, so the same row was simultaneously "not a doc" and "a doc".
    ///
    /// Readers that list many rows drop an unreadable one and carry on (see
    /// `ArtifactPersistenceStore`); readers that were asked for one specific artifact, or for the
    /// whole export, propagate — a silent omission from an export is worse than a failed export.
    public func asArtifact() throws -> Artifact {
        let resolvedSchemaVersion = schemaVersion ?? ArtifactSchema.legacyVersion
        guard ArtifactSchema.supports(resolvedSchemaVersion) else {
            throw StoredArtifactDecodingError.unsupportedSchemaVersion(id: id, version: resolvedSchemaVersion)
        }
        guard let type = ArtifactType(rawValue: typeRawValue) else {
            throw StoredArtifactDecodingError.unrecognizedType(id: id, rawValue: typeRawValue)
        }
        guard let approvalState = ArtifactApprovalState(rawValue: approvalStateRawValue) else {
            throw StoredArtifactDecodingError.unrecognizedApprovalState(id: id, rawValue: approvalStateRawValue)
        }
        return Artifact(
            id: id,
            groupID: groupID,
            version: version,
            schemaVersion: resolvedSchemaVersion,
            type: type,
            title: title,
            creatorPlaybookID: creatorPlaybookID,
            creatorOperatorID: creatorOperatorID,
            createdAt: createdAt,
            provenance: try JSONDecoder().decode(ArtifactProvenance.self, from: provenanceData),
            relatedReceiptIDs: try JSONDecoder().decode([UUID].self, from: relatedReceiptIDsData),
            approvalState: approvalState,
            destination: destination,
            exportFormat: exportFormat,
            content: content
        )
    }

    public func apply(approvalState: ArtifactApprovalState) {
        approvalStateRawValue = approvalState.rawValue
    }

    public func apply(
        approvalState: ArtifactApprovalState,
        destination newDestination: String?,
        exportFormat newExportFormat: String?
    ) {
        approvalStateRawValue = approvalState.rawValue
        if let newDestination { destination = newDestination }
        if let newExportFormat { exportFormat = newExportFormat }
    }

    /// Append a related receipt id if not already present.
    public func appendRelatedReceipt(id receiptID: UUID) throws {
        var ids = try JSONDecoder().decode([UUID].self, from: relatedReceiptIDsData)
        guard !ids.contains(receiptID) else { return }
        ids.append(receiptID)
        relatedReceiptIDsData = try JSONEncoder().encode(ids)
    }
}
