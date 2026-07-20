import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import MusicFeature
import SwiftData
import Testing

@MainActor
struct AuraPlaySearchTests {
    private enum Seed {
        static let accountAddress = "0x1234567890abcdef1234567890abcdef12345678"
        static let chain = Chain.ethMainnet
        static let baseDate = Date(timeIntervalSince1970: 1_750_000_000)

        static var scope: AuraPlayLibraryScope {
            AuraPlayLibraryScope(accountAddress: accountAddress, chain: chain)
        }

        static func makeContainer() throws -> ModelContainer {
            try ModelContainer(
                for: Schema(AuraPlaySchema.models),
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }

        static func seed(_ container: ModelContainer) throws {
            let context = ModelContext(container)
            for item in standardItems() {
                context.insert(item)
            }
            try context.save()
        }

        static func standardItems() -> [AuraPlayMediaItem] {
            [
                makeItem(index: 0, title: "Aurora Drift", artist: "Nova", collection: "Waves", contract: "0xaaa", duration: 201, lastPlayedAt: baseDate.addingTimeInterval(-3_600)),
                makeItem(index: 1, title: "Basalt", artist: "Nova", collection: "Waves", contract: "0xaaa", duration: 154),
                makeItem(index: 2, title: "Cinder Loop", artist: "Kestrel", collection: "Waves", contract: "0xbbb", duration: 320),
                makeItem(index: 3, title: "Delta Bloom", artist: "Kestrel", collection: "Meadow", contract: "0xccc", hasVideo: true, duration: 645),
                makeItem(index: 4, title: "Ember Signal", artist: "Same Name", collection: "Meadow", contract: "0xccc", creatorID: "eth:artist:one", duration: 99),
                makeItem(index: 5, title: "Fen Static", artist: "Same Name", collection: "Meadow", contract: "0xccc", creatorID: "eth:artist:two", duration: 187),
                makeItem(index: 6, title: "Ghost Format", artist: "Nova", collection: "Waves", contract: "0xaaa", isPlayable: false),
                makeItem(index: 7, title: "Halcyon", artist: "Nova", collection: "Waves", contract: "0xaaa", artwork: nil, duration: 260)
            ]
        }

        static func makeItem(
            index: Int,
            title: String,
            artist: String,
            collection: String,
            contract: String?,
            creatorID: String? = nil,
            artwork: String? = "https://artwork.example/item.png",
            hasVideo: Bool = false,
            isPlayable: Bool = true,
            duration: Double? = nil,
            lastPlayedAt: Date? = nil
        ) -> AuraPlayMediaItem {
            AuraPlayMediaItem(
                sourceNFTID: "nft-\(String(format: "%05d", index))",
                accountAddressRawValue: accountAddress,
                chain: chain,
                contractAddressRawValue: contract,
                tokenID: "\(index)",
                tokenType: "ERC721",
                title: title,
                artistName: artist,
                creatorIdentifierRawValue: creatorID,
                collectionName: collection,
                normalizedTitleKey: title.lowercased(),
                normalizedArtistKey: artist.lowercased(),
                normalizedCollectionKey: collection.lowercased(),
                artworkURLString: artwork,
                playbackURLString: isPlayable ? "https://media.example/\(index).\(hasVideo ? "mp4" : "mp3")" : nil,
                durationSeconds: duration,
                contentType: hasVideo ? "video/mp4" : "audio/mpeg",
                sourceUpdatedAtRawValue: nil,
                hasArtwork: artwork != nil,
                hasAudio: !hasVideo,
                hasVideo: hasVideo,
                isPlayable: isPlayable,
                isSearchable: true,
                lastPlayedAt: lastPlayedAt,
                createdAt: baseDate.addingTimeInterval(Double(index) * 60),
                updatedAt: baseDate.addingTimeInterval(Double(index) * 60)
            )
        }
    }

    private final class FakeLibraryRepository: AuraPlayLibraryRepository {
        func itemCount(in scope: AuraPlayLibraryScope) throws -> Int { 0 }
        func needsRebuild(in scope: AuraPlayLibraryScope) async throws -> Bool { false }
        func rebuildLibrary(
            in scope: AuraPlayLibraryScope,
            correlationID: String?
        ) async throws -> AuraPlayLibraryRebuildResult {
            AuraPlayLibraryRebuildResult(scannedCount: 0, writtenCount: 0, removedCount: 0)
        }
    }

    private final class FakePlaybackController: AuraPlayPlaybackControlling {
        var playbackState: AuraPlayPlaybackState = .stopped
        var currentTrack: AuraPlayTrack?
        var currentTrackID: String?
        var currentTime: TimeInterval = 0

        func play() throws {}
        func pause() {}
        func resume() throws {}
        func seek(to time: TimeInterval) throws {}
        func playNext() async {}
        func playPrevious() async {}
    }

    private struct FakeQueueCoordinator: AuraPlayQueueCoordinating {
        func snapshot() -> AuraPlayQueueSnapshot {
            AuraPlayQueueSnapshot(upcomingCount: 0, historyCount: 0)
        }
    }

    private struct FakeArtworkLoader: AuraPlayArtworkLoading {
        func artworkURL(for track: AuraPlayTrack?) throws -> URL? { nil }
    }

    private final class FakeLogger: AuraPlayLogging, @unchecked Sendable {
        func log(_ event: AuraPlayLogEvent) {}
    }

    private actor MockSemanticSearch: AuraPlaySemanticSearching {
        private(set) var requests: [String] = []
        private let resultsByQuery: [String: [AuraPlaySemanticSearchResult]]
        private let delayNanosecondsByQuery: [String: UInt64]

        init(
            resultsByQuery: [String: [AuraPlaySemanticSearchResult]] = [:],
            delayNanosecondsByQuery: [String: UInt64] = [:]
        ) {
            self.resultsByQuery = resultsByQuery
            self.delayNanosecondsByQuery = delayNanosecondsByQuery
        }

        func search(
            query: String,
            in scope: AuraPlayLibraryScope,
            limit: Int,
            minimumScore: Float
        ) async throws -> [AuraPlaySemanticSearchResult] {
            requests.append(query)
            if let delay = delayNanosecondsByQuery[query] {
                try await Task.sleep(nanoseconds: delay)
            }
            return Array((resultsByQuery[query] ?? []).prefix(limit))
        }
    }

    private static let validConfiguration = AuraPlayModuleConfiguration(
        backgroundAudioEnabled: true,
        declaredURLSchemes: ["auraplay", "auralis"],
        walletQuerySchemes: ["metamask", "cbwallet", "rainbow", "ledgerlive"]
    )

    private func makeModel(
        semanticSearch: MockSemanticSearch = MockSemanticSearch(),
        recentStore: AuraPlayRecentSearchStore? = nil
    ) throws -> AuraPlayRootModel {
        let container = try Seed.makeContainer()
        try Seed.seed(container)
        let account = EOAccount(
            address: Seed.accountAddress,
            access: .readonly
        )
        return AuraPlayRootModel(
            libraryRepository: FakeLibraryRepository(),
            librarySyncService: NoOpAuraPlayLibrarySyncService(),
            nftDiscoverySyncService: NoOpAuraPlayNFTDiscoverySyncService(),
            syncProgressProvider: NoOpAuraPlaySyncProgressProvider(),
            semanticSearchService: semanticSearch,
            recentSearchStore: recentStore ?? makeRecentStore(),
            playlistManager: AuraPlayPlaylistService(modelContainer: container),
            playbackController: FakePlaybackController(),
            mediaQueryService: AuraPlayMediaItemService(modelContainer: container),
            queueCoordinator: FakeQueueCoordinator(),
            artworkLoader: FakeArtworkLoader(),
            logger: FakeLogger(),
            configuration: Self.validConfiguration,
            urlResolver: URLResolver(),
            currentAccount: account,
            currentChain: Seed.chain
        )
    }

    private func makeRecentStore(name: String = UUID().uuidString) -> AuraPlayRecentSearchStore {
        let suiteName = "AuraPlaySearchTests.\(name)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return AuraPlayRecentSearchStore(defaults: defaults, keyPrefix: "test.recents")
    }

    private func semanticResult(id: String, title: String, score: Float) -> AuraPlaySemanticSearchResult {
        AuraPlaySemanticSearchResult(
            id: id,
            title: title,
            artistName: nil,
            collectionName: nil,
            artworkURLString: nil,
            playbackURLString: "https://media.example/\(id).mp3",
            isPlayable: true,
            score: score
        )
    }

    @Test("Typing a prefix renders local suggestions and submit calls semantic search")
    func autocompleteAndSubmit() async throws {
        let semantic = MockSemanticSearch()
        let model = try makeModel(semanticSearch: semantic)

        await model.updateSearchText("Aur")

        #expect(model.searchSuggestions.map(\.value).contains("Aurora Drift"))

        model.submitSearch()
        await model.waitForSearchCompletion()

        #expect(await semantic.requests == ["Aur"])
        #expect(model.searchResults.map(\.item.title).contains("Aurora Drift"))
        #expect(model.searchRecentQueries == ["Aur"])
    }

    @Test("Semantic-only matches merge after local matches and keep diagnostics")
    func semanticMatchesMergeWithLocalMatches() async throws {
        let semantic = MockSemanticSearch(resultsByQuery: [
            "late synth": [semanticResult(id: "nft-00003", title: "Delta Bloom", score: 0.91)]
        ])
        let model = try makeModel(semanticSearch: semantic)

        model.submitSearch("late synth")
        await model.waitForSearchCompletion()

        #expect(model.searchResults.map(\.item.title) == ["Delta Bloom"])
        #expect(model.searchResults.first?.source == .semantic)
        #expect(model.searchDiagnostics.semanticCount == 1)
    }

    @Test("Submitting a newer query discards delayed older semantic results")
    func newerQueryDiscardsOlderResults() async throws {
        let semantic = MockSemanticSearch(
            resultsByQuery: [
                "slow": [semanticResult(id: "nft-00003", title: "Delta Bloom", score: 0.91)],
                "fast": [semanticResult(id: "nft-00004", title: "Ember Signal", score: 0.88)]
            ],
            delayNanosecondsByQuery: ["slow": 200_000_000]
        )
        let model = try makeModel(semanticSearch: semantic)

        model.submitSearch("slow")
        model.submitSearch("fast")
        await model.waitForSearchCompletion()

        #expect(model.searchText == "fast")
        #expect(model.searchResults.map(\.item.title) == ["Ember Signal"])
    }

    @Test("Search filters apply after merge and preserve relevance order")
    func filtersApplyAfterMerge() async throws {
        let semantic = MockSemanticSearch(resultsByQuery: [
            "nova": [semanticResult(id: "nft-00003", title: "Delta Bloom", score: 0.9)]
        ])
        let model = try makeModel(semanticSearch: semantic)

        model.submitSearch("nova")
        await model.waitForSearchCompletion()
        let unfilteredTitles = model.filteredSearchResults.map(\.item.title)

        model.searchFilter.mediaType = .video
        let videoTitles = model.filteredSearchResults.map(\.item.title)

        #expect(unfilteredTitles.prefix(2) == ["Aurora Drift", "Basalt"])
        #expect(videoTitles == ["Delta Bloom"])
    }

    @Test("Recent searches cap at ten and deduplicate case-insensitively")
    func recentSearchesCapAndDeduplicate() {
        let store = makeRecentStore()
        let scope = Seed.scope

        for index in 0..<11 {
            store.record("Query \(index)", scope: scope)
        }
        store.record("query 5", scope: scope)

        let queries = store.queries(scope: scope)
        #expect(queries.count == 10)
        #expect(queries.first == "query 5")
        #expect(queries.filter { $0.localizedCaseInsensitiveContains("query 5") }.count == 1)
    }

    @Test("Empty query shows suggestions and does not call semantic search")
    func emptyQueryDoesNotSearch() async throws {
        let semantic = MockSemanticSearch()
        let model = try makeModel(semanticSearch: semantic)

        await model.updateSearchText("")
        model.submitSearch("")
        await model.waitForSearchCompletion()

        #expect(await semantic.requests.isEmpty)
        #expect(model.suggestedSearchQueries.isEmpty == false)
        #expect(model.searchResults.isEmpty)
    }

    @Test("Search queue window uses the visible result set as search origin")
    func searchQueueWindowUsesSearchOrigin() async throws {
        let model = try makeModel()

        model.submitSearch("nova")
        await model.waitForSearchCompletion()
        let firstPlayable = try #require(model.filteredSearchResults.first { $0.item.isPlayable })
        let pair = try #require(model.searchQueueWindow(startingAt: firstPlayable.item.sourceNFTID))

        #expect(pair.window.origin == .search(query: "nova"))
        #expect(pair.window.items.first?.id == firstPlayable.item.sourceNFTID)
        #expect(pair.window.items.count == model.filteredSearchResults.filter { $0.item.isPlayable }.count)
    }
}
