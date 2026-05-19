import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation

/// Enumerates the account-store failures surfaced to wallet entry and selection flows.
public enum AccountStoreError: LocalizedError, Equatable {
    case invalidAddress
    case duplicateAddress(String)
    case accountNotFound(String)

    public var errorDescription: String? {
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
public enum AccountAddressValidationResult: Equatable {
    case empty
    case valid(String)
    case unsupportedENS
    case invalidFormat

    public var normalizedAddress: String? {
        guard case .valid(let address) = self else {
            return nil
        }

        return address
    }

    public var userFacingMessage: String {
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
public struct AccountRemovalResult {
    public let removedAddress: String
    public let fallbackAccount: EOAccount?

    public init(
        removedAddress: String,
        fallbackAccount: EOAccount?
    ) {
        self.removedAddress = removedAddress
        self.fallbackAccount = fallbackAccount
    }
}

/// Describes the result of activating an account, including whether it was newly created.
public struct AccountActivationResult {
    public let account: EOAccount
    public let wasCreated: Bool

    public init(
        account: EOAccount,
        wasCreated: Bool
    ) {
        self.account = account
        self.wasCreated = wasCreated
    }
}

/// Contract for account persistence and selection behavior.
@MainActor
public protocol AccountStoring {
    func listAccounts() throws -> [EOAccount]
    func account(for rawAddress: String) throws -> EOAccount?

    func createWatchAccount(
        from rawAddress: String,
        name: String?,
        source: EOAccountSource,
        overwriteExisting: Bool,
        now: Date,
        correlationID: String?
    ) async throws -> EOAccount

    func activateWatchAccount(
        from rawAddress: String,
        name: String?,
        source: EOAccountSource,
        selectedAt: Date,
        correlationID: String?
    ) async throws -> AccountActivationResult

    func selectAccount(
        address rawAddress: String,
        selectedAt: Date,
        correlationID: String?
    ) async throws -> EOAccount

    func removeAccount(
        address rawAddress: String,
        activeAddress: String?,
        correlationID: String?
    ) async throws -> AccountRemovalResult

    func persistCurrentChain(
        address rawAddress: String,
        chain: Chain,
        correlationID: String?
    ) async throws -> EOAccount

    func persistPreferredChain(
        address rawAddress: String,
        chain: Chain,
        correlationID: String?
    ) async throws -> EOAccount
}

public extension AccountStoring {
    func activateWatchAccount(
        from rawAddress: String,
        source: EOAccountSource = .manualEntry,
        correlationID: String? = nil
    ) async throws -> AccountActivationResult {
        try await activateWatchAccount(
            from: rawAddress,
            name: nil,
            source: source,
            selectedAt: .now,
            correlationID: correlationID
        )
    }

    func activateWatchAccount(
        from rawAddress: String,
        name: String?,
        source: EOAccountSource = .manualEntry,
        correlationID: String? = nil
    ) async throws -> AccountActivationResult {
        try await activateWatchAccount(
            from: rawAddress,
            name: name,
            source: source,
            selectedAt: .now,
            correlationID: correlationID
        )
    }
}

/// Pure account input utilities retained in AccountsCore so UI validation does not depend on storage.
public enum AccountStore {
    /// Normalizes supported wallet-address input into the canonical stored representation.
    public static func normalizeAddress(_ rawAddress: String) -> String? {
        validateAddressInput(rawAddress).normalizedAddress
    }

    /// Validates wallet entry input and reports whether it can be used for account mutations.
    public static func validateAddressInput(_ rawAddress: String) -> AccountAddressValidationResult {
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
    public static func looksLikeENSName(_ candidate: String) -> Bool {
        candidate.trimmingCharacters(in: .whitespacesAndNewlines).range(
            of: #"^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.eth$"#,
            options: .regularExpression
        ) != nil
    }

    private static func strictEthereumAddress(from candidate: String) -> String? {
        AuralisEthereumAddress.normalized(candidate)
    }
}
