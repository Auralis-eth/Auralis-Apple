import ReceiptsCore
@testable import Auralis
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import AuralisTestSupport
import Foundation
import MusicFeature
import SwiftData
import Testing

@Suite(.serialized, .tags(.slow))
@MainActor
struct AuraPlayPersistenceWave2Tests {
    @Test("current AuraPlay schema keeps only persisted media rows in the dedicated store")
    func schemaContainsCurrentCoreEntities() {
        let modelNames = Set(AuraPlaySchema.models.map { String(describing: $0) })

        #expect(modelNames.contains("AuraPlayMediaItem"))
        #expect(modelNames.contains("AuraPlayPlaybackPositionState"))
        #expect(modelNames.count == 2)
    }

    @Test("playback cache state and loudness persist on AuraPlay media rows")
    func playbackCacheStateAndLoudnessPersist() async throws {
        let container = try AuraPlayModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let service = AuraPlayMediaItemService(modelContainer: container)
        let syncedAt = Fixture.referenceDate

        try await service.replaceAll(
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet,
            requests: [
                AuraPlayMediaItemUpsertRequest(
                    sourceNFTID: "nft-cache-1",
                    accountAddressRawValue: "0x1234567890abcdef1234567890abcdef12345678",
                    chain: .ethMainnet,
                    contractAddressRawValue: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
                    tokenID: "1",
                    tokenType: "ERC721",
                    title: "Cached Track",
                    artistName: "Aura",
                    collectionName: "Cache Suite",
                    normalizedTitleKey: "cached track",
                    normalizedArtistKey: "aura",
                    normalizedCollectionKey: "cache suite",
                    artworkURLString: "https://example.com/artwork.png",
                    playbackURLString: "https://example.com/track.mp3",
                    contentType: "audio/mpeg",
                    sourceUpdatedAtRawValue: "2026-07-09T00:00:00Z",
                    hasArtwork: true,
                    hasAudio: true,
                    isPlayable: true,
                    isSearchable: true
                )
            ],
            syncedAt: syncedAt
        )

        try await service.updatePlaybackCacheState(
            sourceNFTID: "nft-cache-1",
            cachedFileStateRawValue: "pinned",
            approxLoudnessLUFS: -18.5,
            updatedAt: syncedAt.addingTimeInterval(60)
        )

        let rows = try context.fetch(FetchDescriptor<AuraPlayMediaItem>())
        let row = try #require(rows.first)
        #expect(row.cachedFileStateRawValue == "pinned")
        #expect(row.approxLoudnessLUFS == -18.5)
        #expect(row.updatedAt == syncedAt.addingTimeInterval(60))
    }

    @Test(
        "account sync state service records per-chain AuraPlay sync state on EOAccount",
        .disabled("Crashes in the Xcode 26 beta app-hosted runner because EOAccount is loaded from both the app and test bundles.")
    )
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
        #expect(try #require(accounts.first).name == "Aura Wallet")
        #expect(accounts.first?.auraPlayLastSyncedAt(for: .ethMainnet) == syncedAt)
    }

    @Test(
        "library repository prefers persisted AuraPlay media once EOAccount marks the chain as synced",
        .disabled("Crashes in the Xcode 26 beta app-hosted runner because EOAccount is loaded from both the app and test bundles.")
    )
    func libraryRepositoryPrefersPersistedMediaGraph() async throws {
        let auraPlayContainer = try AuraPlayModelContainer.make(inMemory: true)
        let primaryContainer = try TestModelContainers.primary()
        let primaryContext = ModelContext(primaryContainer)
        let mediaItemService = AuraPlayMediaItemService(modelContainer: auraPlayContainer)
        let scope = AuraPlayLibraryScope(
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet
        )
        let syncedAt = Fixture.referenceDate

        let account = EOAccount(
            address: "0x1234567890abcdef1234567890abcdef12345678",
            access: .readonly,
            name: "Aura Wallet"
        )
        account.markAuraPlaySynced(on: .ethMainnet, at: syncedAt)
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
            syncedAt: syncedAt
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

        let bundle = requestBuilder.makeRequestBundle(
            from: snapshots
        )

        #expect(bundle.mediaItemRequests.count == 2)
        #expect(bundle.mediaItemRequests.map(\.sourceNFTID) == ["track-1", "track-2"])
    }

    @Test("library sync does not mark account synced when media persistence fails")
    func librarySyncDoesNotMarkAccountSyncedWhenMediaWriteFails() async throws {
        let auraPlayContainer = try AuraPlayModelContainer.make(inMemory: true)
        let primaryContainer = try TestModelContainers.primary()
        let primaryContext = ModelContext(primaryContainer)
        let accountAddress = "0x1234567890abcdef1234567890abcdef12345678"

        primaryContext.insert(
            makeAuraPlaySyncFixtureNFT(
                tokenId: "failed-sync-track",
                accountAddress: accountAddress
            )
        )
        try primaryContext.save()

        let service = LiveAuraPlayLibrarySyncService(
            sourceModelContext: primaryContext,
            auraPlayModelContainer: auraPlayContainer,
            musicReceiptLogger: MusicReceiptEventLogger(receiptStore: UnusedReceiptStore()),
            logger: LiveAuraPlayLogger(),
            mediaItemService: FailingAuraPlayMediaItemWriter()
        )

        await #expect(throws: FailingAuraPlayMediaItemWriter.WriteError.self) {
            try await service.syncLibrary(
                in: AuraPlayLibraryScope(
                    accountAddress: accountAddress,
                    chain: .ethMainnet
                ),
                accountName: "Aura Wallet"
            )
        }

        let accounts = try primaryContext.fetch(FetchDescriptor<EOAccount>())
        #expect(accounts.isEmpty)
    }

    @Test("AuraPlay reset clears the live container and leaves it reusable in the same launch")
    func auraPlayResetClearsLiveContainerWithoutInvalidatingIt() async throws {
        let container = try AuraPlayModelContainer.make(inMemory: true)
        let mediaItemService = AuraPlayMediaItemService(modelContainer: container)
        let resetService = SwiftDataAuraPlayPersistenceResetService(modelContainer: container)
        let syncedAt = Fixture.referenceDate

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
            syncedAt: syncedAt
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
            syncedAt: syncedAt.addingTimeInterval(60)
        )
        let reusedMediaItems = try verificationContext.fetch(FetchDescriptor<AuraPlayMediaItem>())

        #expect(reusedMediaItems.count == 1)
        #expect(try #require(reusedMediaItems.first).accountAddressRawValue == "0x9999999999999999999999999999999999999999")
    }
}

private actor FailingAuraPlayMediaItemWriter: AuraPlayMediaItemReplacing {
    enum WriteError: Error, Equatable {
        case failed
    }

    func replaceAll(
        accountAddress: String,
        chain: Chain,
        requests: [AuraPlayMediaItemUpsertRequest],
        syncedAt: Date
    ) async throws {
        throw WriteError.failed
    }
}

private func makeAuraPlaySyncFixtureNFT(
    contractAddress: String = "0x495f947276749ce646f68ac8c248420045cb7b5e",
    tokenId: String,
    title: String = "Sync Track",
    artistName: String? = "Aura",
    network: Chain = .ethMainnet,
    accountAddress: String,
    audioURL: String = "https://example.com/sync-track.mp3"
) -> NFT {
    let normalizedAccountAddress = NFT.normalizedScopeComponent(accountAddress) ?? "unscoped"
    let normalizedContractAddress = NFT.normalizedScopeComponent(contractAddress) ?? "unknown"

    return NFT(
        id: "\(normalizedAccountAddress):\(network.rawValue):\(normalizedContractAddress):\(tokenId)",
        contract: NFT.Contract(address: contractAddress, chain: network),
        tokenId: tokenId,
        name: title,
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
        artistName: artistName,
        animationUrl: audioURL,
        audioUrl: audioURL
    )
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

    func latest(limit: Int) async throws -> [ReceiptRecord] {
        []
    }

    func receipts(
        forCorrelationID correlationID: String,
        limit: Int
    ) async throws -> [ReceiptRecord] {
        []
    }

    func exportAll() async throws -> Data {
        Data()
    }

    func resetAll() async throws {}
}
