@testable import Auralis
import Foundation
import Testing

@Suite
@MainActor
struct NFTImageLoaderTests {
    @Test("default loaders share the reusable session")
    func defaultLoadersReuseSharedSession() {
        let firstLoader = ImageLoader(url: URL(string: "https://example.com/first.png")!)
        let secondLoader = ImageLoader(url: URL(string: "https://example.com/second.png")!)

        let firstSession = Mirror(reflecting: firstLoader).descendant("session") as? URLSession
        let secondSession = Mirror(reflecting: secondLoader).descendant("session") as? URLSession

        #expect(firstSession != nil)
        #expect(secondSession != nil)
        #expect(firstSession === secondSession)
        #expect(firstSession === ImageLoader.defaultSession)
    }

    @Test("mp4 URL extension rejects immediately and clears loading state")
    func mp4ExtensionRejectClearsLoading() async {
        let loader = ImageLoader(url: URL(string: "https://example.com/clip.mp4")!)
        loader.loadIfNeeded()

        await Task.yield()

        #expect(loader.isLoading == false)
        #expect(loader.image == nil)
        if case .videoData = loader.error {
        } else {
            Issue.record("Expected videoData error for mp4 URL extension.")
        }
    }

    @Test("mp4 content type rejects and clears loading state")
    func mp4ContentTypeRejectClearsLoading() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "video/mp4"]
            )!
            return (response, Data())
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer {
            MockURLProtocol.handler = nil
        }

        let loader = ImageLoader(
            url: URL(string: "https://example.com/not-an-image")!,
            session: session
        )
        loader.loadIfNeeded()

        for _ in 0..<20 {
            if loader.isLoading == false {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(loader.isLoading == false)
        #expect(loader.image == nil)
        if case .videoData = loader.error {
        } else {
            Issue.record("Expected videoData error for video content type.")
        }
    }
}

private final class MockURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (URLResponse, Data)

    // Safety invariant: tests install and clear the handler around a single request flow.
    nonisolated(unsafe) static var handler: Handler?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "example.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@Suite
struct AlchemyTokenHoldingsProviderPaginationTests {
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
@Suite
struct AlchemyTokenHoldingsProviderWarningTests {
    @Test("provider returns holdings plus warning when enrichment fails")
    func providerReturnsWarningForEnrichmentFailure() async throws {
        MockURLProtocol.handler = { request in
            let url = try #require(request.url)

            if url.path.contains("assets/tokens/balances/by-address") {
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                let data = """
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
                """.data(using: .utf8)!
                return (response, data)
            }

            let response = HTTPURLResponse(
                url: url,
                statusCode: 503,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data("{}".utf8))
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let provider = AlchemyTokenHoldingsProvider(
            configurationResolver: MockProviderConfigurationResolver(),
            session: session,
            nowProvider: { Date(timeIntervalSince1970: 123) }
        )
        defer {
            MockURLProtocol.handler = nil
        }

        let result = try await provider.tokenHoldings(
            for: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet
        )

        #expect(result.holdings.count == 1)
        #expect(result.holdings[0].isPlaceholder)
        #expect(result.warning?.message.isEmpty == false)
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
