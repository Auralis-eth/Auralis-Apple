@testable import Auralis
import Testing

@Suite
struct SearchRoutingContractTests {
    @Test("search routes profile matches to the profile owner")
    func searchRoutesProfileMatch() {
        let router = AppRouter()
        let match = SearchLocalMatch(
            kind: .account,
            title: "Primary Wallet",
            subtitle: "0x1234...5678",
            destination: .profile(address: "0x1234567890abcdef1234567890abcdef12345678")
        )

        SearchRootView.route(match: match, router: router)

        #expect(router.selectedTab == .profile)
        #expect(router.profilePath == [.detail(address: "0x1234567890abcdef1234567890abcdef12345678")])
    }

    @Test("search routes token and collection matches back to their owning tabs")
    func searchRoutesOwnedFeatureDestinations() {
        let router = AppRouter()

        SearchRootView.route(
            match: SearchLocalMatch(
                kind: .tokenSymbol,
                title: "USDC",
                subtitle: "Base",
                destination: .token(
                    contractAddress: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
                    chain: .baseMainnet,
                    symbol: "USDC"
                )
            ),
            router: router
        )

        #expect(router.selectedTab == .erc20Tokens)
        #expect(
            router.erc20TokensPath == [
                ERC20TokenRoute(
                    contractAddress: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
                    chain: .baseMainnet,
                    symbol: "USDC"
                )
            ]
        )

        SearchRootView.route(
            match: SearchLocalMatch(
                kind: .collectionName,
                title: "Moonpunks",
                subtitle: "Ethereum",
                destination: .nftCollection(
                    contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                    title: "Moonpunks",
                    chain: .ethMainnet
                )
            ),
            router: router
        )

        #expect(router.selectedTab == .nftTokens)
        #expect(
            router.nftTokensPath.last == .collection(
                contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                title: "Moonpunks",
                chain: .ethMainnet
            )
        )
    }
}
