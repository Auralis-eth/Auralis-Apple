import AccountsFeature
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import AuralisShellCore
import MusicFeature
import Observation
import PolicyCore
import ReceiptsCore
import ReceiptStorage
import SwiftData
import SwiftUI
import AuraUI
import NFTDomain
import NFTPersistence
import NFTPresentation
import NFTProviderAdapters

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext

    let shellStore: ShellStore
    let resolveCurrentAccount: @MainActor () -> EOAccount?
    @Binding var nftService: NFTService
    @Bindable var router: AppRouter
    let audioEngine: AudioEngine?
    let musicUnavailableMessage: String?
    let showsMusicReinstallGuidance: Bool
    let retryMusicSetup: @MainActor () async -> Void
    let modeState: ModeState
    let dependencies: MainTabDependencies
    let auraPlayModelContainer: ModelContainer?
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
            trackedNFTCount: trackedNFTCount,
            pinnedItemCount: pinnedItemCount
        )
    }

    private var trackedNFTCount: Int? {
        currentAccount?.trackedNFTCount
    }

    init(
        shellStore: ShellStore,
        resolveCurrentAccount: @escaping @MainActor () -> EOAccount?,
        nftService: Binding<NFTService>,
        router: AppRouter,
        audioEngine: AudioEngine?,
        musicUnavailableMessage: String?,
        showsMusicReinstallGuidance: Bool,
        retryMusicSetup: @escaping @MainActor () async -> Void,
        modeState: ModeState,
        dependencies: MainTabDependencies,
        auraPlayModelContainer: ModelContainer?
    ) {
        self.shellStore = shellStore
        self.resolveCurrentAccount = resolveCurrentAccount
        self._nftService = nftService
        self.router = router
        self.audioEngine = audioEngine
        self.musicUnavailableMessage = musicUnavailableMessage
        self.showsMusicReinstallGuidance = showsMusicReinstallGuidance
        self.retryMusicSetup = retryMusicSetup
        self.modeState = modeState
        self.dependencies = dependencies
        self.auraPlayModelContainer = auraPlayModelContainer

        let homePinnedItemsStore = dependencies.homePinnedItemsStore
        self.homePinnedItemsStore = homePinnedItemsStore

        _pinnedItemCount = State(
            initialValue: homePinnedItemsStore.pinnedCount(
                for: shellStore.state.selection?.address ?? ""
            )
        )
        _contextService = State(
            initialValue: dependencies.makeContextService(
                shellStore: shellStore,
                resolveCurrentAccount: resolveCurrentAccount,
                modeState: modeState,
                nftServiceProvider: { nftService.wrappedValue }
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
            AccountSwitcherHostSheet(
                currentAccount: currentAccount,
                activeSelection: shellStore.state.selection,
                accountStoreFactory: dependencies.accountStoreFactory,
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
        .sheet(item: auxiliarySurfaceBinding) { auxiliarySurface in
            auxiliarySurfaceView(for: auxiliarySurface)
        }
        .task(id: contextRemoteRefreshKey) {
            let correlationID = nftService.isLoading ? nil : shellStore.state.pendingCorrelationID
            await contextService.refresh(
                correlationID: correlationID,
                receiptEventLogger: dependencies.receiptEventLoggerFactory(modelContext),
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

    private func changeCurrentChain(_ chain: Chain, correlationID: String) async throws {
        await shellStore.send(.routeErrorDismissed)
        await shellStore.send(
            .chainChangeRequested(
                chain: chain,
                correlationID: correlationID
            )
        )

        guard shellStore.state.routeError == nil,
              shellStore.state.selection?.chain == chain
        else {
            throw AccountSwitcherCurrentChainChangeError(
                message: shellStore.state.routeError?.message
                    ?? "Auralis could not save the selected chain."
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
                    ensResolver: dependencies.ensResolver,
                    accountStoreFactory: dependencies.accountStoreFactory,
                    logoutCleanupServiceFactory: dependencies.logoutCleanupServiceFactory,
                    pinnedItemsStore: dependencies.homePinnedItemsStore,
                    pinnedItemCountBinding: $pinnedItemCount
                )
            }
            .accessibilityIdentifier("tab.home")

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
                    GasPriceEstimateView(
                        chain: readOnlyChainBinding,
                        provider: dependencies.gasPricingProvider
                    )
                }
            }
            .accessibilityIdentifier("tab.gas")

            Tab("Music", systemImage: "play.circle", value: AppTab.music) {
                NavigationStack(path: $router.musicPath) {
                    Group {
                        if let audioEngine, let auraPlayModelContainer {
                            VStack {
                                MusicFeatureRootView(
                                    currentAccount: currentAccount,
                                    currentChain: currentChain,
                                    dependencies: dependencies.makeMusicFeatureDependencies(
                                        audioEngine: audioEngine,
                                        auraPlayModelContainer: auraPlayModelContainer,
                                        accountModelContext: modelContext
                                    )
                                )
                            }
                            .navigationDestination(for: MusicRoute.self) { route in
                                switch route {
                                case .item(let id):
                                    AuraPlayMusicItemDetailView(
                                        itemID: id,
                                        currentAccountAddress: currentAccount?.address,
                                        currentChain: currentChain,
                                        onOpenCollection: { key, title in
                                            router.showMusicCollectionDetail(
                                                key: key,
                                                title: title
                                            )
                                        }
                                    )

                                case .collection(let key, let title):
                                    AuraPlayMusicCollectionDetailView(
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
                            AuraPlayUnavailableView(
                                message: musicUnavailableMessage,
                                showsReinstallGuidance: showsMusicReinstallGuidance,
                                retryAction: retryMusicSetup
                            )
                        }
                    }
                }
                .accessibilityIdentifier("tab.music")
            }

            if router.tabBarVisibility.showsInTabBar(.receipts) {
                Tab("Receipts", systemImage: "doc.text", value: AppTab.receipts) {
                    receiptsNavigationStack
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
                        policyActionHandlerFactory: dependencies.policyActionHandlerFactory,
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
                                privacyResetServiceFactory: dependencies.privacyResetServiceFactory,
                                auraPlayModelContainer: auraPlayModelContainer,
                                onPrivacyResetCompleted: {
                                    await shellStore.send(.logoutRequested)
                                }
                            )
                        }
                    }
                }
            }
            .accessibilityIdentifier("tab.profile")

            if router.tabBarVisibility.showsInTabBar(.search) {
                Tab("Search", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                    searchRootView
                }
                .accessibilityIdentifier("tab.search")
            }

            if router.tabBarVisibility.showsInTabBar(.erc20Tokens) {
                Tab("ERC-20", systemImage: "dollarsign.circle", value: AppTab.erc20Tokens) {
                    erc20NavigationStack
                }
                .accessibilityIdentifier("tab.erc20")
            }

            if router.tabBarVisibility.showsInTabBar(.nftTokens) {
                Tab("NFTs", systemImage: "square.stack", value: AppTab.nftTokens) {
                    nftTokensNavigationStack
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

    private var auxiliarySurfaceBinding: Binding<AuxiliarySurface?> {
        Binding(
            get: { router.auxiliarySurface },
            set: { newValue in
                if let newValue {
                    router.auxiliarySurface = newValue
                } else {
                    router.dismissAuxiliarySurface(resetPaths: true)
                }
            }
        )
    }

    private var searchRootView: some View {
        SearchRootView(
            router: router,
            currentAccountAddress: activeAccountAddress,
            currentChain: currentChain,
            historyStore: dependencies.searchHistoryStore
        )
    }

    private var receiptsNavigationStack: some View {
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
    }

    private var erc20NavigationStack: some View {
        NavigationStack(path: $router.erc20TokensPath) {
            ERC20TokensRootView(
                currentAccountAddress: activeAccountAddress,
                currentChain: currentChain,
                contextSnapshot: contextService.snapshot,
                nftService: nftService,
                refreshAction: refreshActiveScopeFromUserAction,
                router: router,
                holdingsSyncerFactory: dependencies.erc20HoldingsSyncerFactory
            )
            .navigationDestination(for: ERC20TokenRoute.self) { route in
                ERC20TokenDetailView(
                    route: route,
                    currentAccountAddress: activeAccountAddress
                )
            }
        }
    }

    private var nftTokensNavigationStack: some View {
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
    }

    @ViewBuilder
    private func auxiliarySurfaceView(for auxiliarySurface: AuxiliarySurface) -> some View {
        switch auxiliarySurface {
        case .search:
            NavigationStack {
                searchRootView
                    .toolbar {
                        auxiliaryDismissToolbar
                    }
            }
        case .receipts:
            receiptsNavigationStack
                .toolbar {
                    auxiliaryDismissToolbar
                }
        case .nftTokens:
            nftTokensNavigationStack
                .toolbar {
                    auxiliaryDismissToolbar
                }
        case .erc20Token:
            auxiliaryERC20NavigationStack
                .toolbar {
                    auxiliaryDismissToolbar
                }
        }
    }

    private var auxiliaryERC20NavigationStack: some View {
        NavigationStack(path: $router.erc20TokensPath) {
            Color.clear
                .navigationDestination(for: ERC20TokenRoute.self) { route in
                    ERC20TokenDetailView(
                        route: route,
                        currentAccountAddress: activeAccountAddress
                    )
                }
                .task {
                    if router.erc20TokensPath.isEmpty {
                        router.dismissAuxiliarySurface(resetPaths: true)
                    }
                }
        }
    }

    @ToolbarContentBuilder
    private var auxiliaryDismissToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close") {
                router.dismissAuxiliarySurface(resetPaths: true)
            }
        }
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

private struct MainTabPreviewWrapper: View {
    @Environment(\.modelContext) private var modelContext
    @State private var nftService = NFTService()
    @State private var router = AppRouter()
    let initialTab: AppTab
    let showsSettings: Bool
    let audioEngine: AudioEngine? = try? AudioEngine()
    @State private var modeState = ModeState()
    private let auraPlayModelContainer = PreviewModelContainers.auraPlay()
    private let shellStore = ShellStore.preview(
        selection: ActiveShellSelection(
            address: "0xpreview0000000000000000000000000000000000",
            chain: .ethMainnet
        )
    )

    init(initialTab: AppTab = .home, showsSettings: Bool = false) {
        self.initialTab = initialTab
        self.showsSettings = showsSettings
    }

    var body: some View {
        MainTabView(
            shellStore: shellStore,
            resolveCurrentAccount: { nil },
            nftService: $nftService,
            router: router,
            audioEngine: audioEngine,
            musicUnavailableMessage: nil,
            showsMusicReinstallGuidance: false,
            retryMusicSetup: {},
            modeState: modeState,
            dependencies: AppEnvironment.live.mainTabs.makeMainTabDependencies(modelContext: modelContext),
            auraPlayModelContainer: auraPlayModelContainer
        )
        .onAppear {
            router.selectedTab = initialTab
            if showsSettings {
                router.profilePath = [.settings]
            }
        }
    }
}

#Preview {
    MainTabPreviewWrapper()
        .modelContainer(PreviewModelContainers.primary())
}

#Preview("Large Text") {
    MainTabPreviewWrapper()
        .environment(\.dynamicTypeSize, .accessibility5)
        .modelContainer(PreviewModelContainers.primary())
}

#Preview("Dark Mode") {
    MainTabPreviewWrapper()
        .preferredColorScheme(.dark)
        .modelContainer(PreviewModelContainers.primary())
}

#Preview("Search Large Text") {
    MainTabPreviewWrapper(initialTab: .search)
        .environment(\.dynamicTypeSize, .accessibility5)
        .modelContainer(PreviewModelContainers.primary())
}

#Preview("Search Dark Mode") {
    MainTabPreviewWrapper(initialTab: .search)
        .preferredColorScheme(.dark)
        .modelContainer(PreviewModelContainers.primary())
}

// NOTE: `accessibilityReduceMotion`, `accessibilityReduceTransparency`, and
// `colorSchemeContrast` are read-only environment values in SwiftUI; they
// cannot be forced via `.environment(...)`. The previews below cover the
// dynamic type / color scheme axes only. Verify Reduce Motion, Reduce
// Transparency, and Increase Contrast on a physical device via
// Settings > Accessibility.
#Preview("Home Large Text (verify Increase Contrast on device)") {
    MainTabPreviewWrapper(initialTab: .home)
        .environment(\.dynamicTypeSize, .accessibility5)
        .modelContainer(PreviewModelContainers.primary())
}

#Preview("Home (verify Reduce Motion + Transparency on device)") {
    MainTabPreviewWrapper(initialTab: .home)
        .modelContainer(PreviewModelContainers.primary())
}

#Preview("Home (verify Reduce Transparency on device)") {
    MainTabPreviewWrapper(initialTab: .home)
        .modelContainer(PreviewModelContainers.primary())
}

#Preview("Home Light (verify Increase Contrast on device)") {
    MainTabPreviewWrapper(initialTab: .home)
        .preferredColorScheme(.light)
        .modelContainer(PreviewModelContainers.primary())
}

#Preview("Search Large Text (verify Increase Contrast on device)") {
    MainTabPreviewWrapper(initialTab: .search)
        .environment(\.dynamicTypeSize, .accessibility5)
        .modelContainer(PreviewModelContainers.primary())
}

#Preview("Search (verify Reduce Motion + Transparency on device)") {
    MainTabPreviewWrapper(initialTab: .search)
        .modelContainer(PreviewModelContainers.primary())
}

#Preview("Search (verify Reduce Transparency on device)") {
    MainTabPreviewWrapper(initialTab: .search)
        .modelContainer(PreviewModelContainers.primary())
}

#Preview("Search Light (verify Increase Contrast on device)") {
    MainTabPreviewWrapper(initialTab: .search)
        .preferredColorScheme(.light)
        .modelContainer(PreviewModelContainers.primary())
}

#Preview("NewsFeed Large Text") {
    MainTabPreviewWrapper(initialTab: .news)
        .environment(\.dynamicTypeSize, .accessibility5)
        .modelContainer(PreviewModelContainers.primary())
}

#Preview("NewsFeed Dark Mode") {
    MainTabPreviewWrapper(initialTab: .news)
        .preferredColorScheme(.dark)
        .modelContainer(PreviewModelContainers.primary())
}

#Preview("Gas Large Text") {
    MainTabPreviewWrapper(initialTab: .gas)
        .environment(\.dynamicTypeSize, .accessibility5)
        .modelContainer(PreviewModelContainers.primary())
}

#Preview("Gas Dark Mode") {
    MainTabPreviewWrapper(initialTab: .gas)
        .preferredColorScheme(.dark)
        .modelContainer(PreviewModelContainers.primary())
}

#Preview("Gas Large Text (verify Increase Contrast on device)") {
    MainTabPreviewWrapper(initialTab: .gas)
        .environment(\.dynamicTypeSize, .accessibility5)
        .modelContainer(PreviewModelContainers.primary())
}

#Preview("Gas (verify Reduce Motion + Transparency on device)") {
    MainTabPreviewWrapper(initialTab: .gas)
        .modelContainer(PreviewModelContainers.primary())
}

#Preview("Gas (verify Reduce Transparency on device)") {
    MainTabPreviewWrapper(initialTab: .gas)
        .modelContainer(PreviewModelContainers.primary())
}

#Preview("Gas Light (verify Increase Contrast on device)") {
    MainTabPreviewWrapper(initialTab: .gas)
        .preferredColorScheme(.light)
        .modelContainer(PreviewModelContainers.primary())
}

#Preview("Music Large Text") {
    MainTabPreviewWrapper(initialTab: .music)
        .environment(\.dynamicTypeSize, .accessibility5)
        .modelContainer(PreviewModelContainers.primary())
}

#Preview("Music Dark Mode") {
    MainTabPreviewWrapper(initialTab: .music)
        .preferredColorScheme(.dark)
        .modelContainer(PreviewModelContainers.primary())
}

#Preview("Music Large Text (verify Increase Contrast on device)") {
    MainTabPreviewWrapper(initialTab: .music)
        .environment(\.dynamicTypeSize, .accessibility5)
        .modelContainer(PreviewModelContainers.primary())
}

#Preview("Music (verify Reduce Motion + Transparency on device)") {
    MainTabPreviewWrapper(initialTab: .music)
        .modelContainer(PreviewModelContainers.primary())
}

#Preview("Music (verify Reduce Transparency on device)") {
    MainTabPreviewWrapper(initialTab: .music)
        .modelContainer(PreviewModelContainers.primary())
}

#Preview("Music Light (verify Increase Contrast on device)") {
    MainTabPreviewWrapper(initialTab: .music)
        .preferredColorScheme(.light)
        .modelContainer(PreviewModelContainers.primary())
}

#Preview("NFT Detail Large Text") {
    MainTabPreviewWrapper(initialTab: .nftTokens)
        .environment(\.dynamicTypeSize, .accessibility5)
        .modelContainer(PreviewModelContainers.primary())
}

#Preview("NFT Detail Dark Mode") {
    MainTabPreviewWrapper(initialTab: .nftTokens)
        .preferredColorScheme(.dark)
        .modelContainer(PreviewModelContainers.primary())
}

#Preview("Receipts Large Text") {
    MainTabPreviewWrapper(initialTab: .receipts)
        .environment(\.dynamicTypeSize, .accessibility5)
        .modelContainer(PreviewModelContainers.primary())
}

#Preview("Receipts Dark Mode") {
    MainTabPreviewWrapper(initialTab: .receipts)
        .preferredColorScheme(.dark)
        .modelContainer(PreviewModelContainers.primary())
}

#Preview("Settings Large Text") {
    MainTabPreviewWrapper(initialTab: .profile, showsSettings: true)
        .environment(\.dynamicTypeSize, .accessibility5)
        .modelContainer(PreviewModelContainers.primary())
}

#Preview("Settings Dark Mode") {
    MainTabPreviewWrapper(initialTab: .profile, showsSettings: true)
        .preferredColorScheme(.dark)
        .modelContainer(PreviewModelContainers.primary())
}
