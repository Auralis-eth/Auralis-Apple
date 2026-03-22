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
        let failureReceipts = try receiptStore.receipts(forCorrelationID: "failure-pass", limit: 10)
        #expect(failureReceipts.contains(where: { $0.kind == "nft.fetch.failed" }))
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
