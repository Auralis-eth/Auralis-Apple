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

    @State private var isloading: Bool = false
    private let routeLogger = Logger(subsystem: "Auralis", category: "Routing")
    private let deepLinkParser = AppDeepLinkParser()

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
            currentChain = Chain(rawValue: currentChainId) ?? .ethMainnet

            guard !currentAddress.isEmpty else {
                currentAccount = nil
                return
            }

            let fetchResult = accounts.filter { $0.address == currentAddress }
            if let first = fetchResult.first {
                currentAccount = first
            } else {
                let account = EOAccount(address: currentAddress)
                currentAccount = account
            }
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        .onChange(of: currentAccount) { oldValue, newValue in
            if currentAccount?.address != currentAddress, currentAccount != nil {
                router.resetAllPaths()
                isloading = true
                Task {
                    await nftService.refreshNFTs(for: currentAccount, chain: currentChain, modelContext: modelContext)
                    await MainActor.run {
                        isloading = false
                        processPendingDeepLinkIfPossible()
                    }
                }
            }

            currentAddress = newValue?.address ?? ""
            processPendingDeepLinkIfPossible()
        }
        .onChange(of: currentChain) { oldValue, newValue in
            currentChainId = newValue.rawValue
        }
        .onChange(of: currentAddress) { oldValue, newValue in
            router.resetAllPaths()
            guard !newValue.isEmpty else {
                currentAccount = nil
                processPendingDeepLinkIfPossible()
                return
            }
            let fetchResult = accounts.filter { $0.address == newValue }
            if let first = fetchResult.first {
                currentAccount = first
            } else {
                let account = EOAccount(address: currentAddress)
                currentAccount = account
            }
            processPendingDeepLinkIfPossible()
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

        switch pendingDeepLink {
        case .account(let address, let chain, let destination):
            if let chain {
                currentChain = chain
                currentChainId = chain.rawValue
            }

            if currentAddress != address {
                router.resetAllPaths()
                router.selectedTab = .home
                currentAddress = address
                return
            }

            guard canResolveDeferredLink else {
                if shouldFailDeferredLink {
                    let message = destination == nil
                        ? "Open or restore an account before using this account link."
                        : "Open or restore an account before routing this deep link."
                    router.showRouteError(
                        title: "No Active Account",
                        message: message,
                        urlString: nil
                    )
                    self.pendingDeepLink = nil
                }
                return
            }

            guard currentAccount?.address == address else { return }

            if let destination {
                route(to: destination, inheritedChain: chain)
            } else {
                router.resetAllPaths()
                router.selectedTab = .home
            }

            self.pendingDeepLink = nil

        case .destination(let destination):
            guard canResolveDeferredLink else {
                if shouldFailDeferredLink {
                    router.showRouteError(
                        title: "No Active Account",
                        message: "Open or restore an account before routing this deep link.",
                        urlString: nil
                    )
                    self.pendingDeepLink = nil
                }
                return
            }

            route(to: destination, inheritedChain: nil)
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
            routeLogger.error("Receipt deep link is unsupported in Phase 0: \(id, privacy: .public)")
            router.showRouteError(
                title: "Receipt Link Unsupported",
                message: "Receipt deep links are not supported in this phase yet.",
                urlString: nil
            )
        }
    }

    private var canResolveDeferredLink: Bool {
        currentAccount != nil && !nftsAreLoading
    }

    private var shouldFailDeferredLink: Bool {
        currentAccount == nil && currentAddress.isEmpty && !nftsAreLoading
    }
}
