import Foundation

public struct MemoryID: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct MemoryRevisionID: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public enum MemoryProvenanceKind: String, Codable, Sendable {
    case userProvided = "user_provided"
    case imported
    case observed
    case inferred
}

public struct MemoryProvenance: Equatable, Codable, Sendable {
    public let kind: MemoryProvenanceKind
    public let sourceReference: String?
    public let capturedAt: Date

    public init(kind: MemoryProvenanceKind, sourceReference: String? = nil, capturedAt: Date) {
        self.kind = kind
        self.sourceReference = sourceReference
        self.capturedAt = capturedAt
    }
}

public enum MemorySensitivity: Int, CaseIterable, Codable, Comparable, Sendable {
    case publicData
    case personal
    case sensitive
    case restricted

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum MemoryRetention: Equatable, Codable, Sendable {
    case session
    case until(Date)
    case durable

    public func isRetained(at date: Date, includesSessionMemory: Bool) -> Bool {
        switch self {
        case .session:
            includesSessionMemory
        case .until(let expiration):
            date < expiration
        case .durable:
            true
        }
    }
}

public enum MemoryRevisionKind: String, Codable, Sendable {
    case created
    case corrected
    case deleted
}

public struct MemoryRevision: Identifiable, Equatable, Codable, Sendable {
    public var id: MemoryRevisionID { revisionID }

    public let memoryID: MemoryID
    public let revisionID: MemoryRevisionID
    public let previousRevisionID: MemoryRevisionID?
    public let kind: MemoryRevisionKind
    public let content: String?
    public let provenance: MemoryProvenance
    public let sensitivity: MemorySensitivity
    public let retention: MemoryRetention
    public let dataScopes: Set<String>
    public let recordedAt: Date

    public init(
        memoryID: MemoryID,
        revisionID: MemoryRevisionID,
        previousRevisionID: MemoryRevisionID? = nil,
        kind: MemoryRevisionKind,
        content: String?,
        provenance: MemoryProvenance,
        sensitivity: MemorySensitivity,
        retention: MemoryRetention,
        dataScopes: Set<String>,
        recordedAt: Date
    ) {
        self.memoryID = memoryID
        self.revisionID = revisionID
        self.previousRevisionID = previousRevisionID
        self.kind = kind
        self.content = content
        self.provenance = provenance
        self.sensitivity = sensitivity
        self.retention = retention
        self.dataScopes = dataScopes
        self.recordedAt = recordedAt
    }
}

public struct MemoryArchive: Equatable, Codable, Sendable {
    public let schemaVersion: Int
    public let revisions: [MemoryRevision]

    public init(schemaVersion: Int = 1, revisions: [MemoryRevision]) {
        self.schemaVersion = schemaVersion
        self.revisions = revisions
    }
}
