import AuralisPrimaryModels
import AuralisShellCore
import Observation

struct AppTabBarVisibility: Equatable {
    let tabBarTabs: Set<AppTab>

    func showsInTabBar(_ tab: AppTab) -> Bool {
        tabBarTabs.contains(tab)
    }

    static let all = AppTabBarVisibility(tabBarTabs: Set(AppTab.allCases))
    static let release = AppTabBarVisibility(tabBarTabs: [.home, .news, .gas, .music, .profile])

    static var live: AppTabBarVisibility {
        #if DEBUG
        .all
        #else
        .release
        #endif
    }
}

enum AuxiliarySurface: String, Hashable, Identifiable {
    case search
    case receipts
    case nftTokens
    case erc20Token

    var id: String {
        rawValue
    }

    var tab: AppTab {
        switch self {
        case .search:
            return .search
        case .receipts:
            return .receipts
        case .nftTokens:
            return .nftTokens
        case .erc20Token:
            return .erc20Tokens
        }
    }
}

/// Represents a routed NFT detail destination within the news flow.
enum NFTDetailRoute: Hashable {
    case detail(id: String)
}

/// Represents a routed destination within the music flow.
enum MusicRoute: Hashable {
    case item(id: String)
    case collection(key: String, title: String)
}

/// Represents a routed destination within the profile flow.
enum ProfileRoute: Hashable {
    case detail(address: String)
    case settings
}

/// Represents a routed destination within the NFT tokens flow.
enum NFTTokensRoute: Hashable {
    case item(id: String)
    case collection(contractAddress: String?, title: String, chain: Chain)
}

/// Describes a routed ERC-20 token detail destination.
struct ERC20TokenRoute: Hashable {
    let contractAddress: String
    let chain: Chain
    let symbol: String
}

/// Describes a routed receipt destination.
struct ReceiptRoute: Hashable {
    let id: String
}

@Observable
/// Owns top-level tab selection and per-tab navigation state for the app shell.
final class AppRouter {
    var selectedTab: AppTab = .home
    var newsPath: [NFTDetailRoute] = []
    var musicPath: [MusicRoute] = []
    var profilePath: [ProfileRoute] = []
    var receiptsPath: [ReceiptRoute] = []
    var nftTokensPath: [NFTTokensRoute] = []
    var erc20TokensPath: [ERC20TokenRoute] = []
    var presentedRouteError: AppRouteError?
    var auxiliarySurface: AuxiliarySurface?

    let tabBarVisibility: AppTabBarVisibility

    init(tabBarVisibility: AppTabBarVisibility = .live) {
        self.tabBarVisibility = tabBarVisibility
    }

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
        nftTokensPath = nftTokensPath + [.item(id: id)]
        showTabOrPresentAuxiliary(tab: .nftTokens, auxiliarySurface: .nftTokens)
    }

    func showNFTCollectionDetail(contractAddress: String?, title: String, chain: Chain) {
        nftTokensPath = nftTokensPath + [
            .collection(
                contractAddress: contractAddress,
                title: title,
                chain: chain
            )
        ]
        showTabOrPresentAuxiliary(tab: .nftTokens, auxiliarySurface: .nftTokens)
    }

    func showNFTFromHome(_ nft: NFT) {
        if nft.isMusic() {
            showMusicNFTDetail(id: nft.id)
        } else {
            showNFTTokensDetail(id: nft.id)
        }
    }

    func showMusicLibrary() {
        auxiliarySurface = nil
        selectedTab = .music
    }

    func showNFTTokens() {
        showTabOrPresentAuxiliary(tab: .nftTokens, auxiliarySurface: .nftTokens)
    }

    func showERC20Token(contractAddress: String, chain: Chain, symbol: String) {
        erc20TokensPath = erc20TokensPath + [
            ERC20TokenRoute(
                contractAddress: contractAddress,
                chain: chain,
                symbol: symbol
            )
        ]
        showTabOrPresentAuxiliary(tab: .erc20Tokens, auxiliarySurface: .erc20Token)
    }

    func showReceipts() {
        showTabOrPresentAuxiliary(tab: .receipts, auxiliarySurface: .receipts)
    }

    func showSearch() {
        showTabOrPresentAuxiliary(tab: .search, auxiliarySurface: .search)
    }

    func showProfileDetail(address: String) {
        auxiliarySurface = nil
        selectedTab = .profile
        profilePath = profilePath + [.detail(address: address)]
    }

    func showSettings() {
        auxiliarySurface = nil
        selectedTab = .profile
        profilePath = profilePath + [.settings]
    }

    func showReceipt(id: String) {
        receiptsPath = [.init(id: id)]
        showTabOrPresentAuxiliary(tab: .receipts, auxiliarySurface: .receipts)
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

    func dismissAuxiliarySurface(resetPaths: Bool = false) {
        guard let auxiliarySurface else {
            return
        }

        if resetPaths {
            clearPaths(for: auxiliarySurface)
        }

        self.auxiliarySurface = nil
    }

    var selectedTabName: String {
        switch activeTab {
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
        switch activeTab {
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
        if let auxiliarySurface {
            switch auxiliarySurface {
            case .search:
                dismissAuxiliarySurface(resetPaths: true)
            case .receipts:
                if !receiptsPath.isEmpty {
                    receiptsPath.removeLast()
                }
                if receiptsPath.isEmpty {
                    dismissAuxiliarySurface()
                }
            case .nftTokens:
                if !nftTokensPath.isEmpty {
                    nftTokensPath.removeLast()
                }
                if nftTokensPath.isEmpty {
                    dismissAuxiliarySurface()
                }
            case .erc20Token:
                if !erc20TokensPath.isEmpty {
                    erc20TokensPath.removeLast()
                }
                if erc20TokensPath.isEmpty {
                    dismissAuxiliarySurface()
                }
            }
            return
        }

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

    private var activeTab: AppTab {
        auxiliarySurface?.tab ?? selectedTab
    }

    private func showTabOrPresentAuxiliary(tab: AppTab, auxiliarySurface: AuxiliarySurface) {
        if tabBarVisibility.showsInTabBar(tab) {
            self.auxiliarySurface = nil
            selectedTab = tab
        } else {
            self.auxiliarySurface = auxiliarySurface
        }
    }

    private func clearPaths(for auxiliarySurface: AuxiliarySurface) {
        switch auxiliarySurface {
        case .search:
            break
        case .receipts:
            receiptsPath.removeAll()
        case .nftTokens:
            nftTokensPath.removeAll()
        case .erc20Token:
            erc20TokensPath.removeAll()
        }
    }
}
