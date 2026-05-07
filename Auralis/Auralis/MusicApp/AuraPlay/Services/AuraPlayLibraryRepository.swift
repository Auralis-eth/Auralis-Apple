import AuralisPrimaryModels
import Foundation
import SwiftData

@MainActor
/// Library-facing seam for AuraPlay surfaces that need music inventory without depending on the raw indexer.
protocol AuraPlayLibraryRepository {
    func itemCount(in scope: AuraPlayLibraryScope) throws -> Int
    func needsRebuild(in scope: AuraPlayLibraryScope) async throws -> Bool
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
    private let readModelContext: ModelContext

    init(
        indexer: any MusicLibraryIndexing,
        receiptEventLogger: ReceiptEventLogger,
        modelContainer: ModelContainer
    ) {
        self.indexer = indexer
        self.receiptEventLogger = receiptEventLogger
        self.readModelContext = ModelContext(modelContainer)
    }

    func itemCount(in scope: AuraPlayLibraryScope) throws -> Int {
        if let persistedCount = try persistedItemCountIfAvailable(in: scope) {
            return persistedCount
        }

        return try indexer.itemCount(
            accountAddress: scope.accountAddress,
            chain: scope.chain
        )
    }

    func needsRebuild(in scope: AuraPlayLibraryScope) async throws -> Bool {
        if try hasPersistedWallet(in: scope) {
            return false
        }

        return try await indexer.needsRebuild(
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

    private func persistedItemCountIfAvailable(in scope: AuraPlayLibraryScope) throws -> Int? {
        guard try hasPersistedWallet(in: scope) else {
            return nil
        }

        let normalizedAccountAddress = NFT.normalizedScopeComponent(scope.accountAddress) ?? ""
        let chainRawValue = scope.chain.rawValue
        let descriptor = FetchDescriptor<AuraPlayMediaItem>(
            predicate: #Predicate<AuraPlayMediaItem> { item in
                item.accountAddressRawValue == normalizedAccountAddress &&
                item.chainRawValue == chainRawValue
            }
        )
        return try readModelContext.fetchCount(descriptor)
    }

    private func hasPersistedWallet(in scope: AuraPlayLibraryScope) throws -> Bool {
        guard let normalizedAccountAddress = NFT.normalizedScopeComponent(scope.accountAddress) else {
            return false
        }

        let walletID = AuraPlayWallet.scopedID(address: normalizedAccountAddress, chain: scope.chain)
        let descriptor = FetchDescriptor<AuraPlayWallet>(
            predicate: #Predicate<AuraPlayWallet> { wallet in
                wallet.id == walletID
            }
        )
        return try readModelContext.fetchCount(descriptor) > 0
    }
}
