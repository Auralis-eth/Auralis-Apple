@testable import Auralis
import Foundation
import SwiftData
import Testing

@MainActor
@Suite
struct PrivacyResetServiceTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            SearchHistoryRecord.self,
            TokenHolding.self,
            EOAccount.self,
            NFT.self,
            Tag.self,
            StoredReceipt.self,
            MusicLibraryItem.self,
        ])
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
        let auraPlayPersistenceResetService = RecordingAuraPlayPersistenceResetService()
        let selectionPersistence = RecordingShellSelectionPersistence()
        let pinnedItemsStore = HomePinnedItemsStore(userDefaults: UserDefaults(suiteName: #function)!)
        let service = PrivacyResetService(
            receiptStore: receiptStore,
            searchHistoryStore: searchHistoryStore,
            ensCacheResetService: ensCacheResetService,
            tokenHoldingsStore: tokenHoldingsStore,
            derivedSupportDataResetService: derivedSupportDataResetService,
            auraPlayPersistenceResetService: auraPlayPersistenceResetService,
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
        #expect(await auraPlayPersistenceResetService.resetCount() == 1)
        #expect(try context.fetch(FetchDescriptor<TokenHolding>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<NFT>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<MusicLibraryItem>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<NFT.Contract>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<NFT.Collection>()).isEmpty)
        #expect(selectionPersistence.clearSelectionCallCount == 1)
        #expect(pinnedItemsStore.pinnedActions(for: "0x1111111111111111111111111111111111111111").isEmpty)
    }

    @Test("removing an account purges only NFTs scoped to that account")
    func accountRemovalPurgesScopedNFTs() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = AccountStore(modelContext: context)

        let removed = try await store.createWatchAccount(
            from: "0x1010101010101010101010101010101010101010",
            now: Date(timeIntervalSince1970: 100)
        )
        let preserved = try await store.createWatchAccount(
            from: "0x2020202020202020202020202020202020202020",
            now: Date(timeIntervalSince1970: 200)
        )

        context.insert(makeFixtureNFT(tokenId: "removed-1", accountAddress: removed.address))
        try await SearchHistoryStore(modelContext: context).recordCommittedQuery("Removed Scope", accountAddress: removed.address)
        try await TokenHoldingsStore(modelContext: context).upsertNativeHolding(
            accountAddress: removed.address,
            chain: .ethMainnet,
            amountDisplay: "4.2",
            updatedAt: .now
        )
        context.insert(makeFixtureNFT(
            tokenId: "preserved-1",
            accountAddress: preserved.address,
            contractAddress: "0x9999999999999999999999999999999999999999"
        ))
        try context.save()

        _ = try await store.removeAccount(
            address: removed.address,
            activeAddress: removed.address
        )

        let remainingNFTs = try context.fetch(FetchDescriptor<NFT>())
        let remainingHoldings = try context.fetch(FetchDescriptor<TokenHolding>())
        #expect(!remainingNFTs.contains(where: { $0.accountAddressRawValue == removed.address }))
        #expect(remainingNFTs.contains(where: { $0.accountAddressRawValue == preserved.address }))
        #expect(!remainingHoldings.contains(where: { $0.accountAddressRawValue == removed.address }))
        #expect(SearchHistoryStore(modelContext: context).entries(for: removed.address).isEmpty)
        #expect(try context.fetch(FetchDescriptor<NFT.Contract>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<NFT.Collection>()).count == 1)
    }

    @Test("overwriting an account purges previously persisted NFTs for that account")
    func accountOverwritePurgesScopedNFTs() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = AccountStore(modelContext: context)

        let overwritten = try await store.createWatchAccount(
            from: "0x3030303030303030303030303030303030303030",
            now: Date(timeIntervalSince1970: 100)
        )
        let other = try await store.createWatchAccount(
            from: "0x4040404040404040404040404040404040404040",
            now: Date(timeIntervalSince1970: 200)
        )

        context.insert(makeFixtureNFT(tokenId: "stale-overwrite", accountAddress: overwritten.address))
        try await SearchHistoryStore(modelContext: context).recordCommittedQuery("Overwrite Scope", accountAddress: overwritten.address)
        try await TokenHoldingsStore(modelContext: context).upsertNativeHolding(
            accountAddress: overwritten.address,
            chain: .ethMainnet,
            amountDisplay: "9.9",
            updatedAt: .now
        )
        context.insert(makeFixtureNFT(
            tokenId: "keep-other",
            accountAddress: other.address,
            contractAddress: "0x8888888888888888888888888888888888888888"
        ))
        try context.save()

        _ = try await store.createWatchAccount(
            from: overwritten.address,
            source: .qrScan,
            overwriteExisting: true,
            now: Date(timeIntervalSince1970: 300)
        )

        let persistedNFTs = try context.fetch(FetchDescriptor<NFT>())
        let persistedHoldings = try context.fetch(FetchDescriptor<TokenHolding>())
        #expect(!persistedNFTs.contains(where: { $0.accountAddressRawValue == overwritten.address }))
        #expect(persistedNFTs.contains(where: { $0.accountAddressRawValue == other.address }))
        #expect(!persistedHoldings.contains(where: { $0.accountAddressRawValue == overwritten.address }))
        #expect(SearchHistoryStore(modelContext: context).entries(for: overwritten.address).isEmpty)
        #expect(try context.fetch(FetchDescriptor<NFT.Contract>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<NFT.Collection>()).count == 1)
    }

    @Test("AuraPlay store reset removes separate persisted store files when no live container is available")
    func auraPlayStoreResetRemovesPersistedFiles() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let storeURL = try AppModelContainer.storeURL(baseDirectory: temporaryDirectory)
        let shmURL = storeURL.appendingPathExtension("shm")
        let walURL = storeURL.appendingPathExtension("wal")
        FileManager.default.createFile(atPath: storeURL.path(), contents: Data("store".utf8))
        FileManager.default.createFile(atPath: shmURL.path(), contents: Data("shm".utf8))
        FileManager.default.createFile(atPath: walURL.path(), contents: Data("wal".utf8))

        let service = AuraPlayStoreResetService(
            fileManager: .default,
            baseDirectory: temporaryDirectory
        )

        try await service.resetAuraPlayPersistence()

        #expect(FileManager.default.fileExists(atPath: storeURL.path()) == false)
        #expect(FileManager.default.fileExists(atPath: shmURL.path()) == false)
        #expect(FileManager.default.fileExists(atPath: walURL.path()) == false)
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

private actor RecordingAuraPlayPersistenceResetService: AuraPlayPersistenceResetting {
    private var resetCallCount = 0

    func resetAuraPlayPersistence() async throws {
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
