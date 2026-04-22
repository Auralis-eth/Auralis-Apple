import SwiftData
import SwiftUI

struct MainAuraView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Query private var accounts: [EOAccount]

    @State private var router = AppRouter()
    @State private var nftService: NFTService
    @StateObject private var modeState: ModeState
    @State private var audioEngine: AudioEngine?
    @State private var shellStore: ShellStore?
    @State private var pendingStartupDeepLink: AppDeepLink?
    @State private var pendingStartupRouteError: AppRouteError?

    private let services: ShellServiceHub
    private let deepLinkParser = AppDeepLinkParser()
    private let audioEngineInitializationErrorMessage: String?

    @MainActor
    init() {
        self.init(services: .live)
    }

    @MainActor
    init(services: ShellServiceHub) {
        self.services = services
        _nftService = State(initialValue: services.nftServiceFactory())
        _modeState = StateObject(wrappedValue: services.modeStateFactory())
        do {
            let engine = try AudioEngine()
            _audioEngine = State(initialValue: engine)
            audioEngineInitializationErrorMessage = nil
        } catch {
            _audioEngine = State(initialValue: nil)
            audioEngineInitializationErrorMessage = error.localizedDescription
        }
    }

    var body: some View {
        Group {
            if let shellStore {
                shellContent(shellStore: shellStore)
            } else {
                bootstrapView
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
                MainTabView(
                    shellStore: shellStore,
                    resolveCurrentAccount: {
                        resolvedCurrentAccount(for: shellStore.state)
                    },
                    nftService: $nftService,
                    router: router,
                    audioEngine: audioEngine,
                    audioUnavailableMessage: audioEngineInitializationErrorMessage,
                    modeState: modeState,
                    services: services,
                    modelContext: modelContext
                )
                .tabBarMinimizeBehavior(.onScrollDown)
                .tabViewBottomAccessory {
                    if let audioEngine {
                        MiniPlayerView(audioEngine: audioEngine)
                    }
                }
            } else if nftsAreLoading, shellStore.state.selection != nil {
                NFTNewsfeedLoadingView(
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
                GatewayView(
                    ensResolver: services.ensResolverFactory(modelContext),
                    services: services,
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

        let store = ShellStore.live(
            services: services,
            modelContext: modelContext,
            nftService: nftService,
            router: router
        )
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

        return accounts.first(where: { $0.persistentModelID == activeAccountID })
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
}
