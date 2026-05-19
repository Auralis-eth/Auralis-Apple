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
import NFTKit
import NFTLibraryFeature

struct MainAuraView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Query private var accounts: [EOAccount]

    @State private var router = AppRouter()
    @State private var nftService: NFTService
    @State private var modeState: ModeState
    @State private var audioEngine: AudioEngine?
    @State private var audioEngineInitializationErrorMessage: String?
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
    private let primaryStoreInitializationErrorMessage: String?

    @MainActor
    init() {
        self.init(
            dependencies: .live,
            primaryStoreInitializationErrorMessage: nil
        )
    }

    @MainActor
    init(
        dependencies: ShellBootstrapDependencies,
        primaryStoreInitializationErrorMessage: String? = nil
    ) {
        self.dependencies = dependencies
        self.primaryStoreInitializationErrorMessage = primaryStoreInitializationErrorMessage
        _nftService = State(initialValue: dependencies.nftServiceFactory())
        _modeState = State(initialValue: dependencies.modeStateFactory())
        let musicRuntime = dependencies.makeMusicRuntime()
        _auraPlayModelContainer = State(initialValue: musicRuntime.auraPlayModelContainer)
        _auraPlayInitializationErrorMessage = State(initialValue: musicRuntime.auraPlayInitializationErrorMessage)
        _audioEngine = State(initialValue: musicRuntime.audioEngine)
        _audioEngineInitializationErrorMessage = State(initialValue: musicRuntime.audioEngineInitializationErrorMessage)
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
            if let primaryStoreInitializationErrorMessage, !primaryStoreWarningDismissed {
                Button {
                    primaryStoreWarningDismissed = true
                } label: {
                    AuraErrorBanner(
                        title: "Limited Local Storage",
                        message: primaryStoreInitializationErrorMessage,
                        systemImage: "externaldrive.badge.exclamationmark"
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Limited local storage warning")
                .accessibilityHint("Dismisses the local storage warning")
            }
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
                        audioEngine: audioEngine,
                        musicUnavailableMessage: musicUnavailableMessage,
                        showsMusicReinstallGuidance: auraPlayInitializationErrorMessage != nil,
                        retryMusicSetup: reloadMusicServices,
                        modeState: modeState,
                        dependencies: mainTabDependencies,
                        auraPlayModelContainer: auraPlayModelContainer
                    )
                    .tabBarMinimizeBehavior(.onScrollDown)
                    .tabViewBottomAccessory {
                        if let audioEngine {
                            AuraPlayMiniPlayerView(player: audioEngine)
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
        }
    }

    private func initializeShellStoreIfNeeded() {
        guard shellStore == nil else {
            return
        }

        dependencies.configureMusicReceiptLogger(audioEngine, modelContext)
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
        switch deepLinkParser.parse(url: url) {
        case .success(let deepLink):
            guard let shellStore else {
                pendingStartupDeepLink = deepLink
                pendingStartupRouteError = nil
                return
            }
            Task {
                await shellStore.send(.deepLinkReceived(deepLink))
            }

        case .failure(let routeError):
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
            audioEngine: audioEngine,
            audioEngineInitializationErrorMessage: audioEngineInitializationErrorMessage,
            auraPlayModelContainer: auraPlayModelContainer,
            auraPlayInitializationErrorMessage: auraPlayInitializationErrorMessage
        ).unavailableMessage
    }

    @MainActor
    private func reloadMusicServices() async {
        let musicRuntime = dependencies.makeMusicRuntime()
        auraPlayModelContainer = musicRuntime.auraPlayModelContainer
        auraPlayInitializationErrorMessage = musicRuntime.auraPlayInitializationErrorMessage
        audioEngine = musicRuntime.audioEngine
        audioEngineInitializationErrorMessage = musicRuntime.audioEngineInitializationErrorMessage
        dependencies.configureMusicReceiptLogger(audioEngine, modelContext)
    }

}
