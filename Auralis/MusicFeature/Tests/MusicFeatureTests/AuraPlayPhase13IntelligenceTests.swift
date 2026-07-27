import AuralisPrimaryModels
import Foundation
import MusicFeature
import SwiftData
import Testing

@MainActor
struct AuraPlayPhase13IntelligenceTests {
    private actor MockSemanticSearch: AuraPlaySemanticSearching {
        let results: [AuraPlaySemanticSearchResult]

        init(results: [AuraPlaySemanticSearchResult]) {
            self.results = results
        }

        func search(
            query: String,
            in scope: AuraPlayLibraryScope,
            limit: Int,
            minimumScore: Float
        ) async throws -> [AuraPlaySemanticSearchResult] {
            results.filter { $0.score >= minimumScore }.prefix(limit).map { $0 }
        }
    }

    private struct FixtureEmbeddingProvider: TextEmbeddingProviding {
        let modelVersion = "fixture"
        let vector: [Float]?

        func vector(for text: String) -> [Float]? {
            vector
        }
    }

    private struct ShuffleItem: Identifiable, Sendable {
        let id: String
    }

    @Test("Embedding availability is cached and refreshable")
    func embeddingAvailabilityCachesProbeResult() async {
        let available = AuraPlayEmbeddingAvailabilityProvider(
            embeddingProvider: FixtureEmbeddingProvider(vector: [1, 0])
        )
        #expect(await available.availability() == .available)
        #expect(await available.availability() == .available)

        let unavailable = AuraPlayEmbeddingAvailabilityProvider(
            embeddingProvider: FixtureEmbeddingProvider(vector: nil)
        )
        #expect(await unavailable.availability().isAvailable == false)
    }

    @Test("Playlist Playground preview saves smart playlist metadata and order")
    func generatedPlaylistSavesSmartMetadataAndItems() async throws {
        let container = try AuraPlayLibrarySeed.makeContainer()
        try AuraPlayLibrarySeed.seed(container, tier: .standard)
        let semantic = MockSemanticSearch(
            results: (0..<8).map { index in
                semanticResult(id: "nft-\(String(format: "%05d", index))", score: 0.9 - Float(index) * 0.03)
            }
        )
        let generator = AuraPlayPlaylistGenerator(
            semanticSearch: semantic,
            mediaQueryService: AuraPlayMediaItemService(modelContainer: container),
            candidateLimit: 8,
            previewLimit: 5
        )

        let preview = try await generator.preview(
            prompt: "late night nova",
            scope: AuraPlayLibrarySeed.scope
        )
        #expect(preview.canSave)
        let previewIDs = preview.items.map(\.sourceNFTID)
        #expect(previewIDs.count == 5)
        #expect(Set(previewIDs).isSubset(of: Set((0..<8).map { "nft-\(String(format: "%05d", $0))" })))

        let metadata = try AuraPlaySmartPlaylistMetadata.metadataData(
            prompt: preview.prompt,
            resultIDs: preview.items.map(\.sourceNFTID),
            minimumScore: 0.18,
            modelVersion: "fixture",
            createdAt: AuraPlayLibrarySeed.baseDate
        )
        let playlistService = AuraPlayPlaylistService(modelContainer: container)
        let playlistID = try await playlistService.createSmartPlaylistID(
            name: "Smart: late night nova",
            mediaItemIDs: preview.items.map(\.sourceNFTID),
            smartQueryData: metadata,
            at: AuraPlayLibrarySeed.baseDate
        )

        let context = ModelContext(container)
        let playlist = try #require(try context.fetch(FetchDescriptor<AuraPlayPlaylist>()).first)
        #expect(playlist.id == playlistID)
        #expect(playlist.isSmart)
        let decoded = try #require(playlist.smartQueryData).decodedSmartMetadata()
        #expect(decoded.prompt == "late night nova")
        let itemIDs = try context.fetch(FetchDescriptor<AuraPlayPlaylistItem>(
            sortBy: [SortDescriptor(\.position)]
        )).map(\.mediaItemID)
        #expect(itemIDs == preview.items.map(\.sourceNFTID))
    }

    @Test("More Like This ranks stored vectors and excludes the source item")
    func moreLikeThisUsesStoredVectors() async throws {
        let container = try AuraPlayLibrarySeed.makeContainer()
        try AuraPlayLibrarySeed.seed(container, tier: .standard)
        try insertEmbedding(mediaID: "nft-00000", vector: [1, 0], in: container)
        try insertEmbedding(mediaID: "nft-00001", vector: [0.9, 0.1], in: container)
        try insertEmbedding(mediaID: "nft-00002", vector: [0.2, 0.9], in: container)

        let service = AuraPlayRecommendationService(modelContainer: container)
        let results = try await service.moreLikeThis(
            mediaItemID: "nft-00000",
            in: AuraPlayLibrarySeed.scope,
            limit: 5,
            minimumScore: 0.1
        )

        #expect(results.map(\.id) == ["nft-00001", "nft-00002"])
        #expect(!results.map(\.id).contains("nft-00000"))
    }

    @Test("Smart Resume restores returned token position from tombstone")
    func smartResumeRestoresReturnedToken() async throws {
        let container = try AuraPlayLibrarySeed.makeContainer()
        let service = AuraPlayMediaItemService(modelContainer: container)
        let date = AuraPlayLibrarySeed.baseDate
        try await service.replaceAll(
            accountAddress: AuraPlayLibrarySeed.accountAddress,
            chain: AuraPlayLibrarySeed.chain,
            requests: [
                upsertRequest(sourceID: "old-media", tokenID: "42")
            ],
            syncedAt: date
        )
        let playback = AuraPlayPlaybackPositionStateService(modelContainer: container)
        try await playback.writePosition(
            mediaID: "old-media",
            positionMilliseconds: 30_000,
            durationMilliseconds: 180_000,
            at: date.addingTimeInterval(60)
        )

        try await service.replaceAll(
            accountAddress: AuraPlayLibrarySeed.accountAddress,
            chain: AuraPlayLibrarySeed.chain,
            requests: [],
            syncedAt: date.addingTimeInterval(120)
        )
        try await service.replaceAll(
            accountAddress: AuraPlayLibrarySeed.accountAddress,
            chain: AuraPlayLibrarySeed.chain,
            requests: [
                upsertRequest(sourceID: "new-media", tokenID: "42")
            ],
            syncedAt: date.addingTimeInterval(180)
        )

        let restored = try await playback.storedPosition(for: "new-media")
        #expect(restored?.positionMilliseconds == 30_000)
    }

    @Test("Smart Shuffle weights unplayed items above recent items")
    func smartShuffleWeightsUnplayedItemsHigher() {
        let now = AuraPlayLibrarySeed.baseDate
        let unplayed = SmartShuffleWeighting.weight(for: nil, now: now)
        let recent = SmartShuffleWeighting.weight(
            for: SmartShufflePlaybackHistory(
                mediaID: "recent",
                lastPlayedAt: now.addingTimeInterval(-60),
                playCount: 4
            ),
            now: now
        )
        #expect(unplayed > recent)

        let ordered = SmartShuffleWeighting.orderedItems(
            [ShuffleItem(id: "recent"), ShuffleItem(id: "fresh")],
            history: [
                "recent": SmartShufflePlaybackHistory(
                    mediaID: "recent",
                    lastPlayedAt: now.addingTimeInterval(-60),
                    playCount: 4
                )
            ],
            now: now,
            seed: 42
        )
        #expect(ordered.first?.id == "fresh")
    }

    @Test("Save as Playlist from recommendations reuses the smart-playlist materialization path")
    func saveRecommendationsReusesSmartPlaylistPath() async throws {
        let container = try AuraPlayLibrarySeed.makeContainer()
        try AuraPlayLibrarySeed.seed(container, tier: .standard)
        let orderedIDs = ["nft-00002", "nft-00001", "nft-00000"]
        let prompt = "More like Aurora Drift"
        let metadata = try AuraPlaySmartPlaylistMetadata.metadataData(
            prompt: prompt,
            resultIDs: orderedIDs,
            minimumScore: 0.18,
            modelVersion: nil,
            createdAt: AuraPlayLibrarySeed.baseDate
        )

        let playlistService = AuraPlayPlaylistService(modelContainer: container)
        let playlistID = try await playlistService.createSmartPlaylistID(
            name: "Smart: \(prompt)",
            mediaItemIDs: orderedIDs,
            smartQueryData: metadata,
            at: AuraPlayLibrarySeed.baseDate
        )

        let context = ModelContext(container)
        let playlist = try #require(
            try context.fetch(FetchDescriptor<AuraPlayPlaylist>(
                predicate: #Predicate { $0.id == playlistID }
            )).first
        )
        #expect(playlist.isSmart)
        let decoded = try #require(playlist.smartQueryData).decodedSmartMetadata()
        #expect(decoded.prompt == prompt)
        let itemIDs = try context.fetch(FetchDescriptor<AuraPlayPlaylistItem>(
            predicate: #Predicate { $0.playlistID == playlistID },
            sortBy: [SortDescriptor(\.position)]
        )).map(\.mediaItemID)
        #expect(itemIDs == orderedIDs)
    }

    @Test("Completing playback increments the persisted play count for Smart Shuffle")
    func markCompletedIncrementsPlayCount() async throws {
        let container = try AuraPlayLibrarySeed.makeContainer()
        let playback = AuraPlayPlaybackPositionStateService(modelContainer: container)
        let date = AuraPlayLibrarySeed.baseDate

        try await playback.markCompleted(mediaID: "media-1", at: date)
        try await playback.markCompleted(mediaID: "media-1", at: date.addingTimeInterval(60))

        let histories = try await playback.playbackHistories()
        let history = try #require(histories.first { $0.mediaID == "media-1" })
        #expect(history.playCount == 2)

        // The play-count term must actually bite: more plays => strictly lower weight.
        let now = date.addingTimeInterval(10 * 24 * 60 * 60)
        let heavy = SmartShuffleWeighting.weight(
            for: SmartShufflePlaybackHistory(mediaID: "media-1", lastPlayedAt: nil, playCount: 5),
            now: now
        )
        let light = SmartShuffleWeighting.weight(
            for: SmartShufflePlaybackHistory(mediaID: "media-1", lastPlayedAt: nil, playCount: 1),
            now: now
        )
        #expect(light > heavy)
    }

    @Test("Smart Resume restores the persisted play count alongside position")
    func smartResumePreservesPlayCount() async throws {
        let container = try AuraPlayLibrarySeed.makeContainer()
        let service = AuraPlayMediaItemService(modelContainer: container)
        let date = AuraPlayLibrarySeed.baseDate
        try await service.replaceAll(
            accountAddress: AuraPlayLibrarySeed.accountAddress,
            chain: AuraPlayLibrarySeed.chain,
            requests: [upsertRequest(sourceID: "old-media", tokenID: "77")],
            syncedAt: date
        )
        let playback = AuraPlayPlaybackPositionStateService(modelContainer: container)
        // One completed play (playCount == 1), then a fresh resumable position.
        try await playback.markCompleted(mediaID: "old-media", at: date.addingTimeInterval(30))
        try await playback.writePosition(
            mediaID: "old-media",
            positionMilliseconds: 30_000,
            durationMilliseconds: 180_000,
            at: date.addingTimeInterval(60)
        )

        try await service.replaceAll(
            accountAddress: AuraPlayLibrarySeed.accountAddress,
            chain: AuraPlayLibrarySeed.chain,
            requests: [],
            syncedAt: date.addingTimeInterval(120)
        )
        try await service.replaceAll(
            accountAddress: AuraPlayLibrarySeed.accountAddress,
            chain: AuraPlayLibrarySeed.chain,
            requests: [upsertRequest(sourceID: "new-media", tokenID: "77")],
            syncedAt: date.addingTimeInterval(180)
        )

        let context = ModelContext(container)
        let restored = try #require(
            try context.fetch(FetchDescriptor<AuraPlayPlaybackPositionState>(
                predicate: #Predicate { $0.mediaID == "new-media" }
            )).first
        )
        #expect(restored.positionMilliseconds == 30_000)
        #expect(restored.playCount == 1)
    }

    // MARK: - Smart Resume through the live sync reconciliation path (P13-003)

    // These drive the exact `AuraPlayMediaPersisting` methods `NFTSyncCoordinator`
    // calls in production — `upsertAll` / `removeItems` / `restorePlaybackTombstones`
    // — rather than `replaceAll`, so the shipping path is covered, not just the
    // helper it shares with tests.

    @Test("Smart Resume restores a returned token through the production reconcile path")
    func smartResumeRestoresThroughReconcilePath() async throws {
        let container = try AuraPlayLibrarySeed.makeContainer()
        let service = AuraPlayMediaItemService(modelContainer: container)
        let date = AuraPlayLibrarySeed.baseDate

        try await service.upsertAll([mediaDTO(id: "old-media", tokenID: "42")])
        let playback = AuraPlayPlaybackPositionStateService(modelContainer: container)
        try await playback.writePosition(
            mediaID: "old-media",
            positionMilliseconds: 30_000,
            durationMilliseconds: 180_000,
            at: date.addingTimeInterval(60)
        )

        // Token leaves the wallet: reconcile removes the row and cuts a tombstone.
        try await service.removeItems(ids: ["old-media"], capturedAt: date.addingTimeInterval(120))
        #expect(try await playback.storedPosition(for: "old-media") == nil)

        // Same on-chain identity returns under a new media ID, then restore runs.
        try await service.upsertAll([mediaDTO(id: "new-media", tokenID: "42")])
        try await service.restorePlaybackTombstones(at: date.addingTimeInterval(180))

        let restored = try await playback.storedPosition(for: "new-media")
        #expect(restored?.positionMilliseconds == 30_000)
    }

    @Test("Reconcile does not tombstone a non-resumable near-end position")
    func reconcileIgnoresNonResumablePosition() async throws {
        let container = try AuraPlayLibrarySeed.makeContainer()
        let service = AuraPlayMediaItemService(modelContainer: container)
        let date = AuraPlayLibrarySeed.baseDate

        try await service.upsertAll([mediaDTO(id: "old-media", tokenID: "42")])
        let playback = AuraPlayPlaybackPositionStateService(modelContainer: container)
        // Within 5s of the end => not resumable.
        try await playback.writePosition(
            mediaID: "old-media",
            positionMilliseconds: 178_000,
            durationMilliseconds: 180_000,
            at: date.addingTimeInterval(60)
        )

        try await service.removeItems(ids: ["old-media"], capturedAt: date.addingTimeInterval(120))
        try await service.upsertAll([mediaDTO(id: "new-media", tokenID: "42")])
        try await service.restorePlaybackTombstones(at: date.addingTimeInterval(180))

        #expect(try await playback.storedPosition(for: "new-media") == nil)
    }

    @Test("Reconcile ignores a tombstone older than the recency window")
    func reconcileIgnoresStaleTombstone() async throws {
        let container = try AuraPlayLibrarySeed.makeContainer()
        let service = AuraPlayMediaItemService(modelContainer: container)
        let date = AuraPlayLibrarySeed.baseDate

        try await service.upsertAll([mediaDTO(id: "old-media", tokenID: "42")])
        let playback = AuraPlayPlaybackPositionStateService(modelContainer: container)
        try await playback.writePosition(
            mediaID: "old-media",
            positionMilliseconds: 30_000,
            durationMilliseconds: 180_000,
            at: date
        )

        try await service.removeItems(ids: ["old-media"], capturedAt: date)
        try await service.upsertAll([mediaDTO(id: "new-media", tokenID: "42")])
        // Restore runs more than 7 days after the tombstone's lastPlayedAt.
        try await service.restorePlaybackTombstones(at: date.addingTimeInterval(8 * 24 * 60 * 60))

        #expect(try await playback.storedPosition(for: "new-media") == nil)
    }

    private func mediaDTO(id: String, tokenID: String) -> MediaItemDTO {
        MediaItemDTO(
            id: id,
            nftTokenId: id,
            title: "Returned Track",
            creatorName: "Nova",
            collectionName: "Waves",
            artworkURL: nil,
            audioURL: "https://media.example/\(id).mp3",
            videoURL: nil,
            durationSeconds: 180,
            format: "audio/mpeg",
            hasAudio: true,
            hasVideo: false,
            isPlayable: true,
            chain: AuraPlayLibrarySeed.chain,
            contractAddress: "0xaaa",
            tokenId: tokenID,
            tokenStandard: "ERC721",
            walletAddress: AuraPlayLibrarySeed.accountAddress,
            classifiedAt: AuraPlayLibrarySeed.baseDate,
            createdAt: AuraPlayLibrarySeed.baseDate
        )
    }

    private func semanticResult(id: String, score: Float) -> AuraPlaySemanticSearchResult {
        AuraPlaySemanticSearchResult(
            id: id,
            title: id,
            artistName: nil,
            collectionName: nil,
            artworkURLString: nil,
            playbackURLString: "https://media.example/\(id).mp3",
            isPlayable: true,
            score: score
        )
    }

    private func insertEmbedding(mediaID: String, vector: [Float], in container: ModelContainer) throws {
        let context = ModelContext(container)
        context.insert(
            AuraPlayMediaEmbedding(
                mediaItemID: mediaID,
                vectorData: AuraPlayEmbeddingVectorCodec.data(from: vector),
                embeddingModelVersion: "fixture",
                sourceFingerprint: mediaID,
                indexedAt: AuraPlayLibrarySeed.baseDate
            )
        )
        try context.save()
    }

    private func upsertRequest(sourceID: String, tokenID: String) -> AuraPlayMediaItemUpsertRequest {
        AuraPlayMediaItemUpsertRequest(
            sourceNFTID: sourceID,
            accountAddressRawValue: AuraPlayLibrarySeed.accountAddress,
            chain: AuraPlayLibrarySeed.chain,
            contractAddressRawValue: "0xaaa",
            tokenID: tokenID,
            tokenType: "ERC721",
            title: "Returned Track",
            artistName: "Nova",
            creatorIdentifierRawValue: nil,
            collectionName: "Waves",
            normalizedTitleKey: "returned track",
            normalizedArtistKey: "nova",
            normalizedCollectionKey: "waves",
            artworkURLString: nil,
            playbackURLString: "https://media.example/\(sourceID).mp3",
            durationSeconds: 180,
            contentType: "audio/mpeg",
            sourceUpdatedAtRawValue: nil,
            hasArtwork: false,
            hasAudio: true,
            hasVideo: false,
            isPlayable: true,
            isSearchable: true
        )
    }
}

private extension Data {
    func decodedSmartMetadata() throws -> AuraPlaySmartPlaylistMetadata {
        try JSONDecoder().decode(AuraPlaySmartPlaylistMetadata.self, from: self)
    }
}
