import Foundation
import AuralisContext
import Testing

@Suite("Memory retrieval")
struct MemoryRetrievalTests {
    @Test("Retrieval enforces sensitivity, scope, retention, and deletion")
    func governedFiltering() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let allowed = revision(content: "allowed", sensitivity: .personal, retention: .durable, scopes: ["task"])
        let restricted = revision(content: "restricted", sensitivity: .restricted, retention: .durable, scopes: ["task"])
        let expired = revision(
            content: "expired",
            sensitivity: .publicData,
            retention: .until(Date(timeIntervalSince1970: 999)),
            scopes: ["task"]
        )
        let wrongScope = revision(content: "other", sensitivity: .publicData, retention: .durable, scopes: ["other"])
        let deletedOriginal = revision(content: "deleted", sensitivity: .publicData, retention: .durable, scopes: ["task"])
        let tombstone = MemoryRevision(
            memoryID: deletedOriginal.memoryID,
            revisionID: MemoryRevisionID(rawValue: UUID()),
            previousRevisionID: deletedOriginal.revisionID,
            kind: .deleted,
            content: nil,
            provenance: deletedOriginal.provenance,
            sensitivity: deletedOriginal.sensitivity,
            retention: deletedOriginal.retention,
            dataScopes: deletedOriginal.dataScopes,
            recordedAt: now
        )
        let store = RetrievalStore(values: [allowed, restricted, expired, wrongScope, deletedOriginal, tombstone])
        let result = try await MemoryRetriever(store: store).retrieve(
            for: MemoryRetrievalRequest(
                permittedSensitivity: .personal,
                permittedDataScopes: ["task"],
                referenceDate: now
            )
        )

        #expect(result.map(\.content) == ["allowed"])
        #expect(result.first?.provenance == allowed.provenance)
    }

    @Test("Cancellation propagates before retrieval touches storage")
    func cancellation() async {
        let store = RetrievalStore(values: [])
        let task = Task {
            try await MemoryRetriever(store: store).retrieve(
                for: MemoryRetrievalRequest(
                    permittedSensitivity: .restricted,
                    permittedDataScopes: []
                )
            )
        }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }

    private func revision(
        content: String,
        sensitivity: MemorySensitivity,
        retention: MemoryRetention,
        scopes: Set<String>
    ) -> MemoryRevision {
        MemoryRevision(
            memoryID: MemoryID(rawValue: UUID()),
            revisionID: MemoryRevisionID(rawValue: UUID()),
            kind: .created,
            content: content,
            provenance: MemoryProvenance(kind: .userProvided, capturedAt: Date(timeIntervalSince1970: 900)),
            sensitivity: sensitivity,
            retention: retention,
            dataScopes: scopes,
            recordedAt: Date(timeIntervalSince1970: 900)
        )
    }
}

private actor RetrievalStore: MemoryStoring {
    let values: [MemoryRevision]

    init(values: [MemoryRevision]) {
        self.values = values
    }

    func append(_ revision: MemoryRevision) async throws {}

    func revisions(for memoryID: MemoryID) async throws -> [MemoryRevision] {
        values.filter { $0.memoryID == memoryID }
    }

    func allRevisions() async throws -> [MemoryRevision] {
        values
    }
}
