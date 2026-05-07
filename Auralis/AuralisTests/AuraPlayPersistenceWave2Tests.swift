@testable import Auralis
import AuralisPrimaryModels
import Foundation
import SwiftData
import Testing

@MainActor
@Suite
struct AuraPlayPersistenceWave2Tests {
    @Test("current AuraPlay schema keeps only persisted media rows in the dedicated store")
    func schemaContainsCurrentCoreEntities() {
        let modelNames = Set(AuraPlaySchema.models.map { String(describing: $0) })

        #expect(modelNames.contains("AuraPlayMediaItem"))
        #expect(modelNames.count == 1)
    }

    @Test("account sync state service records per-chain AuraPlay sync state on EOAccount")
    func accountSyncStateServiceMarksSyncedChain() async throws {
        let container = try TestModelContainers.primary()
        let context = ModelContext(container)
        let service = AuraPlayAccountSyncStateService(modelContainer: container)
        let syncedAt = Date(timeIntervalSince1970: 1_735_689_600)

        try await service.markSynced(
            AuraPlayAccountSyncUpdateRequest(
                address: "0x1234567890abcdef1234567890abcdef12345678",
                chain: .ethMainnet,
                displayName: "Aura Wallet",
                syncedAt: syncedAt
            )
        )

        let accounts = try context.fetch(FetchDescriptor<EOAccount>())

        #expect(accounts.count == 1)
        #expect(accounts.first?.name == "Aura Wallet")
        #expect(accounts.first?.auraPlayLastSyncedAt(for: .ethMainnet) == syncedAt)
    }

    @Test("library repository prefers persisted AuraPlay media once EOAccount marks the chain as synced")
    func libraryRepositoryPrefersPersistedMediaGraph() async throws {
        let auraPlayContainer = try AppModelContainer.make(inMemory: true)
        let primaryContainer = try TestModelContainers.primary()
        let primaryContext = ModelContext(primaryContainer)
        let mediaItemService = AuraPlayMediaItemService(modelContainer: auraPlayContainer)
        let scope = AuraPlayLibraryScope(
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet
        )

        let account = EOAccount(
            address: "0x1234567890abcdef1234567890abcdef12345678",
            access: .readonly,
            name: "Aura Wallet"
        )
        account.markAuraPlaySynced(on: .ethMainnet, at: .now)
        primaryContext.insert(account)
        try primaryContext.save()

        try await mediaItemService.replaceAll(
            accountAddress: account.address,
            chain: .ethMainnet,
            requests: [
                AuraPlayMediaItemUpsertRequest(
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
            auraPlayModelContainer: auraPlayContainer,
            accountModelContext: primaryContext
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
            from: snapshots
        )

        #expect(bundle.mediaItemRequests.count == 2)
        #expect(bundle.mediaItemRequests.map(\.sourceNFTID) == ["track-1", "track-2"])
    }

    @Test("AuraPlay reset clears the live container and leaves it reusable in the same launch")
    func auraPlayResetClearsLiveContainerWithoutInvalidatingIt() async throws {
        let container = try AppModelContainer.make(inMemory: true)
        let mediaItemService = AuraPlayMediaItemService(modelContainer: container)
        let resetService = SwiftDataAuraPlayPersistenceResetService(modelContainer: container)

        try await mediaItemService.replaceAll(
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet,
            requests: [
                AuraPlayMediaItemUpsertRequest(
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
        #expect(try verificationContext.fetch(FetchDescriptor<AuraPlayMediaItem>()).isEmpty)

        try await mediaItemService.replaceAll(
            accountAddress: "0x9999999999999999999999999999999999999999",
            chain: .baseMainnet,
            requests: [
                AuraPlayMediaItemUpsertRequest(
                    sourceNFTID: "nft-2",
                    accountAddressRawValue: "0x9999999999999999999999999999999999999999",
                    chain: .baseMainnet,
                    contractAddressRawValue: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
                    tokenID: "2",
                    tokenType: "ERC721",
                    title: "Replacement Track",
                    artistName: "Aura",
                    collectionName: "Origin",
                    normalizedTitleKey: "replacement track",
                    normalizedArtistKey: "aura",
                    normalizedCollectionKey: "origin",
                    artworkURLString: "https://example.com/replacement.png",
                    playbackURLString: "https://example.com/replacement.mp3",
                    contentType: "audio/mpeg",
                    sourceUpdatedAtRawValue: "2025-01-02T00:00:00Z",
                    hasArtwork: true,
                    hasAudio: true,
                    isPlayable: true,
                    isSearchable: true
                )
            ],
            syncedAt: .now
        )
        let reusedMediaItems = try verificationContext.fetch(FetchDescriptor<AuraPlayMediaItem>())

        #expect(reusedMediaItems.count == 1)
        #expect(reusedMediaItems.first?.accountAddressRawValue == "0x9999999999999999999999999999999999999999")
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
