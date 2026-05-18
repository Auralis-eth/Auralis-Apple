import Foundation

enum LocalDataClassification: String, CaseIterable, Sendable {
    case publicPreference
    case walletMetadata
    case credential

    var storageRule: String {
        switch self {
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
    case userDefaults
    case keychain
    case swiftData
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
