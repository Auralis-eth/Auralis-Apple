import SwiftData
import SwiftUI
import Observation

enum AppTab: Hashable {
    case home
    case news
    case gas
    case music
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

@Observable
final class AppRouter {
    var selectedTab: AppTab = .home
    var newsPath: [NFTDetailRoute] = []
    var musicPath: [NFTDetailRoute] = []
    var nftTokensPath: [NFTDetailRoute] = []
    var erc20TokensPath: [ERC20TokenRoute] = []
    var presentedRouteError: AppRouteError?

    func resetAllPaths() {
        newsPath.removeAll()
        musicPath.removeAll()
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
    @Binding var currentAccount: EOAccount?
    @Binding var currentAddress: String
    @Binding var currentChainId: String
    @Binding var currentChain: Chain
    @Binding var nftService: NFTService
    @Bindable var router: AppRouter
    let audioEngine: AudioEngine

    var body: some View {
        TabView(selection: $router.selectedTab) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                HomeTabView(
                    currentAccount: $currentAccount,
                    currentAddress: $currentAddress,
                    currentChainId: $currentChainId,
                    router: router
                )
            }

            Tab("NewsFeed", systemImage: "bubble.right", value: AppTab.news) {
                NavigationStack(path: $router.newsPath) {
                    NewsFeedView(
                        currentAccount: $currentAccount,
                        nftService: $nftService,
                        currentChain: $currentChain,
                        router: router
                    )
                    .navigationDestination(for: NFTDetailRoute.self) { route in
                        SharedNFTDetailView(route: route)
                    }
                }
                .accessibilityIdentifier("tab.news")
            }

            Tab("Gas", systemImage: "fuelpump", value: AppTab.gas) {
                ZStack(alignment: .bottom) {
                    GatewayBackgroundImage()
                    Color.background.opacity(0.3)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                    GasPriceEstimateView(chain: $currentChain)
                }
            }

            Tab("Music", systemImage: "play.circle", value: AppTab.music) {
                NavigationStack(path: $router.musicPath) {
                    VStack {
                        NFTMusicPlayerApp(
                            audioEngine: audioEngine,
                            onOpenNFT: { nft in
                                router.showMusicNFTDetail(id: nft.id)
                            }
                        )
                    }
                    .navigationDestination(for: NFTDetailRoute.self) { route in
                        SharedNFTDetailView(route: route)
                    }
                }
                .accessibilityIdentifier("tab.music")
            }

            Tab("Profile", systemImage: "person.circle", value: AppTab.profile) {
                Text("SentView()")
                Text("ENS")
            }

            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                Button(action: {}) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.textPrimary)
                        .font(.headline)
                }

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
                    NFTTokensRootView(router: router)
                        .navigationDestination(for: NFTDetailRoute.self) { route in
                            SharedNFTDetailView(route: route)
                        }
                }
                .accessibilityIdentifier("tab.nftTokens")
            }
        }
        .tint(.accent)
    }
}

#Preview {
    struct Wrapper: View {
        @State private var currentAccount: EOAccount? = nil
        @State private var currentAddress: String = ""
        @State private var currentChainId: String = Chain.ethMainnet.rawValue
        @State private var currentChain: Chain = .ethMainnet
        @State private var nftService = NFTService()
        @State private var router = AppRouter()
        let audioEngine: AudioEngine = try! AudioEngine()

        var body: some View {
            MainTabView(
                currentAccount: $currentAccount,
                currentAddress: $currentAddress,
                currentChainId: $currentChainId,
                currentChain: $currentChain,
                nftService: $nftService,
                router: router,
                audioEngine: audioEngine
            )
        }
    }
    return Wrapper()
}

private struct SharedNFTDetailView: View {
    let route: NFTDetailRoute
    @Query private var nfts: [NFT]

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

    var body: some View {
        Group {
            if let nft {
                VStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            AsyncImage(url: imageURL) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.secondary.opacity(0.2))
                                    .overlay {
                                        Image(systemName: "photo")
                                            .font(.largeTitle)
                                            .foregroundStyle(.secondary)
                                    }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                            VStack(alignment: .leading, spacing: 12) {
                                HeadlineFontText(nft.name ?? "Untitled NFT")
                                    .fontWeight(.semibold)
                                    .accessibilityIdentifier("nft.detail.title")

                                if let collectionName = nft.collection?.name ?? nft.collectionName {
                                    SubheadlineFontText(collectionName)
                                }

                                if let description = nft.nftDescription, !description.isEmpty {
                                    SecondaryText(description)
                                }

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
                        .padding()
                    }
                }
                .navigationTitle(nft.name ?? "NFT Detail")
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
}

private struct NFTTokensRootView: View {
    @Query(sort: [SortDescriptor(\NFT.acquiredAt?.blockTimestamp, order: .reverse)]) private var nfts: [NFT]
    let router: AppRouter

    var body: some View {
        VStack(spacing: 0) {
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
        .navigationTitle("NFT Tokens")
        .accessibilityIdentifier("nftTokens.root")
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
private extension Chain {
    var routingDisplayName: String {
        switch self {
        case .ethMainnet:
            return "Ethereum"
        case .polygonMainnet:
            return "Polygon"
        case .arbMainnet:
            return "Arbitrum"
        case .optMainnet:
            return "Optimism"
        case .baseMainnet:
            return "Base"
        default:
            return rawValue.capitalized
        }
    }
}
