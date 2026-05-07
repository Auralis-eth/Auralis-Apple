@testable import Auralis
import AuralisPrimaryModels
import Foundation
import SwiftData
import Testing

@MainActor
@Suite
struct AuraPlayPersistenceWave2Tests {
    @Test("Wave 2 schema registers wallet and media models")
    func schemaContainsWave2CoreEntities() {
        let modelNames = Set(AuraPlaySchemaV2.models.map { String(describing: $0) })

        #expect(modelNames.contains("AuraPlayWallet"))
        #expect(modelNames.contains("AuraPlayMediaItem"))
    }

    @Test("wallet service can upsert a scoped wallet into the AuraPlay container")
    func walletServiceUpsertsScopedWallet() async throws {
        let container = try AppModelContainer.make(inMemory: true)
        let walletService = AuraPlayWalletService(modelContainer: container)

        let walletID = try await walletService.upsert(
            AuraPlayWalletUpsertRequest(
                address: "0x1234567890abcdef1234567890abcdef12345678",
                chain: .ethMainnet,
                displayName: "Aura Wallet",
                syncedAt: .now
            )
        )

        let context = ModelContext(container)
        let wallets = try context.fetch(FetchDescriptor<AuraPlayWallet>())

        #expect(walletID == "0x1234567890abcdef1234567890abcdef12345678:eth-mainnet")
        #expect(wallets.count == 1)
        #expect(wallets.first?.displayName == "Aura Wallet")
    }

    @Test("library repository prefers persisted AuraPlay media once a scoped wallet exists")
    func libraryRepositoryPrefersPersistedMediaGraph() async throws {
        let container = try AppModelContainer.make(inMemory: true)
        let walletService = AuraPlayWalletService(modelContainer: container)
        let mediaItemService = AuraPlayMediaItemService(modelContainer: container)
        let scope = AuraPlayLibraryScope(
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet
        )

        let walletID = try await walletService.upsert(
            AuraPlayWalletUpsertRequest(
                address: "0x1234567890abcdef1234567890abcdef12345678",
                chain: .ethMainnet,
                displayName: "Aura Wallet",
                syncedAt: .now
            )
        )
        try await mediaItemService.replaceAll(
            walletID: walletID,
            requests: [
                AuraPlayMediaItemUpsertRequest(
                    walletID: walletID,
                    sourceNFTID: "nft-1",
                    accountAddressRawValue: "0x1234567890abcdef1234567890abcdef12345678",
                    chain: .ethMainnet,
                    contractAddressRawValue: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
                    tokenID: "1",
                    tokenType: "ERC721",
                    title: "Genesis Track",
                    artistName: "Aura",
                    collectionName: "Origin",
                    normalizedTitleKey: "genesis track",
                    normalizedArtistKey: "aura",
                    normalizedCollectionKey: "origin",
                    artworkURLString: "https://example.com/artwork.png",
                    playbackURLString: "https://example.com/track.mp3",
                    contentType: "audio/mpeg",
                    sourceUpdatedAtRawValue: "2025-01-01T00:00:00Z",
                    hasArtwork: true,
                    hasAudio: true,
                    isPlayable: true,
                    isSearchable: true
                )
            ],
            syncedAt: .now
        )

        let repository = LiveAuraPlayLibraryRepository(
            indexer: MockMusicLibraryIndexer(),
            receiptEventLogger: ReceiptEventLogger(receiptStore: UnusedReceiptStore()),
            modelContainer: container
        )

        #expect(try repository.itemCount(in: scope) == 1)
        #expect(try await repository.needsRebuild(in: scope) == false)
    }

    @Test("request bundle shaping deduplicates and sorts snapshots off the main actor seam")
    func requestBundleDeduplicatesAndSortsSnapshots() async {
        let requestBuilder = AuraPlayLibrarySyncRequestBuilder()
        let snapshots = [
            AuraPlayLibrarySyncRequestBuilder.SourceNFTSnapshot(
                id: "track-2",
                tokenID: "2",
                tokenType: "ERC721",
                accountAddressRawValue: "0x1234567890abcdef1234567890abcdef12345678",
                chain: .ethMainnet,
                contractAddressRawValue: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
                name: "Second",
                artistName: "Aura",
                collectionName: "Origin",
                collectionDisplayName: nil,
                thumbnailURLString: "https://example.com/2-thumb.png",
                originalImageURLString: "https://example.com/2-full.png",
                playbackURLString: "https://example.com/2.mp3",
                contentType: "audio/mpeg",
                sourceUpdatedAtRawValue: "2025-01-02T00:00:00Z"
            ),
            AuraPlayLibrarySyncRequestBuilder.SourceNFTSnapshot(
                id: "track-1",
                tokenID: "1",
                tokenType: "ERC721",
                accountAddressRawValue: "0x1234567890abcdef1234567890abcdef12345678",
                chain: .ethMainnet,
                contractAddressRawValue: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
                name: "First",
                artistName: "Aura",
                collectionName: "Origin",
                collectionDisplayName: nil,
                thumbnailURLString: "https://example.com/1-thumb.png",
                originalImageURLString: "https://example.com/1-full.png",
                playbackURLString: "https://example.com/1.mp3",
                contentType: "audio/mpeg",
                sourceUpdatedAtRawValue: "2025-01-01T00:00:00Z"
            ),
            AuraPlayLibrarySyncRequestBuilder.SourceNFTSnapshot(
                id: "track-2",
                tokenID: "2",
                tokenType: "ERC721",
                accountAddressRawValue: "0x1234567890abcdef1234567890abcdef12345678",
                chain: .ethMainnet,
                contractAddressRawValue: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
                name: "Second duplicate",
                artistName: "Aura",
                collectionName: "Origin",
                collectionDisplayName: nil,
                thumbnailURLString: "https://example.com/2b-thumb.png",
                originalImageURLString: "https://example.com/2b-full.png",
                playbackURLString: "https://example.com/2b.mp3",
                contentType: "audio/mpeg",
                sourceUpdatedAtRawValue: "2025-01-03T00:00:00Z"
            ),
        ]

        let bundle = await requestBuilder.makeRequestBundle(
            from: snapshots,
            walletID: "0x1234567890abcdef1234567890abcdef12345678:eth-mainnet"
        )

        #expect(bundle.mediaItemRequests.count == 2)
        #expect(bundle.mediaItemRequests.map(\.sourceNFTID) == ["track-1", "track-2"])
    }

    @Test("AuraPlay reset clears the live container and leaves it reusable in the same launch")
    func auraPlayResetClearsLiveContainerWithoutInvalidatingIt() async throws {
        let container = try AppModelContainer.make(inMemory: true)
        let walletService = AuraPlayWalletService(modelContainer: container)
        let mediaItemService = AuraPlayMediaItemService(modelContainer: container)
        let resetService = SwiftDataAuraPlayPersistenceResetService(modelContainer: container)

        let walletID = try await walletService.upsert(
            AuraPlayWalletUpsertRequest(
                address: "0x1234567890abcdef1234567890abcdef12345678",
                chain: .ethMainnet,
                displayName: "Aura Wallet",
                syncedAt: .now
            )
        )
        try await mediaItemService.replaceAll(
            walletID: walletID,
            requests: [
                AuraPlayMediaItemUpsertRequest(
                    walletID: walletID,
                    sourceNFTID: "nft-1",
                    accountAddressRawValue: "0x1234567890abcdef1234567890abcdef12345678",
                    chain: .ethMainnet,
                    contractAddressRawValue: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
                    tokenID: "1",
                    tokenType: "ERC721",
                    title: "Genesis Track",
                    artistName: "Aura",
                    collectionName: "Origin",
                    normalizedTitleKey: "genesis track",
                    normalizedArtistKey: "aura",
                    normalizedCollectionKey: "origin",
                    artworkURLString: "https://example.com/artwork.png",
                    playbackURLString: "https://example.com/track.mp3",
                    contentType: "audio/mpeg",
                    sourceUpdatedAtRawValue: "2025-01-01T00:00:00Z",
                    hasArtwork: true,
                    hasAudio: true,
                    isPlayable: true,
                    isSearchable: true
                )
            ],
            syncedAt: .now
        )

        try await resetService.resetAuraPlayPersistence()

        let verificationContext = ModelContext(container)
        #expect(try verificationContext.fetch(FetchDescriptor<AuraPlayWallet>()).isEmpty)
        #expect(try verificationContext.fetch(FetchDescriptor<AuraPlayMediaItem>()).isEmpty)

        let replacementWalletID = try await walletService.upsert(
            AuraPlayWalletUpsertRequest(
                address: "0x9999999999999999999999999999999999999999",
                chain: .baseMainnet,
                displayName: "Replacement Wallet",
                syncedAt: .now
            )
        )
        let reusedWallets = try verificationContext.fetch(FetchDescriptor<AuraPlayWallet>())

        #expect(replacementWalletID == "0x9999999999999999999999999999999999999999:base-mainnet")
        #expect(reusedWallets.count == 1)
        #expect(reusedWallets.first?.displayName == "Replacement Wallet")
    }
}

@MainActor
private final class MockMusicLibraryIndexer: MusicLibraryIndexing {
    func itemCount(accountAddress: String?, chain: Chain) throws -> Int {
        99
    }

    func needsRebuild(accountAddress: String?, chain: Chain) async throws -> Bool {
        true
    }

    func rebuildIndex(
        accountAddress: String?,
        chain: Chain,
        correlationID: String?,
        receiptEventLogger: ReceiptEventLogger?
    ) async throws -> MusicLibraryIndexRebuildResult {
        MusicLibraryIndexRebuildResult(scannedCount: 0, writtenCount: 0, removedCount: 0)
    }
}

@MainActor
private final class UnusedReceiptStore: ReceiptStore {
    func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord {
        fatalError("Unused in AuraPlayPersistenceWave2Tests")
    }

    func latest(limit: Int) throws -> [ReceiptRecord] {
        []
    }

    func receipts(
        forCorrelationID correlationID: String,
        limit: Int
    ) throws -> [ReceiptRecord] {
        []
    }

    func exportAll() throws -> Data {
        Data()
    }

    func resetAll() async throws {}
}
