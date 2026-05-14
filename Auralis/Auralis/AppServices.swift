import ReceiptsCore
import ReceiptStorage
import AccountStorage
import AccountsCore
import ENS
import AuralisPrimaryModels
import Foundation
import ProviderKit
import PolicyCore
import SwiftData
import NFTKit
import TokenStorage

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
            return try modelContext.fetchCount(FetchDescriptor<Playlist>())
        } catch {
            return nil
        }
    }

    func receiptCount(scope: ReceiptTimelineScope) -> Int? {
        do {
            let normalizedAccountAddress = scope.accountAddress.extractedEthereumAddress?.lowercased()
            let chainRawValue = scope.chain.rawValue
            let descriptor: FetchDescriptor<StoredReceipt>

            if let normalizedAccountAddress, !normalizedAccountAddress.isEmpty {
                descriptor = FetchDescriptor<StoredReceipt>(
                    predicate: #Predicate<StoredReceipt> { receipt in
                        receipt.accountAddress == normalizedAccountAddress &&
                        receipt.chainRawValue == chainRawValue
                    }
                )
            } else {
                descriptor = FetchDescriptor<StoredReceipt>()
            }

            return try modelContext.fetchCount(descriptor)
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
struct ShellStoreDependencies {
    let selectionPersistence: any ShellSelectionPersisting
    let accountResolver: any ShellAccountResolving
    let accountMutator: any ShellAccountMutating
    let refreshCoordinator: any ShellRefreshing
    let deepLinkReplayer: any ShellDeepLinkReplaying
    let routerEffectHandler: any ShellRouterEffectHandling
    let receiptLogger: any ShellReceiptLogging
    let clock: any ShellClock

    static func live(
        modelContext: ModelContext,
        nftService: NFTService,
        router: AppRouter
    ) -> ShellStoreDependencies {
        let services = ShellServiceHub.live
        let accountResolver = SwiftDataShellAccountResolver(modelContext: modelContext)
        return ShellStoreDependencies(
            selectionPersistence: UserDefaultsShellSelectionPersistence(),
            accountResolver: accountResolver,
            accountMutator: SwiftDataShellAccountMutator(
                modelContext: modelContext,
                eventRecorder: services.accountEventRecorderFactory(modelContext)
            ),
            refreshCoordinator: NFTServiceShellRefreshCoordinator(
                modelContext: modelContext,
                nftService: nftService,
                accountResolver: accountResolver
            ),
            deepLinkReplayer: DefaultShellDeepLinkReplayer(),
            routerEffectHandler: AppRouterShellEffectHandler(
                router: router,
                modelContext: modelContext
            ),
            receiptLogger: ReceiptEventShellLogger(
                receiptEventLogger: services.receiptEventLoggerFactory(modelContext)
            ),
            clock: SystemShellClock()
        )
    }
}

@MainActor
struct GatewayDependencies {
    let ensResolver: any ENSResolving
    let accountStoreFactory: @MainActor (ModelContext) -> any AccountStoring

    static func live(modelContext: ModelContext) -> GatewayDependencies {
        let services = ShellServiceHub.live
        return GatewayDependencies(
            ensResolver: services.ensResolverFactory(modelContext),
            accountStoreFactory: services.accountStoreFactory
        )
    }
}

@MainActor
struct MainTabDependencies {
    let accountStoreFactory: @MainActor (ModelContext) -> any AccountStoring
    let contextServiceBuilder: any ShellContextServiceBuilding
    let nativeBalanceProvider: any NativeBalanceProviding
    let gasPricingProvider: any GasPricingProviding
    let ensResolver: any ENSResolving
    let homePinnedItemsStore: HomePinnedItemsStore
    let libraryContextProvider: any ShellLibraryContextProviding
    let musicLibraryIndexer: any MusicLibraryIndexing
    let receiptEventLoggerFactory: @MainActor (ModelContext) -> ReceiptEventLogger
    let searchHistoryStore: SearchHistoryStore
    let tokenHoldingsStoreFactory: @MainActor (ModelContext) -> SwiftDataTokenHoldingsStore
    let tokenHoldingsProviderFactory: () -> any TokenHoldingsProviding
    let logoutCleanupServiceFactory: @MainActor (ModelContext) -> any LogoutCleaning
    let privacyResetServiceFactory: @MainActor (ModelContext, ModelContainer?) -> any PrivacyResetting
    let policyActionHandlerFactory: @MainActor (ModelContext, ModeState) -> any PolicyActionGating

    static func live(modelContext: ModelContext) -> MainTabDependencies {
        let services = ShellServiceHub.live
        return MainTabDependencies(
            accountStoreFactory: services.accountStoreFactory,
            contextServiceBuilder: services.contextServiceBuilder,
            nativeBalanceProvider: services.readOnlyProviderFactory.makeNativeBalanceProvider(),
            gasPricingProvider: services.readOnlyProviderFactory.makeGasPricingProvider(),
            ensResolver: services.ensResolverFactory(modelContext),
            homePinnedItemsStore: services.homePinnedItemsStoreFactory(),
            libraryContextProvider: services.libraryContextProviderFactory(modelContext),
            musicLibraryIndexer: services.musicLibraryIndexerFactory(modelContext),
            receiptEventLoggerFactory: services.receiptEventLoggerFactory,
            searchHistoryStore: services.searchHistoryStoreFactory(modelContext),
            tokenHoldingsStoreFactory: services.tokenHoldingsStoreFactory,
            tokenHoldingsProviderFactory: services.tokenHoldingsProviderFactory,
            logoutCleanupServiceFactory: services.logoutCleanupServiceFactory,
            privacyResetServiceFactory: services.privacyResetServiceFactory,
            policyActionHandlerFactory: services.policyActionHandlerFactory
        )
    }
}

@MainActor
struct ShellBootstrapDependencies {
    let modeStateFactory: @MainActor () -> ModeState
    let nftServiceFactory: @MainActor () -> NFTService
    let makeShellStore: @MainActor (ModelContext, NFTService, AppRouter) -> ShellStore
    let makeGatewayDependencies: @MainActor (ModelContext) -> GatewayDependencies
    let makeMainTabDependencies: @MainActor (ModelContext) -> MainTabDependencies

    static let live: ShellBootstrapDependencies = {
        return ShellBootstrapDependencies(
            modeStateFactory: ShellServiceHub.live.modeStateFactory,
            nftServiceFactory: ShellServiceHub.live.nftServiceFactory,
            makeShellStore: { modelContext, nftService, router in
                ShellStore.live(
                    dependencies: ShellStoreDependencies.live(
                        modelContext: modelContext,
                        nftService: nftService,
                        router: router
                    )
                )
            },
            makeGatewayDependencies: { modelContext in
                GatewayDependencies.live(modelContext: modelContext)
            },
            makeMainTabDependencies: { modelContext in
                MainTabDependencies.live(modelContext: modelContext)
            }
        )
    }()
}

@MainActor
/// Bundles the long-lived service factories needed to assemble the Aura shell.
private struct ShellServiceHub {
    /// Builds the shared mode state store used by the shell.
    let modeStateFactory: @MainActor () -> ModeState
    /// Builds the long-lived NFT refresh service.
    let nftServiceFactory: @MainActor () -> NFTService
    /// Builds the ENS resolver for the current model context.
    let ensResolverFactory: @MainActor (ModelContext) -> any ENSResolving
    /// Factory for read-only provider dependencies used across shell features.
    let readOnlyProviderFactory: ReadOnlyProviderFactory
    /// Builds the account store for the current model context.
    let accountStoreFactory: @MainActor (ModelContext) -> any AccountStoring
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
    let tokenHoldingsStoreFactory: @MainActor (ModelContext) -> SwiftDataTokenHoldingsStore
    /// Builds the token holdings network provider.
    let tokenHoldingsProviderFactory: () -> any TokenHoldingsProviding
    /// Builds the logout cleanup service for the current model context.
    let logoutCleanupServiceFactory: @MainActor (ModelContext) -> any LogoutCleaning
    /// Builds the privacy reset service for the current model context.
    let privacyResetServiceFactory: @MainActor (ModelContext, ModelContainer?) -> any PrivacyResetting
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
                SwiftDataAccountStore(
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
                SwiftDataTokenHoldingsStore(modelContext: modelContext)
            },
            tokenHoldingsProviderFactory: {
                readOnlyProviderFactory.makeTokenHoldingsProvider()
            },
            logoutCleanupServiceFactory: { modelContext in
                LogoutCleanupService(modelContext: modelContext)
            },
            privacyResetServiceFactory: { modelContext, auraPlayModelContainer in
                PrivacyResetServices.live(
                    modelContext: modelContext,
                    auraPlayModelContainer: auraPlayModelContainer
                )
            },
            policyActionHandlerFactory: { modelContext, modeState in
                PolicyActionGateService(
                    modeProvider: { modeState.mode },
                    receiptStore: ReceiptStores.live(modelContext: modelContext)
                )
            }
        )
    }()
}
