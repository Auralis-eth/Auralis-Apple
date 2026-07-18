import ENS
import AuralisPrimaryPersistence
import Foundation
import MusicFeature
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
    static let persistedSwiftDataModelIdentifiers: Set<String> = Set(
        PrimaryStoreSchema.models.map { String(describing: $0) }
    ).union(
        AuraPlaySchema.models.map { String(describing: $0) }
    ).union([
        String(describing: NFT.Contract.self),
        String(describing: NFT.Image.self),
        String(describing: NFT.Raw.self),
        String(describing: NFT.NFTMetadata.self),
        String(describing: NFT.Attribute.self),
        String(describing: NFT.Collection.self),
        String(describing: NFT.AcquiredAt.self),
    ])

    static let requiredKnownIdentifiers: Set<String> = Set([
        ModeState.storageDecisionIdentifier,
        HomePinnedItemsStore.storageDecisionIdentifier,
        ENSResolutionCacheStore.storageDecisionIdentifier,
        KeychainReceiptIntegrityHeadStore.storageDecisionIdentifier,
        GasPriceCache.storageDecisionIdentifier,
        "AURALIS_ALCHEMY_API_KEY",
        "auralis.shell.selection.v1",
        "WalletPasswordService/WalletPasswordAccount",
        "view navigation and transient UI state"
    ]).union(persistedSwiftDataModelIdentifiers)

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
            identifier: "NFT",
            classification: .publicIdentifierMetadata,
            storage: .swiftData,
            resetPhase: .transactionalStore,
            rationale: "NFT inventory is composed of public token, contract, collection, media, and wallet-scope identifiers. It is still cleared with transactional wallet data because retaining a local inventory ties this install to a watched wallet."
        ),
        LocalDataStorageDecision(
            identifier: String(describing: NFT.Contract.self),
            classification: .publicIdentifierMetadata,
            storage: .swiftData,
            resetPhase: .transactionalStore,
            rationale: "NFT contract rows store public contract identifiers shared by locally persisted NFTs and are pruned when NFT inventory is reset."
        ),
        LocalDataStorageDecision(
            identifier: String(describing: NFT.Image.self),
            classification: .publicIdentifierMetadata,
            storage: .swiftData,
            resetPhase: .transactionalStore,
            rationale: "NFT image rows store public media URLs associated with local NFT inventory and cascade with the owning NFT rows."
        ),
        LocalDataStorageDecision(
            identifier: String(describing: NFT.Raw.self),
            classification: .publicIdentifierMetadata,
            storage: .swiftData,
            resetPhase: .transactionalStore,
            rationale: "Raw NFT metadata is public provider metadata cached for local inventory and cascades with the owning NFT rows."
        ),
        LocalDataStorageDecision(
            identifier: String(describing: NFT.NFTMetadata.self),
            classification: .publicIdentifierMetadata,
            storage: .swiftData,
            resetPhase: .transactionalStore,
            rationale: "Decoded NFT metadata is public token metadata and belongs to the local NFT inventory reset boundary."
        ),
        LocalDataStorageDecision(
            identifier: String(describing: NFT.Attribute.self),
            classification: .publicIdentifierMetadata,
            storage: .swiftData,
            resetPhase: .transactionalStore,
            rationale: "NFT attributes are public token traits stored only to support local inventory browsing and cascade with the owning NFT rows."
        ),
        LocalDataStorageDecision(
            identifier: String(describing: NFT.Collection.self),
            classification: .publicIdentifierMetadata,
            storage: .swiftData,
            resetPhase: .transactionalStore,
            rationale: "NFT collection rows store public collection identifiers shared by local inventory and are pruned when NFT inventory is reset."
        ),
        LocalDataStorageDecision(
            identifier: String(describing: NFT.AcquiredAt.self),
            classification: .publicIdentifierMetadata,
            storage: .swiftData,
            resetPhase: .transactionalStore,
            rationale: "NFT acquisition timestamps are public chain metadata cached with local inventory and cascade with the owning NFT rows."
        ),
        LocalDataStorageDecision(
            identifier: "Tag",
            classification: .walletMetadata,
            storage: .swiftData,
            resetPhase: .transactionalStore,
            rationale: "Tags are user-authored organization metadata that can reveal local wallet curation choices, so privacy reset clears them with transactional wallet data."
        ),
        LocalDataStorageDecision(
            identifier: "StoredReceipt",
            classification: .walletMetadata,
            storage: .swiftData,
            resetPhase: .transactionalStore,
            rationale: "Receipts are local audit events that can include wallet scope, route context, and action summaries. Privacy reset clears them with their Keychain integrity heads."
        ),
        LocalDataStorageDecision(
            identifier: "Playlist",
            classification: .walletMetadata,
            storage: .swiftData,
            resetPhase: .transactionalStore,
            rationale: "Playlists are user-authored local music organization records that may reveal wallet-scoped NFT listening intent and are cleared during transactional reset."
        ),
        LocalDataStorageDecision(
            identifier: "MusicLibraryItem",
            classification: .walletMetadata,
            storage: .swiftData,
            resetPhase: .transactionalStore,
            rationale: "The music library index is derived from wallet-scoped NFT inventory and is cleared with transactional wallet data."
        ),
        LocalDataStorageDecision(
            identifier: "TokenHolding",
            classification: .walletMetadata,
            storage: .swiftData,
            resetPhase: .transactionalStore,
            rationale: "Token holdings are public chain facts but locally retaining balances ties this install to a watched wallet, so they are cleared with transactional wallet data."
        ),
        LocalDataStorageDecision(
            identifier: "AuraPlayMediaItem",
            classification: .walletMetadata,
            storage: .swiftData,
            resetPhase: .auraPlayPersistence,
            rationale: "AuraPlay media items are a separate SwiftData store derived from wallet-scoped NFT media and are cleared in the AuraPlay persistence reset phase."
        ),
        LocalDataStorageDecision(
            identifier: "AuraPlayMediaEmbedding",
            classification: .walletMetadata,
            storage: .swiftData,
            resetPhase: .auraPlayPersistence,
            rationale: "AuraPlay media embeddings are derived from wallet-scoped media metadata and support local search and ranking, so they clear with the AuraPlay persistence store."
        ),
        LocalDataStorageDecision(
            identifier: "AuraPlayNFTToken",
            classification: .walletMetadata,
            storage: .swiftData,
            resetPhase: .auraPlayPersistence,
            rationale: "AuraPlay NFT token rows mirror public token ownership into a wallet-scoped media store, so reset removes the local ownership index with AuraPlay data."
        ),
        LocalDataStorageDecision(
            identifier: "AuraPlayPlaylist",
            classification: .walletMetadata,
            storage: .swiftData,
            resetPhase: .auraPlayPersistence,
            rationale: "AuraPlay playlists are user-authored listening organization data tied to wallet-scoped media and belong to the AuraPlay reset boundary."
        ),
        LocalDataStorageDecision(
            identifier: "AuraPlayPlaylistItem",
            classification: .walletMetadata,
            storage: .swiftData,
            resetPhase: .auraPlayPersistence,
            rationale: "AuraPlay playlist items reveal local listening curation over wallet-scoped media and are cleared with their owning AuraPlay playlists."
        ),
        LocalDataStorageDecision(
            identifier: "AuraPlayPlaybackPositionState",
            classification: .walletMetadata,
            storage: .swiftData,
            resetPhase: .auraPlayPersistence,
            rationale: "AuraPlay playback positions are wallet-scoped listening state tied to local media rows and are cleared with the AuraPlay persistence store."
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
            rationale: "The active wallet address and chain selection identify a wallet context and must not be mirrored through UserDefaults. The Keychain item uses kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly so shell restoration and background-safe refresh coordination can read the active scope after first unlock, while the ThisDeviceOnly class prevents backup or device-transfer migration. Privacy reset clears it during the local preferences phase."
        ),
        LocalDataStorageDecision(
            identifier: "EOAccount",
            classification: .walletMetadata,
            storage: .swiftData,
            resetPhase: .transactionalStore,
            rationale: "Persisted watch accounts are local wallet metadata. Privacy reset preserves the account rows but clears derived transactional fields such as tracked NFT counts and AuraPlay sync state."
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
