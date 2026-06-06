@testable import Auralis
import AuralisPrimaryModels
import AuralisTestSupport
import Foundation
import NFTDomain
import NFTPersistence
import NFTPresentation
import NFTProviderAdapters
import ProviderKit
import Testing

struct TokenHoldingsPaginationTests {
    @Test("pagination guard rejects repeated cursors")
    func paginationGuardRejectsRepeatedCursors() {
        #expect(throws: ProviderAbstractionError.paginationStalled) {
            try AlchemyTokenHoldingsProvider.updatedEmptyPageCount(
                currentCount: 0,
                requestedPageKey: "cursor-1",
                nextPageKey: "cursor-1",
                returnedItemCount: 1
            )
        }
    }

    @Test("pagination guard rejects repeated empty pages before hanging")
    func paginationGuardRejectsRepeatedEmptyPages() {
        let firstCount = try? AlchemyTokenHoldingsProvider.updatedEmptyPageCount(
            currentCount: 0,
            requestedPageKey: nil,
            nextPageKey: "cursor-1",
            returnedItemCount: 0
        )
        let secondCount = try? AlchemyTokenHoldingsProvider.updatedEmptyPageCount(
            currentCount: try #require(firstCount),
            requestedPageKey: "cursor-1",
            nextPageKey: "cursor-2",
            returnedItemCount: 0
        )

        #expect(firstCount == 1)
        #expect(secondCount == 2)
        #expect(throws: ProviderAbstractionError.paginationStalled) {
            try AlchemyTokenHoldingsProvider.updatedEmptyPageCount(
                currentCount: try #require(secondCount),
                requestedPageKey: "cursor-2",
                nextPageKey: "cursor-3",
                returnedItemCount: 0
            )
        }
    }

    @Test("pagination guard resets after progress or completion")
    func paginationGuardResetsAfterProgressOrCompletion() throws {
        let resetAfterItems = try AlchemyTokenHoldingsProvider.updatedEmptyPageCount(
            currentCount: 2,
            requestedPageKey: "cursor-1",
            nextPageKey: "cursor-2",
            returnedItemCount: 3
        )
        let resetAtCompletion = try AlchemyTokenHoldingsProvider.updatedEmptyPageCount(
            currentCount: 2,
            requestedPageKey: "cursor-2",
            nextPageKey: nil,
            returnedItemCount: 0
        )

        #expect(resetAfterItems == 0)
        #expect(resetAtCompletion == 0)
    }
}

struct AlchemyTokenHoldingsProviderWarningTests {
    @Test("provider returns holdings plus warning when enrichment fails")
    func providerReturnsWarningForEnrichmentFailure() async throws {
        let session = URLSession.mocked { request in
            let url = try #require(request.url)

            if url.path.contains("assets/tokens/balances/by-address") {
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data(AlchemyTokenHoldingsFixtures.singleTokenBalancesPayload.utf8))
            }

            let response = HTTPURLResponse(
                url: url,
                statusCode: 503,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data("{}".utf8))
        }

        let provider = AlchemyTokenHoldingsProvider(
            configurationResolver: MockProviderConfigurationResolver(),
            session: session,
            nowProvider: { Date(timeIntervalSince1970: 123) }
        )
        let result = try await provider.tokenHoldings(
            for: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet
        )

        #expect(result.holdings.count == 1)
        #expect(result.holdings[0].isPlaceholder)
        #expect(result.warning?.message.isEmpty == false)
    }

    @Test("unauthorized enrichment failures surface instead of degrading into a generic warning")
    func unauthorizedEnrichmentFailureThrows() async throws {
        let session = URLSession.mocked { request in
            let url = try #require(request.url)

            if url.path.contains("assets/tokens/balances/by-address") {
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data(AlchemyTokenHoldingsFixtures.singleTokenBalancesPayload.utf8))
            }

            let response = HTTPURLResponse(
                url: url,
                statusCode: 403,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(#"{"message":"unauthorized"}"#.utf8))
        }

        let provider = AlchemyTokenHoldingsProvider(
            configurationResolver: MockProviderConfigurationResolver(),
            session: session,
            nowProvider: { Date(timeIntervalSince1970: 123) }
        )
        await #expect(throws: ProviderAbstractionError.unauthorized) {
            _ = try await provider.tokenHoldings(
                for: "0x1234567890abcdef1234567890abcdef12345678",
                chain: .ethMainnet
            )
        }
    }
}

private struct MockProviderConfigurationResolver: ProviderConfigurationResolving {
    func configuration(for chain: Chain) throws -> ProviderEndpointConfiguration {
        ProviderEndpointConfiguration(
            chain: chain,
            alchemyNFTBaseURL: nil,
            alchemyDataAPIBaseURL: URL(string: "https://example.com/data/v1/demo"),
            alchemyRPCURL: nil
        )
    }
}

private enum AlchemyTokenHoldingsFixtures {
    static let singleTokenBalancesPayload = """
    {
      "data": {
        "tokens": [
          {
            "network": "eth-mainnet",
            "address": "0x1234567890abcdef1234567890abcdef12345678",
            "tokenAddress": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
            "tokenBalance": "1230000"
          }
        ],
        "pageKey": null
      }
    }
    """
}
