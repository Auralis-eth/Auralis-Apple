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

        try modelContext.performUndoableMutation(named: "Remove Account") {
            try modelContext.deleteAccountScopedSupportData(accountAddress: removedAddress)
            try modelContext.deleteNFTsScopedToAccount(removedAddress)
            modelContext.delete(account)
        }

        return AccountPersistenceStore.RemovalSnapshot(
            removedAddress: removedAddress,
            fallbackAddress: fallbackAddress
        )
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
    func deleteAccountScopedSupportData(accountAddress: String) throws {
        try delete(
            model: TokenHolding.self,
            where: #Predicate<TokenHolding> { holding in
                holding.accountAddressRawValue == accountAddress
            }
        )
        try delete(
            model: MusicLibraryItem.self,
            where: #Predicate<MusicLibraryItem> { item in
                item.accountAddressRawValue == accountAddress
            }
        )
        try delete(
            model: SearchHistoryRecord.self,
            where: #Predicate<SearchHistoryRecord> { record in
                record.accountAddressRawValue == accountAddress
            }
        )

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
        let descriptor = FetchDescriptor<NFT>(
            predicate: #Predicate<NFT> { nft in
                nft.accountAddressRawValue == accountAddress
            }
        )

        for nft in try fetch(descriptor) {
            delete(nft)
        }

        try pruneOrphanedNFTSharedModels()
    }

    func pruneOrphanedNFTSharedModels() throws {
        let allNFTs = try fetch(FetchDescriptor<NFT>())
        let referencedContractIDs = Set(allNFTs.map(\.contract.id))
        let referencedCollectionIDs = Set(allNFTs.compactMap(\.collection?.id))

        let persistedContracts = try fetch(FetchDescriptor<NFT.Contract>())
        for contract in persistedContracts where !referencedContractIDs.contains(contract.id) {
            delete(contract)
        }

        let persistedCollections = try fetch(FetchDescriptor<NFT.Collection>())
        for collection in persistedCollections where !referencedCollectionIDs.contains(collection.id) {
            delete(collection)
        }
    }
}
