//
//  MainAuraView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/19/25.
//

import OSLog
import SwiftData
import SwiftUI

struct MainAuraView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("currentAccountAddress") var currentAddress: String = ""
    @AppStorage("currentChainId") var currentChainId: String = Chain.ethMainnet.rawValue
    @State private var currentAccount: EOAccount?
    @State private var currentChain: Chain = .ethMainnet
    @Query private var accounts: [EOAccount]

    @State private var router = AppRouter()

    @Environment(\.modelContext) private var modelContext
    @State private var nftService: NFTService
    @StateObject private var modeState: ModeState
    @State private var audioEngine: AudioEngine?
    @State private var pendingDeepLink: AppDeepLink?
    @State private var didFinishInitialStateRestore = false
    @State private var didRecordAppLaunchReceipt = false
    @State private var pendingShellFlowCorrelationID: String?
    @State private var latestAccountRefreshRequestID: UUID?
    @State private var accountRefreshTask: Task<Void, Never>?

    @State private var isLoading: Bool = false
    @State private var hasPresentedAuthenticatedExperience = false
    private let services: ShellServiceHub
    private let audioEngineInitializationErrorMessage: String?
    private let routeLogger = Logger(subsystem: "Auralis", category: "Routing")
    private let deepLinkParser = AppDeepLinkParser()
    private let pendingDeepLinkResolver = PendingDeepLinkResolver()
    private let shellLogic = MainAuraShellLogic()

    var nftsAreLoading: Bool {
        nftService.isLoading || isLoading
    }

    private var shouldShowFullscreenLoading: Bool {
        nftsAreLoading && !hasPresentedAuthenticatedExperience
    }

    var body: some View {
        Group {
            if currentAccount != .none, !shouldShowFullscreenLoading {
                MainTabView(
                    currentAccount: $currentAccount,
                    currentAddress: $currentAddress,
                    currentChainId: $currentChainId,
                    currentChain: $currentChain,
                    nftService: $nftService,
                    pendingShellFlowCorrelationID: $pendingShellFlowCorrelationID,
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
            } else if nftsAreLoading {
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
                    currentAccount: $currentAccount,
                    ensResolver: services.ensResolverFactory(modelContext),
                    services: services
                )
            }
        }
        .onAppear {
            let result = shellLogic.restoreInitialState(
                currentAddress: currentAddress,
                currentChainId: currentChainId,
                accounts: accounts
            )

            currentAddress = result.currentAddress
            currentChain = result.currentChain
            currentAccount = result.currentAccount
            didFinishInitialStateRestore = result.didFinishInitialStateRestore

            if result.shouldProcessPendingDeepLink {
                processPendingDeepLinkIfPossible()
            }

            if !didRecordAppLaunchReceipt {
                let correlationID = UUID().uuidString
                services.receiptEventLoggerFactory(modelContext).recordAppLaunch(
                    accountAddress: result.currentAddress,
                    chain: result.currentChain,
                    correlationID: correlationID
                )
                didRecordAppLaunchReceipt = true
            }
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        .onChange(of: currentAccount) { _, newValue in
            let result = shellLogic.accountDidChange(newAccount: newValue, persistedAddress: currentAddress)

            currentChain = result.currentChain
            currentChainId = result.currentChain.rawValue

            if result.shouldResetRoutes {
                router.resetAllPaths()
            }

            if result.shouldRefreshNFTs {
                let request = shellLogic.makeAccountRefreshRequest(
                    newAccount: newValue,
                    result: result,
                    correlationID: pendingShellFlowCorrelationID
                )
                beginRefresh(for: request, updatesCurrentAddressOnCompletion: true)
            } else {
                accountRefreshTask?.cancel()
                accountRefreshTask = nil
                latestAccountRefreshRequestID = nil
                currentAddress = result.currentAddress
                if result.shouldProcessPendingDeepLink {
                    processPendingDeepLinkIfPossible()
                }
            }
        }
        .onChange(of: currentChain) { _, newValue in
            currentChainId = newValue.rawValue
        }
        .onChange(of: currentAddress) { _, newValue in
            let result = shellLogic.addressDidChange(
                newAddress: newValue,
                currentChain: currentChain,
                accounts: accounts
            )

            if result.shouldResetRoutes {
                router.resetAllPaths()
            }

            if result.currentAddress != currentAddress {
                currentAddress = result.currentAddress
            }
            currentAccount = result.currentAccount
            currentChain = result.currentChain
            currentChainId = result.currentChain.rawValue
            if result.shouldProcessPendingDeepLink {
                processPendingDeepLinkIfPossible()
            }
        }
        .onChange(of: nftsAreLoading) { _, _ in
            processPendingDeepLinkIfPossible()
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else {
                return
            }

            refreshActiveScopeIfStaleAfterForeground()
        }
        .onChange(of: currentAccount) { _, _ in
            updateAuthenticatedPresentationState()
        }
        .onChange(of: nftsAreLoading) { _, _ in
            updateAuthenticatedPresentationState()
        }
        .sheet(item: $router.presentedRouteError) { routeError in
            RouteErrorScreen(routeError: routeError) {
                router.clearRouteError()
            }
        }
    }

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

    private func handleIncomingURL(_ url: URL) {
        switch deepLinkParser.parse(url: url) {
        case .success(let deepLink):
            pendingDeepLink = deepLink
            processPendingDeepLinkIfPossible()
        case .failure(let routeError):
            routeLogger.error("Rejected deep link: \(url.absoluteString, privacy: .public)")
            router.presentedRouteError = routeError
        }
    }

    private func processPendingDeepLinkIfPossible() {
        guard let pendingDeepLink else { return }

        let resolution = pendingDeepLinkResolver.resolve(
            pendingDeepLink,
            context: PendingDeepLinkContext(
                currentAddress: currentAddress,
                currentAccountAddress: currentAccount?.address,
                canResolveDeferredLink: canResolveDeferredLink,
                shouldFailDeferredLink: shouldFailDeferredLink
            )
        )

        if let chain = resolution.chainOverride {
            currentChain = chain
            currentChainId = chain.rawValue
        }

        switch resolution.action {
        case .wait:
            return
        case .switchAccount(let address):
            router.resetAllPaths()
            router.selectedTab = .home
            currentAddress = address
        case .showHome:
            router.resetAllPaths()
            router.selectedTab = .home
            self.pendingDeepLink = nil
        case .route(let destination, let inheritedChain):
            route(to: destination, inheritedChain: inheritedChain)
            self.pendingDeepLink = nil
        case .showError(let routeError):
            router.presentedRouteError = routeError
            self.pendingDeepLink = nil
        }
    }

    private func route(to destination: AppDeepLinkDestination, inheritedChain: Chain?) {
        switch destination {
        case .nft(let id):
            do {
                let normalizedAccountAddress = NFT.normalizedScopeComponent(currentAccount?.address ?? currentAddress) ?? ""
                let descriptor = FetchDescriptor<NFT>(
                    predicate: #Predicate<NFT> {
                        $0.id == id &&
                        $0.accountAddressRawValue == normalizedAccountAddress &&
                        $0.networkRawValue == currentChain.rawValue
                    }
                )
                guard let nft = try modelContext.fetch(descriptor).first else {
                    router.showRouteError(
                        title: "NFT Not Found",
                        message: "The requested NFT could not be resolved for the current account.",
                        urlString: nil
                    )
                    return
                }

                router.showNFTFromHome(nft)
            } catch {
                routeLogger.error("Failed to resolve NFT deep link \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                router.showRouteError(
                    title: "NFT Lookup Failed",
                    message: "Auralis could not resolve the requested NFT.",
                    urlString: nil
                )
            }

        case .token(let contractAddress, let chain, let symbol):
            let resolvedChain = chain ?? inheritedChain ?? currentChain

            router.showERC20Token(
                contractAddress: contractAddress,
                chain: resolvedChain,
                symbol: symbol
            )

        case .receipt(let id):
            router.showReceipt(id: id)
        }
    }

    private var canResolveDeferredLink: Bool {
        currentAccount != nil && !nftsAreLoading
    }

    private var shouldFailDeferredLink: Bool {
        didFinishInitialStateRestore && currentAccount == nil && currentAddress.isEmpty && !nftsAreLoading
    }

    private func updateAuthenticatedPresentationState() {
        guard currentAccount != nil, !nftsAreLoading else {
            return
        }

        hasPresentedAuthenticatedExperience = true
    }

    private func beginRefresh(
        for request: MainAuraAccountRefreshRequest?,
        updatesCurrentAddressOnCompletion: Bool
    ) {
        isLoading = true
        latestAccountRefreshRequestID = request?.requestID
        accountRefreshTask?.cancel()

        accountRefreshTask = Task {
            guard let request else {
                await MainActor.run {
                    if latestAccountRefreshRequestID == nil {
                        isLoading = false
                    }
                }
                return
            }

            await nftService.refreshNFTs(
                for: request.account,
                chain: request.chain,
                modelContext: modelContext,
                correlationID: request.correlationID
            )

            await MainActor.run {
                guard shellLogic.shouldApplyRefreshCompletion(
                    for: request,
                    latestRequestID: latestAccountRefreshRequestID
                ) else {
                    return
                }

                latestAccountRefreshRequestID = nil
                accountRefreshTask = nil
                isLoading = false
                if updatesCurrentAddressOnCompletion {
                    currentAddress = request.currentAddress
                }
                processPendingDeepLinkIfPossible()
                updateAuthenticatedPresentationState()
            }
        }
    }

    private func refreshActiveScopeIfStaleAfterForeground() {
        guard let currentAccount else {
            return
        }

        guard !nftsAreLoading, accountRefreshTask == nil else {
            return
        }

        let isStale: Bool
        if let lastSuccessfulRefreshAt = nftService.lastSuccessfulRefreshAt {
            isStale = Date().timeIntervalSince(lastSuccessfulRefreshAt) >= nftService.refreshTTL
        } else {
            isStale = true
        }

        guard isStale else {
            return
        }

        let request = MainAuraAccountRefreshRequest(
            requestID: UUID(),
            account: currentAccount,
            chain: currentChain,
            currentAddress: currentAddress,
            correlationID: UUID().uuidString
        )
        pendingShellFlowCorrelationID = request.correlationID
        beginRefresh(for: request, updatesCurrentAddressOnCompletion: false)
    }
}
