import AuralisCrypto
import AuralisAppShell
import AuralisOperators
import AuralisPolicy
import AuralisReceipts
import SwiftData

@MainActor
struct MainTabAssembly {
    private let accounts: AccountAssembly
    private let shell: ShellAssembly
    private let providers: ProviderAssembly
    private let receipts: ReceiptAssembly
    private let music: MusicAssembly
    private let privacy: PrivacyAssembly
    private let tokenHoldings: TokenHoldingsAssembly
    private let search: SearchAssembly
    private let home: HomeAssembly
    private let policy: PolicyAssembly

    init(
        accounts: AccountAssembly,
        shell: ShellAssembly,
        providers: ProviderAssembly,
        receipts: ReceiptAssembly,
        music: MusicAssembly,
        privacy: PrivacyAssembly,
        tokenHoldings: TokenHoldingsAssembly,
        search: SearchAssembly,
        home: HomeAssembly,
        policy: PolicyAssembly
    ) {
        self.accounts = accounts
        self.shell = shell
        self.providers = providers
        self.receipts = receipts
        self.music = music
        self.privacy = privacy
        self.tokenHoldings = tokenHoldings
        self.search = search
        self.home = home
        self.policy = policy
    }

    func makeMainTabDependencies(
        modelContext: ModelContext,
        modeState: ModeState? = nil,
        homePinnedItemsStore: HomePinnedItemsStore? = nil,
        privacyResetServiceFactory: (@MainActor (ModelContext, ModelContainer?) -> any PrivacyResetting)? = nil,
        allWalletDisconnectServiceFactory: (@MainActor (ModelContext, ModelContainer?, String?) -> any AllWalletDisconnecting)? = nil
    ) -> MainTabDependencies {
        MainTabDependencies(
            accountStoreFactory: { [accounts] modelContext in
                accounts.makeAccountStore(
                    modelContext: modelContext,
                    modeProvider: {
                        modeState?.mode.receiptMode ?? PersistedCryptoMode.currentReceiptMode
                    }
                )
            },
            contextServiceBuilder: shell.contextServiceBuilder,
            nativeBalanceProvider: providers.makeNativeBalanceProvider(),
            gasPricingProvider: providers.makeGasPricingProvider(),
            ensResolver: accounts.makeENSResolver(
                modelContext: modelContext,
                modeProvider: {
                    modeState?.mode.receiptMode ?? PersistedCryptoMode.currentReceiptMode
                }
            ),
            homePinnedItemsStore: homePinnedItemsStore ?? home.makePinnedItemsStore(),
            libraryContextProvider: shell.makeLibraryContextProvider(modelContext: modelContext),
            musicLibraryIndexer: music.makeMusicLibraryIndexer(modelContext: modelContext),
            receiptEventLoggerFactory: { [receipts] modelContext in
                receipts.makeReceiptEventLogger(modelContext: modelContext)
            },
            searchHistoryStore: search.makeSearchHistoryStore(modelContext: modelContext),
            searchSpotlightIndexerFactory: { [search] modelContext in
                search.makeSpotlightIndexer(modelContext: modelContext)
            },
            searchAssistantFactory: { [search] modelContext in
                search.makeAssistant(modelContext: modelContext)
            },
            tokenHoldingsStoreFactory: { [tokenHoldings] modelContext in
                tokenHoldings.makeStore(modelContext: modelContext)
            },
            tokenHoldingsProviderFactory: { [tokenHoldings] in
                tokenHoldings.makeProvider()
            },
            erc20HoldingsSyncerFactory: { [tokenHoldings] modelContext in
                tokenHoldings.makeSyncer(modelContext: modelContext)
            },
            logoutCleanupServiceFactory: { [privacy] modelContext in
                privacy.makeLogoutCleanupService(modelContext: modelContext)
            },
            privacyResetServiceFactory: privacyResetServiceFactory ?? { [privacy] modelContext, auraPlayModelContainer in
                privacy.makePrivacyResetService(
                    modelContext: modelContext,
                    auraPlayModelContainer: auraPlayModelContainer
                )
            },
            allWalletDisconnectServiceFactory: allWalletDisconnectServiceFactory ?? { [accounts, privacy] modelContext, auraPlayModelContainer, activeAddress in
                privacy.makeAllWalletDisconnectService(
                    accountStore: accounts.makeAccountStore(
                        modelContext: modelContext,
                        modeProvider: {
                            modeState?.mode.receiptMode ?? PersistedCryptoMode.currentReceiptMode
                        }
                    ),
                    modelContext: modelContext,
                    auraPlayModelContainer: auraPlayModelContainer,
                    activeAddressProvider: { activeAddress }
                )
            },
            policyActionHandlerFactory: { [policy] modelContext, modeState in
                policy.makePolicyActionHandler(
                    modelContext: modelContext,
                    modeState: modeState
                )
            },
            musicFeatureDependenciesFactory: { [music] playbackRuntime, auraPlayModelContainer, accountModelContext, musicLibraryIndexer, videoRouteOpening in
                music.makeMusicFeatureDependencies(
                    playbackRuntime: playbackRuntime,
                    auraPlayModelContainer: auraPlayModelContainer,
                    accountModelContext: accountModelContext,
                    musicLibraryIndexer: musicLibraryIndexer,
                    videoRouteOpening: videoRouteOpening
                )
            }
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
    let searchSpotlightIndexerFactory: @MainActor (ModelContext) -> any SearchSpotlightIndexing
    let searchAssistantFactory: @MainActor (ModelContext) -> any SearchAssistantProviding
    let tokenHoldingsStoreFactory: @MainActor (ModelContext) -> SwiftDataTokenHoldingsStore
    let tokenHoldingsProviderFactory: () -> any TokenHoldingsProviding
    let erc20HoldingsSyncerFactory: @MainActor (ModelContext) -> any ERC20HoldingsSyncing
    let logoutCleanupServiceFactory: @MainActor (ModelContext) -> any LogoutCleaning
    let privacyResetServiceFactory: @MainActor (ModelContext, ModelContainer?) -> any PrivacyResetting
    let allWalletDisconnectServiceFactory: @MainActor (ModelContext, ModelContainer?, String?) -> any AllWalletDisconnecting
    let policyActionHandlerFactory: @MainActor (ModelContext, ModeState) -> any PolicyActionGating
    let musicFeatureDependenciesFactory: @MainActor (
        AuraPlayPlaybackRuntime,
        ModelContainer,
        ModelContext,
        any MusicLibraryIndexing,
        AuraPlayVideoRouteOpening
    ) -> AuraPlayDependencies

    func makeMusicFeatureDependencies(
        playbackRuntime: AuraPlayPlaybackRuntime,
        auraPlayModelContainer: ModelContainer,
        accountModelContext: ModelContext,
        videoRouteOpening: AuraPlayVideoRouteOpening
    ) -> AuraPlayDependencies {
        musicFeatureDependenciesFactory(
            playbackRuntime,
            auraPlayModelContainer,
            accountModelContext,
            musicLibraryIndexer,
            videoRouteOpening
        )
    }

    func makeContextService(
        shellStore: ShellStore,
        resolveCurrentAccount: @escaping @MainActor () -> EOAccount?,
        modeState: ModeState,
        nftServiceProvider: @escaping @MainActor () -> NFTService
    ) -> ContextService {
        contextServiceBuilder.makeContextService(
            accountProvider: { resolveCurrentAccount() },
            addressProvider: { shellStore.state.selection?.address ?? "" },
            chainProvider: { shellStore.state.selection?.chain ?? .ethMainnet },
            modeProvider: { modeState.mode },
            loadingProvider: { nftServiceProvider().isLoading },
            refreshedAtProvider: {
                let activeAddress = resolveCurrentAccount()?.address
                    ?? shellStore.state.selection?.address
                    ?? ""
                return nftServiceProvider().lastSuccessfulRefreshAt(
                    for: activeAddress,
                    chain: shellStore.state.selection?.chain ?? .ethMainnet
                )
            },
            nativeBalanceProvider: nativeBalanceProvider,
            freshnessTTLProvider: { nftServiceProvider().refreshTTL },
            trackedNFTCountProvider: {
                resolveCurrentAccount()?.trackedNFTCount
            },
            musicCollectionCountProvider: {
                libraryContextProvider.playlistCount()
            },
            receiptCountProvider: {
                libraryContextProvider.receiptCount(
                    scope: ReceiptTimelineScope(
                        accountAddress: shellStore.state.selection?.address ?? "",
                        chain: shellStore.state.selection?.chain ?? .ethMainnet
                    )
                )
            },
            pinnedActionsProvider: {
                Array(
                    homePinnedItemsStore.pinnedActions(
                        for: shellStore.state.selection?.address ?? ""
                    )
                )
                .sorted { $0.rawValue < $1.rawValue }
            },
            prefersDemoDataProvider: {
                resolveCurrentAccount()?.source == .guestPass
            },
            pinnedItemCountProvider: {
                homePinnedItemsStore.pinnedCount(
                    for: shellStore.state.selection?.address ?? ""
                )
            }
        )
    }
}

@MainActor
struct AuraPlayVideoRouteOpening {
    let open: @MainActor () -> Void

    init(open: @escaping @MainActor () -> Void) {
        self.open = open
    }
}
