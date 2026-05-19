@testable import Auralis
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import ReceiptStorage
import SwiftData
import Testing
import TokenStorage

@MainActor
@Suite
struct SwiftDataViewServicesTests {
    @Test("home summary service returns scoped counts and recent activity")
    func homeSummaryServiceReturnsScopedCountsAndActivity() throws {
        let context = try makeContext()
        let accountAddress = "0x1234567890abcdef1234567890abcdef12345678"
        let playableNFT = makeRefreshFixtureNFT(
            contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            tokenId: "playable",
            accountAddress: accountAddress
        )
        playableNFT.audioUrl = "https://audio.example/track.mp3"
        context.insert(playableNFT)
        context.insert(
            makeRefreshFixtureNFT(
                contractAddress: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                tokenId: "visual",
                accountAddress: accountAddress
            )
        )
        context.insert(
            try makeReceipt(
                sequenceID: 1,
                summary: "Refreshed wallet",
                accountAddress: accountAddress,
                chain: .ethMainnet
            )
        )
        try context.save()

        let service = HomeScopedNFTCountService(modelContext: context)
        let counts = try service.counts(accountAddress: accountAddress, chain: .ethMainnet)
        let activity = try service.recentActivity(accountAddress: accountAddress, chain: .ethMainnet)

        #expect(counts.scopedNFTCount == 2)
        #expect(counts.musicNFTCount == 1)
        #expect(activity.map(\.summary) == ["Refreshed wallet"])
    }

    @Test("search index builder includes account NFT and token snapshots")
    func searchIndexBuilderIncludesLocalSnapshots() async throws {
        let context = try makeContext()
        let accountAddress = "0x1234567890abcdef1234567890abcdef12345678"
        context.insert(EOAccount(address: accountAddress, name: "Primary Wallet"))
        context.insert(
            makeRefreshFixtureNFT(
                contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                tokenId: "search-nft",
                collectionName: "Search Collection",
                accountAddress: accountAddress
            )
        )
        context.insert(
            TokenHolding(
                accountAddress: accountAddress,
                chain: .ethMainnet,
                contractAddress: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                symbol: "TOK",
                displayName: "Search Token",
                amountDisplay: "10",
                balanceKind: .erc20,
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
        try context.save()

        let index = try await SearchIndexBuilder(modelContext: context).makeIndex(
            currentAccountAddress: accountAddress,
            currentChain: .ethMainnet
        )

        #expect(index.accounts.contains { $0.displayName == "Primary Wallet" })
        #expect(index.collections.contains { $0.displayName == "Search Collection" })
        #expect(index.tokenSymbols.contains { $0.symbol == "TOK" && $0.label == "Search Token" })
    }

    @Test("profile asset summary service returns account and scoped counts")
    func profileAssetSummaryServiceReturnsScopedCounts() throws {
        let context = try makeContext()
        let accountAddress = "0x1234567890abcdef1234567890abcdef12345678"
        context.insert(EOAccount(address: accountAddress, name: "Profile Wallet"))
        context.insert(makeRefreshFixtureNFT(tokenId: "profile-nft", accountAddress: accountAddress))
        context.insert(
            TokenHolding(
                accountAddress: accountAddress,
                chain: .ethMainnet,
                symbol: "ETH",
                displayName: "Ethereum Native",
                amountDisplay: "1 ETH",
                balanceKind: .native,
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
        try context.save()

        let summary = try ProfileAssetSummaryService(modelContext: context).summary(
            accountAddress: accountAddress,
            chain: .ethMainnet
        )

        #expect(summary.account?.name == "Profile Wallet")
        #expect(summary.scopedNFTCount == 1)
        #expect(summary.scopedTokenCount == 1)
    }

    @Test("chrome context refresh service returns latest context receipt and related receipts")
    func chromeContextRefreshServiceReturnsContextReceipts() throws {
        let context = try makeContext()
        let accountAddress = "0x1234567890abcdef1234567890abcdef12345678"
        context.insert(
            try makeReceipt(
                sequenceID: 1,
                summary: "Context built",
                trigger: "context.built",
                correlationID: "context-1",
                accountAddress: accountAddress,
                chain: .ethMainnet
            )
        )
        context.insert(
            try makeReceipt(
                sequenceID: 2,
                summary: "Related refresh",
                trigger: "nft.fetch.succeeded",
                correlationID: "context-1",
                accountAddress: accountAddress,
                chain: .ethMainnet
            )
        )
        try context.save()

        let receipts = try ChromeContextRefreshService(modelContext: context).contextReceipts(
            scope: ReceiptTimelineScope(accountAddress: accountAddress, chain: .ethMainnet)
        )

        #expect(receipts.latest?.summary == "Context built")
        #expect(receipts.related.map(\.summary) == ["Related refresh"])
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema([EOAccount.self, NFT.self, Tag.self, StoredReceipt.self, TokenHolding.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeReceipt(
        sequenceID: Int,
        summary: String,
        trigger: String = "home.activity",
        correlationID: String? = nil,
        accountAddress: String,
        chain: Chain
    ) throws -> StoredReceipt {
        try StoredReceipt(
            sequenceID: sequenceID,
            createdAt: Date(timeIntervalSince1970: TimeInterval(sequenceID)),
            actor: .system,
            mode: .observe,
            trigger: trigger,
            scope: "tests",
            summary: summary,
            provenance: "local_cache",
            isSuccess: true,
            correlationID: correlationID,
            timelineAccountAddress: accountAddress,
            timelineChainRawValue: chain.rawValue,
            accountSequenceID: sequenceID,
            payloadHash: "payload-\(sequenceID)",
            previousReceiptHash: "previous-\(sequenceID)",
            chainHash: "chain-\(sequenceID)",
            details: ReceiptPayload(values: [:])
        )
    }
}
