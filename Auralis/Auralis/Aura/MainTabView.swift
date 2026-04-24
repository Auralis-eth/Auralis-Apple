import Observation
import SwiftData
import SwiftUI

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext

    let shellStore: ShellStore
    let resolveCurrentAccount: @MainActor () -> EOAccount?
    @Binding var nftService: NFTService
    @Bindable var router: AppRouter
    let audioEngine: AudioEngine?
    let audioUnavailableMessage: String?
    let modeState: ModeState
    let services: ShellServiceHub

    private let homePinnedItemsStore: HomePinnedItemsStore

    @State private var showAccountSwitcher = false
    @State private var contextService: ContextService
    @State private var pinnedItemCount: Int
    @State private var showContextInspector = false

    private var currentAccount: EOAccount? {
        resolveCurrentAccount()
    }

    private var currentAddress: String {
        shellStore.state.selection?.address ?? ""
    }

    private var currentChain: Chain {
        shellStore.state.selection?.chain ?? .ethMainnet
    }

    private var activeAccountAddress: String {
        currentAccount?.address ?? currentAddress
    }

    private var contextRemoteRefreshKey: ContextRemoteRefreshKey {
        ContextRemoteRefreshKey(
            accountAddress: activeAccountAddress,
            chain: currentChain,
            mode: modeState.mode,
            isLoading: nftService.isLoading,
            refreshedAt: nftService.lastSuccessfulRefreshAt(
                for: activeAccountAddress,
                chain: currentChain
            )
        )
    }

    private var contextLocalRefreshKey: ContextLocalRefreshKey {
        ContextLocalRefreshKey(
            trackedNFTCount: currentAccount?.trackedNFTCount,
            pinnedItemCount: pinnedItemCount
        )
    }

    init(
        shellStore: ShellStore,
        resolveCurrentAccount: @escaping @MainActor () -> EOAccount?,
        nftService: Binding<NFTService>,
        router: AppRouter,
        audioEngine: AudioEngine?,
        audioUnavailableMessage: String?,
        modeState: ModeState,
        services: ShellServiceHub,
        modelContext: ModelContext
    ) {
        self.shellStore = shellStore
        self.resolveCurrentAccount = resolveCurrentAccount
        self._nftService = nftService
        self.router = router
        self.audioEngine = audioEngine
        self.audioUnavailableMessage = audioUnavailableMessage
        self.modeState = modeState
        self.services = services

        let homePinnedItemsStore = services.homePinnedItemsStoreFactory()
        self.homePinnedItemsStore = homePinnedItemsStore

        let libraryContextProvider = services.libraryContextProviderFactory(modelContext)
        _pinnedItemCount = State(
            initialValue: homePinnedItemsStore.pinnedCount(
                for: shellStore.state.selection?.address ?? ""
            )
        )
        _contextService = State(
            initialValue: services.contextServiceBuilder.makeContextService(
                accountProvider: { resolveCurrentAccount() },
                addressProvider: { shellStore.state.selection?.address ?? "" },
                chainProvider: { shellStore.state.selection?.chain ?? .ethMainnet },
                modeProvider: { modeState.mode },
                loadingProvider: { nftService.wrappedValue.isLoading },
                refreshedAtProvider: {
                    let activeAddress = resolveCurrentAccount()?.address
                        ?? shellStore.state.selection?.address
                        ?? ""
                    return nftService.wrappedValue.lastSuccessfulRefreshAt(
                        for: activeAddress,
                        chain: shellStore.state.selection?.chain ?? .ethMainnet
                    )
                },
                nativeBalanceProvider: services.readOnlyProviderFactory.makeNativeBalanceProvider(),
                freshnessTTLProvider: { nftService.wrappedValue.refreshTTL },
                trackedNFTCountProvider: { resolveCurrentAccount()?.trackedNFTCount },
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
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            chromeContainer
            tabContent
        }
        .background {
            chromeBackground
        }
        .sheet(isPresented: $showAccountSwitcher) {
            AccountSwitcherSheet(
                currentAccount: currentAccount,
                activeSelection: shellStore.state.selection,
                accountStoreFactory: services.accountStoreFactory,
                onSelectAccount: selectAccount,
                onRemoveAccount: removeAccount,
                onCurrentChainChange: changeCurrentChain
            )
        }
        .sheet(isPresented: $showContextInspector) {
            ChromeContextInspectorSheet(
                contextService: contextService,
                onRefreshContext: refreshActiveScopeFromUserAction,
                onOpenReceipt: { receiptID in
                    showContextInspector = false
                    router.showReceipt(id: receiptID)
                }
            )
        }
        .task(id: contextRemoteRefreshKey) {
            let correlationID = nftService.isLoading ? nil : shellStore.state.pendingCorrelationID
            await contextService.refresh(
                correlationID: correlationID,
                receiptEventLogger: services.receiptEventLoggerFactory(modelContext),
                strategy: .remoteAllowed
            )
            if !nftService.isLoading {
                await shellStore.send(.pendingCorrelationConsumed(correlationID))
            }
        }
        .task(id: contextLocalRefreshKey) {
            await contextService.refresh(strategy: .reuseCachedBalance)
        }
        .modeState(modeState)
    }

    private var chromeContainer: some View {
        GlobalChromeView(
            snapshot: contextService.snapshot,
            onOpenAccountSwitcher: { showAccountSwitcher = true },
            onOpenContextInspector: contextInspectorAction,
            onOpenSearch: { router.showSearch() }
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var contextInspectorAction: (() -> Void)? {
        { showContextInspector = true }
    }

    private func selectAccount(_ address: String) {
        Task {
            await shellStore.send(
                .accountSelectionRequested(
                    address: address,
                    correlationID: UUID().uuidString
                )
            )
        }
    }

    private func removeAccount(_ address: String) {
        Task {
            await shellStore.send(
                .activeAccountRemovalRequested(
                    address: address,
                    correlationID: UUID().uuidString
                )
            )
        }
    }

    private func changeCurrentChain(_ chain: Chain) {
        Task {
            await shellStore.send(
                .chainChangeRequested(
                    chain: chain,
                    correlationID: UUID().uuidString
                )
            )
        }
    }

    @MainActor
    private func refreshActiveScopeFromUserAction() async {
        await shellStore.send(
            .refreshCurrentSelectionRequested(
                correlationID: UUID().uuidString
            )
        )
    }

    private var tabContent: some View {
        TabView(selection: $router.selectedTab) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                HomeTabView(
                    shellStore: shellStore,
                    currentAccount: currentAccount,
                    currentAddress: currentAddress,
                    currentChain: currentChain,
                    contextSnapshot: contextService.snapshot,
                    router: router,
                    ensResolver: services.ensResolverFactory(modelContext),
                    services: services,
                    pinnedItemsStore: homePinnedItemsStore,
                    pinnedItemCountBinding: $pinnedItemCount
                )
            }

            Tab("NewsFeed", systemImage: "bubble.right", value: AppTab.news) {
                NavigationStack(path: $router.newsPath) {
                    NewsFeedView(
                        currentAccount: readOnlyAccountBinding,
                        nftService: $nftService,
                        currentChain: readOnlyChainBinding,
                        refreshAction: refreshActiveScopeFromUserAction,
                        router: router
                    )
                    .navigationDestination(for: NFTDetailRoute.self) { route in
                        SharedNFTDetailView(
                            route: route,
                            currentAccountAddress: currentAccount?.address,
                            currentChain: currentChain
                        )
                    }
                }
                .accessibilityIdentifier("tab.news")
            }

            Tab("Gas", systemImage: "fuelpump", value: AppTab.gas) {
                AuraScenicScreen {
                    GasPriceEstimateView(chain: readOnlyChainBinding)
                }
            }

            Tab("Music", systemImage: "play.circle", value: AppTab.music) {
                NavigationStack(path: $router.musicPath) {
                    Group {
                        if let audioEngine {
                            VStack {
                                NFTMusicPlayerApp(
                                    audioEngine: audioEngine,
                                    currentAccount: currentAccount,
                                    currentChain: currentChain,
                                    nftService: nftService,
                                    refreshAction: refreshActiveScopeFromUserAction,
                                    onOpenNFT: { nft in
                                        router.showMusicNFTDetail(id: nft.id)
                                    },
                                    onOpenCollection: { summary in
                                        router.showMusicCollectionDetail(
                                            key: summary.key,
                                            title: summary.title
                                        )
                                    },
                                    musicLibraryIndexer: services.musicLibraryIndexerFactory(modelContext),
                                    musicLibraryReceiptLogger: services.receiptEventLoggerFactory(modelContext)
                                )
                            }
                            .navigationDestination(for: MusicRoute.self) { route in
                                switch route {
                                case .item(let id):
                                    MusicItemDetailView(
                                        itemID: id,
                                        currentAccountAddress: currentAccount?.address,
                                        currentChain: currentChain,
                                        onOpenCollection: { summary in
                                            router.showMusicCollectionDetail(
                                                key: summary.key,
                                                title: summary.title
                                            )
                                        }
                                    )

                                case .collection(let key, let title):
                                    MusicCollectionDetailView(
                                        collectionKey: key,
                                        collectionTitle: title,
                                        currentAccountAddress: currentAccount?.address,
                                        currentChain: currentChain,
                                        onOpenItem: { itemID in
                                            router.showMusicNFTDetail(id: itemID)
                                        }
                                    )
                                }
                            }
                        } else {
                            AuraScenicScreen(contentAlignment: .center) {
                                ContentUnavailableView(
                                    "Music Unavailable",
                                    systemImage: "speaker.slash",
                                    description: Text(audioUnavailableMessage ?? "Auralis could not start audio playback on this launch. The rest of the app remains available.")
                                )
                            }
                        }
                    }
                }
                .accessibilityIdentifier("tab.music")
            }

            Tab("Receipts", systemImage: "doc.text", value: AppTab.receipts) {
                NavigationStack(path: $router.receiptsPath) {
                    ReceiptsRootView(
                        currentAddress: activeAccountAddress,
                        currentChain: currentChain
                    )
                    .navigationDestination(for: ReceiptRoute.self) { route in
                        ReceiptDetailView(
                            route: route,
                            scope: ReceiptTimelineScope(
                                accountAddress: activeAccountAddress,
                                chain: currentChain
                            )
                        )
                    }
                }
                .accessibilityIdentifier("tab.receipts")
            }

            Tab("Profile", systemImage: "person.circle", value: AppTab.profile) {
                NavigationStack(path: $router.profilePath) {
                    ProfileDetailView(
                        accountAddress: activeAccountAddress,
                        currentChain: currentChain,
                        isCurrentAccount: true,
                        showsPolicySection: true,
                        modeState: modeState,
                        services: services,
                        onOpenSettings: router.showSettings
                    )
                    .navigationDestination(for: ProfileRoute.self) { route in
                        switch route {
                        case .detail(let address):
                            ProfileDetailView(
                                accountAddress: address,
                                currentChain: currentChain,
                                isCurrentAccount: address == activeAccountAddress
                            )

                        case .settings:
                            SettingsView(
                                currentAccountAddress: activeAccountAddress,
                                currentChain: currentChain,
                                services: services
                            )
                        }
                    }
                }
            }

            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                SearchRootView(
                    router: router,
                    currentAccountAddress: activeAccountAddress,
                    currentChain: currentChain,
                    historyStore: services.searchHistoryStoreFactory(modelContext)
                )
            }

            Tab("ERC-20", systemImage: "dollarsign.circle", value: AppTab.erc20Tokens) {
                NavigationStack(path: $router.erc20TokensPath) {
                    ERC20TokensRootView(
                        currentAccountAddress: activeAccountAddress,
                        currentChain: currentChain,
                        contextSnapshot: contextService.snapshot,
                        nftService: nftService,
                        refreshAction: refreshActiveScopeFromUserAction,
                        router: router,
                        tokenHoldingsStoreFactory: services.tokenHoldingsStoreFactory,
                        tokenHoldingsProviderFactory: services.tokenHoldingsProviderFactory
                    )
                    .navigationDestination(for: ERC20TokenRoute.self) { route in
                        ERC20TokenDetailView(
                            route: route,
                            currentAccountAddress: activeAccountAddress
                        )
                    }
                }
                .accessibilityIdentifier("tab.erc20")
            }

            Tab("NFTs", systemImage: "square.stack", value: AppTab.nftTokens) {
                NavigationStack(path: $router.nftTokensPath) {
                    NFTTokensRootView(
                        currentAccount: currentAccount,
                        currentChain: currentChain,
                        contextSnapshot: contextService.snapshot,
                        nftService: nftService,
                        refreshAction: refreshActiveScopeFromUserAction,
                        router: router
                    )
                    .navigationDestination(for: NFTTokensRoute.self) { route in
                        switch route {
                        case .item(let id):
                            SharedNFTDetailView(
                                route: .detail(id: id),
                                currentAccountAddress: currentAccount?.address,
                                currentChain: currentChain
                            )

                        case .collection:
                            NFTCollectionDetailView(
                                route: route,
                                currentAccountAddress: currentAccount?.address,
                                currentChain: currentChain,
                                onOpenItem: { itemID in
                                    router.showNFTTokensDetail(id: itemID)
                                }
                            )
                        }
                    }
                }
                .accessibilityIdentifier("tab.nftTokens")
            }
        }
        .tint(.accent)
    }

    @ViewBuilder
    private var chromeBackground: some View {
        switch router.selectedTab {
        case .home, .gas:
            GatewayBackgroundImage()
                .ignoresSafeArea()
            Color.background.opacity(0.3)
                .ignoresSafeArea()

        default:
            Color.background
                .ignoresSafeArea()
        }
    }

    private var readOnlyAccountBinding: Binding<EOAccount?> {
        Binding(
            get: { currentAccount },
            set: { _ in }
        )
    }

    private var readOnlyChainBinding: Binding<Chain> {
        Binding(
            get: { currentChain },
            set: { _ in }
        )
    }
}

private struct ContextRemoteRefreshKey: Hashable {
    let accountAddress: String
    let chain: Chain
    let mode: AppMode
    let isLoading: Bool
    let refreshedAt: Date?
}

private struct ContextLocalRefreshKey: Hashable {
    let trackedNFTCount: Int?
    let pinnedItemCount: Int
}

#Preview {
    struct Wrapper: View {
        @Environment(\.modelContext) private var modelContext
        @State private var nftService = NFTService()
        @State private var router = AppRouter()
        let audioEngine: AudioEngine? = try? AudioEngine()
        @StateObject private var modeState = ModeState()
        private let services = ShellServiceHub.live
        private let shellStore = ShellStore.preview(
            selection: ActiveShellSelection(
                address: "0xpreview0000000000000000000000000000000000",
                chain: .ethMainnet
            )
        )

        var body: some View {
            MainTabView(
                shellStore: shellStore,
                resolveCurrentAccount: { nil },
                nftService: $nftService,
                router: router,
                audioEngine: audioEngine,
                audioUnavailableMessage: nil,
                modeState: modeState,
                services: services,
                modelContext: modelContext
            )
        }
    }

    return Wrapper()
}
