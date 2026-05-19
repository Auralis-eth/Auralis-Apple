import AccountsCore
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import AuralisShellCore
import ENS
import MusicFeature
import NFTKit
import PolicyCore
import ProviderKit
import ReceiptsCore
import SwiftData
import TokenStorage

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
        homePinnedItemsStore: HomePinnedItemsStore? = nil,
        privacyResetServiceFactory: (@MainActor (ModelContext, ModelContainer?) -> any PrivacyResetting)? = nil
    ) -> MainTabDependencies {
        MainTabDependencies(
            accountStoreFactory: { [accounts] modelContext in
                accounts.makeAccountStore(modelContext: modelContext)
            },
            contextServiceBuilder: shell.contextServiceBuilder,
            nativeBalanceProvider: providers.makeNativeBalanceProvider(),
            gasPricingProvider: providers.makeGasPricingProvider(),
            ensResolver: accounts.makeENSResolver(modelContext: modelContext),
            homePinnedItemsStore: homePinnedItemsStore ?? home.makePinnedItemsStore(),
            libraryContextProvider: shell.makeLibraryContextProvider(modelContext: modelContext),
            musicLibraryIndexer: music.makeMusicLibraryIndexer(modelContext: modelContext),
            receiptEventLoggerFactory: { [receipts] modelContext in
                receipts.makeReceiptEventLogger(modelContext: modelContext)
            },
            searchHistoryStore: search.makeSearchHistoryStore(modelContext: modelContext),
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
            policyActionHandlerFactory: { [policy] modelContext, modeState in
                policy.makePolicyActionHandler(
                    modelContext: modelContext,
                    modeState: modeState
                )
            },
            musicFeatureDependenciesFactory: { [music] audioEngine, auraPlayModelContainer, accountModelContext, musicLibraryIndexer in
                music.makeMusicFeatureDependencies(
                    audioEngine: audioEngine,
                    auraPlayModelContainer: auraPlayModelContainer,
                    accountModelContext: accountModelContext,
                    musicLibraryIndexer: musicLibraryIndexer
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
    let tokenHoldingsStoreFactory: @MainActor (ModelContext) -> SwiftDataTokenHoldingsStore
    let tokenHoldingsProviderFactory: () -> any TokenHoldingsProviding
    let erc20HoldingsSyncerFactory: @MainActor (ModelContext) -> any ERC20HoldingsSyncing
    let logoutCleanupServiceFactory: @MainActor (ModelContext) -> any LogoutCleaning
    let privacyResetServiceFactory: @MainActor (ModelContext, ModelContainer?) -> any PrivacyResetting
    let policyActionHandlerFactory: @MainActor (ModelContext, ModeState) -> any PolicyActionGating
    let musicFeatureDependenciesFactory: @MainActor (
        AudioEngine,
        ModelContainer,
        ModelContext,
        any MusicLibraryIndexing
    ) -> AuraPlayDependencies


    func makeMusicFeatureDependencies(
        audioEngine: AudioEngine,
        auraPlayModelContainer: ModelContainer,
        accountModelContext: ModelContext
    ) -> AuraPlayDependencies {
        musicFeatureDependenciesFactory(
            audioEngine,
            auraPlayModelContainer,
            accountModelContext,
            musicLibraryIndexer
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
