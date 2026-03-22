//
//  MainAuraView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/19/25.
//

import SwiftUI
import SwiftData
import OSLog

//    var account: EOAccount? //= EOAccount(address: "0x5b93ff82faaf241c15997ea3975419dddd8362c5", access: .readonly)
struct MainAuraView: View {
    @AppStorage("currentAccountAddress") var currentAddress: String = ""
    @AppStorage("currentChainId") var currentChainId: String = Chain.ethMainnet.rawValue
    @State private var currentAccount: EOAccount?
    @State private var currentChain: Chain = .ethMainnet
    @Query private var accounts: [EOAccount]

    @State private var router = AppRouter()

    @Environment(\.modelContext) private var modelContext
    @State private var nftService = NFTService()
    @StateObject private var audioEngine: AudioEngine
    @State private var pendingDeepLink: AppDeepLink?
    @State private var didFinishInitialStateRestore = false

    @State private var isloading: Bool = false
    private let routeLogger = Logger(subsystem: "Auralis", category: "Routing")
    private let deepLinkParser = AppDeepLinkParser()
    private let pendingDeepLinkResolver = PendingDeepLinkResolver()
    private let shellLogic = MainAuraShellLogic()

    var nftsAreLoading: Bool {
        nftService.isLoading || isloading
    }


    var body: some View {
        Group {
            if !nftsAreLoading, currentAccount != .none {
                MainTabView(
                    currentAccount: $currentAccount,
                    currentAddress: $currentAddress,
                    currentChainId: $currentChainId,
                    currentChain: $currentChain,
                    nftService: $nftService,
                    router: router,
                    audioEngine: audioEngine
                )
                    .tabBarMinimizeBehavior(.onScrollDown)
                    .tabViewBottomAccessory {
                        // Wrap the accessory in a container so it gets proper padding and material.
                        MiniPlayerView(audioEngine: audioEngine)
                    }
            } else if nftsAreLoading {
                NFTNewsfeedLoadingView(
                    itemsLoaded: nftService.itemsLoaded,
                    total: nftService.total
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
                GatewayView(currentAccount: $currentAccount)
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
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        .onChange(of: currentAccount) { oldValue, newValue in
            let result = shellLogic.accountDidChange(newAccount: newValue, persistedAddress: currentAddress)

            currentChain = result.currentChain
            currentChainId = result.currentChain.rawValue

            if result.shouldResetRoutes {
                router.resetAllPaths()
            }

            if result.shouldRefreshNFTs {
                isloading = true
                Task {
                    await nftService.refreshNFTs(
                        for: currentAccount,
                        chain: currentChain,
                        modelContext: modelContext,
                        correlationID: UUID().uuidString
                    )
                    await MainActor.run {
                        isloading = false
                        currentAddress = result.currentAddress
                        processPendingDeepLinkIfPossible()
                    }
                }
            } else {
                currentAddress = result.currentAddress
                if result.shouldProcessPendingDeepLink {
                    processPendingDeepLinkIfPossible()
                }
            }
        }
        .onChange(of: currentChain) { oldValue, newValue in
            currentChainId = newValue.rawValue
        }
        .onChange(of: currentAddress) { oldValue, newValue in
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
        .sheet(item: $router.presentedRouteError) { routeError in
            RouteErrorScreen(routeError: routeError) {
                router.clearRouteError()
            }
        }
    }
    
    init() {
        do {
            let engine = try AudioEngine()
            _audioEngine = StateObject(wrappedValue: engine)
        } catch {
            // Fallback for initialization errors
            fatalError("Failed to initialize AudioEngine: \(error)")
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
                let descriptor = FetchDescriptor<NFT>(
                    predicate: #Predicate<NFT> { $0.id == id }
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
}
