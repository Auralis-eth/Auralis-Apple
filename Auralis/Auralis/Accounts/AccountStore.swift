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

struct AccountRemovalResult {
    let removedAddress: String
    let fallbackAccount: EOAccount?
}

@MainActor
struct AccountStore {
    private let modelContext: ModelContext
    private let eventRecorder: any AccountEventRecorder

    init(
        modelContext: ModelContext,
        eventRecorder: any AccountEventRecorder = NoOpAccountEventRecorder()
    ) {
        self.modelContext = modelContext
        self.eventRecorder = eventRecorder
    }

    func normalizeAddress(_ rawAddress: String) -> String? {
        let trimmed = rawAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if let extractedAddress = trimmed.extractedEthereumAddress {
            return extractedAddress.lowercased()
        }

        if let match = trimmed.range(of: #"0x[a-f0-9]{40}"#, options: .regularExpression) {
            return String(trimmed[match])
        }

        return nil
    }

    func listAccounts() throws -> [EOAccount] {
        let descriptor = FetchDescriptor<EOAccount>()
        let accounts = try modelContext.fetch(descriptor)

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
        guard let normalizedAddress = normalizeAddress(rawAddress) else {
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
        now: Date = .now
    ) throws -> EOAccount {
        guard let normalizedAddress = normalizeAddress(rawAddress) else {
            throw AccountStoreError.invalidAddress
        }

        if let existingAccount = try account(for: normalizedAddress) {
            guard overwriteExisting else {
                throw AccountStoreError.duplicateAddress(normalizedAddress)
            }

            modelContext.delete(existingAccount)
            eventRecorder.record(.removed(address: normalizedAddress))
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
        eventRecorder.record(.added(address: normalizedAddress))
        return account
    }

    func selectAccount(address rawAddress: String, selectedAt: Date = .now) throws -> EOAccount {
        guard let account = try account(for: rawAddress) else {
            let normalizedAddress = normalizeAddress(rawAddress) ?? rawAddress
            throw AccountStoreError.accountNotFound(normalizedAddress)
        }

        account.lastSelectedAt = selectedAt
        try modelContext.save()
        eventRecorder.record(.selected(address: account.address))
        return account
    }

    func removeAccount(address rawAddress: String, activeAddress: String? = nil) throws -> AccountRemovalResult {
        guard let account = try account(for: rawAddress) else {
            let normalizedAddress = normalizeAddress(rawAddress) ?? rawAddress
            throw AccountStoreError.accountNotFound(normalizedAddress)
        }

        let removedAddress = account.address
        let normalizedActiveAddress = activeAddress.flatMap(normalizeAddress)

        modelContext.delete(account)
        try modelContext.save()
        eventRecorder.record(.removed(address: removedAddress))

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
