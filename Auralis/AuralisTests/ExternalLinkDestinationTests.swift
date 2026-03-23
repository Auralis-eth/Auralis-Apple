import Foundation
import Testing
@testable import Auralis

@Suite
struct ExternalLinkDestinationTests {
    @Test("OpenSea URLs are chain aware and unsupported chains stay hidden")
    func openSeaURLsFollowChainSupport() {
        let baseURL = Chain.baseMainnet.openSeaURL(contractAddress: "0xabc", tokenId: "1")
        #expect(baseURL?.absoluteString == "https://opensea.io/assets/base/0xabc/1")

        let unsupportedURL = Chain.baseSepoliaTestnet.openSeaURL(contractAddress: "0xabc", tokenId: "1")
        #expect(unsupportedURL == nil)
    }

    @Test("Explorer URLs use the chain-specific scanner host")
    func explorerURLsFollowChain() {
        let baseURL = Chain.baseMainnet.nftExplorerURL(contractAddress: "0xabc", tokenId: "1")
        #expect(baseURL?.absoluteString == "https://basescan.org/token/0xabc?a=1")

        let arbitrumLabel = Chain.arbMainnet.nftExplorerDestination?.label
        #expect(arbitrumLabel == "Arbiscan")
    }
}
