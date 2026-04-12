import Foundation
import Testing
@testable import Auralis

@Suite
struct NFTProviderFailurePresentationTests {
    @Test("degraded offline failures preserve cached-browsing language")
    func degradedOfflinePresentation() throws {
        let presentation = try #require(
            NFTProviderFailure(
                error: NFTFetcher.FetcherError.networkError(URLError(.notConnectedToInternet))
            )
        ).presentation(mode: .degraded)

        #expect(presentation.mode == .degraded)
        #expect(presentation.title == "Refresh Paused")
        #expect(presentation.message.contains("last synced collection is still visible"))
        #expect(presentation.systemImage == "bolt.horizontal.circle")
        #expect(presentation.isRetryable)
    }

    @Test("blocking rate-limited failures use explicit delay language")
    func blockingRateLimitedPresentation() throws {
        let presentation = try #require(
            NFTProviderFailure(error: NFTFetcher.FetcherError.rateLimited)
        ).presentation(mode: .blocking)

        #expect(presentation.mode == .blocking)
        #expect(presentation.title == "Refresh Delayed")
        #expect(presentation.message.contains("rate-limiting refreshes"))
        #expect(presentation.systemImage == "hourglass")
        #expect(presentation.isRetryable)
    }
}
