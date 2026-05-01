import Foundation
import SwiftData

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
        try modelContext.save()
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

    func removeAccount(
        normalizedAddress: String,
        normalizedActiveAddress: String?
    ) throws -> RemovalSnapshot {
        guard let account = try account(for: normalizedAddress) else {
            throw AccountStoreError.accountNotFound(normalizedAddress)
        }

        let removedAddress = account.address
        try modelContext.deleteAccountScopedSupportData(accountAddress: removedAddress)
        try modelContext.deleteNFTsScopedToAccount(removedAddress)
        modelContext.delete(account)
        try modelContext.save()

        let fallbackAddress: String?
        if normalizedActiveAddress == removedAddress {
            fallbackAddress = try listAccounts().first?.address
        } else {
            fallbackAddress = nil
        }

        return RemovalSnapshot(
            removedAddress: removedAddress,
            fallbackAddress: fallbackAddress
        )
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

    private func listAccounts() throws -> [EOAccount] {
        try modelContext.fetch(FetchDescriptor(sortBy: accountSortDescriptors))
    }
}

/// Enumerates the account-store failures surfaced to wallet entry and selection flows.
enum AccountStoreError: LocalizedError, Equatable {
    case invalidAddress
    case duplicateAddress(String)
    case accountNotFound(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return NSLocalizedString(
                "account_store.error.invalid_address",
                value: "The wallet address is invalid.",
                comment: "Error shown when a wallet address fails validation"
            )
        case .duplicateAddress(let address):
            let format = NSLocalizedString(
                "account_store.error.duplicate_address",
                value: "An account for %@ already exists.",
                comment: "Error shown when attempting to create a duplicate account"
            )
            return String(format: format, address)
        case .accountNotFound(let address):
            let format = NSLocalizedString(
                "account_store.error.account_not_found",
                value: "No persisted account exists for %@.",
                comment: "Error shown when an account cannot be found in local storage"
            )
            return String(format: format, address)
        }
    }
}

/// Classifies pasted or scanned wallet input before account mutations run.
enum AccountAddressValidationResult: Equatable {
    case empty
    case valid(String)
    case unsupportedENS
    case invalidFormat

    var normalizedAddress: String? {
        guard case .valid(let address) = self else {
            return nil
        }

        return address
    }

    var userFacingMessage: String {
        switch self {
        case .empty:
            return "Please enter your Ethereum address or use a guest pass."
        case .valid:
            return ""
        case .unsupportedENS:
            return "ENS names are not supported in this entry flow yet. Paste the resolved wallet address instead."
        case .invalidFormat:
            return "Enter a valid EVM wallet address."
        }
    }
}

/// Describes the result of removing an account, including any fallback selection.
struct AccountRemovalResult {
    let removedAddress: String
    let fallbackAccount: EOAccount?
}

/// Describes the result of activating an account, including whether it was newly created.
struct AccountActivationResult {
    let account: EOAccount
    let wasCreated: Bool
}

@MainActor
/// Coordinates wallet validation, persistence, selection, and account-level receipt logging.
struct AccountStore {
    private let modelContext: ModelContext
    private let eventRecorder: any AccountEventRecorder
    private let persistenceStore: AccountPersistenceStore

    /// Creates an account store that performs mutations without recording account events.
    init(modelContext: ModelContext) {
        self.init(
            modelContext: modelContext,
            eventRecorder: NoOpAccountEventRecorder()
        )
    }

    /// Creates an account store backed by SwiftData and an explicit account event recorder.
    init(
        modelContext: ModelContext,
        eventRecorder: any AccountEventRecorder
    ) {
        self.modelContext = modelContext
        self.eventRecorder = eventRecorder
        self.persistenceStore = AccountPersistenceStore(modelContainer: modelContext.container)
    }

    /// Normalizes supported wallet-address input into the canonical stored representation.
    static func normalizeAddress(_ rawAddress: String) -> String? {
        validateAddressInput(rawAddress).normalizedAddress
    }

    /// Validates wallet entry input and reports whether it can be used for account mutations.
    static func validateAddressInput(_ rawAddress: String) -> AccountAddressValidationResult {
        let trimmed = rawAddress.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return .empty
        }

        if looksLikeENSName(trimmed) {
            return .unsupportedENS
        }

        guard let normalizedAddress = strictEthereumAddress(from: trimmed) else {
            return .invalidFormat
        }

        return .valid(normalizedAddress)
    }

    /// Returns whether the supplied input resembles an ENS name instead of a raw wallet address.
    static func looksLikeENSName(_ candidate: String) -> Bool {
        candidate.trimmingCharacters(in: .whitespacesAndNewlines).range(
            of: #"^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.eth$"#,
            options: .regularExpression
        ) != nil
    }

    func listAccounts() throws -> [EOAccount] {
        let accounts = try modelContext.fetch(
            FetchDescriptor(sortBy: accountSortDescriptors)
        )
        if accounts.contains(where: { $0.normalizeStoredChainsIfNeeded() }) {
            try modelContext.save()
        }

        return accounts
    }

    func account(for rawAddress: String) throws -> EOAccount? {
        guard let normalizedAddress = AccountStore.normalizeAddress(rawAddress) else {
            return nil
        }

        let descriptor = FetchDescriptor<EOAccount>(
            predicate: #Predicate<EOAccount> { account in
                account.address == normalizedAddress
            }
        )

        let account = try modelContext.fetch(descriptor).first
        if let account, account.normalizeStoredChainsIfNeeded() {
            try modelContext.save()
        }

        return account
    }

    func createWatchAccount(
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

    func activateWatchAccount(
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

    func selectAccount(
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

    func removeAccount(
        address rawAddress: String,
        activeAddress: String? = nil,
        correlationID: String? = nil
    ) async throws -> AccountRemovalResult {
        guard let normalizedAddress = AccountStore.normalizeAddress(rawAddress) else {
            throw AccountStoreError.accountNotFound(rawAddress)
        }

        let removalSnapshot = try await persistenceStore.removeAccount(
            normalizedAddress: normalizedAddress,
            normalizedActiveAddress: activeAddress.flatMap(AccountStore.normalizeAddress)
        )
        await eventRecorder.record(.removed(address: removalSnapshot.removedAddress), correlationID: correlationID)

        return AccountRemovalResult(
            removedAddress: removalSnapshot.removedAddress,
            fallbackAccount: try removalSnapshot.fallbackAddress.flatMap { try account(for: $0) }
        )
    }

    func persistCurrentChain(
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

    func persistPreferredChain(
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

private extension AccountStore {
    static func strictEthereumAddress(from candidate: String) -> String? {
        let lowered = candidate.lowercased()

        if lowered.range(of: #"^0x[a-f0-9]{40}$"#, options: .regularExpression) != nil {
            return lowered
        }

        if lowered.range(of: #"^[a-f0-9]{40}$"#, options: .regularExpression) != nil {
            return "0x" + lowered
        }

        return nil
    }
}
