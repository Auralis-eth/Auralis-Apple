import SwiftData
import SwiftUI
import Observation

enum AppTab: Hashable {
    case home
    case news
    case gas
    case music
    case receipts
    case profile
    case search
    case erc20Tokens
    case nftTokens
}

enum NFTDetailRoute: Hashable {
    case detail(id: String)
}

enum MusicRoute: Hashable {
    case item(id: String)
    case collection(key: String, title: String)
}

enum ProfileRoute: Hashable {
    case detail(address: String)
}

enum NFTTokensRoute: Hashable {
    case item(id: String)
    case collection(contractAddress: String?, title: String, chain: Chain)
}

struct ERC20TokenRoute: Hashable {
    let contractAddress: String
    let chain: Chain
    let symbol: String
}

struct ReceiptRoute: Hashable {
    let id: String
}

@Observable
final class AppRouter {
    var selectedTab: AppTab = .home
    var newsPath: [NFTDetailRoute] = []
    var musicPath: [MusicRoute] = []
    var profilePath: [ProfileRoute] = []
    var receiptsPath: [ReceiptRoute] = []
    var nftTokensPath: [NFTTokensRoute] = []
    var erc20TokensPath: [ERC20TokenRoute] = []
    var presentedRouteError: AppRouteError?

    func resetAllPaths() {
        newsPath.removeAll()
        musicPath.removeAll()
        profilePath.removeAll()
        receiptsPath.removeAll()
        nftTokensPath.removeAll()
        erc20TokensPath.removeAll()
    }

    func showNewsNFTDetail(id: String) {
        selectedTab = .news
        newsPath = newsPath + [.detail(id: id)]
    }

    func showMusicNFTDetail(id: String) {
        selectedTab = .music
        musicPath = musicPath + [.item(id: id)]
    }

    func showMusicCollectionDetail(key: String, title: String) {
        selectedTab = .music
        musicPath = musicPath + [.collection(key: key, title: title)]
    }

    func showNFTTokensDetail(id: String) {
        selectedTab = .nftTokens
        nftTokensPath = nftTokensPath + [.item(id: id)]
    }

    func showNFTCollectionDetail(contractAddress: String?, title: String, chain: Chain) {
        selectedTab = .nftTokens
        nftTokensPath = nftTokensPath + [
            .collection(
                contractAddress: contractAddress,
                title: title,
                chain: chain
            )
        ]
    }

    func showNFTFromHome(_ nft: NFT) {
        if nft.isMusic() {
            showMusicNFTDetail(id: nft.id)
        } else {
            showNFTTokensDetail(id: nft.id)
        }
    }

    func showMusicLibrary() {
        selectedTab = .music
    }

    func showNFTTokens() {
        selectedTab = .nftTokens
    }

    func showERC20Token(contractAddress: String, chain: Chain, symbol: String) {
        selectedTab = .erc20Tokens
        erc20TokensPath = erc20TokensPath + [
            ERC20TokenRoute(
                contractAddress: contractAddress,
                chain: chain,
                symbol: symbol
            )
        ]
    }

    func showReceipts() {
        selectedTab = .receipts
    }

    func showSearch() {
        selectedTab = .search
    }

    func showProfileDetail(address: String) {
        selectedTab = .profile
        profilePath = profilePath + [.detail(address: address)]
    }

    func showReceipt(id: String) {
        selectedTab = .receipts
        receiptsPath = [.init(id: id)]
    }

    func showRouteError(title: String, message: String, urlString: String? = nil) {
        presentedRouteError = AppRouteError(
            title: title,
            message: message,
            urlString: urlString
        )
    }

    func clearRouteError() {
        presentedRouteError = nil
    }

    var selectedTabName: String {
        switch selectedTab {
        case .home:
            return "home"
        case .news:
            return "news"
        case .gas:
            return "gas"
        case .music:
            return "music"
        case .receipts:
            return "receipts"
        case .profile:
            return "profile"
        case .search:
            return "search"
        case .erc20Tokens:
            return "erc20Tokens"
        case .nftTokens:
            return "nftTokens"
        }
    }

    var currentRouteDepth: Int {
        switch selectedTab {
        case .news:
            return newsPath.count
        case .music:
            return musicPath.count
        case .profile:
            return profilePath.count
        case .receipts:
            return receiptsPath.count
        case .erc20Tokens:
            return erc20TokensPath.count
        case .nftTokens:
            return nftTokensPath.count
        case .home, .gas, .search:
            return 0
        }
    }

    func popCurrentRoute() {
        switch selectedTab {
        case .news:
            if !newsPath.isEmpty {
                newsPath.removeLast()
            }
        case .music:
            if !musicPath.isEmpty {
                musicPath.removeLast()
            }
        case .profile:
            if !profilePath.isEmpty {
                profilePath.removeLast()
            }
        case .receipts:
            if !receiptsPath.isEmpty {
                receiptsPath.removeLast()
            }
        case .erc20Tokens:
            if !erc20TokensPath.isEmpty {
                erc20TokensPath.removeLast()
            }
        case .nftTokens:
            if !nftTokensPath.isEmpty {
                nftTokensPath.removeLast()
            }
        case .home, .gas, .search:
            break
        }
    }
}

struct MainTabView: View {
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
            currentChainId = newValue.rawValue

            guard let currentAccount, currentAccount.currentChain != newValue else {
                return
            }

            currentAccount.currentChain = newValue
            try? modelContext.save()
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
                        services: services
                    )
                    .navigationDestination(for: ProfileRoute.self) { route in
                        switch route {
                        case .detail(let address):
                            ProfileDetailView(
                                accountAddress: address,
                                currentChain: currentChain,
                                isCurrentAccount: address == (currentAccount?.address ?? currentAddress)
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

private struct SharedNFTDetailView: View {
    let route: NFTDetailRoute
    let currentAccountAddress: String?
    let currentChain: Chain
    @Query private var nfts: [NFT]

    init(route: NFTDetailRoute, currentAccountAddress: String?, currentChain: Chain) {
        self.route = route
        self.currentAccountAddress = currentAccountAddress
        self.currentChain = currentChain

        let normalizedAccountAddress = NFT.normalizedScopeComponent(currentAccountAddress) ?? ""
        let chainRawValue = currentChain.rawValue
        _nfts = Query(
            filter: #Predicate<NFT> {
                $0.accountAddressRawValue == normalizedAccountAddress &&
                $0.networkRawValue == chainRawValue
            }
        )
    }

    private var nft: NFT? {
        switch route {
        case .detail(let id):
            return nfts.first { $0.id == id }
        }
    }

    private var imageURL: URL? {
        guard let nft else { return nil }

        if let originalURL = nft.image?.originalUrl, let url = URL(string: originalURL) {
            return url
        }

        if let thumbnailURL = nft.image?.thumbnailUrl, let url = URL(string: thumbnailURL) {
            return url
        }

        return nil
    }

    private var titleText: String {
        nft?.name ?? "Untitled NFT"
    }

    private var collectionName: String? {
        nft?.collection?.name ?? nft?.collectionName
    }

    private var descriptionText: String? {
        guard let description = nft?.nftDescription, !description.isEmpty else {
            return nil
        }

        return description
    }

    var body: some View {
        Group {
            if let nft {
                VStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            nftImage

                            VStack(alignment: .leading, spacing: 12) {
                                AuraTrustLabel(kind: .metadata)

                                HeadlineFontText(titleText)
                                    .fontWeight(.semibold)
                                    .accessibilityIdentifier("nft.detail.title")

                                if let collectionName {
                                    SubheadlineFontText(collectionName)
                                }

                                if let description = descriptionText {
                                    SecondaryText(description)
                                }

                                badgeRow(for: nft)
                            }
                        }
                        .padding()
                    }
                }
                .navigationTitle(titleText)
                .navigationBarTitleDisplayMode(.inline)
                .background(Color.background)
                .accessibilityIdentifier("nft.detail.screen")
            } else {
                ContentUnavailableView(
                    "NFT Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("The requested NFT could not be resolved for the current account.")
                )
                .navigationTitle("NFT Detail")
                .accessibilityIdentifier("nft.detail.unavailable")
            }
        }
    }

    private var nftImage: some View {
        AsyncImage(url: imageURL) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.secondary.opacity(0.2))
                .overlay {
                    SystemImage("photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private func badgeRow(for nft: NFT) -> some View {
        HStack(spacing: 12) {
            if let chain = nft.network {
                BadgeLabel(title: chain.routingDisplayName)
            }

            if nft.isMusic() {
                BadgeLabel(title: "Music NFT")
            }
        }
    }
}

private struct NFTTokensRootView: View {
    @Query private var nfts: [NFT]
    let currentAccount: EOAccount?
    let currentChain: Chain
    let contextSnapshot: ContextSnapshot
    let nftService: NFTService
    let refreshAction: @MainActor () async -> Void
    let router: AppRouter

    init(
        currentAccount: EOAccount?,
        currentChain: Chain,
        contextSnapshot: ContextSnapshot,
        nftService: NFTService,
        refreshAction: @escaping @MainActor () async -> Void,
        router: AppRouter
    ) {
        self.currentAccount = currentAccount
        self.currentChain = currentChain
        self.contextSnapshot = contextSnapshot
        self.nftService = nftService
        self.refreshAction = refreshAction
        self.router = router

        let normalizedAccountAddress = NFT.normalizedScopeComponent(currentAccount?.address) ?? ""
        let chainRawValue = currentChain.rawValue
        _nfts = Query(
            filter: #Predicate<NFT> {
                $0.accountAddressRawValue == normalizedAccountAddress &&
                $0.networkRawValue == chainRawValue
            },
            sort: [SortDescriptor(\NFT.acquiredAt?.blockTimestamp, order: .reverse)]
        )
    }

    var body: some View {
        Group {
            if nfts.isEmpty {
                AuraScenicScreen(contentAlignment: .center) {
                    if let failure = nftService.providerFailurePresentation(isShowingCachedContent: false) {
                        ShellProviderFailureStateView(
                            failure: failure,
                            retry: refresh
                        )
                    } else {
                        ShellEmptyLibraryStateView(
                            kind: .nft,
                            snapshot: contextSnapshot
                        )
                    }
                }
            } else {
                VStack(spacing: 0) {
                    if let failure = nftService.providerFailurePresentation(isShowingCachedContent: true) {
                        ShellStatusBanner(
                            title: failure.title,
                            message: failure.message,
                            systemImage: failure.systemImage,
                            tone: .warning,
                            action: failure.isRetryable ? ShellStatusAction(
                                title: "Retry",
                                systemImage: "arrow.clockwise",
                                handler: refresh
                            ) : nil
                        )
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                    }

                    List(nfts) { nft in
                        Button {
                            router.showNFTTokensDetail(id: nft.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(nft.name ?? "Untitled NFT")
                                    .foregroundStyle(Color.textPrimary)

                                Text(nft.collection?.name ?? nft.collectionName ?? nft.tokenId)
                                    .font(.caption)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("nftTokens.row.\(nft.id)")
                    }
                }
            }
        }
        .navigationTitle("NFT Tokens")
        .accessibilityIdentifier("nftTokens.root")
    }

    private func refresh() {
        Task {
            await refreshAction()
        }
    }
}

private struct ObserveModePolicyView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var denialMessage: String?

    let modeState: ModeState
    let services: ShellServiceHub

    private let blockedActions: [PolicyControlledAction] = [
        .signMessage,
        .approveSpending,
        .draftTransaction
    ]

    var body: some View {
        AuraScenicScreen(contentAlignment: .top) {
            VStack(alignment: .leading, spacing: 16) {
                ShellStatusCard(
                    eyebrow: "Observe Mode",
                    title: "Execution Is Locked",
                    message: "Auralis is currently read-only. Signing, approvals, and transaction drafting stay blocked until a later phase unlocks them intentionally.",
                    systemImage: "eye.slash",
                    tone: .warning
                )

                ForEach(blockedActions, id: \.rawValue) { action in
                    AuraSurfaceCard(style: .soft, cornerRadius: 24, padding: 16) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(action.title)
                                    .font(.headline)
                                    .foregroundStyle(Color.textPrimary)

                                Text(action.summary)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.textSecondary)
                            }

                            Spacer(minLength: 8)

                            AuraActionButton("Try", style: .surface) {
                                attempt(action)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Profile")
        .alert("Not available in Observe mode", isPresented: denialAlertBinding) {
            Button("OK", role: .cancel) {
                denialMessage = nil
            }
        } message: {
            Text(denialMessage ?? "This action is not available right now.")
        }
    }

    private var denialAlertBinding: Binding<Bool> {
        Binding(
            get: { denialMessage != nil },
            set: { isPresented in
                if !isPresented {
                    denialMessage = nil
                }
            }
        )
    }

    private func attempt(_ action: PolicyControlledAction) {
        let result = services.policyActionHandlerFactory(modelContext, modeState).attempt(action)

        if !result.isAllowed {
            denialMessage = result.userMessage
        }
    }
}

private struct ERC20TokensRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var holdings: [TokenHolding]

    let currentAccountAddress: String
    let currentChain: Chain
    let contextSnapshot: ContextSnapshot
    let nftService: NFTService
    let refreshAction: @MainActor () async -> Void
    let router: AppRouter
    let tokenHoldingsStoreFactory: @MainActor (ModelContext) -> TokenHoldingsStore
    let tokenHoldingsProviderFactory: () -> any TokenHoldingsProviding

    @State private var persistenceErrorMessage: String?
    @State private var providerErrorMessage: String?

    init(
        currentAccountAddress: String,
        currentChain: Chain,
        contextSnapshot: ContextSnapshot,
        nftService: NFTService,
        refreshAction: @escaping @MainActor () async -> Void,
        router: AppRouter,
        tokenHoldingsStoreFactory: @escaping @MainActor (ModelContext) -> TokenHoldingsStore,
        tokenHoldingsProviderFactory: @escaping () -> any TokenHoldingsProviding
    ) {
        self.currentAccountAddress = currentAccountAddress
        self.currentChain = currentChain
        self.contextSnapshot = contextSnapshot
        self.nftService = nftService
        self.refreshAction = refreshAction
        self.router = router
        self.tokenHoldingsStoreFactory = tokenHoldingsStoreFactory
        self.tokenHoldingsProviderFactory = tokenHoldingsProviderFactory

        let normalizedAccountAddress = NFT.normalizedScopeComponent(currentAccountAddress) ?? ""
        let chainRawValue = currentChain.rawValue
        _holdings = Query(
            filter: #Predicate<TokenHolding> {
                $0.accountAddressRawValue == normalizedAccountAddress &&
                $0.chainRawValue == chainRawValue
            },
            sort: [
                SortDescriptor(\TokenHolding.sortPriority, order: .forward),
                SortDescriptor(\TokenHolding.displayName, order: .forward)
            ]
        )
    }

    private var rowModels: [TokenHoldingRowModel] {
        holdings.map(TokenHoldingRowModel.init(holding:))
    }

    private var nativeBalanceDisplay: String? {
        contextSnapshot.balances.nativeBalanceDisplay.value
    }

    private var nativeBalanceUpdatedAt: Date? {
        contextSnapshot.balances.nativeBalanceDisplay.updatedAt
            ?? contextSnapshot.freshness.lastSuccessfulRefreshAt
    }

    private var syncKey: ERC20HoldingsSyncKey {
        ERC20HoldingsSyncKey(
            accountAddress: NFT.normalizedScopeComponent(currentAccountAddress) ?? "",
            chain: currentChain,
            nativeBalanceDisplay: nativeBalanceDisplay,
            updatedAt: nativeBalanceUpdatedAt,
            refreshAnchor: contextSnapshot.freshness.lastSuccessfulRefreshAt
        )
    }

    var body: some View {
        Group {
            if holdings.isEmpty {
                AuraScenicScreen(contentAlignment: .center) {
                    if let providerErrorMessage {
                        ShellStatusCard(
                            eyebrow: "Provider Error",
                            title: "Token Holdings Unavailable",
                            message: providerErrorMessage,
                            systemImage: "externaldrive.badge.wifi",
                            tone: .critical,
                            primaryAction: ShellStatusAction(
                                title: "Retry",
                                systemImage: "arrow.clockwise",
                                handler: refresh
                            )
                        )
                    } else if let failure = nftService.providerFailurePresentation(isShowingCachedContent: false) {
                        ShellProviderFailureStateView(
                            failure: failure,
                            retry: refresh
                        )
                    } else {
                        ShellEmptyLibraryStateView(
                            kind: .token,
                            snapshot: contextSnapshot
                        )
                    }
                }
            } else {
                VStack(spacing: 0) {
                    if let persistenceErrorMessage {
                        ShellStatusBanner(
                            title: "Local holdings could not be updated",
                            message: persistenceErrorMessage,
                            systemImage: "externaldrive.badge.exclamationmark",
                            tone: .warning,
                            action: nil
                        )
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                    } else if let providerErrorMessage {
                        ShellStatusBanner(
                            title: "Showing Last Saved Holdings",
                            message: providerErrorMessage,
                            systemImage: "externaldrive.badge.wifi",
                            tone: .warning,
                            action: ShellStatusAction(
                                title: "Retry",
                                systemImage: "arrow.clockwise",
                                handler: refresh
                            )
                        )
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                    } else if let failure = nftService.providerFailurePresentation(isShowingCachedContent: true) {
                        ShellStatusBanner(
                            title: failure.title,
                            message: failure.message,
                            systemImage: failure.systemImage,
                            tone: .warning,
                            action: failure.isRetryable ? ShellStatusAction(
                                title: "Retry",
                                systemImage: "arrow.clockwise",
                                handler: refresh
                            ) : nil
                        )
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                    }

                    List(rowModels) { row in
                        if row.canOpenDetail, let contractAddress = row.contractAddress {
                            Button {
                                router.showERC20Token(
                                    contractAddress: contractAddress,
                                    chain: currentChain,
                                    symbol: row.symbol ?? row.title
                                )
                            } label: {
                                ERC20HoldingRow(row: row)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("erc20.row.\(row.id)")
                        } else {
                            ERC20HoldingRow(row: row)
                                .accessibilityIdentifier("erc20.row.\(row.id)")
                        }
                    }
                }
            }
        }
        .navigationTitle("ERC-20")
        .accessibilityIdentifier("erc20.root")
        .task(id: syncKey) {
            await syncHoldings()
        }
    }

    private func refresh() {
        Task {
            await refreshAction()
        }
    }

    private func syncHoldings() async {
        syncNativeHoldingIfAvailable()

        guard !currentAccountAddress.isEmpty,
              currentChain.supportsERC20Holdings else {
            providerErrorMessage = nil
            return
        }

        do {
            let providerHoldings = try await tokenHoldingsProviderFactory().tokenHoldings(
                for: currentAccountAddress,
                chain: currentChain
            )
            try tokenHoldingsStoreFactory(modelContext).replaceERC20Holdings(
                accountAddress: currentAccountAddress,
                chain: currentChain,
                holdings: providerHoldings
            )
            providerErrorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            providerErrorMessage = holdings.isEmpty
                ? "Auralis could not load token holdings for the active wallet and chain just now. Try again in a moment."
                : "Auralis kept the last saved ERC-20 holdings because the live token provider did not respond cleanly for this scope."
        }
    }

    private func syncNativeHoldingIfAvailable() {
        guard let nativeBalanceDisplay,
              let updatedAt = nativeBalanceUpdatedAt,
              !currentAccountAddress.isEmpty else {
            return
        }

        do {
            try tokenHoldingsStoreFactory(modelContext).upsertNativeHolding(
                accountAddress: currentAccountAddress,
                chain: currentChain,
                amountDisplay: nativeBalanceDisplay,
                updatedAt: updatedAt
            )
            persistenceErrorMessage = nil
        } catch {
            persistenceErrorMessage = "Auralis kept the last saved holdings view, but the latest native balance could not be written on this device."
        }
    }
}

private struct ERC20TokenDetailView: View {
    let route: ERC20TokenRoute
    let currentAccountAddress: String

    @Query private var holdings: [TokenHolding]

    init(route: ERC20TokenRoute, currentAccountAddress: String) {
        self.route = route
        self.currentAccountAddress = currentAccountAddress

        let normalizedAccountAddress = NFT.normalizedScopeComponent(currentAccountAddress) ?? ""
        let contractAddress = NFT.normalizedScopeComponent(route.contractAddress) ?? route.contractAddress
        let chainRawValue = route.chain.rawValue
        _holdings = Query(
            filter: #Predicate<TokenHolding> {
                $0.accountAddressRawValue == normalizedAccountAddress &&
                $0.chainRawValue == chainRawValue &&
                $0.contractAddressRawValue == contractAddress
            }
        )
    }

    private var presentation: ERC20TokenDetailPresentation {
        ERC20TokenDetailPresentation(
            route: route,
            holding: holdings.first
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AuraSurfaceCard(style: .soft, cornerRadius: 28, padding: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(presentation.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Color.textPrimary)
                            .accessibilityIdentifier("erc20.detail.title")

                        if let symbol = presentation.symbol {
                            Text(symbol)
                                .font(.title3.weight(.medium))
                                .foregroundStyle(Color.textSecondary)
                        }

                        HStack(spacing: 10) {
                            BadgeLabel(title: presentation.chainTitle)

                            if presentation.isPlaceholder {
                                BadgeLabel(title: "Metadata pending")
                            }

                            if presentation.isNativeStyleFallback {
                                BadgeLabel(title: "Native-style fallback")
                            }
                        }

                        if let metadataStatus = presentation.metadataStatus {
                            SecondaryText(metadataStatus)
                        }
                    }
                }

                AuraSurfaceCard(style: .soft, cornerRadius: 24, padding: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        HeadlineFontText("Balance")
                        ERC20TokenDetailRow(title: "Amount", value: presentation.amountDisplay)
                        ERC20TokenDetailRow(title: "Scope", value: presentation.scopeTitle)
                        ERC20TokenDetailRow(title: "Updated", value: presentation.updatedLabel)
                    }
                }

                AuraSurfaceCard(style: .soft, cornerRadius: 24, padding: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        HeadlineFontText("Token Identity")
                        ERC20TokenDetailRow(title: "Name", value: presentation.title)
                        ERC20TokenDetailRow(title: "Symbol", value: presentation.symbol)
                        ERC20TokenDetailRow(title: "Contract", value: presentation.contractAddress)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(presentation.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("erc20.detail.screen")
    }
}

struct ERC20TokenDetailPresentation: Equatable {
    let title: String
    let navigationTitle: String
    let symbol: String?
    let amountDisplay: String
    let chainTitle: String
    let scopeTitle: String
    let contractAddress: String
    let updatedLabel: String?
    let isPlaceholder: Bool
    let isNativeStyleFallback: Bool
    let metadataStatus: String?

    init(route: ERC20TokenRoute, holding: TokenHolding?) {
        let resolvedTitle = Self.cleanedText(holding?.displayName)
            ?? Self.cleanedText(route.symbol)
            ?? "Token Detail"
        let resolvedSymbol = Self.cleanedText(holding?.symbol)
            ?? Self.cleanedText(route.symbol)
        let resolvedAmount = Self.cleanedText(holding?.amountDisplay)
            ?? "Balance unavailable"
        let resolvedContract = Self.cleanedText(holding?.contractAddress)
            ?? route.contractAddress

        self.title = resolvedTitle
        self.navigationTitle = resolvedTitle
        self.symbol = resolvedSymbol
        self.amountDisplay = resolvedAmount
        self.chainTitle = route.chain.routingDisplayName
        self.scopeTitle = "\(route.chain.routingDisplayName) token scope"
        self.contractAddress = resolvedContract
        self.updatedLabel = holding?.updatedAt.formatted(date: .abbreviated, time: .shortened)
        self.isPlaceholder = holding?.isPlaceholder ?? false
        self.isNativeStyleFallback = holding?.balanceKind == .native

        if holding == nil {
            self.metadataStatus = "This token route is valid, but a scoped local holding is not currently available."
        } else if isNativeStyleFallback {
            self.metadataStatus = "This screen is using a native-style holding fallback inside the token detail contract."
        } else if isPlaceholder || resolvedSymbol == nil {
            self.metadataStatus = "Some token metadata is still sparse for this holding."
        } else {
            self.metadataStatus = nil
        }
    }

    private static func cleanedText(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

private struct ERC20TokenDetailRow: View {
    let title: String
    let value: String?

    var body: some View {
        if let value, !value.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.textSecondary)

                Spacer(minLength: 12)

                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

private struct ERC20HoldingRow: View {
    let row: TokenHoldingRowModel

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(row.title)
                        .foregroundStyle(Color.textPrimary)

                    if let symbol = row.symbol, !symbol.isEmpty {
                        Text(symbol)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                Text(row.subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)

                if row.isPlaceholder {
                    Text("Metadata pending")
                        .font(.caption2)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            Spacer(minLength: 12)

            Text(row.amountDisplay)
                .fontWeight(.semibold)
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct ERC20HoldingsSyncKey: Hashable {
    let accountAddress: String
    let chain: Chain
    let nativeBalanceDisplay: String?
    let updatedAt: Date?
    let refreshAnchor: Date?
}

private struct BadgeLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.deepBlue.opacity(0.18))
            )
            .overlay(
                Capsule()
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            )
    }
}
