import Foundation

@MainActor
/// Library-facing seam for AuraPlay surfaces that need music inventory without depending on the raw indexer.
protocol AuraPlayLibraryRepository {
    func itemCount(in scope: AuraPlayLibraryScope) throws -> Int
    func needsRebuild(in scope: AuraPlayLibraryScope) throws -> Bool
    func rebuildLibrary(
        in scope: AuraPlayLibraryScope,
        correlationID: String?
    ) async throws -> MusicLibraryIndexRebuildResult
}

@MainActor
/// Production adapter over the existing shared music-library indexer.
struct LiveAuraPlayLibraryRepository: AuraPlayLibraryRepository {
    private let indexer: any MusicLibraryIndexing
    private let receiptEventLogger: ReceiptEventLogger

    init(
        indexer: any MusicLibraryIndexing,
        receiptEventLogger: ReceiptEventLogger
    ) {
        self.indexer = indexer
        self.receiptEventLogger = receiptEventLogger
    }

    func itemCount(in scope: AuraPlayLibraryScope) throws -> Int {
        try indexer.itemCount(
            accountAddress: scope.accountAddress,
            chain: scope.chain
        )
    }

    func needsRebuild(in scope: AuraPlayLibraryScope) throws -> Bool {
        try indexer.needsRebuild(
            accountAddress: scope.accountAddress,
            chain: scope.chain
        )
    }

    func rebuildLibrary(
        in scope: AuraPlayLibraryScope,
        correlationID: String?
    ) async throws -> MusicLibraryIndexRebuildResult {
        try await indexer.rebuildIndex(
            accountAddress: scope.accountAddress,
            chain: scope.chain,
            correlationID: correlationID,
            receiptEventLogger: receiptEventLogger
        )
    }
}
