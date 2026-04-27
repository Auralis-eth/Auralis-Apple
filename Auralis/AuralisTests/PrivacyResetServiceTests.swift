@testable import Auralis
import Foundation
import SwiftData
import Testing

@MainActor
@Suite
struct PrivacyResetServiceTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([SearchHistoryRecord.self, TokenHolding.self, NFT.self, Tag.self, MusicLibraryItem.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @Test("resetLocalPrivacyData clears persisted search history rows")
    func resetLocalPrivacyDataClearsSearchHistory() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let searchHistoryStore = SearchHistoryStore(modelContext: context)
        let tokenHoldingsStore = TokenHoldingsStore(modelContext: context)
        let receiptStore = RecordingReceiptStore()
        let ensCacheResetService = RecordingENSCacheResetService()
        let derivedSupportDataResetService = SwiftDataDerivedSupportDataResetService(
            modelContainer: context.container
        )
        let selectionPersistence = RecordingShellSelectionPersistence()
        let pinnedItemsStore = HomePinnedItemsStore(userDefaults: UserDefaults(suiteName: #function)!)
        let service = PrivacyResetService(
            receiptStore: receiptStore,
            searchHistoryStore: searchHistoryStore,
            ensCacheResetService: ensCacheResetService,
            tokenHoldingsStore: tokenHoldingsStore,
            derivedSupportDataResetService: derivedSupportDataResetService,
            selectionPersistence: selectionPersistence,
            homePinnedItemsStore: pinnedItemsStore
        )

        try await searchHistoryStore.recordCommittedQuery("Moonpunks", accountAddress: nil)
        try await searchHistoryStore.recordCommittedQuery("USDC", accountAddress: "0x1111111111111111111111111111111111111111")
        try await tokenHoldingsStore.upsertNativeHolding(
            accountAddress: "0x1111111111111111111111111111111111111111",
            chain: .ethMainnet,
            amountDisplay: "1.25",
            updatedAt: .now
        )
        try pinnedItemsStore.togglePin(
            .openNews,
            accountAddress: "0x1111111111111111111111111111111111111111"
        )
        context.insert(makeFixtureNFT(tokenId: "moon-1"))
        context.insert(makeFixtureMusicLibraryItem(id: "track-1", sourceNFTID: "music-source-1"))
        try context.save()

        try await service.resetLocalPrivacyData()

        #expect(searchHistoryStore.entries(for: nil).isEmpty)
        #expect(searchHistoryStore.entries(for: "0x1111111111111111111111111111111111111111").isEmpty)
        #expect(receiptStore.resetAllCallCount == 1)
        #expect(await ensCacheResetService.resetCount() == 1)
        #expect(try context.fetch(FetchDescriptor<TokenHolding>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<NFT>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<MusicLibraryItem>()).isEmpty)
        #expect(selectionPersistence.clearSelectionCallCount == 1)
        #expect(pinnedItemsStore.pinnedActions(for: "0x1111111111111111111111111111111111111111").isEmpty)
    }

    @Test("token holdings persistence rejects empty account scope instead of silently succeeding")
    func tokenHoldingsStoreRejectsEmptyAccountScope() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = TokenHoldingsStore(modelContext: context)

        await #expect(throws: TokenHoldingsStoreError.invalidAccountAddress("   ")) {
            try await store.upsertNativeHolding(
                accountAddress: "   ",
                chain: .ethMainnet,
                amountDisplay: "1.25",
                updatedAt: .now
            )
        }

        await #expect(throws: TokenHoldingsStoreError.invalidAccountAddress("")) {
            try await store.replaceERC20Holdings(
                accountAddress: "",
                chain: .ethMainnet,
                holdings: []
            )
        }

        #expect(try context.fetch(FetchDescriptor<TokenHolding>()).isEmpty)
    }
}

private func makeFixtureNFT(
    tokenId: String,
    accountAddress: String = "0x1111111111111111111111111111111111111111",
    contractAddress: String = "0x495f947276749ce646f68ac8c248420045cb7b5e"
) -> NFT {
    let network: Chain = .ethMainnet
    let normalizedAccountAddress = NFT.normalizedScopeComponent(accountAddress) ?? "unscoped"
    let normalizedContractAddress = NFT.normalizedScopeComponent(contractAddress) ?? "unknown"

    return NFT(
        id: "\(normalizedAccountAddress):\(network.rawValue):\(normalizedContractAddress):\(tokenId)",
        contract: NFT.Contract(address: contractAddress, chain: network),
        tokenId: tokenId,
        name: "Fixture \(tokenId)",
        image: nil,
        raw: nil,
        collection: NFT.Collection(
            name: "Fixture Collection",
            chain: network,
            contractAddress: contractAddress
        ),
        tokenUri: "ipfs://fixture-\(tokenId)",
        timeLastUpdated: "2025-01-01T00:00:00Z",
        network: network,
        accountAddress: accountAddress,
        contentType: "audio/mpeg",
        collectionName: "Fixture Collection",
        artistName: "Fixture Artist",
        animationUrl: "https://example.com/\(tokenId).mp3",
        audioUrl: "https://example.com/\(tokenId).mp3"
    )
}

private func makeFixtureMusicLibraryItem(
    id: String,
    sourceNFTID: String
) -> MusicLibraryItem {
    MusicLibraryItem(
        id: id,
        sourceNFTID: sourceNFTID,
        accountAddressRawValue: "0x1111111111111111111111111111111111111111",
        networkRawValue: Chain.ethMainnet.rawValue,
        title: "Fixture Track",
        artistName: "Fixture Artist",
        collectionName: "Fixture Collection",
        normalizedTitleKey: "fixture track",
        normalizedArtistKey: "fixture artist",
        normalizedCollectionKey: "fixture collection",
        artworkURLString: "https://example.com/\(id).png",
        contentType: "audio/mpeg",
        playbackURLString: "https://example.com/\(id).mp3",
        availability: .ready,
        availabilityReason: nil,
        sourceUpdatedAtRawValue: nil
    )
}

@MainActor
private final class RecordingReceiptStore: ReceiptStore {
    private(set) var resetAllCallCount = 0

    func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord {
        fatalError("append is not used in PrivacyResetServiceTests")
    }

    func latest(limit: Int) throws -> [ReceiptRecord] {
        fatalError("latest is not used in PrivacyResetServiceTests")
    }

    func receipts(forCorrelationID correlationID: String, limit: Int) throws -> [ReceiptRecord] {
        fatalError("receipts(forCorrelationID:limit:) is not used in PrivacyResetServiceTests")
    }

    func exportAll() throws -> Data {
        fatalError("exportAll is not used in PrivacyResetServiceTests")
    }

    func resetAll() async throws {
        resetAllCallCount += 1
    }
}

private actor RecordingENSCacheResetService: ENSCacheResetting {
    private var resetCallCount = 0

    func resetCache() async {
        resetCallCount += 1
    }

    func resetCount() -> Int {
        resetCallCount
    }
}

@MainActor
private final class RecordingShellSelectionPersistence: ShellSelectionPersisting {
    private(set) var clearSelectionCallCount = 0

    func loadSelection() -> (address: String, chainID: String) {
        ("", Chain.ethMainnet.rawValue)
    }

    func saveSelection(address: String, chainID: String) { }

    func clearSelection() {
        clearSelectionCallCount += 1
    }
}
