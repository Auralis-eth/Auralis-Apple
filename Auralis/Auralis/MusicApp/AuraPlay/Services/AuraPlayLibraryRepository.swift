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
    private let auraPlayModelContext: ModelContext
    private let accountModelContext: ModelContext

    init(
        indexer: any MusicLibraryIndexing,
        receiptEventLogger: ReceiptEventLogger,
        auraPlayModelContainer: ModelContainer,
        accountModelContext: ModelContext
    ) {
        self.indexer = indexer
        self.receiptEventLogger = receiptEventLogger
        self.auraPlayModelContext = ModelContext(auraPlayModelContainer)
        self.accountModelContext = accountModelContext
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
        if try hasPersistedLibrary(in: scope) {
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
        guard try hasPersistedLibrary(in: scope) else {
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
        return try auraPlayModelContext.fetchCount(descriptor)
    }

    private func hasPersistedLibrary(in scope: AuraPlayLibraryScope) throws -> Bool {
        guard let normalizedAccountAddress = NFT.normalizedScopeComponent(scope.accountAddress) else {
            return false
        }

        let descriptor = FetchDescriptor<EOAccount>(
            predicate: #Predicate<EOAccount> { account in
                account.address == normalizedAccountAddress
            }
        )
        guard let account = try accountModelContext.fetch(descriptor).first else {
            return false
        }

        return account.auraPlayLastSyncedAt(for: scope.chain) != nil
    }
}
