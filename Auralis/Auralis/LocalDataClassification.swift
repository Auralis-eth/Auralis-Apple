import ENS
import Foundation
import ProviderKit
import ReceiptStorage

enum LocalDataClassification: String, CaseIterable, Sendable {
    case publicIdentifierMetadata
    case publicPreference
    case walletMetadata
    case credential

    var storageRule: String {
        switch self {
        case .publicIdentifierMetadata:
            return "UserDefaults or memory caches are allowed for public identifiers only when retention and reset behavior are explicit."
        case .publicPreference:
            return "UserDefaults is allowed for non-sensitive UI preferences that are safe to reset."
        case .walletMetadata:
            return "Use protected local storage for wallet identity, active selection, and wallet-scoped cache ownership."
        case .credential:
            return "Use Keychain only. Never mirror credentials into UserDefaults, SwiftData, logs, or receipts."
        }
    }
}

enum LocalDataStorage: String, Sendable {
    case bundleConfiguration
    case userDefaults
    case keychain
    case swiftData
    case memoryCache
    case viewState
}

struct LocalDataStorageDecision: Equatable, Sendable {
    let identifier: String
    let classification: LocalDataClassification
    let storage: LocalDataStorage
    let resetPhase: PrivacyResetPhase?
    let rationale: String
}

enum LocalDataStoragePolicy {
    static let requiredKnownIdentifiers: Set<String> = [
        ModeState.storageDecisionIdentifier,
        HomePinnedItemsStore.storageDecisionIdentifier,
        ENSResolutionCacheStore.storageDecisionIdentifier,
        KeychainReceiptIntegrityHeadStore.storageDecisionIdentifier,
        "SearchHistoryRecord",
        GasPriceCache.storageDecisionIdentifier,
        "AURALIS_ALCHEMY_API_KEY",
        "auralis.shell.selection.v1",
        "EOAccount",
        "WalletPasswordService/WalletPasswordAccount",
        "view navigation and transient UI state"
    ]

    static let decisions: [LocalDataStorageDecision] = [
        LocalDataStorageDecision(
            identifier: "app.mode",
            classification: .publicPreference,
            storage: .userDefaults,
            resetPhase: .localPreferences,
            rationale: "Observe mode is a non-sensitive UI capability preference and is normalized to the safe default on launch."
        ),
        LocalDataStorageDecision(
            identifier: "auralis.home.pinned-items.v1",
            classification: .publicPreference,
            storage: .userDefaults,
            resetPhase: .localPreferences,
            rationale: "Pinned launcher actions are account-scoped UI preferences, not credentials or capability grants."
        ),
        LocalDataStorageDecision(
            identifier: ENSResolutionCacheStore.storageDecisionIdentifier,
            classification: .publicIdentifierMetadata,
            storage: .userDefaults,
            resetPhase: .supportCaches,
            rationale: "ENS names and Ethereum address mappings are public identifiers. UserDefaults is acceptable for the short-lived cache because privacy reset clears the cache and expired entries self-prune."
        ),
        LocalDataStorageDecision(
            identifier: KeychainReceiptIntegrityHeadStore.storageDecisionIdentifier,
            classification: .walletMetadata,
            storage: .keychain,
            resetPhase: .transactionalStore,
            rationale: "Receipt integrity heads bind public receipt chain hashes to wallet account keys, so they are wallet metadata cleared with receipt data."
        ),
        LocalDataStorageDecision(
            identifier: "SearchHistoryRecord",
            classification: .walletMetadata,
            storage: .swiftData,
            resetPhase: .transactionalStore,
            rationale: "Search history can reveal wallet-scoped user intent even when terms include public identifiers, so it is reset with transactional wallet data."
        ),
        LocalDataStorageDecision(
            identifier: GasPriceCache.storageDecisionIdentifier,
            classification: .publicIdentifierMetadata,
            storage: .memoryCache,
            resetPhase: .supportCaches,
            rationale: "Gas estimates are public chain data and live only in memory, but privacy reset still flushes the support cache."
        ),
        LocalDataStorageDecision(
            identifier: "AURALIS_ALCHEMY_API_KEY",
            classification: .publicPreference,
            storage: .bundleConfiguration,
            resetPhase: nil,
            rationale: "The Alchemy value is a bundled public provider client key populated at build time, not user-local mutable data and not cleared by privacy reset."
        ),
        LocalDataStorageDecision(
            identifier: "auralis.shell.selection.v1",
            classification: .walletMetadata,
            storage: .keychain,
            resetPhase: .localPreferences,
            rationale: "The active wallet address and chain selection identify a wallet context and must not be mirrored through UserDefaults."
        ),
        LocalDataStorageDecision(
            identifier: "EOAccount",
            classification: .walletMetadata,
            storage: .swiftData,
            resetPhase: .transactionalStore,
            rationale: "Persisted watch accounts are local wallet metadata. They are read-only records and never contain signing credentials."
        ),
        LocalDataStorageDecision(
            identifier: "WalletPasswordService/WalletPasswordAccount",
            classification: .credential,
            storage: .keychain,
            resetPhase: .credentialStore,
            rationale: "Wallet passwords are credentials and are cleared in the credential reset phase."
        ),
        LocalDataStorageDecision(
            identifier: "view navigation and transient UI state",
            classification: .publicPreference,
            storage: .viewState,
            resetPhase: nil,
            rationale: "Transient navigation and presentation state is not persisted across launches."
        )
    ]

    static func decision(for identifier: String) -> LocalDataStorageDecision? {
        decisions.first { $0.identifier == identifier }
    }
}
