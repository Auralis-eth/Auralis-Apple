import Foundation
import MemoryCore

public actor JSONFileMemoryStore: MemoryStoring {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var revisions: [MemoryRevision]

    public init(fileURL: URL) throws {
        self.fileURL = fileURL
        encoder = JSONEncoder()
        decoder = JSONDecoder()

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            revisions = try decoder.decode(MemoryArchive.self, from: data).revisions
        } else {
            revisions = []
        }
    }

    public func append(_ revision: MemoryRevision) async throws {
        guard !revisions.contains(where: { $0.revisionID == revision.revisionID }) else {
            return
        }

        let history = revisions.filter { $0.memoryID == revision.memoryID }
        if let latest = history.last {
            guard revision.previousRevisionID == latest.revisionID else {
                throw MemoryStoreError.revisionConflict
            }
        } else if revision.previousRevisionID != nil || revision.kind != .created {
            throw MemoryStoreError.revisionConflict
        }

        revisions.append(revision)
        do {
            try persist()
        } catch {
            revisions.removeLast()
            throw error
        }
    }

    public func revisions(for memoryID: MemoryID) async throws -> [MemoryRevision] {
        revisions.filter { $0.memoryID == memoryID }
    }

    public func allRevisions() async throws -> [MemoryRevision] {
        revisions
    }

    private func persist() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(MemoryArchive(revisions: revisions))
        try data.write(to: fileURL, options: [.atomic])
    }
}
