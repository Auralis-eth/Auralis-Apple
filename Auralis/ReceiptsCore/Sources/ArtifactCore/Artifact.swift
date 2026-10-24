import Foundation
import RuntimeCore

/// Receipt-domain name for the runtime's portable output-kind contract. (P1-401)
public typealias ArtifactType = ArtifactOutputType

/// Lifecycle state of an artifact.
public enum ArtifactApprovalState: String, Codable, CaseIterable, Sendable {
    case draft
    case approved
    case exported
    case superseded
}

/// Where an artifact came from — who/what made it and under what inference provenance.
public struct ArtifactProvenance: Equatable, Sendable, Codable {
    public let actor: ActorRef
    public let inference: InferenceProvenance?

    public init(actor: ActorRef, inference: InferenceProvenance? = nil) {
        self.actor = actor
        self.inference = inference
    }
}

/// A first-class, durable work product. Important operator work ends as an `Artifact`, not as
/// ephemeral chat. Versions of the same logical artifact share a `groupID`.
public struct Artifact: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    /// Stable identity across versions of the same logical artifact.
    public let groupID: UUID
    public let version: Int
    /// The ``ArtifactSchema`` version this artifact's *fields* were written under (P0.5-802).
    ///
    /// Distinct from ``version``, which counts revisions of the user's work product. This one
    /// describes the record shape, so a later build can tell "an old draft" from "a shape I don't
    /// understand".
    public let schemaVersion: Int
    public let type: ArtifactType
    public let title: String
    public let creatorPlaybookID: String?
    public let creatorOperatorID: String?
    public let createdAt: Date
    public let provenance: ArtifactProvenance
    public let relatedReceiptIDs: [UUID]
    public let approvalState: ArtifactApprovalState
    public let destination: String?
    public let exportFormat: String?
    /// The artifact body (text/markdown/JSON). Larger binary content is out of scope for v1.
    public let content: String

    public init(
        id: UUID,
        groupID: UUID,
        version: Int,
        schemaVersion: Int = ArtifactSchema.currentVersion,
        type: ArtifactType,
        title: String,
        creatorPlaybookID: String?,
        creatorOperatorID: String?,
        createdAt: Date,
        provenance: ArtifactProvenance,
        relatedReceiptIDs: [UUID],
        approvalState: ArtifactApprovalState,
        destination: String?,
        exportFormat: String?,
        content: String
    ) {
        self.id = id
        self.groupID = groupID
        self.version = version
        self.schemaVersion = schemaVersion
        self.type = type
        self.title = title
        self.creatorPlaybookID = creatorPlaybookID
        self.creatorOperatorID = creatorOperatorID
        self.createdAt = createdAt
        self.provenance = provenance
        self.relatedReceiptIDs = relatedReceiptIDs
        self.approvalState = approvalState
        self.destination = destination
        self.exportFormat = exportFormat
        self.content = content
    }

    /// Artifacts exported before ``schemaVersion`` existed decode as the legacy version rather than
    /// failing outright — an export produced by an earlier build is still readable history, and a
    /// required key here would turn every one of those files into a decode error.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        groupID = try container.decode(UUID.self, forKey: .groupID)
        version = try container.decode(Int.self, forKey: .version)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? ArtifactSchema.legacyVersion
        type = try container.decode(ArtifactType.self, forKey: .type)
        title = try container.decode(String.self, forKey: .title)
        creatorPlaybookID = try container.decodeIfPresent(String.self, forKey: .creatorPlaybookID)
        creatorOperatorID = try container.decodeIfPresent(String.self, forKey: .creatorOperatorID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        provenance = try container.decode(ArtifactProvenance.self, forKey: .provenance)
        relatedReceiptIDs = try container.decode([UUID].self, forKey: .relatedReceiptIDs)
        approvalState = try container.decode(ArtifactApprovalState.self, forKey: .approvalState)
        destination = try container.decodeIfPresent(String.self, forKey: .destination)
        exportFormat = try container.decodeIfPresent(String.self, forKey: .exportFormat)
        content = try container.decode(String.self, forKey: .content)
    }
}

/// Input to the store when creating an artifact (or a new version). The store assigns id/version/
/// createdAt and, for new versions, reuses the caller-supplied `groupID`.
public struct ArtifactDraft: Equatable, Sendable {
    public let type: ArtifactType
    public let title: String
    public let creatorPlaybookID: String?
    public let creatorOperatorID: String?
    public let provenance: ArtifactProvenance
    public let relatedReceiptIDs: [UUID]
    public let destination: String?
    public let exportFormat: String?
    public let content: String

    public init(
        type: ArtifactType,
        title: String,
        creatorPlaybookID: String? = nil,
        creatorOperatorID: String? = nil,
        provenance: ArtifactProvenance,
        relatedReceiptIDs: [UUID] = [],
        destination: String? = nil,
        exportFormat: String? = nil,
        content: String
    ) {
        self.type = type
        self.title = title
        self.creatorPlaybookID = creatorPlaybookID
        self.creatorOperatorID = creatorOperatorID
        self.provenance = provenance
        self.relatedReceiptIDs = relatedReceiptIDs
        self.destination = destination
        self.exportFormat = exportFormat
        self.content = content
    }
}

/// Why a write could not be applied.
///
/// Declared beside ``ArtifactStore`` rather than in the SwiftData package, because it is part of
/// that protocol's contract and every implementation has to be able to throw it — a second
/// implementation could not, without taking a dependency on SwiftData to report "no such row".
///
/// The write path used to return normally when the named artifact was absent, so a caller that
/// approved an artifact deleted from under it — another window, a `resetAll`, a sync — was told the
/// decision had been recorded. "Nothing to write to" is an outcome the caller has to be able to see.
public enum ArtifactStoreWriteError: LocalizedError, Equatable {
    case artifactNotFound(id: UUID)

    public var errorDescription: String? {
        switch self {
        case let .artifactNotFound(id):
            return "Artifact \(id) no longer exists, so the change was not recorded."
        }
    }
}

/// The artifact persistence surface. Create-and-version; browse; export; reset. (P1-401..404)
public protocol ArtifactStore: Sendable {
    /// Create a brand-new artifact (version 1 of a fresh `groupID`).
    func create(_ draft: ArtifactDraft) async throws -> Artifact
    /// Add a new version to an existing group; the prior latest becomes `.superseded`.
    func addVersion(toGroup groupID: UUID, _ draft: ArtifactDraft) async throws -> Artifact
    func get(id: UUID) async throws -> Artifact?
    /// Latest version of each group, newest first.
    func latest(limit: Int) async throws -> [Artifact]
    func versions(ofGroup groupID: UUID) async throws -> [Artifact]
    func all(ofType type: ArtifactType, limit: Int) async throws -> [Artifact]
    /// - Throws: ``ArtifactStoreWriteError/artifactNotFound(id:)`` when no artifact has that id.
    ///   Required of every implementation, not just the durable one: a test double that returned
    ///   normally here green-lit the concurrent-deletion path that throws in the shipping build.
    func setApprovalState(id: UUID, to state: ArtifactApprovalState) async throws
    /// - Throws: ``ArtifactStoreWriteError/artifactNotFound(id:)`` when no artifact has that id.
    func linkRelatedReceipt(id receiptID: UUID, toArtifact artifactID: UUID) async throws
    /// - Throws: ``ArtifactStoreWriteError/artifactNotFound(id:)`` when no artifact has that id.
    func updateLifecycle(
        id: UUID,
        to state: ArtifactApprovalState,
        destination: String?,
        exportFormat: String?
    ) async throws
    func exportAll() async throws -> Data
    func resetAll() async throws
}
