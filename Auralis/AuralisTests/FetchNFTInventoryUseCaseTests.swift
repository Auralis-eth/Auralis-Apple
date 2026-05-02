@testable import Auralis
import Foundation
import Testing

@Suite
struct FetchNFTInventoryUseCaseTests {
    @Test("returns fetched inventory and marks a completed full refresh")
    @MainActor
    func returnsInventoryAndCompletionState() async throws {
        let nft = makeRefreshFixtureNFT()
        let fetcher = FetchUseCaseFetcherStub(
            result: .success([nft]),
            total: 1,
            itemsLoaded: 1,
            currentCursor: nil
        )
        let useCase = LiveFetchNFTInventoryUseCase(nftFetcher: fetcher)

        let inventory = try await useCase.fetchInventory(
            for: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet,
            correlationID: "fetch-complete",
            eventRecorder: NoOpNFTRefreshEventRecorder()
        )

        #expect(inventory.nfts.count == 1)
        #expect(inventory.nfts.first?.id == nft.id)
        #expect(inventory.didCompleteFullRefresh)
    }

    @Test("keeps partial refreshes from pretending cleanup is safe")
    @MainActor
    func detectsPartialRefresh() async throws {
        let fetcher = FetchUseCaseFetcherStub(
            result: .success([]),
            total: 10,
            itemsLoaded: 3,
            currentCursor: "next-page"
        )
        let useCase = LiveFetchNFTInventoryUseCase(nftFetcher: fetcher)

        let inventory = try await useCase.fetchInventory(
            for: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet,
            correlationID: "fetch-partial",
            eventRecorder: NoOpNFTRefreshEventRecorder()
        )

        #expect(!inventory.didCompleteFullRefresh)
    }

    @Test("propagates provider failures")
    @MainActor
    func propagatesFailures() async {
        let expectedError = NFTFetcher.FetcherError.networkError(URLError(.notConnectedToInternet))
        let fetcher = FetchUseCaseFetcherStub(
            result: .failure(expectedError),
            total: 0,
            itemsLoaded: 0,
            currentCursor: nil
        )
        let useCase = LiveFetchNFTInventoryUseCase(nftFetcher: fetcher)

        await #expect(throws: Error.self) {
            _ = try await useCase.fetchInventory(
                for: "0x1234567890abcdef1234567890abcdef12345678",
                chain: .ethMainnet,
                correlationID: "fetch-error",
                eventRecorder: NoOpNFTRefreshEventRecorder()
            )
        }
    }
}

@MainActor
private final class FetchUseCaseFetcherStub: NFTFetching {
    var total: Int?
    var itemsLoaded: Int?
    var loading = false
    var error: Error?
    var currentCursor: String?

    private let result: Result<[NFT], Error>

    init(
        result: Result<[NFT], Error>,
        total: Int?,
        itemsLoaded: Int?,
        currentCursor: String?
    ) {
        self.result = result
        self.total = total
        self.itemsLoaded = itemsLoaded
        self.currentCursor = currentCursor
    }

    func fetchAllNFTs(
        for account: String,
        chain: Chain,
        correlationID: String?,
        eventRecorder: any NFTRefreshEventRecording
    ) async throws -> [NFT] {
        try result.get()
    }

    func reset() {
        total = nil
        itemsLoaded = nil
        loading = false
        error = nil
        currentCursor = nil
    }
}
