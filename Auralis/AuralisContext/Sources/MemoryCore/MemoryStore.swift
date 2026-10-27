public protocol MemoryStoring: Sendable {
    func append(_ revision: MemoryRevision) async throws
    func revisions(for memoryID: MemoryID) async throws -> [MemoryRevision]
    func allRevisions() async throws -> [MemoryRevision]
}

public enum MemoryStoreError: Error, Equatable, Sendable {
    case emptyContent
    case memoryNotFound
    case revisionConflict
    case unsupportedArchiveVersion(Int)
}
