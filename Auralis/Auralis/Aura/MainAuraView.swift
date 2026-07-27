import ReceiptsCore
import ReceiptStorage
import AccountsFeature
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import AuralisShellCore
import MusicFeature
import SwiftData
import SwiftUI
import AuraUI
import NFTDomain
import NFTPersistence
import NFTPresentation
import NFTProviderAdapters
import NFTLibraryFeature

struct IncomingDeepLinkHandlingDecision {
    let deepLink: AppDeepLink?
    let routeError: AppRouteError?
}

struct IncomingDeepLinkPolicy {
    func decision(for parseResult: Result<AppDeepLink, AppRouteError>) -> IncomingDeepLinkHandlingDecision {
        switch parseResult {
        case .success(let deepLink):
            IncomingDeepLinkHandlingDecision(deepLink: deepLink, routeError: nil)
        case .failure(let routeError):
            IncomingDeepLinkHandlingDecision(deepLink: nil, routeError: routeError)
        }
    }
}

struct MainAuraView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Query private var accounts: [EOAccount]

    @State private var router: AppRouter
    @State private var nftService: NFTService
    @State private var modeState: ModeState
    @State private var playbackRuntime: AuraPlayPlaybackRuntime?
    @State private var playbackRuntimeInitializationErrorMessage: String?
    @State private var auraPlayModelContainer: ModelContainer?
    @State private var auraPlayInitializationErrorMessage: String?
    @State private var shellStore: ShellStore?
    @State private var gatewayDependencies: GatewayDependencies?
    @State private var mainTabDependencies: MainTabDependencies?
    @State private var pendingStartupDeepLink: AppDeepLink?
    @State private var pendingStartupRouteError: AppRouteError?
    @State private var primaryStoreWarningDismissed = false

    private let dependencies: ShellBootstrapDependencies
    private let deepLinkParser = AppDeepLinkParser()
    private let deepLinkPolicy = IncomingDeepLinkPolicy()
    private let primaryStoreInitializationErrorMessage: String?

    @MainActor
    init() {
        self.init(
            dependencies: .live,
            tabBarVisibility: .live,
            primaryStoreInitializationErrorMessage: nil
        )
    }

    @MainActor
    init(
        dependencies: ShellBootstrapDependencies,
        tabBarVisibility: AppTabBarVisibility = .live,
        primaryStoreInitializationErrorMessage: String? = nil
    ) {
        self.dependencies = dependencies
        self.primaryStoreInitializationErrorMessage = primaryStoreInitializationErrorMessage
        _router = State(initialValue: AppRouter(tabBarVisibility: tabBarVisibility))
        _nftService = State(initialValue: dependencies.nftServiceFactory())
        _modeState = State(initialValue: dependencies.modeStateFactory())
        let musicRuntime = dependencies.makeMusicRuntime()
        _auraPlayModelContainer = State(initialValue: musicRuntime.auraPlayModelContainer)
        _auraPlayInitializationErrorMessage = State(initialValue: musicRuntime.auraPlayInitializationErrorMessage)
        _playbackRuntime = State(initialValue: musicRuntime.playbackRuntime)
        _playbackRuntimeInitializationErrorMessage = State(initialValue: musicRuntime.playbackRuntimeInitializationErrorMessage)
    }

    var body: some View {
        Group {
            if let shellStore {
                shellContent(shellStore: shellStore)
            } else {
                bootstrapView
            }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if let primaryStoreInitializationErrorMessage, !primaryStoreWarningDismissed {
                    Button {
                        primaryStoreWarningDismissed = true
                    } label: {
                        AuraErrorBanner(
                            title: "Limited Local Storage",
                            message: primaryStoreInitializationErrorMessage,
                            systemImage: "externaldrive.badge.exclamationmark"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Limited local storage warning"))
                    .accessibilityValue(primaryStoreInitializationErrorMessage)
                    .accessibilityHint(String(localized: "Dismisses the local storage warning"))
                }

                if let playbackAlert = playbackRuntime?.auraPlayPlaybackAlert {
                    Button {
                        playbackRuntime?.auraPlayDismissPlaybackAlert()
                    } label: {
                        AuraErrorBanner(
                            title: playbackAlert.title,
                            message: playbackAlert.message,
                            systemImage: "exclamationmark.triangle"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(A11yID.AuraPlay.playbackToast)
                    .accessibilityLabel(String(localized: "Playback warning"))
                    .accessibilityValue("\(playbackAlert.title). \(playbackAlert.message)")
                    .accessibilityHint(String(localized: "Dismisses the playback warning"))
                    .task(id: playbackAlert.id) {
                        AuraAccessibilityAnnouncer.announce(
                            "\(playbackAlert.title). \(playbackAlert.message)"
                        )
                        try? await Task.sleep(nanoseconds: 4_000_000_000)
                        playbackRuntime?.auraPlayDismissPlaybackAlert()
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
        }
        .task {
            initializeShellStoreIfNeeded()
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active, let shellStore else {
                return
            }

            Task {
                await shellStore.send(.sceneBecameActive)
            }
        }
    }

    @ViewBuilder
    private func shellContent(shellStore: ShellStore) -> some View {
        let currentAccount = resolvedCurrentAccount(for: shellStore.state)
        let nftsAreLoading = nftService.isLoading || shellStore.state.isRefreshingSelection
        let shouldShowFullscreenLoading = nftsAreLoading && !shellStore.state.hasPresentedAuthenticatedExperience

        Group {
            if currentAccount != nil, !shouldShowFullscreenLoading {
                if let mainTabDependencies {
                    MainTabView(
                        shellStore: shellStore,
                        resolveCurrentAccount: {
                            resolvedCurrentAccount(for: shellStore.state)
                        },
                        nftService: $nftService,
                        router: router,
                        playbackRuntime: playbackRuntime,
                        musicUnavailableMessage: musicUnavailableMessage,
                        showsMusicReinstallGuidance: auraPlayInitializationErrorMessage != nil,
                        retryMusicSetup: reloadMusicServices,
                        modeState: modeState,
                        dependencies: mainTabDependencies,
                        auraPlayModelContainer: auraPlayModelContainer
                    )
                    .tabBarMinimizeBehavior(.onScrollDown)
                    .tabViewBottomAccessory {
                        if let playbackRuntime {
                            AuraPlayMiniPlayerView(player: playbackRuntime)
                        }
                    }
                }
            } else if nftsAreLoading, shellStore.state.selection != nil {
                NFTLibraryLoadingView(
                    itemsLoaded: nftService.itemsLoaded,
                    total: nftService.total,
                    phase: nftService.refreshPhase
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal)
                .background {
                    GatewayBackgroundImage()
                        .ignoresSafeArea()

                    Color.background.opacity(0.3)
                        .ignoresSafeArea()
                }
            } else {
                if let gatewayDependencies {
                    AccountsGatewayView(
                        dependencies: gatewayDependencies.featureDependencies,
                        onAccountActivated: { account, correlationID in
                            Task {
                                await shellStore.send(
                                    .accountActivated(
                                        account: account,
                                        correlationID: correlationID
                                    )
                                )
                            }
                        }
                    )
                }
            }
        }
        .sheet(item: routeErrorBinding(for: shellStore)) { routeError in
            RouteErrorScreen(routeError: routeError) {
                Task {
                    await shellStore.send(.routeErrorDismissed)
                }
            }
        }
    }

    private var bootstrapView: some View {
        ZStack {
            GatewayBackgroundImage()
                .ignoresSafeArea()

            Color.background.opacity(0.3)
                .ignoresSafeArea()

            ProgressView()
                .tint(Color.textPrimary)
                .accessibilityLabel(String(localized: "Loading Auralis"))
                .accessibilityValue(String(localized: "Preparing wallet and local data"))
        }
    }

    private func initializeShellStoreIfNeeded() {
        guard shellStore == nil else {
            return
        }

        dependencies.configureMusicReceiptLogger(playbackRuntime, modelContext)
        let gatewayDependencies = dependencies.makeGatewayDependencies(modelContext)
        let mainTabDependencies = dependencies.makeMainTabDependencies(modelContext)
        let store = dependencies.makeShellStore(modelContext, nftService, router)
        self.gatewayDependencies = gatewayDependencies
        self.mainTabDependencies = mainTabDependencies
        shellStore = store

        Task {
            await store.send(.restoreFromPersistence)
            await replayPendingStartupRoutingIfNeeded(using: store)
        }
    }

    private func handleIncomingURL(_ url: URL) {
        let decision = deepLinkPolicy.decision(for: deepLinkParser.parse(url: url))

        if let deepLink = decision.deepLink {
            guard let shellStore else {
                pendingStartupDeepLink = deepLink
                return
            }
            Task {
                await shellStore.send(.deepLinkReceived(deepLink))
            }
            return
        }

        if let routeError = decision.routeError {
            guard let shellStore else {
                pendingStartupRouteError = routeError
                pendingStartupDeepLink = nil
                return
            }
            Task {
                await shellStore.send(.routeErrorEncountered(routeError))
            }
        }
    }

    private func replayPendingStartupRoutingIfNeeded(using shellStore: ShellStore) async {
        if let routeError = pendingStartupRouteError {
            pendingStartupRouteError = nil
            await shellStore.send(.routeErrorEncountered(routeError))
        }

        if let deepLink = pendingStartupDeepLink {
            pendingStartupDeepLink = nil
            await shellStore.send(.deepLinkReceived(deepLink))
        }
    }

    private func resolvedCurrentAccount(for state: ShellState) -> EOAccount? {
        guard let activeAccountID = state.activeAccountID else {
            return nil
        }

        return accounts.first(where: { $0.address == activeAccountID })
    }

    private func routeErrorBinding(for shellStore: ShellStore) -> Binding<AppRouteError?> {
        Binding(
            get: { shellStore.state.routeError },
            set: { newValue in
                guard newValue == nil else {
                    return
                }

                Task {
                    await shellStore.send(.routeErrorDismissed)
                }
            }
        )
    }

    private var musicUnavailableMessage: String? {
        MusicRuntime(
            playbackRuntime: playbackRuntime,
            playbackRuntimeInitializationErrorMessage: playbackRuntimeInitializationErrorMessage,
            auraPlayModelContainer: auraPlayModelContainer,
            auraPlayInitializationErrorMessage: auraPlayInitializationErrorMessage
        ).unavailableMessage
    }

    @MainActor
    private func reloadMusicServices() async {
        let musicRuntime = dependencies.makeMusicRuntime()
        auraPlayModelContainer = musicRuntime.auraPlayModelContainer
        auraPlayInitializationErrorMessage = musicRuntime.auraPlayInitializationErrorMessage
        playbackRuntime = musicRuntime.playbackRuntime
        playbackRuntimeInitializationErrorMessage = musicRuntime.playbackRuntimeInitializationErrorMessage
        dependencies.configureMusicReceiptLogger(playbackRuntime, modelContext)
    }

}
