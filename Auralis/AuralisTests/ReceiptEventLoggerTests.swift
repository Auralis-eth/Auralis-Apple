@testable import Auralis
import AuralisPrimaryModels
import AuralisContext
import Foundation
import AuralisOperators
import AuralisReceipts
import SwiftData
import Testing

struct ReceiptEventLoggerTests {
    @Test("receipt event logger records app launch, context build, link open, and copy actions")
    @MainActor
    func loggerRecordsPhaseFourActions() async throws {
        let container = try TestModelContainers.inMemory(TestSchemas.receipts)
        let context = ModelContext(container)
        let store = SwiftDataReceiptStore(
            modelContext: context
        )
        let logger = ReceiptEventLogger(receiptStore: store)
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = LiveContextSource(
            accountProvider: { nil },
            addressProvider: { "0x1234567890abcdef1234567890abcdef12345678" },
            chainProvider: { .baseMainnet },
            modeProvider: { .observe },
            loadingProvider: { false },
            refreshedAtProvider: { referenceDate },
            freshnessTTLProvider: { 300 },
            trackedNFTCountProvider: { 12 },
            prefersDemoDataProvider: { false },
            nowProvider: { referenceDate }
        ).snapshot()

        _ = try await logger.recordAppLaunch(
            accountAddress: snapshot.scope.accountAddress.value ?? "",
            chain: Chain.baseMainnet,
            correlationID: "launch-1"
        )
        _ = try await logger.recordContextBuilt(snapshot: snapshot, correlationID: "context-1")
        _ = try await logger.recordExternalLinkOpened(
            label: "OpenSea",
            url: try #require(URL(string: "https://opensea.io/assets/ethereum/0xabc/1")),
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

        let receipts = try await store.latest(limit: 10)

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
        // A real per-address digest, not a constant placeholder. This used to pin
        // `<redacted-opaque-token>`: the sanitizer classified any 24+ character `[A-Za-z0-9_-]` run
        // as an opaque token *before* honouring the declared `.hashed(kind: .walletAddress)`, and a
        // 42-character `0x…` address matches — so every account collapsed to the same string and
        // per-account correlation inside the payload was impossible.
        #expect(maskedLinkAddress.hasPrefix("sha256:"))
        #expect(linkReceipt.details.values["url"] == ReceiptJSONValue.string("<redacted-url>"))
        let copyReceipt = try #require(receipts.first(where: { $0.kind == "copy.performed" }))
        #expect(copyReceipt.details.values["chain"] == ReceiptJSONValue.string(Chain.baseMainnet.rawValue))
        guard case .string(let maskedCopyAddress)? = copyReceipt.details.values["accountAddress"] else {
            Issue.record("Expected sanitized accountAddress")
            return
        }
        #expect(maskedCopyAddress.hasPrefix("sha256:"))
        // Same account in both receipts, so the two digests must agree — that is the property the
        // hash exists for and the one the constant placeholder could not express.
        #expect(maskedCopyAddress == maskedLinkAddress)
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
        let container = try TestModelContainers.inMemory(TestSchemas.receipts)
        let context = ModelContext(container)
        let store = SwiftDataReceiptStore(
            modelContext: context
        )
        let logger = ReceiptEventLogger(receiptStore: store)

        _ = try await logger.recordExternalLinkOpened(
            label: "Explorer",
            url: try #require(URL(string: "https://basescan.org/token/0xabc?a=123")),
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

        let linkReceipt = try #require(try await store.receipts(forCorrelationID: "link-flow", limit: 1).first)
        let copyReceipt = try #require(try await store.receipts(forCorrelationID: "copy-flow", limit: 1).first)

        #expect(linkReceipt.details.values["label"] == ReceiptJSONValue.string("Explorer"))
        #expect(linkReceipt.details.values["surface"] == ReceiptJSONValue.string("newsfeed.nft_detail"))
        #expect(linkReceipt.details.values["provenance"] == ReceiptJSONValue.string(ExternalLinkOpenProvenance.userConfirmedTap.rawValue))
        #expect(linkReceipt.details.values["url"] == ReceiptJSONValue.string("<redacted-url>"))
        #expect(copyReceipt.details.values["subject"] == ReceiptJSONValue.string("wallet.address"))
        #expect(copyReceipt.details.values["surface"] == ReceiptJSONValue.string("profile.detail"))
        // Still fully redacted — the key is `value`, a suspicious fragment — but now named for what
        // it actually held rather than for the opaque-token heuristic that used to win first.
        #expect(copyReceipt.details.values["value"] == ReceiptJSONValue.string("<redacted-wallet-address>"))
    }

    @Test("receipt event logger preserves explicit provenance for confirmed operator and plugin opens")
    @MainActor
    func loggerPreservesExternalLinkProvenance() async throws {
        let container = try TestModelContainers.inMemory(TestSchemas.receipts)
        let context = ModelContext(container)
        let store = SwiftDataReceiptStore(
            modelContext: context
        )
        let logger = ReceiptEventLogger(receiptStore: store)

        _ = try await logger.recordExternalLinkOpened(
            label: "Operator",
            url: try #require(URL(string: "https://etherscan.io/token/0xabc?a=1")),
            surface: "operator.console",
            provenance: .operatorConfirmed
        )
        _ = try await logger.recordExternalLinkOpened(
            label: "Plugin",
            url: try #require(URL(string: "https://ipfs.io/ipfs/QmHash")),
            surface: "plugin.runtime",
            provenance: .pluginConfirmed
        )

        let receipts = try await store.latest(limit: 10)
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

    func latest(limit: Int) async throws -> [ReceiptRecord] {
        []
    }

    func receipts(forCorrelationID correlationID: String, limit: Int) async throws -> [ReceiptRecord] {
        []
    }

    func exportAll() async throws -> Data {
        Data()
    }

    func resetAll() async throws { }
}
