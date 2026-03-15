import Foundation
import Testing
@testable import Auralis

@Suite struct AppDeepLinkParserTests {
    private let parser = AppDeepLinkParser()

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
}
