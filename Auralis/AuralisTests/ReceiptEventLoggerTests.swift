@testable import Auralis
import Foundation
import SwiftData
import Testing

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
    func loggerRecordsPhaseFourActions() async throws {
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

        _ = try await logger.recordAppLaunch(
            accountAddress: snapshot.scope.accountAddress.value ?? "",
            chain: Chain.baseMainnet,
            correlationID: "launch-1"
        )
        _ = try await logger.recordContextBuilt(snapshot: snapshot, correlationID: "context-1")
        _ = try await logger.recordExternalLinkOpened(
            label: "OpenSea",
            url: URL(string: "https://opensea.io/assets/ethereum/0xabc/1")!,
            surface: "newsfeed.nft_detail",
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: Chain.baseMainnet,
            correlationID: "link-1"
        )
        _ = try await logger.recordCopyAction(
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
        #expect(linkReceipt.provenance == ExternalLinkOpenProvenance.userConfirmedTap.rawValue)
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
    func loggerReturnsFailureWhenStoreAppendFails() async {
        let logger = ReceiptEventLogger(receiptStore: FailingReceiptStore())

        await #expect(throws: FailingReceiptStore.StoreError.appendFailed) {
            _ = try await logger.recordCopyAction(
                subject: "nft.id",
                value: "nft-123",
                surface: "newsfeed.card",
                correlationID: "copy-failure-1"
            )
        }
    }

    @Test("receipt event logger preserves correlation and non-sensitive provenance while redacting mounted sensitive payloads")
    @MainActor
    func loggerRedactsSensitivePayloadsWithoutDroppingFlowContext() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = SwiftDataReceiptStore(
            modelContext: context,
            sequenceAllocator: ReceiptSequenceAllocator()
        )
        let logger = ReceiptEventLogger(receiptStore: store)

        _ = try await logger.recordExternalLinkOpened(
            label: "Explorer",
            url: URL(string: "https://basescan.org/token/0xabc?a=123")!,
            surface: "newsfeed.nft_detail",
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: Chain.baseMainnet,
            correlationID: "link-flow"
        )
        _ = try await logger.recordCopyAction(
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
        #expect(linkReceipt.details.values["provenance"] == ReceiptJSONValue.string(ExternalLinkOpenProvenance.userConfirmedTap.rawValue))
        #expect(linkReceipt.details.values["url"] == ReceiptJSONValue.string("<redacted-url>"))
        #expect(copyReceipt.details.values["subject"] == ReceiptJSONValue.string("wallet.address"))
        #expect(copyReceipt.details.values["surface"] == ReceiptJSONValue.string("profile.detail"))
        #expect(copyReceipt.details.values["value"] == ReceiptJSONValue.string("<redacted-opaque-token>"))
    }

    @Test("receipt event logger preserves explicit provenance for confirmed operator and plugin opens")
    @MainActor
    func loggerPreservesExternalLinkProvenance() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = SwiftDataReceiptStore(
            modelContext: context,
            sequenceAllocator: ReceiptSequenceAllocator()
        )
        let logger = ReceiptEventLogger(receiptStore: store)

        _ = try await logger.recordExternalLinkOpened(
            label: "Operator",
            url: URL(string: "https://etherscan.io/token/0xabc?a=1")!,
            surface: "operator.console",
            provenance: .operatorConfirmed
        )
        _ = try await logger.recordExternalLinkOpened(
            label: "Plugin",
            url: URL(string: "https://ipfs.io/ipfs/QmHash")!,
            surface: "plugin.runtime",
            provenance: .pluginConfirmed
        )

        let receipts = try store.latest(limit: 10)
        let operatorReceipt = try #require(receipts.first(where: { $0.details.values["surface"] == .string("operator.console") }))
        let pluginReceipt = try #require(receipts.first(where: { $0.details.values["surface"] == .string("plugin.runtime") }))

        #expect(operatorReceipt.actor == .system)
        #expect(operatorReceipt.provenance == ExternalLinkOpenProvenance.operatorConfirmed.rawValue)
        #expect(operatorReceipt.details.values["provenance"] == ReceiptJSONValue.string(ExternalLinkOpenProvenance.operatorConfirmed.rawValue))
        #expect(pluginReceipt.actor == .system)
        #expect(pluginReceipt.provenance == ExternalLinkOpenProvenance.pluginConfirmed.rawValue)
        #expect(pluginReceipt.details.values["provenance"] == ReceiptJSONValue.string(ExternalLinkOpenProvenance.pluginConfirmed.rawValue))
    }
}

@MainActor
private struct FailingReceiptStore: ReceiptStore {
    enum StoreError: Error, Equatable {
        case appendFailed
    }

    func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord {
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

    func resetAll() async throws { }
}
