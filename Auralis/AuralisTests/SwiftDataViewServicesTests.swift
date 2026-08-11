@testable import Auralis
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import AuralisTestSupport
import Foundation
import ReceiptStorage
import SwiftData
import Testing
import TokenStorage

@MainActor
struct SwiftDataViewServicesTests {
    @Test("home summary service returns scoped counts and recent activity")
    func homeSummaryServiceReturnsScopedCountsAndActivity() throws {
        let context = try makeContext()
        let accountAddress = "0x1234567890abcdef1234567890abcdef12345678"
        let playableNFT = NFTFixture.music
            .with {
                $0.contractAddress = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
                $0.tokenId = "playable"
                $0.accountAddress = accountAddress
                $0.audioUrl = "https://audio.example/track.mp3"
            }
            .build()
        context.insert(playableNFT)
        context.insert(
            NFTFixture.image
                .with {
                    $0.contractAddress = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
                    $0.tokenId = "visual"
                    $0.accountAddress = accountAddress
                }
                .build()
        )
        context.insert(
            try receipt(
                sequenceID: 1,
                summary: "Refreshed wallet",
                accountAddress: accountAddress
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
            NFTFixture.image
                .with {
                    $0.contractAddress = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
                    $0.tokenId = "search-nft"
                    $0.collectionName = "Search Collection"
                    $0.accountAddress = accountAddress
                }
                .build()
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
        context.insert(
            NFTFixture.image
                .with {
                    $0.tokenId = "profile-nft"
                    $0.accountAddress = accountAddress
                }
                .build()
        )
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

        #expect(try #require(summary.account).name == "Profile Wallet")
        #expect(summary.scopedNFTCount == 1)
        #expect(summary.scopedTokenCount == 1)
    }

    @Test("chrome context refresh service returns latest context receipt and related receipts")
    func chromeContextRefreshServiceReturnsContextReceipts() throws {
        let context = try makeContext()
        let accountAddress = "0x1234567890abcdef1234567890abcdef12345678"
        context.insert(
            try receipt(
                sequenceID: 1,
                summary: "Context built",
                trigger: "context.built",
                correlationID: "context-1",
                accountAddress: accountAddress
            )
        )
        context.insert(
            try receipt(
                sequenceID: 2,
                summary: "Related refresh",
                trigger: "nft.fetch.succeeded",
                correlationID: "context-1",
                accountAddress: accountAddress
            )
        )
        try context.save()

        let receipts = try ChromeContextRefreshService(modelContext: context).contextReceipts(
            scope: ReceiptTimelineScope(accountAddress: accountAddress, chain: .ethMainnet)
        )

        #expect(try #require(receipts.latest).summary == "Context built")
        #expect(receipts.related.map(\.summary) == ["Related refresh"])
    }

    private func makeContext() throws -> ModelContext {
        ModelContext(try TestModelContainers.primary())
    }

    private func receipt(
        sequenceID: Int,
        summary: String,
        trigger: String = "home.activity",
        correlationID: String? = nil,
        accountAddress: String
    ) throws -> StoredReceipt {
        try StoredReceiptFixture.successful
            .with {
                $0.sequenceID = sequenceID
                $0.createdAt = Fixture.referenceDate.plus(seconds: TimeInterval(sequenceID))
                $0.trigger = trigger
                $0.summary = summary
                $0.provenance = "local_cache"
                $0.correlationID = correlationID
                $0.accountAddress = accountAddress
                $0.accountSequenceID = sequenceID
                $0.payloadHash = "payload-\(sequenceID)"
                $0.previousReceiptHash = "previous-\(sequenceID)"
                $0.chainHash = "chain-\(sequenceID)"
            }
            .build()
    }
}
