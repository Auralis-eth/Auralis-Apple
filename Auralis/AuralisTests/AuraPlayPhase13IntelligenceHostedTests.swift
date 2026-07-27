import AuralisPrimaryModels
import Foundation
import MusicFeature
import SwiftData
import Testing

/// App-hosted mirror of the Phase 13 intelligence scenarios (P13-005 A–F).
///
/// The package-local `MusicFeatureTests` suite covers the same behavior, but the
/// auto-generated package scheme has an empty test plan on this machine, so those
/// tests do not run in the normal lane. These run in `AuralisTests`, which Xcode
/// executes, using deterministic fixtures, in-memory SwiftData, mock embeddings,
/// and zero network access.
@MainActor
@Suite("AuraPlay Phase 13 intelligence (hosted)")
struct AuraPlayPhase13IntelligenceHostedTests {
    private static let scope = AuraPlayLibraryScope(accountAddress: "0x123", chain: .ethMainnet)
    private static let accountAddress = "0x123"
    private static let baseDate = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - A. Playlist Playground

    @Test("A: Playlist Playground saves an ordered smart playlist with decodable metadata")
    func playlistPlaygroundSavesOrderedSmartPlaylist() async throws {
        let container = try AuraPlayModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        for index in 0..<8 {
            context.insert(Self.mediaItem(id: Self.mediaID(index)))
        }
        try context.save()

        let semantic = MockSemanticSearch(
            results: (0..<8).map { Self.semanticResult(id: Self.mediaID($0), score: 0.9 - Float($0) * 0.03) }
        )
        let generator = AuraPlayPlaylistGenerator(
            semanticSearch: semantic,
            mediaQueryService: AuraPlayMediaItemService(modelContainer: container),
            candidateLimit: 8,
            previewLimit: 5
        )

        let preview = try await generator.preview(prompt: "late night nova", scope: Self.scope)
        #expect(preview.canSave)
        #expect(preview.items.count == 5)
        #expect(Set(preview.items.map(\.sourceNFTID)).isSubset(of: Set((0..<8).map(Self.mediaID))))

        let metadata = try AuraPlaySmartPlaylistMetadata.metadataData(
            prompt: preview.prompt,
            resultIDs: preview.items.map(\.sourceNFTID),
            minimumScore: 0.18,
            modelVersion: "fixture",
            createdAt: Self.baseDate
        )
        let playlistService = AuraPlayPlaylistService(modelContainer: container)
        let playlistID = try await playlistService.createSmartPlaylistID(
            name: "Smart: late night nova",
            mediaItemIDs: preview.items.map(\.sourceNFTID),
            smartQueryData: metadata,
            at: Self.baseDate
        )

        let playlist = try #require(
            try context.fetch(FetchDescriptor<AuraPlayPlaylist>(
                predicate: #Predicate { $0.id == playlistID }
            )).first
        )
        #expect(playlist.isSmart)
        let decoded = try JSONDecoder().decode(
            AuraPlaySmartPlaylistMetadata.self,
            from: try #require(playlist.smartQueryData)
        )
        #expect(decoded.prompt == "late night nova")
        let itemIDs = try context.fetch(FetchDescriptor<AuraPlayPlaylistItem>(
            predicate: #Predicate { $0.playlistID == playlistID },
            sortBy: [SortDescriptor(\.position)]
        )).map(\.mediaItemID)
        #expect(itemIDs == preview.items.map(\.sourceNFTID))
    }

    @Test("A: Playlist Playground samples weighted candidates instead of taking a strict top cut")
    func playlistPlaygroundUsesWeightedSampling() async throws {
        let container = try AuraPlayModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        for index in 0..<20 {
            context.insert(Self.mediaItem(id: Self.mediaID(index)))
        }
        try context.save()

        let generator = AuraPlayPlaylistGenerator(
            semanticSearch: MockSemanticSearch(
                results: (0..<20).map { Self.semanticResult(id: Self.mediaID($0), score: 0.95 - Float($0) * 0.005) }
            ),
            mediaQueryService: AuraPlayMediaItemService(modelContainer: container),
            candidateLimit: 20,
            previewLimit: 5
        )

        let preview = try await generator.preview(prompt: "weighted fixture", scope: Self.scope)
        let previewIDs = preview.items.map(\.sourceNFTID)
        #expect(previewIDs.count == 5)
        #expect(Set(previewIDs).isSubset(of: Set((0..<20).map(Self.mediaID))))
        #expect(previewIDs != (0..<5).map(Self.mediaID))
    }

    @Test("A: Prompts with fewer than five matches do not offer a save")
    func playlistPlaygroundBelowThresholdCannotSave() async throws {
        let container = try AuraPlayModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        for index in 0..<3 {
            context.insert(Self.mediaItem(id: Self.mediaID(index)))
        }
        try context.save()

        let semantic = MockSemanticSearch(
            results: (0..<3).map { Self.semanticResult(id: Self.mediaID($0), score: 0.8) }
        )
        let generator = AuraPlayPlaylistGenerator(
            semanticSearch: semantic,
            mediaQueryService: AuraPlayMediaItemService(modelContainer: container),
            candidateLimit: 60,
            previewLimit: 25
        )

        let preview = try await generator.preview(prompt: "sparse", scope: Self.scope)
        #expect(preview.items.count == 3)
        #expect(!preview.canSave)
        #expect(preview.note != nil)
    }

    // MARK: - B. Regenerate

    @Test("B: Regenerate changes the preview for a large pool and uses the fallback for a small pool")
    func regenerateBehaviorDependsOnPoolSize() async throws {
        let container = try AuraPlayModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        for index in 0..<20 {
            context.insert(Self.mediaItem(id: Self.mediaID(index)))
        }
        try context.save()
        let mediaService = AuraPlayMediaItemService(modelContainer: container)

        // Large pool: 20 candidates, preview 5 -> regenerate excludes the previous set.
        let largeGenerator = AuraPlayPlaylistGenerator(
            semanticSearch: MockSemanticSearch(
                results: (0..<20).map { Self.semanticResult(id: Self.mediaID($0), score: 0.95 - Float($0) * 0.01) }
            ),
            mediaQueryService: mediaService,
            candidateLimit: 20,
            previewLimit: 5
        )
        let firstLarge = try await largeGenerator.preview(prompt: "mix", scope: Self.scope)
        let secondLarge = try await largeGenerator.preview(
            prompt: "mix",
            scope: Self.scope,
            excludingPreviousIDs: Set(firstLarge.items.map(\.sourceNFTID))
        )
        #expect(secondLarge.mode == .regenerated)
        #expect(secondLarge.items.map(\.sourceNFTID) != firstLarge.items.map(\.sourceNFTID))
        #expect(Set(secondLarge.items.map(\.sourceNFTID)).isDisjoint(with: Set(firstLarge.items.map(\.sourceNFTID))))

        // Small pool: 6 candidates, preview 5 -> fallback path (reshuffle), not exclusion.
        let smallGenerator = AuraPlayPlaylistGenerator(
            semanticSearch: MockSemanticSearch(
                results: (0..<6).map { Self.semanticResult(id: Self.mediaID($0), score: 0.9 - Float($0) * 0.02) }
            ),
            mediaQueryService: mediaService,
            candidateLimit: 6,
            previewLimit: 5
        )
        let firstSmall = try await smallGenerator.preview(prompt: "tiny", scope: Self.scope)
        let secondSmall = try await smallGenerator.preview(
            prompt: "tiny",
            scope: Self.scope,
            excludingPreviousIDs: Set(firstSmall.items.map(\.sourceNFTID))
        )
        #expect(secondSmall.mode == .smallPoolFallback)
        #expect(secondSmall.items.count == 5)
    }

    // MARK: - C. More Like This

    @Test("C: More Like This ranks stored vectors, excludes the source, and gates on embeddings")
    func moreLikeThisRanksAndGates() async throws {
        let container = try AuraPlayModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        for index in 0..<5 {
            context.insert(Self.mediaItem(id: Self.mediaID(index)))
        }
        context.insert(Self.mediaItem(id: "no-embedding"))
        try context.save()
        try Self.insertEmbedding(mediaID: Self.mediaID(0), vector: [1, 0], in: container)
        try Self.insertEmbedding(mediaID: Self.mediaID(1), vector: [0.99, 0.01], in: container)
        try Self.insertEmbedding(mediaID: Self.mediaID(2), vector: [0.90, 0.10], in: container)
        try Self.insertEmbedding(mediaID: Self.mediaID(3), vector: [0.80, 0.20], in: container)
        try Self.insertEmbedding(mediaID: Self.mediaID(4), vector: [0.65, 0.76], in: container)

        let service = AuraPlayRecommendationService(modelContainer: container)
        let results = try await service.moreLikeThis(
            mediaItemID: Self.mediaID(0),
            in: Self.scope,
            limit: 5,
            minimumScore: AuraPlayIntelligenceSettings.recommendationStrictMinimumScore
        )
        #expect(results.map(\.id) == [Self.mediaID(1), Self.mediaID(2), Self.mediaID(3)])
        #expect(!results.map(\.id).contains(Self.mediaID(0)))

        #expect(try await service.hasEmbedding(mediaItemID: Self.mediaID(0)))
        #expect(!(try await service.hasEmbedding(mediaItemID: "no-embedding")))
        let embedded = try await service.embeddedMediaItemIDs(in: Self.scope)
        #expect(embedded == Set((0..<5).map(Self.mediaID)))
        #expect(!embedded.contains("no-embedding"))
    }

    @Test("C: More Like This relaxes from strict to 0.60 only when strict matches are sparse")
    func moreLikeThisRelaxesSparseStrictMatches() async throws {
        let container = try AuraPlayModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        for index in 0..<4 {
            context.insert(Self.mediaItem(id: Self.mediaID(index)))
        }
        try context.save()
        try Self.insertEmbedding(mediaID: Self.mediaID(0), vector: [1, 0], in: container)
        try Self.insertEmbedding(mediaID: Self.mediaID(1), vector: [0.99, 0.01], in: container)
        try Self.insertEmbedding(mediaID: Self.mediaID(2), vector: [0.65, 0.76], in: container)
        try Self.insertEmbedding(mediaID: Self.mediaID(3), vector: [0.50, 0.87], in: container)

        let service = AuraPlayRecommendationService(modelContainer: container)
        let results = try await service.moreLikeThis(
            mediaItemID: Self.mediaID(0),
            in: Self.scope,
            limit: 5,
            minimumScore: AuraPlayIntelligenceSettings.recommendationStrictMinimumScore
        )

        #expect(results.map(\.id) == [Self.mediaID(1), Self.mediaID(2)])
        #expect(results.allSatisfy { $0.score >= AuraPlayIntelligenceSettings.recommendationRelaxedMinimumScore })
    }

    @Test("C: Playlist Playground and More Like This rank locally without URL loading")
    func intelligenceRankingMakesZeroNetworkRequests() async throws {
        URLLoadingTrap.reset()
        URLProtocol.registerClass(URLLoadingTrap.self)
        defer {
            URLProtocol.unregisterClass(URLLoadingTrap.self)
            URLLoadingTrap.reset()
        }

        let container = try AuraPlayModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        for index in 0..<8 {
            context.insert(Self.mediaItem(id: Self.mediaID(index)))
        }
        try context.save()
        try Self.insertEmbedding(mediaID: Self.mediaID(0), vector: [1, 0], in: container)
        try Self.insertEmbedding(mediaID: Self.mediaID(1), vector: [0.9, 0.1], in: container)
        try Self.insertEmbedding(mediaID: Self.mediaID(2), vector: [0.65, 0.76], in: container)

        let generator = AuraPlayPlaylistGenerator(
            semanticSearch: MockSemanticSearch(
                results: (0..<8).map { Self.semanticResult(id: Self.mediaID($0), score: 0.9 - Float($0) * 0.03) }
            ),
            mediaQueryService: AuraPlayMediaItemService(modelContainer: container),
            candidateLimit: 8,
            previewLimit: 5
        )
        let preview = try await generator.preview(prompt: "local only", scope: Self.scope)

        let recommendationService = AuraPlayRecommendationService(modelContainer: container)
        let recommendations = try await recommendationService.moreLikeThis(
            mediaItemID: Self.mediaID(0),
            in: Self.scope,
            limit: 5,
            minimumScore: AuraPlayIntelligenceSettings.recommendationStrictMinimumScore
        )

        #expect(preview.items.count == 5)
        #expect(recommendations.map(\.id) == [Self.mediaID(1), Self.mediaID(2)])
        #expect(URLLoadingTrap.requestedURLs.isEmpty)
    }

    // MARK: - D. Smart Resume restore

    @Test("D: Smart Resume restores a tombstoned position when the exact token returns")
    func smartResumeRestoresReturnedToken() async throws {
        let container = try AuraPlayModelContainer.make(inMemory: true)
        let service = AuraPlayMediaItemService(modelContainer: container)
        let playback = AuraPlayPlaybackPositionStateService(modelContainer: container)
        let date = Self.baseDate

        try await service.replaceAll(
            accountAddress: Self.accountAddress,
            chain: .ethMainnet,
            requests: [Self.upsertRequest(sourceID: "old-media", tokenID: "42")],
            syncedAt: date
        )
        try await playback.writePosition(
            mediaID: "old-media",
            positionMilliseconds: 30_000,
            durationMilliseconds: 180_000,
            at: date.addingTimeInterval(60)
        )

        // Token disappears, then returns under a new media id with the same identity.
        try await service.replaceAll(
            accountAddress: Self.accountAddress,
            chain: .ethMainnet,
            requests: [],
            syncedAt: date.addingTimeInterval(120)
        )
        try await service.replaceAll(
            accountAddress: Self.accountAddress,
            chain: .ethMainnet,
            requests: [Self.upsertRequest(sourceID: "new-media", tokenID: "42")],
            syncedAt: date.addingTimeInterval(180)
        )

        let restored = try await playback.storedPosition(for: "new-media")
        #expect(restored?.positionMilliseconds == 30_000)
    }

    @Test("D: Smart Resume tombstones expose the Persistent History recovery contract")
    func smartResumeTombstoneExposesPersistentHistoryContract() {
        let tombstone = AuraPlayPlaybackPositionTombstone(
            originalMediaID: "old-media",
            accountAddressRawValue: Self.accountAddress,
            chainRawValue: Chain.ethMainnet.rawValue,
            contractAddressRawValue: "0xaaa",
            tokenID: "42",
            positionMilliseconds: 30_000,
            durationMilliseconds: 180_000,
            lastPlayedAt: Self.baseDate,
            completedAt: nil,
            playCount: 2,
            capturedAt: Self.baseDate.addingTimeInterval(60)
        )

        #expect(tombstone.persistentHistoryIdentity == AuraPlayPersistentHistoryTokenIdentity(
            accountAddressRawValue: Self.accountAddress,
            chainRawValue: Chain.ethMainnet.rawValue,
            contractAddressRawValue: "0xaaa",
            tokenID: "42"
        ))
        #expect(tombstone.isInsidePersistentHistoryResumeWindow(
            at: Self.baseDate.addingTimeInterval(AuraPlayPersistentHistoryTombstonePolicy.resumeWindow)
        ))
        #expect(!tombstone.isInsidePersistentHistoryResumeWindow(
            at: Self.baseDate.addingTimeInterval(AuraPlayPersistentHistoryTombstonePolicy.resumeWindow + 1)
        ))
    }

    // MARK: - E. Smart Resume ignores stale / non-resumable

    @Test("E: Smart Resume ignores non-resumable near-start progress")
    func smartResumeIgnoresNonResumableProgress() async throws {
        let container = try AuraPlayModelContainer.make(inMemory: true)
        let service = AuraPlayMediaItemService(modelContainer: container)
        let playback = AuraPlayPlaybackPositionStateService(modelContainer: container)
        let date = Self.baseDate

        try await service.replaceAll(
            accountAddress: Self.accountAddress,
            chain: .ethMainnet,
            requests: [Self.upsertRequest(sourceID: "old-media", tokenID: "99")],
            syncedAt: date
        )
        // Under the 5s near-start threshold -> not resumable -> never tombstoned.
        try await playback.writePosition(
            mediaID: "old-media",
            positionMilliseconds: 2_000,
            durationMilliseconds: 180_000,
            at: date.addingTimeInterval(60)
        )
        try await service.replaceAll(
            accountAddress: Self.accountAddress,
            chain: .ethMainnet,
            requests: [],
            syncedAt: date.addingTimeInterval(120)
        )
        try await service.replaceAll(
            accountAddress: Self.accountAddress,
            chain: .ethMainnet,
            requests: [Self.upsertRequest(sourceID: "new-media", tokenID: "99")],
            syncedAt: date.addingTimeInterval(180)
        )

        let restored = try await playback.storedPosition(for: "new-media")
        #expect(restored == nil)
    }

    @Test("E: Smart Resume ignores tombstones older than the recency window")
    func smartResumeIgnoresStaleTombstone() async throws {
        let container = try AuraPlayModelContainer.make(inMemory: true)
        let service = AuraPlayMediaItemService(modelContainer: container)
        let playback = AuraPlayPlaybackPositionStateService(modelContainer: container)
        let date = Self.baseDate

        try await service.replaceAll(
            accountAddress: Self.accountAddress,
            chain: .ethMainnet,
            requests: [Self.upsertRequest(sourceID: "old-media", tokenID: "7")],
            syncedAt: date
        )
        // Last played well beyond the 7-day window relative to the return sync.
        try await playback.writePosition(
            mediaID: "old-media",
            positionMilliseconds: 30_000,
            durationMilliseconds: 180_000,
            at: date
        )
        try await service.replaceAll(
            accountAddress: Self.accountAddress,
            chain: .ethMainnet,
            requests: [],
            syncedAt: date.addingTimeInterval(60)
        )
        // Return 30 days later -> tombstone is stale and must be ignored.
        try await service.replaceAll(
            accountAddress: Self.accountAddress,
            chain: .ethMainnet,
            requests: [Self.upsertRequest(sourceID: "new-media", tokenID: "7")],
            syncedAt: date.addingTimeInterval(30 * 24 * 60 * 60)
        )

        let restored = try await playback.storedPosition(for: "new-media")
        #expect(restored == nil)
    }

    // MARK: - F. Smart Shuffle weighting

    @Test("F: Smart Shuffle favors unplayed items over recently played ones")
    func smartShuffleFavorsUnplayedItems() {
        let now = Self.baseDate
        let unplayed = SmartShuffleWeighting.weight(for: nil, now: now)
        let recent = SmartShuffleWeighting.weight(
            for: SmartShufflePlaybackHistory(mediaID: "recent", lastPlayedAt: now.addingTimeInterval(-60), playCount: 4),
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

        // Higher play count strictly lowers weight even with no recent play.
        let future = now.addingTimeInterval(10 * 24 * 60 * 60)
        let heavy = SmartShuffleWeighting.weight(
            for: SmartShufflePlaybackHistory(mediaID: "x", lastPlayedAt: nil, playCount: 5),
            now: future
        )
        let light = SmartShuffleWeighting.weight(
            for: SmartShufflePlaybackHistory(mediaID: "x", lastPlayedAt: nil, playCount: 1),
            now: future
        )
        #expect(light > heavy)
    }

    @Test("F: Smart Shuffle favors unplayed items over a large seeded trial count")
    func smartShuffleFavorsUnplayedItemsAcrossSeededTrials() {
        let now = Self.baseDate
        let items = (0..<40).map { ShuffleItem(id: "shuffle-\($0)") }
        let unplayedIDs = Set(items.prefix(20).map(\.id))
        let history = Dictionary(
            uniqueKeysWithValues: items.dropFirst(20).map {
                (
                    $0.id,
                    SmartShufflePlaybackHistory(
                        mediaID: $0.id,
                        lastPlayedAt: now.addingTimeInterval(-60),
                        playCount: 4
                    )
                )
            }
        )
        var unplayedTopTenCount = 0
        let trialCount = 200

        for seed in 0..<UInt64(trialCount) {
            let ordered = SmartShuffleWeighting.orderedItems(
                items,
                history: history,
                now: now,
                seed: seed
            )
            unplayedTopTenCount += ordered.prefix(10).filter { unplayedIDs.contains($0.id) }.count
        }

        let ratio = Double(unplayedTopTenCount) / Double(trialCount * 10)
        #expect(ratio >= 0.85)
    }

    // MARK: - Fixtures

    private struct ShuffleItem: Identifiable, Sendable {
        let id: String
    }

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

    private static func mediaID(_ index: Int) -> String {
        "nft-\(String(format: "%05d", index))"
    }

    private static func semanticResult(id: String, score: Float) -> AuraPlaySemanticSearchResult {
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

    private static func mediaItem(id: String) -> AuraPlayMediaItem {
        AuraPlayMediaItem(
            sourceNFTID: id,
            accountAddressRawValue: accountAddress,
            chain: .ethMainnet,
            contractAddressRawValue: "0xcontract",
            tokenID: id,
            tokenType: "ERC721",
            title: id,
            artistName: "Aura",
            collectionName: "Nova",
            normalizedTitleKey: id,
            normalizedArtistKey: "aura",
            normalizedCollectionKey: "nova",
            artworkURLString: "https://example.com/\(id).png",
            playbackURLString: "https://example.com/\(id).mp3",
            contentType: "mp3",
            sourceUpdatedAtRawValue: nil,
            hasArtwork: true,
            hasAudio: true,
            hasVideo: false,
            isPlayable: true,
            isSearchable: true,
            createdAt: baseDate,
            updatedAt: baseDate
        )
    }

    private static func insertEmbedding(mediaID: String, vector: [Float], in container: ModelContainer) throws {
        let context = ModelContext(container)
        context.insert(
            AuraPlayMediaEmbedding(
                mediaItemID: mediaID,
                vectorData: AuraPlayEmbeddingVectorCodec.data(from: vector),
                embeddingModelVersion: "fixture",
                sourceFingerprint: mediaID,
                indexedAt: baseDate
            )
        )
        try context.save()
    }

    private static func upsertRequest(sourceID: String, tokenID: String) -> AuraPlayMediaItemUpsertRequest {
        AuraPlayMediaItemUpsertRequest(
            sourceNFTID: sourceID,
            accountAddressRawValue: accountAddress,
            chain: .ethMainnet,
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

private final class URLLoadingTrap: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var urls: [URL] = []

    static var requestedURLs: [URL] {
        lock.withLock { urls }
    }

    static func reset() {
        lock.withLock {
            urls = []
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url,
              url.scheme == "http" || url.scheme == "https" else {
            return false
        }
        lock.withLock {
            urls.append(url)
        }
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
    }

    override func stopLoading() {}
}
