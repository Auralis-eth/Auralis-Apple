import Foundation
import SwiftData

protocol ShellContextSourceBuilding {
    func makeContextSource(
        accountProvider: @escaping () -> EOAccount?,
        addressProvider: @escaping () -> String,
        chainProvider: @escaping () -> Chain,
        modeProvider: @escaping () -> AppMode,
        loadingProvider: @escaping () -> Bool,
        refreshedAtProvider: @escaping () -> Date?,
        nativeBalanceDisplayProvider: @escaping () -> String?,
        nativeBalanceStatusMessageProvider: @escaping () -> String?,
        nativeBalanceUpdatedAtProvider: @escaping () -> Date?,
        nativeBalanceProvenanceProvider: @escaping () -> ContextProvenance,
        freshnessTTLProvider: @escaping () -> TimeInterval?,
        trackedNFTCountProvider: @escaping () -> Int?,
        musicCollectionCountProvider: @escaping () -> Int?,
        receiptCountProvider: @escaping () -> Int?,
        pinnedActionsProvider: @escaping () -> [HomeLauncherAction],
        prefersDemoDataProvider: @escaping () -> Bool?,
        pinnedItemCountProvider: @escaping () -> Int?
    ) -> any ContextSource
}

@MainActor
protocol ShellContextServiceBuilding {
    func makeContextService(
        accountProvider: @escaping () -> EOAccount?,
        addressProvider: @escaping () -> String,
        chainProvider: @escaping () -> Chain,
        modeProvider: @escaping () -> AppMode,
        loadingProvider: @escaping () -> Bool,
        refreshedAtProvider: @escaping () -> Date?,
        nativeBalanceProvider: any NativeBalanceProviding,
        freshnessTTLProvider: @escaping () -> TimeInterval?,
        trackedNFTCountProvider: @escaping () -> Int?,
        musicCollectionCountProvider: @escaping () -> Int?,
        receiptCountProvider: @escaping () -> Int?,
        pinnedActionsProvider: @escaping () -> [HomeLauncherAction],
        prefersDemoDataProvider: @escaping () -> Bool?,
        pinnedItemCountProvider: @escaping () -> Int?
    ) -> ContextService
}

@MainActor
protocol ShellLibraryContextProviding {
    func playlistCount() -> Int?
    func receiptCount(scope: ReceiptTimelineScope) -> Int?
}

struct LiveShellContextSourceBuilder: ShellContextSourceBuilding {
    func makeContextSource(
        accountProvider: @escaping () -> EOAccount?,
        addressProvider: @escaping () -> String,
        chainProvider: @escaping () -> Chain,
        modeProvider: @escaping () -> AppMode,
        loadingProvider: @escaping () -> Bool,
        refreshedAtProvider: @escaping () -> Date?,
        nativeBalanceDisplayProvider: @escaping () -> String?,
        nativeBalanceStatusMessageProvider: @escaping () -> String?,
        nativeBalanceUpdatedAtProvider: @escaping () -> Date?,
        nativeBalanceProvenanceProvider: @escaping () -> ContextProvenance,
        freshnessTTLProvider: @escaping () -> TimeInterval?,
        trackedNFTCountProvider: @escaping () -> Int?,
        musicCollectionCountProvider: @escaping () -> Int?,
        receiptCountProvider: @escaping () -> Int?,
        pinnedActionsProvider: @escaping () -> [HomeLauncherAction],
        prefersDemoDataProvider: @escaping () -> Bool?,
        pinnedItemCountProvider: @escaping () -> Int?
    ) -> any ContextSource {
        LiveContextSource(
            accountProvider: accountProvider,
            addressProvider: addressProvider,
            chainProvider: chainProvider,
            modeProvider: modeProvider,
            loadingProvider: loadingProvider,
            refreshedAtProvider: refreshedAtProvider,
            nativeBalanceDisplayProvider: nativeBalanceDisplayProvider,
            nativeBalanceStatusMessageProvider: nativeBalanceStatusMessageProvider,
            nativeBalanceUpdatedAtProvider: nativeBalanceUpdatedAtProvider,
            nativeBalanceProvenanceProvider: nativeBalanceProvenanceProvider,
            freshnessTTLProvider: freshnessTTLProvider,
            trackedNFTCountProvider: trackedNFTCountProvider,
            musicCollectionCountProvider: musicCollectionCountProvider,
            receiptCountProvider: receiptCountProvider,
            pinnedActionsProvider: pinnedActionsProvider,
            prefersDemoDataProvider: prefersDemoDataProvider,
            pinnedItemCountProvider: pinnedItemCountProvider
        )
    }
}

@MainActor
struct SwiftDataShellLibraryContextProvider: ShellLibraryContextProviding {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func playlistCount() -> Int? {
        do {
            return try modelContext.fetch(FetchDescriptor<Playlist>()).count
        } catch {
            return nil
        }
    }

    func receiptCount(scope: ReceiptTimelineScope) -> Int? {
        do {
            let normalizedAccountAddress = scope.accountAddress.extractedEthereumAddress?.lowercased()
            let descriptor: FetchDescriptor<StoredReceipt>

            if let normalizedAccountAddress, !normalizedAccountAddress.isEmpty {
                descriptor = FetchDescriptor<StoredReceipt>(
                    predicate: #Predicate<StoredReceipt> { receipt in
                        receipt.accountAddress == normalizedAccountAddress
                    }
                )
            } else {
                descriptor = FetchDescriptor<StoredReceipt>()
            }

            return try modelContext.fetch(descriptor).count
        } catch {
            return nil
        }
    }
}

@MainActor
struct LiveShellContextServiceBuilder: ShellContextServiceBuilding {
    private let contextSourceBuilder: any ShellContextSourceBuilding

    init(contextSourceBuilder: any ShellContextSourceBuilding = LiveShellContextSourceBuilder()) {
        self.contextSourceBuilder = contextSourceBuilder
    }

    func makeContextService(
        accountProvider: @escaping () -> EOAccount?,
        addressProvider: @escaping () -> String,
        chainProvider: @escaping () -> Chain,
        modeProvider: @escaping () -> AppMode,
        loadingProvider: @escaping () -> Bool,
        refreshedAtProvider: @escaping () -> Date?,
        nativeBalanceProvider: any NativeBalanceProviding,
        freshnessTTLProvider: @escaping () -> TimeInterval?,
        trackedNFTCountProvider: @escaping () -> Int?,
        musicCollectionCountProvider: @escaping () -> Int?,
        receiptCountProvider: @escaping () -> Int?,
        pinnedActionsProvider: @escaping () -> [HomeLauncherAction],
        prefersDemoDataProvider: @escaping () -> Bool?,
        pinnedItemCountProvider: @escaping () -> Int?
    ) -> ContextService {
        ContextService(
            contextSourceBuilder: contextSourceBuilder,
            accountProvider: accountProvider,
            addressProvider: addressProvider,
            chainProvider: chainProvider,
            modeProvider: modeProvider,
            loadingProvider: loadingProvider,
            refreshedAtProvider: refreshedAtProvider,
            nativeBalanceProvider: nativeBalanceProvider,
            freshnessTTLProvider: freshnessTTLProvider,
            trackedNFTCountProvider: trackedNFTCountProvider,
            musicCollectionCountProvider: musicCollectionCountProvider,
            receiptCountProvider: receiptCountProvider,
            pinnedActionsProvider: pinnedActionsProvider,
            prefersDemoDataProvider: prefersDemoDataProvider,
            pinnedItemCountProvider: pinnedItemCountProvider
        )
    }
}

@MainActor
protocol PolicyActionGating {
    func attempt(_ action: PolicyControlledAction) async -> PolicyGateResult
}

@MainActor
struct PolicyActionGateService: PolicyActionGating {
    private let modeState: ModeState
    private let receiptStore: any ReceiptStore

    init(
        modeState: ModeState,
        receiptStore: any ReceiptStore
    ) {
        self.modeState = modeState
        self.receiptStore = receiptStore
    }

    func attempt(_ action: PolicyControlledAction) async -> PolicyGateResult {
        await ActionPolicyGate.attempt(
            action,
            modeState: modeState,
            receiptStore: receiptStore
        )
    }
}

@MainActor
/// Bundles the long-lived service factories needed to assemble the Aura shell.
struct ShellServiceHub {
    /// Builds the shared mode state store used by the shell.
    let modeStateFactory: @MainActor () -> ModeState
    /// Builds the long-lived NFT refresh service.
    let nftServiceFactory: @MainActor () -> NFTService
    /// Builds the ENS resolver for the current model context.
    let ensResolverFactory: @MainActor (ModelContext) -> any ENSResolving
    /// Factory for read-only provider dependencies used across shell features.
    let readOnlyProviderFactory: ReadOnlyProviderFactory
    /// Builds the account store for the current model context.
    let accountStoreFactory: @MainActor (ModelContext) -> AccountStore
    /// Builds the account event recorder for the current model context.
    let accountEventRecorderFactory: @MainActor (ModelContext) -> any AccountEventRecorder
    /// Builds the shell context service.
    let contextServiceBuilder: any ShellContextServiceBuilding
    /// Builds lightweight library-count providers for the shell.
    let libraryContextProviderFactory: @MainActor (ModelContext) -> any ShellLibraryContextProviding
    /// Builds the music library indexer.
    let musicLibraryIndexerFactory: @MainActor (ModelContext) -> any MusicLibraryIndexing
    /// Builds the receipt store for the current model context.
    let receiptStoreFactory: @MainActor (ModelContext) -> any ReceiptStore
    /// Builds the receipt event logger for the current model context.
    let receiptEventLoggerFactory: @MainActor (ModelContext) -> ReceiptEventLogger
    /// Builds the search history store.
    let searchHistoryStoreFactory: @MainActor (ModelContext) -> SearchHistoryStore
    /// Builds the home pinned-items store.
    let homePinnedItemsStoreFactory: () -> HomePinnedItemsStore
    /// Builds the persisted token holdings store.
    let tokenHoldingsStoreFactory: @MainActor (ModelContext) -> TokenHoldingsStore
    /// Builds the token holdings network provider.
    let tokenHoldingsProviderFactory: () -> any TokenHoldingsProviding
    /// Builds the privacy reset service for the current model context.
    let privacyResetServiceFactory: @MainActor (ModelContext) -> any PrivacyResetting
    /// Builds the policy gate service for the current mode and model context.
    let policyActionHandlerFactory: @MainActor (ModelContext, ModeState) -> any PolicyActionGating

    /// Returns the production service hub used by the app shell.
    static let live: ShellServiceHub = {
        let readOnlyProviderFactory = ReadOnlyProviderFactory()
        return ShellServiceHub(
            modeStateFactory: { ModeState() },
            nftServiceFactory: {
                NFTService(
                    nftFetcher: NFTFetcher(
                        nftProviderFactory: { chain in
                            try readOnlyProviderFactory.makeNFTInventoryProvider(for: chain)
                        }
                    )
                )
            },
            ensResolverFactory: { modelContext in
                ENSResolvers.live(modelContext: modelContext)
            },
            readOnlyProviderFactory: readOnlyProviderFactory,
            accountStoreFactory: { modelContext in
                AccountStore(
                    modelContext: modelContext,
                    eventRecorder: AccountEventRecorders.live(modelContext: modelContext)
                )
            },
            accountEventRecorderFactory: { modelContext in
                AccountEventRecorders.live(modelContext: modelContext)
            },
            contextServiceBuilder: LiveShellContextServiceBuilder(),
            libraryContextProviderFactory: { modelContext in
                SwiftDataShellLibraryContextProvider(modelContext: modelContext)
            },
            musicLibraryIndexerFactory: { modelContext in
                SwiftDataMusicLibraryIndexer(modelContext: modelContext)
            },
            receiptStoreFactory: { modelContext in
                ReceiptStores.live(modelContext: modelContext)
            },
            receiptEventLoggerFactory: { modelContext in
                ReceiptEventLogger(
                    receiptStore: ReceiptStores.live(modelContext: modelContext)
                )
            },
            searchHistoryStoreFactory: { modelContext in
                SearchHistoryStore(modelContext: modelContext)
            },
            homePinnedItemsStoreFactory: {
                HomePinnedItemsStore()
            },
            tokenHoldingsStoreFactory: { modelContext in
                TokenHoldingsStore(modelContext: modelContext)
            },
            tokenHoldingsProviderFactory: {
                readOnlyProviderFactory.makeTokenHoldingsProvider()
            },
            privacyResetServiceFactory: { modelContext in
                PrivacyResetServices.live(modelContext: modelContext)
            },
            policyActionHandlerFactory: { modelContext, modeState in
                PolicyActionGateService(
                    modeState: modeState,
                    receiptStore: ReceiptStores.live(modelContext: modelContext)
                )
            }
        )
    }()
}
