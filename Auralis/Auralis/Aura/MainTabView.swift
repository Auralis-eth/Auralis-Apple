import OSLog
import Observation
import SwiftData
import SwiftUI

struct MainTabView: View {
    private let logger = Logger(subsystem: "Auralis", category: "MainTabView")
    @Environment(\.modelContext) private var modelContext
    @Binding var currentAccount: EOAccount?
    @Binding var currentAddress: String
    @Binding var currentChainId: String
    @Binding var currentChain: Chain
    @Binding var nftService: NFTService
    @Binding var pendingShellFlowCorrelationID: String?
    @Bindable var router: AppRouter
    let audioEngine: AudioEngine?
    let audioUnavailableMessage: String?
    let modeState: ModeState
    let services: ShellServiceHub
    private let homePinnedItemsStore: HomePinnedItemsStore
    @State private var showAccountSwitcher = false
    @State private var showContextInspector = false
    @State private var contextService: ContextService
    @State private var pinnedItemCount: Int
    @State private var feedbackAlert: MainTabAlert?

    private var contextRefreshKey: ContextRefreshKey {
        ContextRefreshKey(
            accountAddress: currentAccount?.address ?? currentAddress,
            chain: currentChain,
            mode: modeState.mode,
            isLoading: nftService.isLoading,
            refreshedAt: nftService.lastSuccessfulRefreshAt,
            trackedNFTCount: currentAccount?.trackedNFTCount,
            pinnedItemCount: pinnedItemCount
        )
    }

    init(
        currentAccount: Binding<EOAccount?>,
        currentAddress: Binding<String>,
        currentChainId: Binding<String>,
        currentChain: Binding<Chain>,
        nftService: Binding<NFTService>,
        pendingShellFlowCorrelationID: Binding<String?>,
        router: AppRouter,
        audioEngine: AudioEngine?,
        audioUnavailableMessage: String?,
        modeState: ModeState,
        services: ShellServiceHub,
        modelContext: ModelContext
    ) {
        self._currentAccount = currentAccount
        self._currentAddress = currentAddress
        self._currentChainId = currentChainId
        self._currentChain = currentChain
        self._nftService = nftService
        self._pendingShellFlowCorrelationID = pendingShellFlowCorrelationID
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
                for: currentAddress.wrappedValue
            )
        )
        _contextService = State(
            initialValue: services.contextServiceBuilder.makeContextService(
                accountProvider: { currentAccount.wrappedValue },
                addressProvider: { currentAddress.wrappedValue },
                chainProvider: { currentChain.wrappedValue },
                modeProvider: { modeState.mode },
                loadingProvider: { nftService.wrappedValue.isLoading },
                refreshedAtProvider: { nftService.wrappedValue.lastSuccessfulRefreshAt },
                nativeBalanceProvider: services.readOnlyProviderFactory.makeNativeBalanceProvider(),
                freshnessTTLProvider: { nftService.wrappedValue.refreshTTL },
                trackedNFTCountProvider: { currentAccount.wrappedValue?.trackedNFTCount },
                musicCollectionCountProvider: {
                    libraryContextProvider.playlistCount()
                },
                receiptCountProvider: {
                    libraryContextProvider.receiptCount(
                        scope: ReceiptTimelineScope(
                            accountAddress: currentAddress.wrappedValue,
                            chain: currentChain.wrappedValue
                        )
                    )
                },
                pinnedActionsProvider: {
                    Array(
                        homePinnedItemsStore.pinnedActions(for: currentAddress.wrappedValue)
                    )
                    .sorted { $0.rawValue < $1.rawValue }
                },
                prefersDemoDataProvider: {
                    currentAccount.wrappedValue?.source == .guestPass
                },
                pinnedItemCountProvider: {
                    homePinnedItemsStore.pinnedCount(
                        for: currentAddress.wrappedValue
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
                currentAccount: $currentAccount,
                currentAddress: $currentAddress,
                currentChain: $currentChain,
                accountStoreFactory: services.accountStoreFactory,
                onAccountSelectionStarted: { correlationID in
                    pendingShellFlowCorrelationID = correlationID
                },
                onCurrentChainChanged: refreshActiveChainScope
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
        .task(id: contextRefreshKey) {
            let correlationID = nftService.isLoading ? nil : pendingShellFlowCorrelationID
            await contextService.refresh(
                correlationID: correlationID,
                receiptEventLogger: services.receiptEventLoggerFactory(modelContext)
            )
            if !nftService.isLoading, pendingShellFlowCorrelationID == correlationID {
                pendingShellFlowCorrelationID = nil
            }
        }
        .onChange(of: currentAccount) { _, newAccount in
            if let acct = newAccount {
                currentChain = acct.currentChain
                currentChainId = acct.currentChain.rawValue
            }
        }
        .onChange(of: currentChain) { _, newValue in
            guard let currentAccount, currentAccount.currentChain != newValue else {
                currentChainId = newValue.rawValue
                return
            }

            persistCurrentChainSelection(newValue, for: currentAccount)
        }
        .alert(
            feedbackAlert?.title ?? "",
            isPresented: Binding(
                get: { feedbackAlert != nil },
                set: { isPresented in
                    if !isPresented {
                        feedbackAlert = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                feedbackAlert = nil
            }
        } message: {
            if let message = feedbackAlert?.message {
                Text(message)
            }
        }
        .modeState(modeState)
    }

    private var chromeContainer: some View {
        GlobalChromeView(
            snapshot: contextService.snapshot,
            onOpenAccountSwitcher: { showAccountSwitcher = true },
            onOpenContextInspector: { showContextInspector = true },
            onOpenSearch: { router.showSearch() }
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private func persistCurrentChainSelection(_ newValue: Chain, for account: EOAccount) {
        let previousChain = account.currentChain
        let previousChainId = currentChainId

        currentChainId = newValue.rawValue
        account.currentChain = newValue

        do {
            try modelContext.save()
        } catch {
            account.currentChain = previousChain
            currentChain = previousChain
            currentChainId = previousChainId
            logger.error(
                "Failed to persist current chain change address=\(account.address, privacy: .public) from=\(previousChain.rawValue, privacy: .public) to=\(newValue.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            feedbackAlert = MainTabAlert(
                title: "Chain Change Failed",
                message: "Auralis could not save the selected chain. Your previous chain is still active."
            )
        }
    }

    @MainActor
    private func refreshActiveChainScope(_ chain: Chain, correlationID: String) {
        guard let activeAccount = currentAccount else {
            return
        }

        Task {
            pendingShellFlowCorrelationID = correlationID
            await nftService.refreshNFTs(
                for: activeAccount,
                chain: chain,
                modelContext: modelContext,
                correlationID: correlationID
            )
        }
    }

    @MainActor
    private func refreshActiveScopeFromUserAction() async {
        let correlationID = UUID().uuidString
        pendingShellFlowCorrelationID = correlationID
        await nftService.refreshNFTs(
            for: currentAccount,
            chain: currentChain,
            modelContext: modelContext,
            correlationID: correlationID
        )
    }

    private var tabContent: some View {
        TabView(selection: $router.selectedTab) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                HomeTabView(
                    currentAccount: $currentAccount,
                    currentAddress: $currentAddress,
                    currentChainId: $currentChainId,
                    currentChain: $currentChain,
                    contextSnapshot: contextService.snapshot,
                    onCurrentChainChanged: refreshActiveChainScope,
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
                        currentAccount: $currentAccount,
                        nftService: $nftService,
                        currentChain: $currentChain,
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
                    GasPriceEstimateView(chain: $currentChain)
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
                        currentAddress: currentAccount?.address ?? currentAddress,
                        currentChain: currentChain
                    )
                        .navigationDestination(for: ReceiptRoute.self) { route in
                            ReceiptDetailView(
                                route: route,
                                scope: ReceiptTimelineScope(
                                    accountAddress: currentAccount?.address ?? currentAddress,
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
                        accountAddress: currentAccount?.address ?? currentAddress,
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
                                isCurrentAccount: address == (currentAccount?.address ?? currentAddress)
                            )
                        case .settings:
                            SettingsView(
                                currentAccountAddress: currentAccount?.address ?? currentAddress,
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
                    currentAccountAddress: currentAccount?.address ?? currentAddress,
                    currentChain: currentChain,
                    historyStore: services.searchHistoryStoreFactory()
                )
            }

            Tab("ERC-20", systemImage: "dollarsign.circle", value: AppTab.erc20Tokens) {
                NavigationStack(path: $router.erc20TokensPath) {
                    ERC20TokensRootView(
                        currentAccountAddress: currentAccount?.address ?? currentAddress,
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
                                currentAccountAddress: currentAccount?.address ?? currentAddress
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
}

private struct MainTabAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct ContextRefreshKey: Hashable {
    let accountAddress: String
    let chain: Chain
    let mode: AppMode
    let isLoading: Bool
    let refreshedAt: Date?
    let trackedNFTCount: Int?
    let pinnedItemCount: Int
}

#Preview {
    struct Wrapper: View {
        @Environment(\.modelContext) private var modelContext
        @State private var currentAccount: EOAccount? = nil
        @State private var currentAddress: String = ""
        @State private var currentChainId: String = Chain.ethMainnet.rawValue
        @State private var currentChain: Chain = .ethMainnet
        @State private var nftService = NFTService()
        @State private var pendingShellFlowCorrelationID: String?
        @State private var router = AppRouter()
        let audioEngine: AudioEngine? = try? AudioEngine()
        @StateObject private var modeState = ModeState()
        private let services = ShellServiceHub.live

        var body: some View {
            MainTabView(
                currentAccount: $currentAccount,
                currentAddress: $currentAddress,
                currentChainId: $currentChainId,
                currentChain: $currentChain,
                nftService: $nftService,
                pendingShellFlowCorrelationID: $pendingShellFlowCorrelationID,
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
