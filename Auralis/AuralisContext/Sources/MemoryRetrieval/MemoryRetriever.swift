import Foundation
import MemoryCore

public struct MemoryRetrievalRequest: Equatable, Sendable {
    public let permittedSensitivity: MemorySensitivity
    public let permittedDataScopes: Set<String>
    public let includesSessionMemory: Bool
    public let referenceDate: Date

    public init(
        permittedSensitivity: MemorySensitivity,
        permittedDataScopes: Set<String>,
        includesSessionMemory: Bool = false,
        referenceDate: Date = .now
    ) {
        self.permittedSensitivity = permittedSensitivity
        self.permittedDataScopes = permittedDataScopes
        self.includesSessionMemory = includesSessionMemory
        self.referenceDate = referenceDate
    }
}

public struct RetrievedMemory: Equatable, Sendable {
    public let memoryID: MemoryID
    public let content: String
    public let provenance: MemoryProvenance
    public let sensitivity: MemorySensitivity
    public let dataScopes: Set<String>

    public init(revision: MemoryRevision, content: String) {
        memoryID = revision.memoryID
        self.content = content
        provenance = revision.provenance
        sensitivity = revision.sensitivity
        dataScopes = revision.dataScopes
    }
}

public struct MemoryRetriever: Sendable {
    private let store: any MemoryStoring

    public init(store: any MemoryStoring) {
        self.store = store
    }

    public func retrieve(for request: MemoryRetrievalRequest) async throws -> [RetrievedMemory] {
        try Task.checkCancellation()
        let revisions = try await store.allRevisions()
        try Task.checkCancellation()

        let latest = Dictionary(grouping: revisions, by: \MemoryRevision.memoryID)
            .compactMap { $0.value.last }

        return latest.compactMap { revision in
            guard revision.kind != .deleted,
                  let content = revision.content,
                  revision.sensitivity <= request.permittedSensitivity,
                  revision.retention.isRetained(
                    at: request.referenceDate,
                    includesSessionMemory: request.includesSessionMemory
                  ),
                  revision.dataScopes.isSubset(of: request.permittedDataScopes) else {
                return nil
            }
            return RetrievedMemory(revision: revision, content: content)
        }
        .sorted { $0.memoryID.rawValue.uuidString < $1.memoryID.rawValue.uuidString }
    }
}
