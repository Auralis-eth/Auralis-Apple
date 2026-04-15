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
        let store = SwiftDataReceiptStore(
            modelContext: context,
            sequenceAllocator: ReceiptSequenceAllocator()
        )
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
            chain: Chain.baseMainnet,
            correlationID: "launch-1"
        )
        logger.recordContextBuilt(snapshot: snapshot, correlationID: "context-1")
        logger.recordExternalLinkOpened(
            label: "OpenSea",
            url: URL(string: "https://opensea.io/assets/ethereum/0xabc/1")!,
            surface: "newsfeed.nft_detail",
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: Chain.baseMainnet,
            correlationID: "link-1"
        )
        logger.recordCopyAction(
            subject: "nft.id",
            value: "nft-123",
            surface: "newsfeed.card",
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: Chain.baseMainnet,
            correlationID: "copy-1"
        )

        let receipts = try store.latest(limit: 10)

        #expect(receipts.map { $0.kind } == [
            "copy.performed",
            "external_link.opened",
            "context.built",
            "app.launch"
        ])
        let contextReceipt = try #require(receipts.first(where: { $0.kind == "context.built" }))
        #expect(contextReceipt.details.values["refreshState"] == ReceiptJSONValue.string(ContextRefreshState.idle.rawValue))
        #expect(contextReceipt.details.values["isStale"] == ReceiptJSONValue.bool(false))
        let linkReceipt = try #require(receipts.first(where: { $0.kind == "external_link.opened" }))
        #expect(linkReceipt.scope == "navigation.external")
        #expect(linkReceipt.details.values["chain"] == ReceiptJSONValue.string(Chain.baseMainnet.rawValue))
        guard case .string(let maskedLinkAddress)? = linkReceipt.details.values["accountAddress"] else {
            Issue.record("Expected sanitized accountAddress")
            return
        }
        #expect(maskedLinkAddress == "<redacted-opaque-token>")
        #expect(linkReceipt.details.values["url"] == ReceiptJSONValue.string("<redacted-url>"))
        let copyReceipt = try #require(receipts.first(where: { $0.kind == "copy.performed" }))
        #expect(copyReceipt.details.values["chain"] == ReceiptJSONValue.string(Chain.baseMainnet.rawValue))
        guard case .string(let maskedCopyAddress)? = copyReceipt.details.values["accountAddress"] else {
            Issue.record("Expected sanitized accountAddress")
            return
        }
        #expect(maskedCopyAddress == "<redacted-opaque-token>")
        #expect(copyReceipt.details.values["value"] == ReceiptJSONValue.string("<redacted-copied-value>"))
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

    @Test("receipt event logger preserves correlation and non-sensitive provenance while redacting mounted sensitive payloads")
    @MainActor
    func loggerRedactsSensitivePayloadsWithoutDroppingFlowContext() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = SwiftDataReceiptStore(
            modelContext: context,
            sequenceAllocator: ReceiptSequenceAllocator()
        )
        let logger = ReceiptEventLogger(receiptStore: store)

        logger.recordExternalLinkOpened(
            label: "Explorer",
            url: URL(string: "https://basescan.org/token/0xabc?a=123")!,
            surface: "newsfeed.nft_detail",
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: Chain.baseMainnet,
            correlationID: "link-flow"
        )
        logger.recordCopyAction(
            subject: "wallet.address",
            value: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
            surface: "profile.detail",
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: Chain.baseMainnet,
            correlationID: "copy-flow"
        )

        let linkReceipt = try #require(store.receipts(forCorrelationID: "link-flow", limit: 1).first)
        let copyReceipt = try #require(store.receipts(forCorrelationID: "copy-flow", limit: 1).first)

        #expect(linkReceipt.details.values["label"] == ReceiptJSONValue.string("Explorer"))
        #expect(linkReceipt.details.values["surface"] == ReceiptJSONValue.string("newsfeed.nft_detail"))
        #expect(linkReceipt.details.values["url"] == ReceiptJSONValue.string("<redacted-url>"))
        #expect(copyReceipt.details.values["subject"] == ReceiptJSONValue.string("wallet.address"))
        #expect(copyReceipt.details.values["surface"] == ReceiptJSONValue.string("profile.detail"))
        #expect(copyReceipt.details.values["value"] == ReceiptJSONValue.string("<redacted-opaque-token>"))
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
