import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import ReceiptStorage
import SwiftData
import TokenStorage

struct HomeScopedNFTCounts: Equatable {
    let scopedNFTCount: Int
    let musicNFTCount: Int
}

@MainActor
struct HomeScopedNFTCountService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func counts(accountAddress: String, chain: Chain) throws -> HomeScopedNFTCounts {
        let normalizedAccountAddress = NFT.normalizedScopeComponent(accountAddress) ?? ""
        let chainRawValue = chain.rawValue
        let scopedDescriptor = FetchDescriptor<NFT>(
            predicate: #Predicate<NFT> { nft in
                nft.accountAddressRawValue == normalizedAccountAddress &&
                nft.networkRawValue == chainRawValue
            }
        )
        let musicDescriptor = FetchDescriptor<NFT>(
            predicate: #Predicate<NFT> { nft in
                nft.accountAddressRawValue == normalizedAccountAddress &&
                nft.networkRawValue == chainRawValue &&
                nft.audioUrl != nil &&
                nft.audioUrl != ""
            }
        )

        return HomeScopedNFTCounts(
            scopedNFTCount: try modelContext.fetchCount(scopedDescriptor),
            musicNFTCount: try modelContext.fetchCount(musicDescriptor)
        )
    }

    func recentActivity(accountAddress: String, chain: Chain, limit: Int = 5) throws -> [ReceiptTimelineRecord] {
        let normalizedAccountAddress = NFT.normalizedScopeComponent(accountAddress) ?? ""
        let chainRawValue = chain.rawValue
        var descriptor = FetchDescriptor<StoredReceipt>(
            predicate: #Predicate<StoredReceipt> { receipt in
                receipt.accountAddress == normalizedAccountAddress &&
                receipt.chainRawValue == chainRawValue
            },
            sortBy: [
                SortDescriptor(\StoredReceipt.createdAt, order: .reverse),
                SortDescriptor(\StoredReceipt.sequenceID, order: .reverse)
            ]
        )
        descriptor.fetchLimit = limit

        return try modelContext.fetch(descriptor).map(ReceiptTimelineRecord.init)
    }

    func observePersistenceChanges(_ onChange: @escaping @MainActor () async -> Void) async {
        for await _ in NotificationCenter.default.notifications(named: ModelContext.didSave) {
            guard !Task.isCancelled else { return }
            await onChange()
        }
    }
}

@MainActor
struct SearchIndexBuilder {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func makeIndex(currentAccountAddress: String?, currentChain: Chain) async throws -> SearchLocalIndex {
        let nftSnapshots = try fetchScopedNFTSnapshots(
            currentAccountAddress: currentAccountAddress,
            currentChain: currentChain
        )
        let holdingSnapshots = try fetchScopedHoldingSnapshots(
            currentAccountAddress: currentAccountAddress,
            currentChain: currentChain
        )
        let accountSnapshots = try fetchAccountSnapshots()

        return await Task.detached(priority: .userInitiated) {
            SearchLocalIndex.make(
                nftSnapshots: nftSnapshots,
                holdingSnapshots: holdingSnapshots,
                accountSnapshots: accountSnapshots,
                currentAccountAddress: currentAccountAddress,
                currentChain: currentChain
            )
        }.value
    }

    func observePersistenceChanges(_ onChange: @escaping @MainActor () async -> Void) async {
        let observedContextID = ObjectIdentifier(modelContext)

        for await notification in NotificationCenter.default.notifications(named: ModelContext.didSave) {
            guard !Task.isCancelled else { return }
            guard let savedContext = notification.object as? ModelContext,
                  ObjectIdentifier(savedContext) == observedContextID else {
                continue
            }
            await onChange()
        }
    }

    private func fetchAccountSnapshots() throws -> [SearchLocalIndex.AccountSnapshot] {
        let descriptor = FetchDescriptor<EOAccount>(
            sortBy: [
                SortDescriptor(\EOAccount.lastSelectedAt, order: .reverse),
                SortDescriptor(\EOAccount.addedAt, order: .reverse),
                SortDescriptor(\EOAccount.address)
            ]
        )

        return try modelContext.fetch(descriptor).map {
            SearchLocalIndex.AccountSnapshot(address: $0.address, name: $0.name)
        }
    }

    private func fetchScopedNFTSnapshots(
        currentAccountAddress: String?,
        currentChain: Chain
    ) throws -> [SearchLocalIndex.NFTSnapshot] {
        let normalizedAccountAddress = NFT.normalizedScopeComponent(currentAccountAddress) ?? ""
        let chainRawValue = currentChain.rawValue
        var descriptor = FetchDescriptor<NFT>(
            predicate: #Predicate<NFT> {
                $0.accountAddressRawValue == normalizedAccountAddress &&
                $0.networkRawValue == chainRawValue
            },
            sortBy: [SortDescriptor(\NFT.id)]
        )
        descriptor.relationshipKeyPathsForPrefetching = [\NFT.contract, \NFT.collection]

        return try modelContext.fetch(descriptor).map {
            SearchLocalIndex.NFTSnapshot(
                id: $0.id,
                name: $0.name,
                collectionName: $0.collectionName,
                collectionDisplayName: $0.collection?.name,
                contractAddress: $0.contract.address,
                accountAddressRawValue: $0.accountAddressRawValue,
                networkRawValue: $0.networkRawValue
            )
        }
    }

    private func fetchScopedHoldingSnapshots(
        currentAccountAddress: String?,
        currentChain: Chain
    ) throws -> [SearchLocalIndex.HoldingSnapshot] {
        let normalizedAccountAddress = NFT.normalizedScopeComponent(currentAccountAddress) ?? ""
        let chainRawValue = currentChain.rawValue
        let descriptor = FetchDescriptor<TokenHolding>(
            predicate: #Predicate<TokenHolding> {
                $0.accountAddressRawValue == normalizedAccountAddress &&
                $0.chainRawValue == chainRawValue
            },
            sortBy: [
                SortDescriptor(\TokenHolding.sortPriority),
                SortDescriptor(\TokenHolding.displayName)
            ]
        )

        return try modelContext.fetch(descriptor).map {
            SearchLocalIndex.HoldingSnapshot(
                accountAddressRawValue: $0.accountAddressRawValue,
                chainRawValue: $0.chainRawValue,
                balanceKind: $0.balanceKind,
                contractAddress: $0.contractAddress,
                symbol: $0.symbol,
                displayName: $0.displayName
            )
        }
    }
}

struct ProfileAssetSummary: Equatable {
    let account: EOAccount?
    let scopedNFTCount: Int
    let scopedTokenCount: Int
}

@MainActor
struct ProfileAssetSummaryService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func summary(accountAddress: String, chain: Chain) throws -> ProfileAssetSummary {
        let normalizedAccountAddress = NFT.normalizedScopeComponent(accountAddress) ?? ""
        let chainRawValue = chain.rawValue
        let accountDescriptor = FetchDescriptor<EOAccount>(
            predicate: #Predicate<EOAccount> { account in
                account.address == normalizedAccountAddress
            }
        )
        let nftDescriptor = FetchDescriptor<NFT>(
            predicate: #Predicate<NFT> { nft in
                nft.accountAddressRawValue == normalizedAccountAddress &&
                nft.networkRawValue == chainRawValue
            }
        )
        let holdingDescriptor = FetchDescriptor<TokenHolding>(
            predicate: #Predicate<TokenHolding> { holding in
                holding.accountAddressRawValue == normalizedAccountAddress &&
                holding.chainRawValue == chainRawValue
            }
        )

        return ProfileAssetSummary(
            account: try modelContext.fetch(accountDescriptor).first,
            scopedNFTCount: try modelContext.fetchCount(nftDescriptor),
            scopedTokenCount: try modelContext.fetchCount(holdingDescriptor)
        )
    }

    func observePersistenceChanges(_ onChange: @escaping @MainActor () async -> Void) async {
        for await _ in NotificationCenter.default.notifications(named: ModelContext.didSave) {
            guard !Task.isCancelled else { return }
            await onChange()
        }
    }
}

struct ChromeContextReceipts: Equatable {
    let latest: ReceiptTimelineRecord?
    let related: [ReceiptTimelineRecord]
}

@MainActor
struct ChromeContextRefreshService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func contextReceipts(scope: ReceiptTimelineScope?) throws -> ChromeContextReceipts {
        guard let scope else {
            return ChromeContextReceipts(latest: nil, related: [])
        }

        guard let latestStoredReceipt = try modelContext.fetch(
            makeLatestContextReceiptDescriptor(for: scope)
        ).first else {
            return ChromeContextReceipts(latest: nil, related: [])
        }

        let latestReceipt = ReceiptTimelineRecord(storedReceipt: latestStoredReceipt)
        let relatedReceipts = try relatedContextReceipts(
            correlationID: latestReceipt.correlationID,
            excludingReceiptID: latestReceipt.id,
            scope: scope
        )
        return ChromeContextReceipts(latest: latestReceipt, related: relatedReceipts)
    }

    private func relatedContextReceipts(
        correlationID: String?,
        excludingReceiptID: UUID,
        scope: ReceiptTimelineScope
    ) throws -> [ReceiptTimelineRecord] {
        guard let correlationID, !correlationID.isEmpty else {
            return []
        }

        return try modelContext.fetch(
            makeRelatedContextReceiptsDescriptor(
                correlationID: correlationID,
                excludingReceiptID: excludingReceiptID,
                scope: scope
            )
        )
        .map(ReceiptTimelineRecord.init)
    }

    private func makeLatestContextReceiptDescriptor(
        for scope: ReceiptTimelineScope
    ) -> FetchDescriptor<StoredReceipt> {
        let normalizedAccountAddress = AuralisEthereumAddress.normalized(scope.accountAddress)
        let chainRawValue = scope.chain.rawValue

        return FetchDescriptor(
            predicate: #Predicate<StoredReceipt> { storedReceipt in
                storedReceipt.trigger == "context.built"
                    && storedReceipt.accountAddress == normalizedAccountAddress
                    && storedReceipt.chainRawValue == chainRawValue
            },
            sortBy: [
                SortDescriptor(\StoredReceipt.createdAt, order: .reverse),
                SortDescriptor(\StoredReceipt.sequenceID, order: .reverse)
            ]
        )
    }

    private func makeRelatedContextReceiptsDescriptor(
        correlationID: String,
        excludingReceiptID: UUID,
        scope: ReceiptTimelineScope
    ) -> FetchDescriptor<StoredReceipt> {
        let normalizedAccountAddress = AuralisEthereumAddress.normalized(scope.accountAddress)
        let chainRawValue = scope.chain.rawValue

        return FetchDescriptor(
            predicate: #Predicate<StoredReceipt> { storedReceipt in
                storedReceipt.correlationID == correlationID
                    && storedReceipt.id != excludingReceiptID
                    && storedReceipt.accountAddress == normalizedAccountAddress
                    && storedReceipt.chainRawValue == chainRawValue
            },
            sortBy: [
                SortDescriptor(\StoredReceipt.createdAt, order: .reverse),
                SortDescriptor(\StoredReceipt.sequenceID, order: .reverse)
            ]
        )
    }
}
