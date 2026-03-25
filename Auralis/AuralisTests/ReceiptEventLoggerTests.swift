import Foundation
import SwiftData
import Testing
@testable import Auralis

@Suite
struct ReceiptEventLoggerTests {
    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([StoredReceipt.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @Test("receipt event logger records app launch, context build, link open, and copy actions")
    @MainActor
    func loggerRecordsPhaseFourActions() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = SwiftDataReceiptStore(modelContext: context)
        let logger = ReceiptEventLogger(receiptStore: store)
        let snapshot = LiveContextSource(
            accountProvider: { nil },
            addressProvider: { "0x1234567890abcdef1234567890abcdef12345678" },
            chainProvider: { .baseMainnet },
            modeProvider: { .observe },
            loadingProvider: { false },
            refreshedAtProvider: { Date() },
            freshnessTTLProvider: { 300 },
            trackedNFTCountProvider: { 12 },
            prefersDemoDataProvider: { false }
        ).snapshot()

        logger.recordAppLaunch(
            accountAddress: snapshot.scope.accountAddress.value ?? "",
            chain: .baseMainnet,
            correlationID: "launch-1"
        )
        logger.recordContextBuilt(snapshot: snapshot, correlationID: "context-1")
        logger.recordExternalLinkOpened(
            label: "OpenSea",
            url: URL(string: "https://opensea.io/assets/ethereum/0xabc/1")!,
            surface: "newsfeed.nft_detail",
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .baseMainnet,
            correlationID: "link-1"
        )
        logger.recordCopyAction(
            subject: "nft.id",
            value: "nft-123",
            surface: "newsfeed.card",
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .baseMainnet,
            correlationID: "copy-1"
        )

        let receipts = try store.latest(limit: 10)

        #expect(receipts.map(\.kind) == [
            "copy.performed",
            "external_link.opened",
            "context.built",
            "app.launch"
        ])
        let contextReceipt = try #require(receipts.first(where: { $0.kind == "context.built" }))
        #expect(contextReceipt.details.values["refreshState"] == .string(ContextRefreshState.idle.rawValue))
        #expect(contextReceipt.details.values["isStale"] == .bool(false))
        let linkReceipt = try #require(receipts.first(where: { $0.kind == "external_link.opened" }))
        #expect(linkReceipt.scope == "navigation.external")
        #expect(linkReceipt.details.values["chain"] == .string(Chain.baseMainnet.rawValue))
        #expect(linkReceipt.details.values["accountAddress"] == .string("0x1234567890abcdef1234567890abcdef12345678"))
        let copyReceipt = try #require(receipts.first(where: { $0.kind == "copy.performed" }))
        #expect(copyReceipt.details.values["chain"] == .string(Chain.baseMainnet.rawValue))
        #expect(copyReceipt.details.values["accountAddress"] == .string("0x1234567890abcdef1234567890abcdef12345678"))
    }

    @Test("receipt event logger returns a failure result when the store append fails")
    @MainActor
    func loggerReturnsFailureWhenStoreAppendFails() {
        let logger = ReceiptEventLogger(receiptStore: FailingReceiptStore())

        let result = logger.recordCopyAction(
            subject: "nft.id",
            value: "nft-123",
            surface: "newsfeed.card",
            correlationID: "copy-failure-1"
        )

        switch result {
        case .success:
            Issue.record("Expected receipt logging to fail when the store append throws.")
        case .failure(let error):
            #expect((error as? FailingReceiptStore.StoreError) == .appendFailed)
        }
    }
}

@MainActor
private struct FailingReceiptStore: ReceiptStore {
    enum StoreError: Error, Equatable {
        case appendFailed
    }

    func append(_ receipt: ReceiptDraft) throws -> ReceiptRecord {
        throw StoreError.appendFailed
    }

    func latest(limit: Int) throws -> [ReceiptRecord] {
        []
    }

    func receipts(forCorrelationID correlationID: String, limit: Int) throws -> [ReceiptRecord] {
        []
    }

    func exportAll() throws -> Data {
        Data()
    }

    func resetAll() throws { }
}
