import AccountsCore
import AuralisPrimaryModels
import Foundation
import SwiftData
import SwiftDataAdapters

private let accountSortDescriptors: [SortDescriptor<EOAccount>] = [
    SortDescriptor(\EOAccount.lastSelectedAt, order: .reverse),
    SortDescriptor(\EOAccount.addedAt, order: .reverse),
    SortDescriptor(\EOAccount.address),
]

@ModelActor
private actor AccountPersistenceStore {
    struct RemovalSnapshot: Sendable {
        let removedAddress: String
        let fallbackAddress: String?
    }

    func createWatchAccount(
        normalizedAddress: String,
        name: String?,
        source: EOAccountSource,
        overwriteExisting: Bool,
        now: Date
    ) throws {
        try modelContext.performRollbackSafeMutation {
            if let existingAccount = try account(for: normalizedAddress) {
                guard overwriteExisting else {
                    throw AccountStoreError.duplicateAddress(normalizedAddress)
                }

                try modelContext.deleteAccountScopedSupportData(accountAddress: normalizedAddress)
                try modelContext.deleteNFTsScopedToAccount(normalizedAddress)
                modelContext.delete(existingAccount)
            }

            let account = EOAccount(
                address: normalizedAddress,
                access: .readonly,
                name: name,
                source: source,
                addedAt: now,
                lastSelectedAt: nil,
                trackedNFTCount: 0
            )

            modelContext.insert(account)
        }
    }

    func selectAccount(
        normalizedAddress: String,
        selectedAt: Date
    ) throws {
        guard let account = try account(for: normalizedAddress) else {
            throw AccountStoreError.accountNotFound(normalizedAddress)
        }

        account.lastSelectedAt = selectedAt
        try modelContext.save()
    }

    func persistCurrentChain(
        normalizedAddress: String,
        chain: Chain
    ) throws {
        guard let account = try account(for: normalizedAddress) else {
            throw AccountStoreError.accountNotFound(normalizedAddress)
        }

        account.currentChain = chain
        try modelContext.save()
    }

    func persistPreferredChain(
        normalizedAddress: String,
        chain: Chain
    ) throws {
        guard let account = try account(for: normalizedAddress) else {
            throw AccountStoreError.accountNotFound(normalizedAddress)
        }

        account.preferredChain = chain
        try modelContext.save()
    }

    private func account(for normalizedAddress: String) throws -> EOAccount? {
        let descriptor = FetchDescriptor<EOAccount>(
            predicate: #Predicate<EOAccount> { account in
                account.address == normalizedAddress
            }
        )

        return try modelContext.fetch(descriptor).first
    }
}

@MainActor
/// Coordinates wallet validation, persistence, selection, and account-level receipt logging.
public struct SwiftDataAccountStore: AccountStoring {
    private let modelContext: ModelContext
    private let eventRecorder: any AccountEventRecorder
    private let persistenceStore: AccountPersistenceStore

    /// Creates an account store that performs mutations without recording account events.
    public init(modelContext: ModelContext) {
        self.init(
            modelContext: modelContext,
            eventRecorder: NoOpAccountEventRecorder()
        )
    }

    /// Creates an account store backed by SwiftData and an explicit account event recorder.
    public init(
        modelContext: ModelContext,
        eventRecorder: any AccountEventRecorder
    ) {
        self.modelContext = modelContext
        self.eventRecorder = eventRecorder
        self.persistenceStore = AccountPersistenceStore(modelContainer: modelContext.container)
    }

    public func listAccounts() throws -> [EOAccount] {
        let accounts = try modelContext.fetch(
            FetchDescriptor(sortBy: accountSortDescriptors)
        )
        if accounts.contains(where: { $0.normalizeStoredMetadataIfNeeded() }) {
            try modelContext.save()
        }

        return accounts
    }

    public func account(for rawAddress: String) throws -> EOAccount? {
        guard let normalizedAddress = AccountStore.normalizeAddress(rawAddress) else {
            return nil
        }

        let descriptor = FetchDescriptor<EOAccount>(
            predicate: #Predicate<EOAccount> { account in
                account.address == normalizedAddress
            }
        )

        let account = try modelContext.fetch(descriptor).first
        if let account, account.normalizeStoredMetadataIfNeeded() {
            try modelContext.save()
        }

        return account
    }

    public func createWatchAccount(
        from rawAddress: String,
        name: String? = nil,
        source: EOAccountSource = .manualEntry,
        overwriteExisting: Bool = false,
        now: Date = .now,
        correlationID: String? = nil
    ) async throws -> EOAccount {
        guard let normalizedAddress = AccountStore.normalizeAddress(rawAddress) else {
            throw AccountStoreError.invalidAddress
        }

        try await persistenceStore.createWatchAccount(
            normalizedAddress: normalizedAddress,
            name: name,
            source: source,
            overwriteExisting: overwriteExisting,
            now: now
        )

        if overwriteExisting {
            await eventRecorder.record(.removed(address: normalizedAddress), correlationID: correlationID)
        }
        await eventRecorder.record(.added(address: normalizedAddress), correlationID: correlationID)

        guard let account = try account(for: normalizedAddress) else {
            throw AccountStoreError.accountNotFound(normalizedAddress)
        }
        return account
    }

    public func activateWatchAccount(
        from rawAddress: String,
        name: String? = nil,
        source: EOAccountSource = .manualEntry,
        selectedAt: Date = .now,
        correlationID: String? = nil
    ) async throws -> AccountActivationResult {
        do {
            let createdAccount = try await createWatchAccount(
                from: rawAddress,
                name: name,
                source: source,
                now: selectedAt,
                correlationID: correlationID
            )
            let selectedAccount = try await selectAccount(
                address: createdAccount.address,
                selectedAt: selectedAt,
                correlationID: correlationID
            )

            return AccountActivationResult(account: selectedAccount, wasCreated: true)
        } catch let error as AccountStoreError {
            guard case .duplicateAddress = error else {
                throw error
            }

            guard let existingAccount = try account(for: rawAddress) else {
                throw error
            }

            let selectedAccount = try await selectAccount(
                address: existingAccount.address,
                selectedAt: selectedAt,
                correlationID: correlationID
            )

            return AccountActivationResult(account: selectedAccount, wasCreated: false)
        }
    }

    public func selectAccount(
        address rawAddress: String,
        selectedAt: Date = .now,
        correlationID: String? = nil
    ) async throws -> EOAccount {
        guard let normalizedAddress = AccountStore.normalizeAddress(rawAddress) else {
            throw AccountStoreError.accountNotFound(rawAddress)
        }

        try await persistenceStore.selectAccount(
            normalizedAddress: normalizedAddress,
            selectedAt: selectedAt
        )

        guard let account = try account(for: normalizedAddress) else {
            throw AccountStoreError.accountNotFound(normalizedAddress)
        }

        await eventRecorder.record(.selected(address: account.address), correlationID: correlationID)
        return account
    }

    public func removeAccount(
        address rawAddress: String,
        activeAddress: String? = nil,
        correlationID: String? = nil
    ) async throws -> AccountRemovalResult {
        guard let normalizedAddress = AccountStore.normalizeAddress(rawAddress) else {
            throw AccountStoreError.accountNotFound(rawAddress)
        }

        let removalSnapshot = try removeAccountFromMainContext(
            normalizedAddress: normalizedAddress,
            normalizedActiveAddress: activeAddress.flatMap(AccountStore.normalizeAddress)
        )
        await eventRecorder.record(.removed(address: removalSnapshot.removedAddress), correlationID: correlationID)

        return AccountRemovalResult(
            removedAddress: removalSnapshot.removedAddress,
            fallbackAccount: try removalSnapshot.fallbackAddress.flatMap { try account(for: $0) }
        )
    }

    public func persistCurrentChain(
        address rawAddress: String,
        chain: Chain,
        correlationID: String? = nil
    ) async throws -> EOAccount {
        guard let normalizedAddress = AccountStore.normalizeAddress(rawAddress) else {
            throw AccountStoreError.accountNotFound(rawAddress)
        }

        guard let existingAccount = try account(for: normalizedAddress) else {
            throw AccountStoreError.accountNotFound(normalizedAddress)
        }
        let previousChain = existingAccount.currentChain

        guard previousChain != chain else {
            return existingAccount
        }

        try await persistenceStore.persistCurrentChain(
            normalizedAddress: normalizedAddress,
            chain: chain
        )
        await eventRecorder.record(
            .currentChainChanged(address: existingAccount.address, from: previousChain, to: chain),
            correlationID: correlationID
        )

        guard let refreshedAccount = try account(for: normalizedAddress) else {
            throw AccountStoreError.accountNotFound(normalizedAddress)
        }
        return refreshedAccount
    }

    public func persistPreferredChain(
        address rawAddress: String,
        chain: Chain,
        correlationID: String? = nil
    ) async throws -> EOAccount {
        guard let normalizedAddress = AccountStore.normalizeAddress(rawAddress) else {
            throw AccountStoreError.accountNotFound(rawAddress)
        }

        guard let existingAccount = try account(for: normalizedAddress) else {
            throw AccountStoreError.accountNotFound(normalizedAddress)
        }
        let previousChain = existingAccount.preferredChain

        guard previousChain != chain else {
            return existingAccount
        }

        try await persistenceStore.persistPreferredChain(
            normalizedAddress: normalizedAddress,
            chain: chain
        )
        await eventRecorder.record(
            .preferredChainChanged(address: existingAccount.address, from: previousChain, to: chain),
            correlationID: correlationID
        )

        guard let refreshedAccount = try account(for: normalizedAddress) else {
            throw AccountStoreError.accountNotFound(normalizedAddress)
        }
        return refreshedAccount
    }
}

private extension SwiftDataAccountStore {
    func removeAccountFromMainContext(
        normalizedAddress: String,
        normalizedActiveAddress: String?
    ) throws -> AccountPersistenceStore.RemovalSnapshot {
        guard let account = try account(for: normalizedAddress) else {
            throw AccountStoreError.accountNotFound(normalizedAddress)
        }

        let removedAddress = account.address
        let fallbackAddress: String?
        if normalizedActiveAddress == removedAddress {
            fallbackAddress = try listAccounts()
                .first(where: { $0.address != removedAddress })?
                .address
        } else {
            fallbackAddress = nil
        }

        if let undoManager = modelContext.undoManager {
            let undoSnapshot = try modelContext.accountRemovalUndoSnapshot(
                account: account,
                accountAddress: removedAddress
            )

            undoManager.disableUndoRegistration()
            do {
                try modelContext.performRollbackSafeMutation {
                    try modelContext.deleteAccountScopedSupportData(accountAddress: removedAddress)
                    try modelContext.deleteNFTsScopedToAccount(removedAddress)
                    modelContext.delete(account)
                }
            } catch {
                undoManager.enableUndoRegistration()
                throw error
            }
            undoManager.enableUndoRegistration()

            undoManager.removeAllActions()
            undoManager.registerUndo(withTarget: modelContext) { context in
                context.undoManager?.disableUndoRegistration()
                defer {
                    context.undoManager?.enableUndoRegistration()
                }
                try? context.restoreAccountRemovalUndoSnapshot(undoSnapshot)
            }
            undoManager.setActionName("Remove Account")
        } else {
            try modelContext.performRollbackSafeMutation {
                try modelContext.deleteAccountScopedSupportData(accountAddress: removedAddress)
                try modelContext.deleteNFTsScopedToAccount(removedAddress)
                modelContext.delete(account)
            }
        }

        return AccountPersistenceStore.RemovalSnapshot(
            removedAddress: removedAddress,
            fallbackAddress: fallbackAddress
        )
    }
}

private struct AccountRemovalUndoSnapshot {
    let account: AccountSnapshot
    let tokenHoldings: [TokenHoldingSnapshot]
    let searchHistory: [SearchHistorySnapshot]
    let nfts: [NFTSnapshot]
}

private struct AccountSnapshot {
    let address: String
    let access: EthereumAddressAccess?
    let name: String?
    let source: EOAccountSource
    let addedAt: Date
    let lastSelectedAt: Date?
    let trackedNFTCount: Int
    let preferredChainRawValue: String
    let currentChainRawValue: String
    let auraPlaySyncStateRawValue: String?

    init(_ account: EOAccount) {
        self.address = account.address
        self.access = account.access
        self.name = account.name
        self.source = account.source
        self.addedAt = account.addedAt
        self.lastSelectedAt = account.lastSelectedAt
        self.trackedNFTCount = account.trackedNFTCount
        self.preferredChainRawValue = account.preferredChainRawValue
        self.currentChainRawValue = account.currentChainRawValue
        self.auraPlaySyncStateRawValue = account.auraPlaySyncStateRawValue
    }

    func model() -> EOAccount {
        let account = EOAccount(
            address: address,
            access: access,
            name: name,
            source: source,
            addedAt: addedAt,
            lastSelectedAt: lastSelectedAt,
            trackedNFTCount: trackedNFTCount
        )
        account.preferredChainRawValue = preferredChainRawValue
        account.currentChainRawValue = currentChainRawValue
        account.auraPlaySyncStateRawValue = auraPlaySyncStateRawValue
        return account
    }
}

private struct TokenHoldingSnapshot {
    let accountAddress: String
    let chain: Chain
    let contractAddress: String?
    let symbol: String?
    let displayName: String
    let amountDisplay: String
    let balanceKind: TokenHoldingKind
    let updatedAt: Date
    let isPlaceholder: Bool
    let sortPriority: Int

    init(_ holding: TokenHolding) {
        self.accountAddress = holding.accountAddressRawValue
        self.chain = holding.chain
        self.contractAddress = holding.contractAddressRawValue
        self.symbol = holding.symbol
        self.displayName = holding.displayName
        self.amountDisplay = holding.amountDisplay
        self.balanceKind = holding.balanceKind
        self.updatedAt = holding.updatedAt
        self.isPlaceholder = holding.isPlaceholder
        self.sortPriority = holding.sortPriority
    }

    func model() -> TokenHolding {
        TokenHolding(
            accountAddress: accountAddress,
            chain: chain,
            contractAddress: contractAddress,
            symbol: symbol,
            displayName: displayName,
            amountDisplay: amountDisplay,
            balanceKind: balanceKind,
            updatedAt: updatedAt,
            isPlaceholder: isPlaceholder,
            sortPriority: sortPriority
        )
    }
}

private struct SearchHistorySnapshot {
    let accountAddressRawValue: String?
    let normalizedQuery: String
    let query: String
    let recordedAt: Date

    init(_ record: SearchHistoryRecord) {
        self.accountAddressRawValue = record.accountAddressRawValue
        self.normalizedQuery = record.normalizedQuery
        self.query = record.query
        self.recordedAt = record.recordedAt
    }

    func model() -> SearchHistoryRecord {
        SearchHistoryRecord(
            accountAddressRawValue: accountAddressRawValue,
            normalizedQuery: normalizedQuery,
            query: query,
            recordedAt: recordedAt
        )
    }
}

private struct NFTSnapshot {
    let id: String
    let contractAddress: String?
    let tokenId: String
    let tokenType: String?
    let name: String?
    let nftDescription: String?
    let collectionNameValue: String?
    let collectionContractAddress: String?
    let tokenUri: String?
    let timeLastUpdated: String?
    let acquiredAtBlockTimestamp: String?
    let network: Chain
    let accountAddress: String
    let contentType: String?
    let displayCollectionName: String?
    let artistName: String?
    let animationUrl: String?
    let secureAnimationUrl: String?
    let audioUrl: String?
    let attributes: [AttributeSnapshot]

    init(_ nft: NFT) {
        self.id = nft.id
        self.contractAddress = nft.contract.address
        self.tokenId = nft.tokenId
        self.tokenType = nft.tokenType
        self.name = nft.name
        self.nftDescription = nft.nftDescription
        self.collectionNameValue = nft.collection?.name
        self.collectionContractAddress = nft.collection?.contractAddress
        self.tokenUri = nft.tokenUri
        self.timeLastUpdated = nft.timeLastUpdated
        self.acquiredAtBlockTimestamp = nft.acquiredAt?.blockTimestamp
        self.network = nft.network ?? .ethMainnet
        self.accountAddress = nft.accountAddressRawValue
        self.contentType = nft.contentType
        self.displayCollectionName = nft.collectionName
        self.artistName = nft.artistName
        self.animationUrl = nft.animationUrl
        self.secureAnimationUrl = nft.secureAnimationUrl
        self.audioUrl = nft.audioUrl
        self.attributes = (nft.attributes ?? []).map(AttributeSnapshot.init)
    }

    func model() -> NFT {
        NFT(
            id: id,
            contract: NFT.Contract(address: contractAddress, chain: network),
            tokenId: tokenId,
            tokenType: tokenType,
            name: name,
            nftDescription: nftDescription,
            collection: NFT.Collection(
                name: collectionNameValue,
                chain: network,
                contractAddress: collectionContractAddress
            ),
            tokenUri: tokenUri,
            timeLastUpdated: timeLastUpdated,
            acquiredAt: NFT.AcquiredAt(blockTimestamp: acquiredAtBlockTimestamp),
            network: network,
            accountAddress: accountAddress,
            contentType: contentType,
            collectionName: displayCollectionName,
            artistName: artistName,
            animationUrl: animationUrl,
            secureAnimationUrl: secureAnimationUrl,
            audioUrl: audioUrl
        )
    }
}

private struct AttributeSnapshot {
    let value: String
    let traitType: String?

    init(_ attribute: NFT.Attribute) {
        self.value = attribute.value
        self.traitType = attribute.traitType
    }
}

private extension EOAccount {
    func normalizeStoredMetadataIfNeeded() -> Bool {
        let repairedChains = normalizeStoredChainsIfNeeded()
        let repairedName = normalizeStoredNameIfNeeded()
        return repairedChains || repairedName
    }
}

private extension ModelContext {
    func containsModel<T: PersistentModel>(_ modelType: T.Type) -> Bool {
        container.schema.entity(for: modelType) != nil
    }

    func accountRemovalUndoSnapshot(account: EOAccount, accountAddress: String) throws -> AccountRemovalUndoSnapshot {
        AccountRemovalUndoSnapshot(
            account: AccountSnapshot(account),
            tokenHoldings: try fetchTokenHoldings(accountAddress: accountAddress).map(TokenHoldingSnapshot.init),
            searchHistory: try fetchSearchHistory(accountAddress: accountAddress).map(SearchHistorySnapshot.init),
            nfts: try fetchNFTs(accountAddress: accountAddress).map(NFTSnapshot.init)
        )
    }

    func restoreAccountRemovalUndoSnapshot(_ snapshot: AccountRemovalUndoSnapshot) throws {
        insert(snapshot.account.model())

        for holding in snapshot.tokenHoldings where containsModel(TokenHolding.self) {
            insert(holding.model())
        }

        for record in snapshot.searchHistory where containsModel(SearchHistoryRecord.self) {
            insert(record.model())
        }

        for nft in snapshot.nfts where containsModel(NFT.self) {
            insert(nft.model())
        }

        try save()
    }

    func fetchTokenHoldings(accountAddress: String) throws -> [TokenHolding] {
        guard containsModel(TokenHolding.self) else {
            return []
        }

        let descriptor = FetchDescriptor<TokenHolding>(
            predicate: #Predicate<TokenHolding> { holding in
                holding.accountAddressRawValue == accountAddress
            }
        )
        return try fetch(descriptor)
    }

    func fetchSearchHistory(accountAddress: String) throws -> [SearchHistoryRecord] {
        guard containsModel(SearchHistoryRecord.self) else {
            return []
        }

        let descriptor = FetchDescriptor<SearchHistoryRecord>(
            predicate: #Predicate<SearchHistoryRecord> { record in
                record.accountAddressRawValue == accountAddress
            }
        )
        return try fetch(descriptor)
    }

    func fetchNFTs(accountAddress: String) throws -> [NFT] {
        guard containsModel(NFT.self) else {
            return []
        }

        let descriptor = FetchDescriptor<NFT>(
            predicate: #Predicate<NFT> { nft in
                nft.accountAddressRawValue == accountAddress
            }
        )
        return try fetch(descriptor)
    }

    func deleteAccountScopedSupportData(accountAddress: String) throws {
        if containsModel(TokenHolding.self) {
            try delete(
                model: TokenHolding.self,
                where: #Predicate<TokenHolding> { holding in
                    holding.accountAddressRawValue == accountAddress
                }
            )
        }
        if containsModel(MusicLibraryItem.self) {
            try delete(
                model: MusicLibraryItem.self,
                where: #Predicate<MusicLibraryItem> { item in
                    item.accountAddressRawValue == accountAddress
                }
            )
        }
        if containsModel(SearchHistoryRecord.self) {
            try delete(
                model: SearchHistoryRecord.self,
                where: #Predicate<SearchHistoryRecord> { record in
                    record.accountAddressRawValue == accountAddress
                }
            )
        }

        let accountDescriptor = FetchDescriptor<EOAccount>(
            predicate: #Predicate<EOAccount> { account in
                account.address == accountAddress
            }
        )
        if let account = try fetch(accountDescriptor).first {
            account.clearAllAuraPlaySyncState()
        }
    }

    func deleteNFTsScopedToAccount(_ accountAddress: String) throws {
        guard containsModel(NFT.self) else {
            return
        }

        for nft in try fetchNFTs(accountAddress: accountAddress) {
            delete(nft)
        }

        try pruneOrphanedNFTSharedModels()
    }

    func pruneOrphanedNFTSharedModels() throws {
        guard containsModel(NFT.self) else {
            return
        }

        let allNFTs = try fetch(FetchDescriptor<NFT>())
        let referencedContractIDs = Set(allNFTs.map(\.contract.id))
        let referencedCollectionIDs = Set(allNFTs.compactMap(\.collection?.id))

        if containsModel(NFT.Contract.self) {
            let persistedContracts = try fetch(FetchDescriptor<NFT.Contract>())
            for contract in persistedContracts where !referencedContractIDs.contains(contract.id) {
                delete(contract)
            }
        }

        if containsModel(NFT.Collection.self) {
            let persistedCollections = try fetch(FetchDescriptor<NFT.Collection>())
            for collection in persistedCollections where !referencedCollectionIDs.contains(collection.id) {
                delete(collection)
            }
        }
    }
}
