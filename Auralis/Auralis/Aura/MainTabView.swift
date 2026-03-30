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
    var musicPath: [NFTDetailRoute] = []
    var receiptsPath: [ReceiptRoute] = []
    var nftTokensPath: [NFTDetailRoute] = []
    var erc20TokensPath: [ERC20TokenRoute] = []
    var presentedRouteError: AppRouteError?

    func resetAllPaths() {
        newsPath.removeAll()
        musicPath.removeAll()
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
        musicPath = musicPath + [.detail(id: id)]
    }

    func showNFTTokensDetail(id: String) {
        selectedTab = .nftTokens
        nftTokensPath = nftTokensPath + [.detail(id: id)]
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
        case .receipts:
            return receiptsPath.count
        case .erc20Tokens:
            return erc20TokensPath.count
        case .nftTokens:
            return nftTokensPath.count
        case .home, .gas, .profile, .search:
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
        case .home, .gas, .profile, .search:
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
    @State private var showAccountSwitcher = false
    @State private var showContextInspector = false
    @State private var contextService: ContextService

    private var contextRefreshKey: ContextRefreshKey {
        ContextRefreshKey(
            accountAddress: currentAccount?.address ?? currentAddress,
            chain: currentChain,
            mode: modeState.mode,
            isLoading: nftService.isLoading,
            refreshedAt: nftService.lastSuccessfulRefreshAt,
            trackedNFTCount: currentAccount?.trackedNFTCount
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
        let libraryContextProvider = services.libraryContextProviderFactory(modelContext)
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
                receiptEventLogger: ReceiptEventLogger(
                    receiptStore: services.receiptStoreFactory(modelContext)
                )
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
                    ensResolver: services.ensResolverFactory(modelContext)
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
                                    }
                                )
                            }
                            .navigationDestination(for: NFTDetailRoute.self) { route in
                                SharedNFTDetailView(
                                    route: route,
                                    currentAccountAddress: currentAccount?.address,
                                    currentChain: currentChain
                                )
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
                ObserveModePolicyView(modeState: modeState, services: services)
            }

            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                SearchRootView(
                    currentAccountAddress: currentAccount?.address ?? currentAddress,
                    currentChain: currentChain
                )
            }

            Tab("ERC-20", systemImage: "dollarsign.circle", value: AppTab.erc20Tokens) {
                NavigationStack(path: $router.erc20TokensPath) {
                    ERC20TokensRootView(router: router, chain: currentChain)
                        .navigationDestination(for: ERC20TokenRoute.self) { route in
                            ERC20TokenDetailView(route: route)
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
                        .navigationDestination(for: NFTDetailRoute.self) { route in
                            SharedNFTDetailView(
                                route: route,
                                currentAccountAddress: currentAccount?.address,
                                currentChain: currentChain
                            )
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

    private let blockedActions: [ObserveBlockedAction] = [
        .signMessage,
        .approveSpending,
        .draftTransaction,
        .runPlugin
    ]

    var body: some View {
        AuraScenicScreen(contentAlignment: .top) {
            VStack(alignment: .leading, spacing: 16) {
                ShellStatusCard(
                    eyebrow: "Observe Mode",
                    title: "Execution Is Locked",
                    message: "Auralis is currently read-only. Signing, approvals, transaction drafting, and plugin execution stay blocked until a later phase unlocks them intentionally.",
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

    private func attempt(_ action: ObserveBlockedAction) {
        let result = services.policyActionHandlerFactory(modelContext, modeState).attempt(action)

        if !result.isAllowed {
            denialMessage = result.userMessage
        }
    }
}

private struct ERC20TokensRootView: View {
    let router: AppRouter
    let chain: Chain

    var body: some View {
        ContentUnavailableView {
            Label("ERC-20 Tokens", systemImage: "dollarsign.circle")
        } description: {
            Text("Routing is wired for ERC-20 token detail, but the token portfolio surface has not been built yet.")
        } actions: {
            Button("Open Example Token") {
                router.showERC20Token(
                    contractAddress: "0x0000000000000000000000000000000000000000",
                    chain: chain,
                    symbol: "TOKEN"
                )
            }
            .accessibilityIdentifier("erc20.openExampleToken")
        }
        .navigationTitle("ERC-20")
        .accessibilityIdentifier("erc20.root")
    }
}

private struct ERC20TokenDetailView: View {
    let route: ERC20TokenRoute

    var body: some View {
        List {
            LabeledContent("Symbol", value: route.symbol)
            LabeledContent("Chain", value: route.chain.routingDisplayName)
            LabeledContent("Contract", value: route.contractAddress)
        }
        .navigationTitle(route.symbol)
        .accessibilityIdentifier("erc20.detail.screen")
    }
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
