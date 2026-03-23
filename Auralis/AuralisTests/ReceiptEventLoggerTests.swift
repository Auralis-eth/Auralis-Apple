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
            refreshedAtProvider: { Date(timeIntervalSince1970: 1_700_000_000) },
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
            correlationID: "link-1"
        )
        logger.recordCopyAction(
            subject: "nft.id",
            value: "nft-123",
            surface: "newsfeed.card",
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
    }
}
