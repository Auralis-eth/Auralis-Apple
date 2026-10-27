import Foundation
import AuralisContext
import Testing

@Suite("Memory storage")
struct MemoryStorageTests {
    @Test("The file ledger survives reconstruction and enforces revision order")
    func persistenceAndRevisionOrder() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("memory.json")
        let first = makeRevision()

        let store = try JSONFileMemoryStore(fileURL: fileURL)
        try await store.append(first)
        let restored = try JSONFileMemoryStore(fileURL: fileURL)

        #expect(try await restored.allRevisions() == [first])

        let conflicting = MemoryRevision(
            memoryID: first.memoryID,
            revisionID: MemoryRevisionID(rawValue: UUID()),
            previousRevisionID: MemoryRevisionID(rawValue: UUID()),
            kind: .corrected,
            content: "conflict",
            provenance: first.provenance,
            sensitivity: first.sensitivity,
            retention: first.retention,
            dataScopes: first.dataScopes,
            recordedAt: first.recordedAt
        )
        await #expect(throws: MemoryStoreError.revisionConflict) {
            try await restored.append(conflicting)
        }
        #expect(try await restored.allRevisions() == [first])
    }

    private func makeRevision() -> MemoryRevision {
        MemoryRevision(
            memoryID: MemoryID(rawValue: UUID()),
            revisionID: MemoryRevisionID(rawValue: UUID()),
            kind: .created,
            content: "portable",
            provenance: MemoryProvenance(kind: .observed, capturedAt: Date(timeIntervalSince1970: 10)),
            sensitivity: .personal,
            retention: .durable,
            dataScopes: ["profile"],
            recordedAt: Date(timeIntervalSince1970: 11)
        )
    }
}
