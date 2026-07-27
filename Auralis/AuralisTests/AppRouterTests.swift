@testable import Auralis
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import AuralisShellCore
import AuralisTestSupport
import Testing

@MainActor
struct AppRouterTests {
    @Test("music detail flow keeps the music tab and unwinds one level at a time")
    func musicDetailFlow() {
        let router = AppRouter()

        router.showMusicLibrary()
        #expect(router.selectedTab == .music)
        #expect(router.currentRouteDepth == 0)

        router.showMusicNFTDetail(id: "music-1")
        #expect(router.selectedTab == .music)
        #expect(router.musicPath == [.item(id: "music-1")])
        #expect(router.currentRouteDepth == 1)

        router.popCurrentRoute()
        #expect(router.selectedTab == .music)
        #expect(router.musicPath.isEmpty)
        #expect(router.currentRouteDepth == 0)
    }

    @Test("AuraPlay ecosystem routes append to the music tab")
    func auraPlayEcosystemRoutesUseMusicTab() {
        let router = AppRouter()

        router.showMusicPlaylist(id: "playlist-1")
        router.showMusicCreator(id: "creator:cross", title: "Cross Creator")
        router.showMusicCollectionDetail(key: "eth-mainnet|0xabc", title: "Waves")

        #expect(router.selectedTab == .music)
        #expect(
            router.musicPath == [
                .playlist(id: "playlist-1"),
                .creator(id: "creator:cross", title: "Cross Creator"),
                .collection(key: "eth-mainnet|0xabc", title: "Waves")
            ]
        )
        #expect(router.currentRouteDepth == 3)
    }

    @Test("PiP restoration returns to the music video route without stacking duplicates")
    func pictureInPictureRestorationReturnsToVideoRoute() {
        let router = AppRouter()

        router.showSearch()
        let firstRestoreSucceeded = router.restoreMusicVideoWireframe()
        let secondRestoreSucceeded = router.restoreMusicVideoWireframe()

        #expect(firstRestoreSucceeded)
        #expect(secondRestoreSucceeded)
        #expect(router.selectedTab == .music)
        #expect(router.auxiliarySurface == nil)
        #expect(router.musicPath == [.video])
        #expect(router.currentRouteDepth == 1)
    }

    @Test("token detail flow keeps the NFT Tokens tab and unwinds correctly")
    func nftTokenDetailFlow() {
        let router = AppRouter()

        router.showNFTTokens()
        #expect(router.selectedTab == .nftTokens)
        #expect(router.currentRouteDepth == 0)

        router.showNFTTokensDetail(id: "visual-1")
        #expect(router.selectedTab == .nftTokens)
        #expect(router.nftTokensPath == [.item(id: "visual-1")])
        #expect(router.currentRouteDepth == 1)

        router.popCurrentRoute()
        #expect(router.selectedTab == .nftTokens)
        #expect(router.nftTokensPath.isEmpty)
        #expect(router.currentRouteDepth == 0)
    }

    @Test("ERC-20 routes append details on the ERC-20 tab")
    func erc20RouteFlow() {
        let router = AppRouter()

        router.showERC20Token(
            contractAddress: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
            chain: .baseMainnet,
            symbol: "USDC"
        )

        #expect(router.selectedTab == .erc20Tokens)
        #expect(router.currentRouteDepth == 1)
        #expect(
            router.erc20TokensPath == [
                ERC20TokenRoute(
                    contractAddress: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
                    chain: .baseMainnet,
                    symbol: "USDC"
                )
            ]
        )

        router.popCurrentRoute()
        #expect(router.selectedTab == .erc20Tokens)
        #expect(router.erc20TokensPath.isEmpty)
        #expect(router.currentRouteDepth == 0)
    }

    @Test("home launch routes NFTs by media type")
    func homeLaunchRoutesNFTByMediaType() {
        let router = AppRouter()

        router.showNFTFromHome(id: "music-1", isMusic: true)
        #expect(router.selectedTab == .music)
        #expect(router.musicPath == [.item(id: "music-1")])

        router.resetAllPaths()

        router.showNFTFromHome(id: "visual-1", isMusic: false)
        #expect(router.selectedTab == .nftTokens)
        #expect(router.nftTokensPath == [.item(id: "visual-1")])
    }

    @Test("profile detail routes stay on the profile tab")
    func profileDetailFlow() {
        let router = AppRouter()

        router.showProfileDetail(address: "0x1111111111111111111111111111111111111111")

        #expect(router.selectedTab == .profile)
        #expect(router.profilePath == [.detail(address: "0x1111111111111111111111111111111111111111")])
        #expect(router.currentRouteDepth == 1)
    }

    @Test("NFT collection routes stay on the NFT tab")
    func nftCollectionFlow() {
        let router = AppRouter()

        router.showNFTCollectionDetail(
            contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            title: "Moonpunks",
            chain: .ethMainnet
        )

        #expect(router.selectedTab == .nftTokens)
        #expect(
            router.nftTokensPath == [
                .collection(
                    contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                    title: "Moonpunks",
                    chain: .ethMainnet
                )
            ]
        )
        #expect(router.currentRouteDepth == 1)
    }

    @Test("reset clears every route stack without disturbing the selected tab")
    func resetClearsAllPaths() {
        let router = AppRouter()

        router.showNewsNFTDetail(id: "news-1")
        router.showMusicNFTDetail(id: "music-1")
        router.showNFTTokensDetail(id: "visual-1")
        router.showERC20Token(
            contractAddress: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
            chain: .ethMainnet,
            symbol: "ETH"
        )

        router.resetAllPaths()

        #expect(router.newsPath.isEmpty)
        #expect(router.musicPath.isEmpty)
        #expect(router.nftTokensPath.isEmpty)
        #expect(router.erc20TokensPath.isEmpty)
        #expect(router.selectedTab == .erc20Tokens)
    }

    @Test("search route selects the global search tab without mutating detail stacks")
    func searchRouteFlow() {
        let router = AppRouter()

        router.showMusicNFTDetail(id: "music-1")
        #expect(router.musicPath == [.item(id: "music-1")])

        router.showSearch()

        #expect(router.selectedTab == .search)
        #expect(router.currentRouteDepth == 0)
        #expect(router.musicPath == [.item(id: "music-1")])
    }

    @Test("release tab policy presents search as an auxiliary surface instead of a tab")
    func releaseSearchRouteFlow() {
        let router = AppRouter(tabBarVisibility: .release)

        router.showSearch()

        #expect(router.selectedTab == .home)
        #expect(router.auxiliarySurface == .search)
        #expect(router.selectedTabName == "search")
        #expect(router.currentRouteDepth == 0)
    }

    @Test("release tab policy presents receipts as an auxiliary surface")
    func releaseReceiptsRouteFlow() {
        let router = AppRouter(tabBarVisibility: .release)

        router.showReceipt(id: "receipt-1")

        #expect(router.selectedTab == .home)
        #expect(router.auxiliarySurface == .receipts)
        #expect(router.receiptsPath == [.init(id: "receipt-1")])
        #expect(router.selectedTabName == "receipts")
        #expect(router.currentRouteDepth == 1)
    }

    @Test("release tab policy presents NFT routes as an auxiliary surface")
    func releaseNFTTokensRouteFlow() {
        let router = AppRouter(tabBarVisibility: .release)

        router.showNFTCollectionDetail(
            contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            title: "Moonpunks",
            chain: .ethMainnet
        )

        #expect(router.selectedTab == .home)
        #expect(router.auxiliarySurface == .nftTokens)
        #expect(router.currentRouteDepth == 1)
        #expect(router.selectedTabName == "nftTokens")
    }

    @Test("AuraPlay collection deep links resolve the chain-qualified key using the chain raw value")
    func auraPlayCollectionDeepLinkUsesChainRawValue() throws {
        let router = AppRouter()
        let handler = try AppRouterShellEffectHandler(
            router: router,
            modelContext: TestModelContainers.primary().mainContext
        )
        let selection = ActiveShellSelection(
            address: "0x1111111111111111111111111111111111111111",
            chain: .ethMainnet
        )

        // Explicit chain on the destination wins and must use its raw value ("base-mainnet"),
        // matching the "chain|contract" key format the collection detail resolves against.
        let explicitError = handler.handle(
            .routeDeepLink(
                destination: .auraPlayCollection(identifier: "0xabc", chain: .baseMainnet),
                selection: selection,
                inheritedChain: nil
            )
        )
        #expect(explicitError == nil)
        #expect(router.selectedTab == .music)
        #expect(router.musicPath == [.collection(key: "base-mainnet|0xabc", title: "Collection")])

        // With no explicit chain, the inherited chain is used — still as its raw value.
        router.resetAllPaths()
        let inheritedError = handler.handle(
            .routeDeepLink(
                destination: .auraPlayCollection(identifier: "0xdef", chain: nil),
                selection: selection,
                inheritedChain: .arbMainnet
            )
        )
        #expect(inheritedError == nil)
        #expect(router.musicPath == [.collection(key: "arb-mainnet|0xdef", title: "Collection")])
    }

    @Test("release tab policy presents ERC-20 details as an auxiliary surface")
    func releaseERC20RouteFlow() {
        let router = AppRouter(tabBarVisibility: .release)

        router.showERC20Token(
            contractAddress: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
            chain: .baseMainnet,
            symbol: "USDC"
        )

        #expect(router.selectedTab == .home)
        #expect(router.auxiliarySurface == .erc20Token)
        #expect(router.currentRouteDepth == 1)
        #expect(router.selectedTabName == "erc20Tokens")
    }
}
