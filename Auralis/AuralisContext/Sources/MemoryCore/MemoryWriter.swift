import Foundation

public struct MemoryWriter: Sendable {
    private let store: any MemoryStoring
    private let now: @Sendable () -> Date
    private let makeUUID: @Sendable () -> UUID

    public init(
        store: any MemoryStoring,
        now: @escaping @Sendable () -> Date = { .now },
        makeUUID: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.store = store
        self.now = now
        self.makeUUID = makeUUID
    }

    @discardableResult
    public func write(
        content: String,
        provenance: MemoryProvenance,
        sensitivity: MemorySensitivity,
        retention: MemoryRetention,
        dataScopes: Set<String>
    ) async throws -> MemoryRevision {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MemoryStoreError.emptyContent
        }

        let revision = MemoryRevision(
            memoryID: MemoryID(rawValue: makeUUID()),
            revisionID: MemoryRevisionID(rawValue: makeUUID()),
            kind: .created,
            content: content,
            provenance: provenance,
            sensitivity: sensitivity,
            retention: retention,
            dataScopes: dataScopes,
            recordedAt: now()
        )
        try await store.append(revision)
        return revision
    }

    @discardableResult
    public func correct(
        memoryID: MemoryID,
        content: String,
        provenance: MemoryProvenance
    ) async throws -> MemoryRevision {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MemoryStoreError.emptyContent
        }
        guard let latest = try await store.revisions(for: memoryID).last,
              latest.kind != .deleted else {
            throw MemoryStoreError.memoryNotFound
        }

        let revision = MemoryRevision(
            memoryID: memoryID,
            revisionID: MemoryRevisionID(rawValue: makeUUID()),
            previousRevisionID: latest.revisionID,
            kind: .corrected,
            content: content,
            provenance: provenance,
            sensitivity: latest.sensitivity,
            retention: latest.retention,
            dataScopes: latest.dataScopes,
            recordedAt: now()
        )
        try await store.append(revision)
        return revision
    }

    @discardableResult
    public func delete(memoryID: MemoryID, provenance: MemoryProvenance) async throws -> MemoryRevision {
        guard let latest = try await store.revisions(for: memoryID).last,
              latest.kind != .deleted else {
            throw MemoryStoreError.memoryNotFound
        }

        let tombstone = MemoryRevision(
            memoryID: memoryID,
            revisionID: MemoryRevisionID(rawValue: makeUUID()),
            previousRevisionID: latest.revisionID,
            kind: .deleted,
            content: nil,
            provenance: provenance,
            sensitivity: latest.sensitivity,
            retention: latest.retention,
            dataScopes: latest.dataScopes,
            recordedAt: now()
        )
        try await store.append(tombstone)
        return tombstone
    }

    public func exportArchive() async throws -> MemoryArchive {
        MemoryArchive(revisions: try await store.allRevisions())
    }

    public func importArchive(_ archive: MemoryArchive) async throws {
        guard archive.schemaVersion == 1 else {
            throw MemoryStoreError.unsupportedArchiveVersion(archive.schemaVersion)
        }
        for revision in archive.revisions {
            try await store.append(revision)
        }
    }
}
