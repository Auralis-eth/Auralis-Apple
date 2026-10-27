import Foundation
import AuralisReceipts
import SwiftData
import AuralisFoundation

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
    private let scopedPersistenceParticipants: [AccountScopedPersistenceParticipant]
    private let participantDidDelete: ((String) throws -> Void)?

    /// Creates an account store that performs mutations without recording account events.
    public init(
        modelContext: ModelContext,
        scopedPersistenceParticipants: [AccountScopedPersistenceParticipant] = []
    ) {
        self.init(
            modelContext: modelContext,
            eventRecorder: NoOpAccountEventRecorder(),
            scopedPersistenceParticipants: scopedPersistenceParticipants
        )
    }

    /// Creates an account store backed by SwiftData and an explicit account event recorder.
    public init(
        modelContext: ModelContext,
        eventRecorder: any AccountEventRecorder,
        scopedPersistenceParticipants: [AccountScopedPersistenceParticipant] = []
    ) {
        self.init(
            modelContext: modelContext,
            eventRecorder: eventRecorder,
            scopedPersistenceParticipants: scopedPersistenceParticipants,
            participantDidDelete: nil
        )
    }

    /// Internal fault-injection seam used to prove that domain participant failures roll back the
    /// complete account mutation. Production composition always uses the public initializers.
    init(
        modelContext: ModelContext,
        eventRecorder: any AccountEventRecorder,
        scopedPersistenceParticipants: [AccountScopedPersistenceParticipant] = [],
        participantDidDelete: ((String) throws -> Void)?
    ) {
        self.modelContext = modelContext
        self.eventRecorder = eventRecorder
        self.persistenceStore = AccountPersistenceStore(modelContainer: modelContext.container)
        self.scopedPersistenceParticipants = scopedPersistenceParticipants
        self.participantDidDelete = participantDidDelete
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

        try createWatchAccountInMainContext(
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
    func createWatchAccountInMainContext(
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

                try modelContext.deleteAccountScopedData(
                    accountAddress: normalizedAddress,
                    scopedPersistenceParticipants: scopedPersistenceParticipants,
                    participantDidDelete: participantDidDelete
                )
                modelContext.delete(existingAccount)
            }

            modelContext.insert(
                EOAccount(
                    address: normalizedAddress,
                    access: .readonly,
                    name: name,
                    source: source,
                    addedAt: now,
                    lastSelectedAt: nil,
                    trackedNFTCount: 0
                )
            )
        }
    }

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
                accountAddress: removedAddress,
                scopedPersistenceParticipants: scopedPersistenceParticipants
            )

            undoManager.disableUndoRegistration()
            do {
                try modelContext.performRollbackSafeMutation {
                    try modelContext.deleteAccountScopedData(
                        accountAddress: removedAddress,
                        scopedPersistenceParticipants: scopedPersistenceParticipants,
                        participantDidDelete: participantDidDelete
                    )
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
                try modelContext.deleteAccountScopedData(
                    accountAddress: removedAddress,
                    scopedPersistenceParticipants: scopedPersistenceParticipants,
                    participantDidDelete: participantDidDelete
                )
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
    let tokenHoldings: [TokenHoldingAccountSnapshot]
    let scopedPersistenceSnapshots: [AccountScopedPersistenceSnapshot]
    let nfts: [NFTAccountSnapshot]
}

private struct AccountScopedPersistenceSnapshot {
    let participant: AccountScopedPersistenceParticipant
    let value: Any
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

private extension EOAccount {
    func normalizeStoredMetadataIfNeeded() -> Bool {
        let repairedChains = normalizeStoredChainsIfNeeded()
        let repairedName = normalizeStoredNameIfNeeded()
        return repairedChains || repairedName
    }
}

private extension ModelContext {
    func accountRemovalUndoSnapshot(
        account: EOAccount,
        accountAddress: String,
        scopedPersistenceParticipants: [AccountScopedPersistenceParticipant]
    ) throws -> AccountRemovalUndoSnapshot {
        AccountRemovalUndoSnapshot(
            account: AccountSnapshot(account),
            tokenHoldings: try TokenHoldingAccountPersistenceParticipant.capture(scope: accountAddress, in: self),
            scopedPersistenceSnapshots: try scopedPersistenceParticipants.map { participant in
                AccountScopedPersistenceSnapshot(
                    participant: participant,
                    value: try participant.capture(scope: accountAddress, in: self)
                )
            },
            nfts: try NFTAccountPersistenceParticipant.capture(scope: accountAddress, in: self)
        )
    }

    func restoreAccountRemovalUndoSnapshot(_ snapshot: AccountRemovalUndoSnapshot) throws {
        insert(snapshot.account.model())

        try TokenHoldingAccountPersistenceParticipant.restore(snapshot.tokenHoldings, in: self)
        for scopedSnapshot in snapshot.scopedPersistenceSnapshots {
            try scopedSnapshot.participant.restore(scopedSnapshot.value, in: self)
        }
        try NFTAccountPersistenceParticipant.restore(snapshot.nfts, in: self)

        try save()
    }

    func deleteAccountScopedData(
        accountAddress: String,
        scopedPersistenceParticipants: [AccountScopedPersistenceParticipant],
        participantDidDelete: ((String) throws -> Void)? = nil
    ) throws {
        try TokenHoldingAccountPersistenceParticipant.delete(scope: accountAddress, in: self)
        try participantDidDelete?("token")
        for participant in scopedPersistenceParticipants {
            try participant.delete(scope: accountAddress, in: self)
            try participantDidDelete?(participant.identifier)
        }
        try NFTAccountPersistenceParticipant.delete(scope: accountAddress, in: self)
        try participantDidDelete?("nft")
    }
}
