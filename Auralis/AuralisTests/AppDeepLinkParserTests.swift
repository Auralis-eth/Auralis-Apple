@testable import Auralis
import Foundation
import Testing

@Suite struct AppDeepLinkParserTests {
    private let parser = AppDeepLinkParser()

    @Test(
        "parses supported top-level destination routes",
        arguments: [
            (
                "auralis://nft/uitest.visual.nft",
                AppDeepLink.destination(.nft(id: "uitest.visual.nft"))
            ),
            (
                "auralis://token/0xabcdefabcdefabcdefabcdefabcdefabcdefabcd/base-mainnet/USDC",
                AppDeepLink.destination(
                    .token(
                        contractAddress: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
                        chain: .baseMainnet,
                        symbol: "USDC"
                    )
                )
            ),
            (
                "auralis://receipt/0xreceipt123",
                AppDeepLink.destination(.receipt(id: "0xreceipt123"))
            )
        ]
    )
    func parsesTopLevelRoutes(urlString: String, expectedRoute: AppDeepLink) throws {
        let url = try #require(URL(string: urlString))
        let result = parser.parse(url: url)

        switch result {
        case .success(let route):
            #expect(route == expectedRoute)
        case .failure(let error):
            Issue.record("Expected valid route to parse, received \(error.title)")
        }
    }

    @Test("parses account deep link with nested nft route")
    func parsesAccountThenNFTRoute() throws {
        let url = try #require(
            URL(string: "auralis://account/0x1234567890abcdef1234567890abcdef12345678/nft/nft_123")
        )

        let result = parser.parse(url: url)

        switch result {
        case .success(.account(let address, let chain, let destination)):
            #expect(address == "0x1234567890abcdef1234567890abcdef12345678")
            #expect(chain == nil)
            #expect(destination == .nft(id: "nft_123"))
        default:
            Issue.record("Expected nested account+nft deep link to parse")
        }
    }

    @Test("parses account deep link with nested token route and inherited chain")
    func parsesAccountThenTokenRoute() throws {
        let url = try #require(
            URL(string: "auralis://account/0x1234567890abcdef1234567890abcdef12345678/token/0xabcdefabcdefabcdefabcdefabcdefabcdefabcd/USDC?chain=base-mainnet")
        )

        let result = parser.parse(url: url)

        switch result {
        case .success(.account(let address, let chain, let destination)):
            #expect(address == "0x1234567890abcdef1234567890abcdef12345678")
            #expect(chain == .baseMainnet)
            #expect(
                destination == .token(
                    contractAddress: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
                    chain: .baseMainnet,
                    symbol: "USDC"
                )
            )
        default:
            Issue.record("Expected nested account+token deep link to parse")
        }
    }

    @Test("rejects invalid nested route")
    func rejectsInvalidNestedRoute() throws {
        let url = try #require(
            URL(string: "auralis://account/0x1234567890abcdef1234567890abcdef12345678/playlist/42")
        )

        let result = parser.parse(url: url)

        switch result {
        case .failure(let error):
            #expect(error.title == "Invalid Nested Route")
        default:
            Issue.record("Expected invalid nested route to fail parsing")
        }
    }

    @Test(
        "rejects invalid route payloads",
        arguments: [
            (
                "auralis://account/not-an-address",
                "Invalid Account Link"
            ),
            (
                "auralis://account/0x1234567890abcdef1234567890abcdef12345678?chain=not-a-chain",
                "Invalid Chain"
            ),
            (
                "auralis://token/0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
                "Invalid Token Link"
            ),
            (
                "auralis://token/not-a-contract/base-mainnet/USDC",
                "Invalid Token Link"
            ),
            (
                "auralis://nft/",
                "Invalid NFT Link"
            ),
            (
                "auralis://token/0xabcdefabcdefabcdefabcdefabcdefabcdefabcd/not-a-chain/USDC",
                "Invalid Token Link"
            ),
            (
                "auralis://receipt/",
                "Invalid Receipt Link"
            )
        ]
    )
    func rejectsInvalidRoutePayloads(urlString: String, expectedTitle: String) throws {
        let url = try #require(URL(string: urlString))
        let result = parser.parse(url: url)

        switch result {
        case .failure(let error):
            #expect(error.title == expectedTitle)
        default:
            Issue.record("Expected invalid route payload to fail parsing")
        }
    }
}
