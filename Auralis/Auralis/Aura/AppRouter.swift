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
    case settings
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

    func showSettings() {
        selectedTab = .profile
        profilePath = profilePath + [.settings]
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
