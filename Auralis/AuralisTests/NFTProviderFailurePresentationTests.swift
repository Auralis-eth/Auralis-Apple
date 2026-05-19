@testable import Auralis
import AuralisPrimaryModels
import Foundation
import Testing
import NFTKit
import ProviderKit

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

    @Test("provider abstraction errors preserve offline collection messaging")
    func providerAbstractionOfflinePresentation() throws {
        let failure = try #require(
            NFTProviderFailure(error: ProviderAbstractionError.offline)
        )

        #expect(failure.kind == .offline)
        #expect(failure.message.contains("offline"))
        #expect(failure.isRetryable)
    }

    @Test("alchemy API credential failures stay misconfigured instead of collapsing to unavailable")
    func apiCredentialFailuresStaySpecific() throws {
        let failure = try #require(
            NFTProviderFailure(error: AlchemyNFTService.APIError.unauthorized(message: "bad key"))
        )

        #expect(failure.kind == .misconfigured)
        #expect(failure.message.contains("authenticate with the collection provider"))
        #expect(failure.isRetryable == false)
    }
}
