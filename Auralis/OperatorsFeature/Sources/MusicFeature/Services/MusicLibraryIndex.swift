import AuralisPrimaryModels
import Foundation
import ReceiptsCore

public struct MusicLibraryIndexRebuildResult: Equatable, Sendable {
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
public protocol MusicLibraryIndexing {
    func itemCount(accountAddress: String?, chain: Chain) throws -> Int
    func needsRebuild(accountAddress: String?, chain: Chain) async throws -> Bool
    func rebuildIndex(
        accountAddress: String?,
        chain: Chain,
        correlationID: String?,
        receiptEventLogger: ReceiptEventLogger?
    ) async throws -> MusicLibraryIndexRebuildResult
}
