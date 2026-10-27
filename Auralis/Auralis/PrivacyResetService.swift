import AccountsCore
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import AuralisShellCore
import ENS
import Foundation
import MusicFeature
import ProviderKit
import AuralisReceipts
import RuntimeKit
import SwiftData
import TokenStorage

protocol TransactionalPrivacyResetting: Sendable {
    func resetTransactionalPrivacyData() async throws
}

/// The receipt ledger's half of the transactional reset, kept separate from
/// ``TransactionalPrivacyResetting`` for one reason: it has to run through the ledger's own lock, and
/// that lock lives on a `@MainActor`-resolved actor the `@ModelActor` reset service cannot reach.
protocol ReceiptLedgerPrivacyResetting: Sendable {
    func resetReceiptLedger() async throws
}

/// Resets receipts by asking the ledger to reset itself (F-46).
///
/// The provider closure, rather than a stored `any ReceiptStore`, for the same reason
/// ``RuntimeHostHistoryResetService`` takes one: `ReceiptStores` is `@MainActor` and memoized per
/// `ModelContainer`, so the store must be resolved on the main actor at call time — and resolving it
/// there is the point, because the memoized instance *is* the one the app appends through. A store
/// constructed fresh would carry its own ledger queue (`storeID: ObjectIdentifier(self)`) and
/// serialize against nothing at all.
struct ReceiptStoreLedgerResetService: ReceiptLedgerPrivacyResetting {
    private let store: @MainActor () -> any ReceiptStore

    init(store: @escaping @MainActor () -> any ReceiptStore) {
        self.store = store
    }

    func resetReceiptLedger() async throws {
        try await store().resetAll()
    }
}

protocol AuraPlayPersistenceResetting: Sendable {
    func resetAuraPlayPersistence() async throws
}

protocol AuraPlaySearchIndexResetting: Sendable {
    func resetAuraPlaySearchIndex() async throws
}

struct NoOpAuraPlaySearchIndexResetter: AuraPlaySearchIndexResetting {
    func resetAuraPlaySearchIndex() async throws {}
}

actor CoreSpotlightAuraPlaySearchIndexResetter: AuraPlaySearchIndexResetting {
    private let indexer: AuraPlaySpotlightIndexer

    init(modelContainer: ModelContainer) {
        self.indexer = AuraPlaySpotlightIndexer(modelContainer: modelContainer)
    }

    func resetAuraPlaySearchIndex() async throws {
        try await indexer.deleteAllItems()
    }
}

protocol CredentialPrivacyResetting: Sendable {
    func clearCredentials() async throws
}

protocol SocialCoordinationPrivacyResetting: Sendable {
    func resetSocialCoordinationData() async throws
}

/// Clears the operator runtime's durable history: worklog trace, agent sessions, execution records,
/// performance events, event history, artifacts, and capability grants.
///
/// Separate from ``TransactionalPrivacyResetting`` because these live in their own on-disk container
/// (`OperatorRuntimeStorage`), not the app's main model container, so deleting `StoredReceipt` and
/// friends never touched them.
@MainActor
protocol RuntimeHistoryPrivacyResetting {
    func resetRuntimeHistory() async throws
}

/// Resets the operator runtime history through the app's shared ``RuntimeHost``.
///
/// Resolves the host lazily and through ``RuntimeAssembly/sharedHost(modelContext:)`` on purpose: the
/// rows to delete are on disk from earlier launches, so the reset must reach them even when the
/// person never opened Mission Control this session and no host has been built yet.
@MainActor
struct RuntimeHostHistoryResetService: RuntimeHistoryPrivacyResetting {
    private let host: @MainActor () -> RuntimeHost

    init(host: @escaping @MainActor () -> RuntimeHost) {
        self.host = host
    }

    func resetRuntimeHistory() async throws {
        try await host().resetAllHistory()
    }
}

@MainActor
protocol AllWalletDisconnecting {
    func disconnectAllWalletsAndEraseLocalData() async throws
}

struct PasswordCredentialPrivacyResetter: CredentialPrivacyResetting {
    func clearCredentials() async throws {
        try await Password.clear()
    }
}

struct UserDefaultsSocialCoordinationResetter: SocialCoordinationPrivacyResetting, @unchecked Sendable {
    static let localParticipantIDKey = "social.participantID.v1"
    static let sessionPlaylistKeyPrefix = "social.session.playlist."

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func resetSocialCoordinationData() async throws {
        defaults.removeObject(forKey: UserDefaultsSharedSessionPersistence.defaultKey)
        defaults.removeObject(forKey: UserDefaultsRitualStatePersistence.defaultKey)
        defaults.removeObject(forKey: UserDefaultsSocialEventLogPersistence.defaultKey)
        defaults.removeObject(forKey: Self.localParticipantIDKey)

        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Self.sessionPlaylistKeyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }
}

@ModelActor
actor SwiftDataTransactionalResetService: TransactionalPrivacyResetting {
    /// Everything but the receipts in one rollback-safe transaction, then the receipts through the
    /// ledger's own reset (F-46).
    ///
    /// This used to be a *fourth* receipt-reset implementation: it snapshotted the integrity heads,
    /// called `clearAllHeads()`, deleted the `StoredReceipt` rows, and restored the snapshot only on
    /// failure — all **outside** `ReceiptPersistenceStore`'s ledger lock, which is the one thing that
    /// serializes a reset against in-flight appends. Sequentially it was consistent; concurrently an
    /// append landing inside that window left a head with no row or a row with no head, which is
    /// exactly the state `verifyIntegrity()` then reports as
    /// `.invalid("persisted receipts without protected heads")` — permanently, with another reset as
    /// the only exit. It also cleared the anchors *first*, the ordering `performResetAll` documents as
    /// the unrecoverable direction.
    ///
    /// `ReceiptStores.live(_:)` is memoized per `ModelContainer` and so hands back the very actor the
    /// app appends through — the lock lives on the instance (`storeID: ObjectIdentifier(self)`), so a
    /// freshly constructed store would have its own queue and serialize against nothing. Going through
    /// the facade is what makes this mutually exclusive with `append`, and it inherits the rows-first
    /// ordering and the documented recoverable failure state rather than restating them here.
    ///
    /// The receipt half itself is **not** here — it is ``ReceiptStoreLedgerResetService``, sequenced
    /// immediately after this call inside the same reset phase. It cannot live in this type: the
    /// memoized store has to be resolved on the main actor, and this is a `@ModelActor`.
    func resetTransactionalPrivacyData() async throws {
        try modelContext.performRollbackSafeMutation {
            try modelContext.deleteFetchedModels(matching: FetchDescriptor<SearchHistoryRecord>())
            try modelContext.deleteFetchedModels(matching: FetchDescriptor<TokenHolding>())
            try modelContext.deleteFetchedModels(matching: FetchDescriptor<MusicLibraryItem>())
            try modelContext.deleteFetchedModels(matching: FetchDescriptor<Playlist>())
            try modelContext.deleteAllNFTData()
            try modelContext.deleteFetchedModels(matching: FetchDescriptor<Tag>())

            let accounts = try modelContext.fetch(FetchDescriptor<EOAccount>())
            for account in accounts {
                if account.trackedNFTCount != 0 {
                    account.trackedNFTCount = 0
                }
                account.clearAllAuraPlaySyncState()
            }
        }
    }
}

// The `StoredReceipt` head-ranking extension that used to sit here went with the hand-rolled receipt
// reset (F-46). `ReceiptPersistenceStore` has always had its own copy — it is the only thing that
// needs to rank heads, and it does so under the ledger lock.

actor AuraPlayStoreResetService: AuraPlayPersistenceResetting {
    private let fileManager: FileManager
    private let baseDirectory: URL?

    init(
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory
    }

    func resetAuraPlayPersistence() throws {
        try AuraPlayModelContainer.resetStoreFiles(
            fileManager: fileManager,
            baseDirectory: baseDirectory
        )
    }
}

@ModelActor
actor SwiftDataAuraPlayPersistenceResetService: AuraPlayPersistenceResetting {
    func resetAuraPlayPersistence() throws {
        try modelContext.performRollbackSafeMutation {
            try modelContext.deleteFetchedModels(matching: FetchDescriptor<AuraPlayPlaylistItem>())
            try modelContext.deleteFetchedModels(matching: FetchDescriptor<AuraPlayPlaylist>())
            try modelContext.deleteFetchedModels(matching: FetchDescriptor<AuraPlayMediaEmbedding>())
            try modelContext.deleteFetchedModels(matching: FetchDescriptor<AuraPlayPlaybackPositionTombstone>())
            try modelContext.deleteFetchedModels(matching: FetchDescriptor<AuraPlayPlaybackPositionState>())
            try modelContext.deleteFetchedModels(matching: FetchDescriptor<AuraPlayMediaItem>())
            try modelContext.deleteFetchedModels(matching: FetchDescriptor<AuraPlayNFTToken>())
        }
    }
}

@MainActor
protocol PrivacyResetting {
    func resetLocalPrivacyData() async throws
}

enum PrivacyResetPhase: String, Sendable, CaseIterable {
    case transactionalStore = "transactional wallet data"
    /// Its own phase since F-46 moved the receipt reset out of the SwiftData transaction and onto the
    /// ledger's own locked `resetAll()`. It is a separate *step* with a separate failure mode — the
    /// transaction above has already committed by the time it runs — so collapsing it back into
    /// `transactionalStore` is what made a receipt failure claim a rollback that had not happened.
    case receiptHistory = "receipt history"
    case operatorRuntimeHistory = "operator runtime history"
    case supportCaches = "support caches"
    case socialCoordination = "social coordination data"
    case auraPlayPersistence = "AuraPlay persistence"
    case credentialStore = "credential store"
    case localPreferences = "local preferences"
}

enum LocalDataResetError: LocalizedError {
    case rollbackCompleted(phase: PrivacyResetPhase, underlying: Error)
    case phaseFailed(
        phase: PrivacyResetPhase,
        completedPhases: [PrivacyResetPhase],
        underlying: Error
    )

    var errorDescription: String? {
        switch self {
        case .rollbackCompleted(let phase, _):
            return """
            Auralis could not clear \(phase.rawValue). Changes in that phase were rolled back, so you can retry the privacy reset safely.
            """
        case .phaseFailed(let phase, let completedPhases, _):
            let completedDescription = completedPhases.map(\.rawValue).joined(separator: ", ")
            return """
            Auralis already cleared \(completedDescription) before failing while clearing \(phase.rawValue). The reset is safe to retry and will continue from the remaining phases.
            """
        }
    }
}

@MainActor
struct PrivacyResetService: PrivacyResetting {
    private let transactionalResetService: any TransactionalPrivacyResetting
    private let receiptLedgerResetService: any ReceiptLedgerPrivacyResetting
    private let runtimeHistoryResetService: any RuntimeHistoryPrivacyResetting
    private let ensCacheResetService: any ENSCacheResetting
    private let socialCoordinationResetService: any SocialCoordinationPrivacyResetting
    private let auraPlayPersistenceResetService: any AuraPlayPersistenceResetting
    private let auraPlaySearchIndexResetService: any AuraPlaySearchIndexResetting
    private let credentialResetService: any CredentialPrivacyResetting
    private let selectionPersistence: any ShellSelectionPersisting
    private let homePinnedItemsStore: HomePinnedItemsStore

    init(
        transactionalResetService: any TransactionalPrivacyResetting,
        receiptLedgerResetService: any ReceiptLedgerPrivacyResetting,
        runtimeHistoryResetService: any RuntimeHistoryPrivacyResetting,
        ensCacheResetService: any ENSCacheResetting,
        socialCoordinationResetService: any SocialCoordinationPrivacyResetting = UserDefaultsSocialCoordinationResetter(),
        auraPlayPersistenceResetService: any AuraPlayPersistenceResetting,
        auraPlaySearchIndexResetService: any AuraPlaySearchIndexResetting = NoOpAuraPlaySearchIndexResetter(),
        credentialResetService: any CredentialPrivacyResetting = PasswordCredentialPrivacyResetter(),
        selectionPersistence: any ShellSelectionPersisting = KeychainShellSelectionPersistence(),
        homePinnedItemsStore: HomePinnedItemsStore = HomePinnedItemsStore()
    ) {
        self.transactionalResetService = transactionalResetService
        self.receiptLedgerResetService = receiptLedgerResetService
        self.runtimeHistoryResetService = runtimeHistoryResetService
        self.ensCacheResetService = ensCacheResetService
        self.socialCoordinationResetService = socialCoordinationResetService
        self.auraPlayPersistenceResetService = auraPlayPersistenceResetService
        self.auraPlaySearchIndexResetService = auraPlaySearchIndexResetService
        self.credentialResetService = credentialResetService
        self.selectionPersistence = selectionPersistence
        self.homePinnedItemsStore = homePinnedItemsStore
    }

    func resetLocalPrivacyData() async throws {
        var completedPhases: [PrivacyResetPhase] = []

        do {
            try await transactionalResetService.resetTransactionalPrivacyData()
        } catch {
            // A genuine rollback: `performRollbackSafeMutation` leaves the store exactly as it was,
            // so "nothing was lost, retry safely" is the truth here.
            throw LocalDataResetError.rollbackCompleted(
                phase: .transactionalStore,
                underlying: error
            )
        }
        completedPhases.append(.transactionalStore)

        // Receipts last, and in their own step. The transaction above rolls back whole on failure, so
        // reaching this line means everything else in that phase is already gone and the ledger is the
        // only thing left; the reverse order would destroy the ledger first and only then discover the
        // rest could not be erased.
        //
        // **Reported as its own phase, and not as `rollbackCompleted`.** Sharing the transactional
        // catch made a receipt failure say "Changes in that phase were rolled back, so you can retry
        // the privacy reset safely" — and by then the transaction had committed, so search history,
        // token holdings, the music library, playlists, NFT data and tags were all already erased.
        // Telling a person their data is intact when it is gone is the one direction a privacy
        // feature must not get wrong, even though retrying really is safe.
        do {
            try await receiptLedgerResetService.resetReceiptLedger()
        } catch {
            throw LocalDataResetError.phaseFailed(
                phase: .receiptHistory,
                completedPhases: completedPhases,
                underlying: error
            )
        }
        completedPhases.append(.receiptHistory)

        // Runs immediately after the receipt/wallet phase because it clears the same conceptual
        // layer: receipts are the summary of what the runtime did, the worklog is the trace of it.
        do {
            try await runtimeHistoryResetService.resetRuntimeHistory()
        } catch {
            throw LocalDataResetError.phaseFailed(
                phase: .operatorRuntimeHistory,
                completedPhases: completedPhases,
                underlying: error
            )
        }
        completedPhases.append(.operatorRuntimeHistory)

        await ensCacheResetService.resetCache()
        await GasPriceCache.shared.clearCache()
        completedPhases.append(.supportCaches)

        do {
            try await socialCoordinationResetService.resetSocialCoordinationData()
        } catch {
            throw LocalDataResetError.phaseFailed(
                phase: .socialCoordination,
                completedPhases: completedPhases,
                underlying: error
            )
        }
        completedPhases.append(.socialCoordination)

        do {
            try await auraPlayPersistenceResetService.resetAuraPlayPersistence()
            try await auraPlaySearchIndexResetService.resetAuraPlaySearchIndex()
        } catch {
            throw LocalDataResetError.phaseFailed(
                phase: .auraPlayPersistence,
                completedPhases: completedPhases,
                underlying: error
            )
        }
        completedPhases.append(.auraPlayPersistence)

        do {
            try await credentialResetService.clearCredentials()
        } catch {
            throw LocalDataResetError.phaseFailed(
                phase: .credentialStore,
                completedPhases: completedPhases,
                underlying: error
            )
        }
        completedPhases.append(.credentialStore)

        do {
            try await selectionPersistence.clearSelection()
            homePinnedItemsStore.clearAll()
        } catch {
            throw LocalDataResetError.phaseFailed(
                phase: .localPreferences,
                completedPhases: completedPhases,
                underlying: error
            )
        }
        completedPhases.append(.localPreferences)
    }
}

@MainActor
struct AllWalletDisconnectService: AllWalletDisconnecting {
    private let accountStore: any AccountStoring
    private let privacyResetService: any PrivacyResetting
    private let activeAddressProvider: @MainActor () -> String?

    init(
        accountStore: any AccountStoring,
        privacyResetService: any PrivacyResetting,
        activeAddressProvider: @escaping @MainActor () -> String?
    ) {
        self.accountStore = accountStore
        self.privacyResetService = privacyResetService
        self.activeAddressProvider = activeAddressProvider
    }

    func disconnectAllWalletsAndEraseLocalData() async throws {
        let activeAddress = activeAddressProvider()
        let accounts = try accountStore.listAccounts()

        // `source == .inAppWallet` is deliberately **not** disconnected. "Disconnect" is a meaningful
        // operation for an external wallet — it drops a session this device merely borrowed — and is
        // meaningless for a self-custodial key this device owns and that has no mnemonic to restore
        // from. It also matches `PrivacyResetService`, which preserves every `EOAccount` for the same
        // reason: accounts are identity, not "local data".
        //
        // Removing it was worse than meaningless, it was a trap. Neither this method nor the reset
        // touches `InAppWalletKeystore` or `InAppWalletRegistry` — correctly, because the sealed seed
        // holds funds — so deleting only the `EOAccount` left the registry non-empty and the seed
        // present. That combination is incoherent in one specific way: `needsAddressRecovery` is
        // `hasConfirmedWallet && registry.isEmpty`, so it stayed `false` and the Restore path was never
        // offered, while `primaryAddress()` stayed non-nil so `InAppWalletView` rendered the
        // existing-wallet screen. The wallet was then invisible to every account list (no `EOAccount`),
        // un-recreatable (`createWallet()` throws `walletAlreadyExists`), and the only control left on
        // screen was **Remove Wallet** — which destroys the seed and makes any funds at the derived
        // address permanently unreachable. `InAppWalletService.recoverWallet` documents that exact
        // stranded state as the thing to avoid, and guards it on the failed-save path; this reached it
        // from an ordinary user action.
        //
        // Removing the in-app wallet stays available, deliberately and in one place only: the explicit,
        // confirmation-gated Remove button in `InAppWalletView`, which says the funds become
        // unrecoverable.
        for account in accounts where account.source != .inAppWallet {
            _ = try await accountStore.removeAccount(
                address: account.address,
                activeAddress: activeAddress,
                correlationID: nil
            )
        }

        try await privacyResetService.resetLocalPrivacyData()
    }
}

@MainActor
enum PrivacyResetServices {
    static func live(
        modelContext: ModelContext,
        auraPlayModelContainer: ModelContainer?
    ) -> PrivacyResetService {
        PrivacyResetService(
            transactionalResetService: SwiftDataTransactionalResetService(
                modelContainer: modelContext.container
            ),
            receiptLedgerResetService: ReceiptStoreLedgerResetService(
                store: { ReceiptStores.live(modelContext: modelContext) }
            ),
            runtimeHistoryResetService: RuntimeHostHistoryResetService(
                host: { RuntimeAssembly.sharedHost(modelContext: modelContext) }
            ),
            ensCacheResetService: ENSResolvers.cacheResetService(),
            auraPlayPersistenceResetService: auraPlayModelContainer.map {
                SwiftDataAuraPlayPersistenceResetService(modelContainer: $0)
            } ?? AuraPlayStoreResetService(),
            auraPlaySearchIndexResetService: auraPlayModelContainer.map {
                CoreSpotlightAuraPlaySearchIndexResetter(modelContainer: $0)
            } ?? NoOpAuraPlaySearchIndexResetter(),
            credentialResetService: PasswordCredentialPrivacyResetter(),
            selectionPersistence: KeychainShellSelectionPersistence(),
            homePinnedItemsStore: HomePinnedItemsStore()
        )
    }
}
