import Foundation

public struct AuraPlayLibraryRebuildResult: Equatable, Sendable {
    public let scannedCount: Int
    public let writtenCount: Int
    public let removedCount: Int

    public init(scannedCount: Int, writtenCount: Int, removedCount: Int) {
        self.scannedCount = scannedCount
        self.writtenCount = writtenCount
        self.removedCount = removedCount
    }
}

@MainActor
/// Library-facing contract for AuraPlay surfaces that need music inventory without depending on the raw indexer.
public protocol AuraPlayLibraryRepository {
    func itemCount(in scope: AuraPlayLibraryScope) throws -> Int
    func needsRebuild(in scope: AuraPlayLibraryScope) async throws -> Bool
    func rebuildLibrary(
        in scope: AuraPlayLibraryScope,
        correlationID: String?
    ) async throws -> AuraPlayLibraryRebuildResult
}
