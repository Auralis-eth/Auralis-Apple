@testable import Auralis
import AuralisPrimaryModels
import Foundation
import Testing
import NFTDomain
import NFTPersistence
import NFTPresentation
import NFTProviderAdapters
import ProviderKit

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
        #expect(
            presentation.message ==
                "Auralis is offline right now. Your last synced collection is still visible so you can keep browsing safely."
        )
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
        #expect(
            presentation.message ==
                "The collection provider is rate-limiting refreshes right now. Wait a moment and try again."
        )
        #expect(presentation.systemImage == "hourglass")
        #expect(presentation.isRetryable)
    }

    @Test("provider abstraction errors preserve offline collection messaging")
    func providerAbstractionOfflinePresentation() throws {
        let failure = try #require(
            NFTProviderFailure(error: ProviderAbstractionError.offline)
        )

        #expect(failure.kind == .offline)
        #expect(
            failure.message ==
                "Auralis could not reach the collection provider because this device appears to be offline."
        )
        #expect(failure.isRetryable)
    }

    @Test("alchemy API credential failures stay misconfigured instead of collapsing to unavailable")
    func apiCredentialFailuresStaySpecific() throws {
        let failure = try #require(
            NFTProviderFailure(error: AlchemyNFTService.APIError.unauthorized(message: "bad key"))
        )

        #expect(failure.kind == .misconfigured)
        #expect(
            failure.message ==
                "Auralis could not authenticate with the collection provider for this build."
        )
        #expect(failure.isRetryable == false)
    }
}
