import Foundation
import MemoryCore
import Testing

@Suite("Memory core")
struct MemoryCoreTests {
    @Test("Correction and deletion append audit history instead of rewriting it")
    func correctionsAndDeletionPreserveHistory() async throws {
        let store = TestMemoryStore()
        let ids = UUIDSequence()
        let writer = MemoryWriter(
            store: store,
            now: { Date(timeIntervalSince1970: 100) },
            makeUUID: { ids.next() }
        )
        let provenance = MemoryProvenance(
            kind: .userProvided,
            sourceReference: "settings",
            capturedAt: Date(timeIntervalSince1970: 90)
        )

        let created = try await writer.write(
            content: "Prefers concise answers",
            provenance: provenance,
            sensitivity: .personal,
            retention: .durable,
            dataScopes: ["assistant.preferences"]
        )
        let corrected = try await writer.correct(
            memoryID: created.memoryID,
            content: "Prefers concise answers with examples",
            provenance: provenance
        )
        let deleted = try await writer.delete(memoryID: created.memoryID, provenance: provenance)
        let history = try await store.revisions(for: created.memoryID)

        #expect(history == [created, corrected, deleted])
        #expect(corrected.previousRevisionID == created.revisionID)
        #expect(deleted.previousRevisionID == corrected.revisionID)
        #expect(deleted.content == nil)
    }

    @Test("Portable archives preserve provenance and reject unknown schema versions")
    func archiveRoundTrip() async throws {
        let source = TestMemoryStore()
        let writer = MemoryWriter(store: source)
        let provenance = MemoryProvenance(kind: .imported, sourceReference: "export-7", capturedAt: .now)
        _ = try await writer.write(
            content: "Remember me",
            provenance: provenance,
            sensitivity: .sensitive,
            retention: .durable,
            dataScopes: ["profile"]
        )

        let archive = try await writer.exportArchive()
        let encoded = try JSONEncoder().encode(archive)
        let decoded = try JSONDecoder().decode(MemoryArchive.self, from: encoded)
        let destination = TestMemoryStore()
        let importer = MemoryWriter(store: destination)
        try await importer.importArchive(decoded)

        #expect(try await destination.allRevisions() == archive.revisions)
        await #expect(throws: MemoryStoreError.unsupportedArchiveVersion(2)) {
            try await importer.importArchive(MemoryArchive(schemaVersion: 2, revisions: []))
        }
    }
}

private actor TestMemoryStore: MemoryStoring {
    private var values: [MemoryRevision] = []

    func append(_ revision: MemoryRevision) async throws {
        if values.contains(where: { $0.revisionID == revision.revisionID }) { return }
        values.append(revision)
    }

    func revisions(for memoryID: MemoryID) async throws -> [MemoryRevision] {
        values.filter { $0.memoryID == memoryID }
    }

    func allRevisions() async throws -> [MemoryRevision] {
        values
    }
}

private final class UUIDSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> UUID {
        lock.withLock {
            value += 1
            return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
        }
    }
}
