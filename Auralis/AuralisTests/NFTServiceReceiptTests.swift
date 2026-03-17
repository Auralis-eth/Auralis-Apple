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
