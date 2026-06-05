import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import Testing
import NFTDomain
import NFTPersistence
import NFTPresentation
import NFTProviderAdapters

@Suite
struct FetchNFTInventoryUseCaseTests {
    @Test("returns fetched inventory and marks a completed full refresh")
    @MainActor
    func returnsInventoryAndCompletionState() async throws {
        let nft = makeRefreshFixtureSnapshot()
        let fetcher = FetchUseCaseFetcherStub(
            result: .success(
                NFTFetchInventoryResult(
                    nfts: [nft],
                    didCompleteFullRefresh: true,
                    totalCount: 1
                )
            )
        )
        let useCase = LiveFetchNFTInventoryUseCase(nftFetcher: fetcher)

        let inventory = try await useCase.fetchInventory(
            for: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet,
            correlationID: "fetch-complete",
            eventRecorder: NoOpNFTRefreshEventRecorder()
        )

        #expect(inventory.nfts.count == 1)
        #expect(try #require(inventory.nfts.first).id == nft.id)
        #expect(inventory.didCompleteFullRefresh)
    }

    @Test("keeps partial refreshes from pretending cleanup is safe")
    @MainActor
    func detectsPartialRefresh() async throws {
        let fetcher = FetchUseCaseFetcherStub(
            result: .success(
                NFTFetchInventoryResult(
                    nfts: [],
                    didCompleteFullRefresh: false,
                    totalCount: 10
                )
            )
        )
        let useCase = LiveFetchNFTInventoryUseCase(nftFetcher: fetcher)

        let inventory = try await useCase.fetchInventory(
            for: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet,
            correlationID: "fetch-partial",
            eventRecorder: NoOpNFTRefreshEventRecorder()
        )

        #expect(inventory.didCompleteFullRefresh == false)
    }

    @Test("propagates provider failures")
    @MainActor
    func propagatesFailures() async {
        let expectedError = NFTFetcher.FetcherError.networkError(URLError(.notConnectedToInternet))
        let fetcher = FetchUseCaseFetcherStub(result: .failure(expectedError))
        let useCase = LiveFetchNFTInventoryUseCase(nftFetcher: fetcher)

        do {
            _ = try await useCase.fetchInventory(
                for: "0x1234567890abcdef1234567890abcdef12345678",
                chain: .ethMainnet,
                correlationID: "fetch-error",
                eventRecorder: NoOpNFTRefreshEventRecorder()
            )
            Issue.record("Expected NFTFetcher.FetcherError.networkError.")
        } catch NFTFetcher.FetcherError.networkError(let error as URLError) {
            #expect(error.code == .notConnectedToInternet)
        } catch {
            Issue.record("Expected NFTFetcher.FetcherError.networkError, got \(error).")
        }
    }
}

private final class FetchUseCaseFetcherStub: NFTFetching {
    private let result: Result<NFTFetchInventoryResult, Error>

    init(result: Result<NFTFetchInventoryResult, Error>) {
        self.result = result
    }

    func fetchAllNFTs(
        for account: String,
        chain: Chain,
        correlationID: String?,
        eventRecorder: any NFTRefreshEventRecording,
        progressHandler: NFTFetchProgressHandler?
    ) async throws -> NFTFetchInventoryResult {
        try result.get()
    }
}
