import Foundation
import SwiftData

enum AccountStoreError: LocalizedError, Equatable {
    case invalidAddress
    case duplicateAddress(String)
    case accountNotFound(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return "The wallet address is invalid."
        case .duplicateAddress(let address):
            return "An account for \(address) already exists."
        case .accountNotFound(let address):
            return "No persisted account exists for \(address)."
        }
    }
}

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

struct AccountRemovalResult {
    let removedAddress: String
    let fallbackAccount: EOAccount?
}

struct AccountActivationResult {
    let account: EOAccount
    let wasCreated: Bool
}

@MainActor
struct AccountStore {
    private let modelContext: ModelContext
    private let eventRecorder: any AccountEventRecorder

    init(modelContext: ModelContext) {
        self.init(
            modelContext: modelContext,
            eventRecorder: NoOpAccountEventRecorder()
        )
    }

    init(
        modelContext: ModelContext,
        eventRecorder: any AccountEventRecorder
    ) {
        self.modelContext = modelContext
        self.eventRecorder = eventRecorder
    }

    static func normalizeAddress(_ rawAddress: String) -> String? {
        validateAddressInput(rawAddress).normalizedAddress
    }

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

    static func looksLikeENSName(_ candidate: String) -> Bool {
        candidate.trimmingCharacters(in: .whitespacesAndNewlines).range(
            of: #"^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.eth$"#,
            options: .regularExpression
        ) != nil
    }

    func listAccounts() throws -> [EOAccount] {
        let accounts = try modelContext.fetch(FetchDescriptor<EOAccount>())

        return accounts.sorted { lhs, rhs in
            if lhs.mostRecentActivityAt != rhs.mostRecentActivityAt {
                return lhs.mostRecentActivityAt > rhs.mostRecentActivityAt
            }

            if lhs.addedAt != rhs.addedAt {
                return lhs.addedAt > rhs.addedAt
            }

            return lhs.address.localizedCompare(rhs.address) == .orderedAscending
        }
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

        return try modelContext.fetch(descriptor).first
    }

    func createWatchAccount(
        from rawAddress: String,
        name: String? = nil,
        source: EOAccountSource = .manualEntry,
        overwriteExisting: Bool = false,
        now: Date = .now,
        correlationID: String? = nil
    ) throws -> EOAccount {
        guard let normalizedAddress = AccountStore.normalizeAddress(rawAddress) else {
            throw AccountStoreError.invalidAddress
        }

        if let existingAccount = try account(for: normalizedAddress) {
            guard overwriteExisting else {
                throw AccountStoreError.duplicateAddress(normalizedAddress)
            }

            modelContext.delete(existingAccount)
            eventRecorder.record(.removed(address: normalizedAddress), correlationID: correlationID)
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
        eventRecorder.record(.added(address: normalizedAddress), correlationID: correlationID)
        return account
    }

    func activateWatchAccount(
        from rawAddress: String,
        name: String? = nil,
        source: EOAccountSource = .manualEntry,
        selectedAt: Date = .now,
        correlationID: String? = nil
    ) throws -> AccountActivationResult {
        do {
            let createdAccount = try createWatchAccount(
                from: rawAddress,
                name: name,
                source: source,
                now: selectedAt,
                correlationID: correlationID
            )
            let selectedAccount = try selectAccount(
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

            let selectedAccount = try selectAccount(
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
    ) throws -> EOAccount {
        guard let account = try account(for: rawAddress) else {
            let normalizedAddress = AccountStore.normalizeAddress(rawAddress) ?? rawAddress
            throw AccountStoreError.accountNotFound(normalizedAddress)
        }

        account.lastSelectedAt = selectedAt
        try modelContext.save()
        eventRecorder.record(.selected(address: account.address), correlationID: correlationID)
        return account
    }

    func removeAccount(
        address rawAddress: String,
        activeAddress: String? = nil,
        correlationID: String? = nil
    ) throws -> AccountRemovalResult {
        guard let account = try account(for: rawAddress) else {
            let normalizedAddress = AccountStore.normalizeAddress(rawAddress) ?? rawAddress
            throw AccountStoreError.accountNotFound(normalizedAddress)
        }

        let removedAddress = account.address
        let normalizedActiveAddress = activeAddress.flatMap(AccountStore.normalizeAddress)

        modelContext.delete(account)
        try modelContext.save()
        eventRecorder.record(.removed(address: removedAddress), correlationID: correlationID)

        let fallbackAccount: EOAccount?
        if normalizedActiveAddress == removedAddress {
            fallbackAccount = try listAccounts().first
        } else {
            fallbackAccount = nil
        }

        return AccountRemovalResult(
            removedAddress: removedAddress,
            fallbackAccount: fallbackAccount
        )
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
