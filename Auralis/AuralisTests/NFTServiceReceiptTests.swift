import Foundation
import SwiftData
import Testing
@testable import Auralis

@Suite
struct NFTServiceReceiptTests {
    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([EOAccount.self, NFT.self, Tag.self, StoredReceipt.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @Test("refresh flow carries one caller-provided correlation ID across service fetch and persistence receipts")
    @MainActor
    func refreshFlowUsesSharedCorrelationID() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let receiptStore = SwiftDataReceiptStore(modelContext: context)
        let recorder = ReceiptBackedNFTRefreshEventRecorder(receiptStore: receiptStore)
        let fetcher = StubNFTFetcher()
        let service = NFTService(
            nftFetcher: fetcher,
            eventRecorderFactory: { _ in recorder }
        )
        let account = EOAccount(address: "0x1234567890abcdef1234567890abcdef12345678")
        let correlationID = "refresh-flow-123"

        await service.refreshNFTs(
            for: account,
            chain: .ethMainnet,
            modelContext: context,
            correlationID: correlationID
        )

        let receipts = try receiptStore.receipts(forCorrelationID: correlationID, limit: 10)

        #expect(fetcher.receivedCorrelationIDs == [correlationID])
        #expect(receipts.map(\.kind) == [
            "nft.persistence.completed",
            "nft.fetch.succeeded",
            "nft.refresh.started"
        ])
        #expect(receipts.allSatisfy { $0.correlationID == correlationID })
    }

    @Test("freshness keeps the last successful refresh timestamp when a later refresh fails")
    @MainActor
    func refreshFailureKeepsLastSuccessfulTimestamp() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let receiptStore = SwiftDataReceiptStore(modelContext: context)
        let recorder = ReceiptBackedNFTRefreshEventRecorder(receiptStore: receiptStore)
        let fetcher = FlakyNFTFetcher()
        let service = NFTService(
            nftFetcher: fetcher,
            refreshTTL: 300,
            eventRecorderFactory: { _ in recorder }
        )
        let account = EOAccount(address: "0x1234567890abcdef1234567890abcdef12345678")

        await service.refreshNFTs(
            for: account,
            chain: .ethMainnet,
            modelContext: context,
            correlationID: "success-pass"
        )

        let firstSuccessTimestamp = try #require(service.lastSuccessfulRefreshAt)

        await service.refreshNFTs(
            for: account,
            chain: .ethMainnet,
            modelContext: context,
            correlationID: "failure-pass"
        )

        #expect(service.lastSuccessfulRefreshAt == firstSuccessTimestamp)
        #expect(service.error != nil)
        #expect(service.providerFailure?.kind == .offline)
        let failureReceipts = try receiptStore.receipts(forCorrelationID: "failure-pass", limit: 10)
        #expect(failureReceipts.contains(where: { $0.kind == "nft.fetch.failed" }))
        let fetchFailure = try #require(failureReceipts.first(where: { $0.kind == "nft.fetch.failed" }))
        #expect(fetchFailure.details.values["errorKind"] == .string(NFTProviderFailureKind.offline.rawValue))
        #expect(fetchFailure.details.values["isRetryable"] == .bool(true))
    }

    @Test("duplicate in-flight refreshes coalesce into one fetch for the same account scope")
    @MainActor
    func duplicateRefreshesCoalesce() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let receiptStore = SwiftDataReceiptStore(modelContext: context)
        let recorder = ReceiptBackedNFTRefreshEventRecorder(receiptStore: receiptStore)
        let fetcher = SlowStubNFTFetcher()
        let service = NFTService(
            nftFetcher: fetcher,
            refreshTTL: 300,
            eventRecorderFactory: { _ in recorder }
        )
        let account = EOAccount(address: "0x1234567890abcdef1234567890abcdef12345678")

        async let first: Void = service.refreshNFTs(
            for: account,
            chain: .ethMainnet,
            modelContext: context,
            correlationID: "coalesce-1"
        )
        async let second: Void = service.refreshNFTs(
            for: account,
            chain: .ethMainnet,
            modelContext: context,
            correlationID: "coalesce-2"
        )

        _ = await (first, second)

        #expect(fetcher.fetchCallCount == 1)
    }

    @Test("provider failures map rate-limited and degraded states without relying on raw localized errors")
    @MainActor
    func providerFailuresExposeTypedPresentation() {
        let rateLimitedFailure = NFTProviderFailure(error: NFTFetcher.FetcherError.rateLimited)
        let degradedPresentation = rateLimitedFailure?.presentation(mode: .degraded)

        #expect(rateLimitedFailure?.kind == .rateLimited)
        #expect(rateLimitedFailure?.isRetryable == true)
        #expect(degradedPresentation?.title == "Showing Last Sync")
        #expect(degradedPresentation?.systemImage == "bolt.horizontal.circle")

        let offlineFailure = NFTProviderFailure(
            error: NFTFetcher.FetcherError.networkError(URLError(.notConnectedToInternet))
        )
        let blockingPresentation = offlineFailure?.presentation(mode: .blocking)

        #expect(offlineFailure?.kind == .offline)
        #expect(blockingPresentation?.title == "Collection Unavailable")
        #expect(blockingPresentation?.systemImage == "wifi.slash")
        #expect(blockingPresentation?.isRetryable == true)
    }

    @Test("provider failure presentation switches between blocking and degraded modes based on cached-content visibility")
    @MainActor
    func providerFailurePresentationRespectsCachedContentMode() {
        let service = NFTService(
            nftFetcher: FailingStateNFTFetcher(
                error: NFTFetcher.FetcherError.networkError(URLError(.notConnectedToInternet))
            )
        )

        let blocking = service.providerFailurePresentation(isShowingCachedContent: false)
        let degraded = service.providerFailurePresentation(isShowingCachedContent: true)

        #expect(blocking?.mode == .blocking)
        #expect(blocking?.title == "Collection Unavailable")
        #expect(degraded?.mode == .degraded)
        #expect(degraded?.title == "Refresh Paused")
        #expect(degraded?.isRetryable == true)
    }

    @Test("one shell refresh flow can share a correlation ID across NFT refresh and context build receipts")
    @MainActor
    func shellRefreshFlowSharesCorrelationAcrossNFTAndContextReceipts() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let receiptStore = SwiftDataReceiptStore(modelContext: context)
        let recorder = ReceiptBackedNFTRefreshEventRecorder(receiptStore: receiptStore)
        let fetcher = StubNFTFetcher()
        let nftService = NFTService(
            nftFetcher: fetcher,
            eventRecorderFactory: { _ in recorder }
        )
        let logger = ReceiptEventLogger(receiptStore: receiptStore)
        let account = EOAccount(address: "0x1234567890abcdef1234567890abcdef12345678")
        let correlationID = "shell-flow-correlation-1"

        await nftService.refreshNFTs(
            for: account,
            chain: .ethMainnet,
            modelContext: context,
            correlationID: correlationID
        )

        let contextService = ContextService(
            contextSourceBuilder: LiveShellContextSourceBuilder(),
            accountProvider: { account },
            addressProvider: { account.address },
            chainProvider: { .ethMainnet },
            modeProvider: { .observe },
            loadingProvider: { nftService.isLoading },
            refreshedAtProvider: { nftService.lastSuccessfulRefreshAt },
            freshnessTTLProvider: { nftService.refreshTTL },
            trackedNFTCountProvider: { account.trackedNFTCount },
            prefersDemoDataProvider: { false }
        )

        _ = await contextService.refresh(
            correlationID: correlationID,
            receiptEventLogger: logger
        )

        let receipts = try receiptStore.receipts(forCorrelationID: correlationID, limit: 10)

        #expect(receipts.contains(where: { $0.kind == "nft.refresh.started" }))
        #expect(receipts.contains(where: { $0.kind == "nft.fetch.succeeded" }))
        #expect(receipts.contains(where: { $0.kind == "nft.persistence.completed" }))
        #expect(receipts.contains(where: { $0.kind == "context.built" }))
        #expect(receipts.allSatisfy { $0.correlationID == correlationID })
    }
}

private final class StubNFTFetcher: NFTFetching {
    var total: Int? = 0
    var itemsLoaded: Int? = 0
    var loading = false
    var error: Error?
    var currentCursor: String?
    private(set) var receivedCorrelationIDs: [String?] = []

    func fetchAllNFTs(
        for account: String,
        chain: Chain,
        correlationID: String?,
        eventRecorder: any NFTRefreshEventRecording
    ) async throws -> [NFT] {
        receivedCorrelationIDs.append(correlationID)

        if let correlationID {
            await eventRecorder.recordFetchSucceeded(
                accountAddress: account,
                chain: chain,
                correlationID: correlationID,
                itemCount: 0,
                totalCount: 0
            )
        }

        return []
    }

    func reset() {
        total = nil
        itemsLoaded = 0
        loading = false
        currentCursor = nil
        error = nil
    }
}

private final class FlakyNFTFetcher: NFTFetching {
    var total: Int? = 0
    var itemsLoaded: Int? = 0
    var loading = false
    var error: Error?
    var currentCursor: String?
    private(set) var fetchCallCount = 0

    func fetchAllNFTs(
        for account: String,
        chain: Chain,
        correlationID: String?,
        eventRecorder: any NFTRefreshEventRecording
    ) async throws -> [NFT] {
        fetchCallCount += 1

        if fetchCallCount == 1 {
            if let correlationID {
                await eventRecorder.recordFetchSucceeded(
                    accountAddress: account,
                    chain: chain,
                    correlationID: correlationID,
                    itemCount: 0,
                    totalCount: 0
                )
            }
            return []
        }

        let error = NFTFetcher.FetcherError.networkError(URLError(.notConnectedToInternet))
        if let correlationID {
            await eventRecorder.recordFetchFailed(
                accountAddress: account,
                chain: chain,
                correlationID: correlationID,
                error: error
            )
        }
        throw error
    }

    func reset() {
        total = nil
        itemsLoaded = 0
        loading = false
        currentCursor = nil
        error = nil
    }
}

private final class SlowStubNFTFetcher: NFTFetching {
    var total: Int? = 0
    var itemsLoaded: Int? = 0
    var loading = false
    var error: Error?
    var currentCursor: String?
    private(set) var fetchCallCount = 0

    func fetchAllNFTs(
        for account: String,
        chain: Chain,
        correlationID: String?,
        eventRecorder: any NFTRefreshEventRecording
    ) async throws -> [NFT] {
        fetchCallCount += 1

        if let correlationID {
            await eventRecorder.recordFetchSucceeded(
                accountAddress: account,
                chain: chain,
                correlationID: correlationID,
                itemCount: 0,
                totalCount: 0
            )
        }

        try await Task.sleep(for: .milliseconds(50))
        return []
    }

    func reset() {
        total = nil
        itemsLoaded = 0
        loading = false
        currentCursor = nil
        error = nil
    }
}

private final class FailingStateNFTFetcher: NFTFetching {
    var total: Int? = 0
    var itemsLoaded: Int? = 0
    var loading = false
    var error: Error?
    var currentCursor: String?

    init(error: Error) {
        self.error = error
    }

    func fetchAllNFTs(
        for account: String,
        chain: Chain,
        correlationID: String?,
        eventRecorder: any NFTRefreshEventRecording
    ) async throws -> [NFT] {
        throw error ?? NFTFetcher.FetcherError.networkError(URLError(.unknown))
    }

    func reset() {
        total = nil
        itemsLoaded = 0
        loading = false
        currentCursor = nil
        error = nil
    }
}
