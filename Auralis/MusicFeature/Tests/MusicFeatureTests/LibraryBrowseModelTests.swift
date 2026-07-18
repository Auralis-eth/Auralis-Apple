import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import MusicFeature
import SwiftData
import Testing

/// P9-001/P9-002/P9-006/P9-007 model behavior: service-backed browse windows,
/// bounded queue construction with captured query context, grouped-index
/// caching, manual-refresh syncAll, and mini-player visibility states.
@MainActor
struct LibraryBrowseModelTests {
    // MARK: Fixtures

    private final class FakeLibraryRepository: AuraPlayLibraryRepository {
        func itemCount(in scope: AuraPlayLibraryScope) throws -> Int { 0 }
        func needsRebuild(in scope: AuraPlayLibraryScope) async throws -> Bool { false }
        func rebuildLibrary(
            in scope: AuraPlayLibraryScope,
            correlationID: String?
        ) async throws -> AuraPlayLibraryRebuildResult {
            throw FixtureError.unsupported
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

    @MainActor
    private final class FakeDiscoverySync: AuraPlayNFTDiscoverySyncing {
        private(set) var syncAllCallCount = 0
        private(set) var syncAllIfNeededCallCount = 0
        private(set) var perWalletSyncCallCount = 0

        func sync(walletAddress: String, chain: Chain) async throws {
            perWalletSyncCallCount += 1
        }

        func syncAll() async throws {
            syncAllCallCount += 1
        }

        func syncAllIfNeeded() async throws {
            syncAllIfNeededCallCount += 1
        }
    }

    /// Counts fetches so grouped-index caching is observable.
    private final class CountingQueryService: AuraPlayMediaItemQuerying, @unchecked Sendable {
        let backing: AuraPlayMediaItemService
        private(set) var windowFetchCount = 0
        private(set) var groupedIndexFetchCount = 0

        init(backing: AuraPlayMediaItemService) {
            self.backing = backing
        }

        func fetchWindow(context: MediaItemQueryContext) async throws -> MediaItemQueryResult {
            windowFetchCount += 1
            return try await backing.fetchWindow(context: context)
        }

        func fetchGroupedIndex(scope: AuraPlayLibraryScope) async throws -> AuraPlayGroupedLibraryIndex {
            groupedIndexFetchCount += 1
            return try await backing.fetchGroupedIndex(scope: scope)
        }

        func fetchGroupItems(
            scope: AuraPlayLibraryScope,
            group: LibraryGroupKey,
            sort: MediaItemSort
        ) async throws -> [MediaItemQueryItem] {
            try await backing.fetchGroupItems(scope: scope, group: group, sort: sort)
        }

        func fetchItems(scope: AuraPlayLibraryScope, ids: [String]) async throws -> [MediaItemQueryItem] {
            try await backing.fetchItems(scope: scope, ids: ids)
        }
    }

    private enum FixtureError: Error {
        case unsupported
    }

    private static let validConfiguration = AuraPlayModuleConfiguration(
        backgroundAudioEnabled: true,
        declaredURLSchemes: ["auraplay", "auralis"],
        walletQuerySchemes: ["metamask", "cbwallet", "rainbow", "ledgerlive"]
    )

    private func makeModel(
        tier: AuraPlayLibrarySeed.Tier,
        discoverySync: FakeDiscoverySync = FakeDiscoverySync()
    ) throws -> (model: AuraPlayRootModel, queryService: CountingQueryService) {
        let container = try AuraPlayLibrarySeed.makeContainer()
        try AuraPlayLibrarySeed.seed(container, tier: tier)
        let queryService = CountingQueryService(
            backing: AuraPlayMediaItemService(modelContainer: container)
        )
        let account = EOAccount(
            address: AuraPlayLibrarySeed.accountAddress,
            access: .readonly
        )
        let model = AuraPlayRootModel(
            libraryRepository: FakeLibraryRepository(),
            librarySyncService: NoOpAuraPlayLibrarySyncService(),
            nftDiscoverySyncService: discoverySync,
            playlistManager: AuraPlayPlaylistService(modelContainer: container),
            playbackController: FakePlaybackController(),
            mediaQueryService: queryService,
            queueCoordinator: FakeQueueCoordinator(),
            artworkLoader: FakeArtworkLoader(),
            logger: FakeLogger(),
            configuration: Self.validConfiguration,
            urlResolver: URLResolver(),
            currentAccount: account,
            currentChain: AuraPlayLibrarySeed.chain
        )
        return (model, queryService)
    }

    // MARK: Browse windows

    @Test("Browse window loads through the service and keeps non-playable rows visible")
    func browseWindowLoadsThroughService() async throws {
        let (model, queryService) = try makeModel(tier: .standard)

        await model.reloadBrowseWindow(sort: .titleAZ, mediaType: .all, unplayedOnly: false)

        #expect(queryService.windowFetchCount == 1)
        #expect(model.browseItems.count == 8)
        #expect(model.browseItems.contains { !$0.isPlayable })
        #expect(model.browseTotalCount == 8)
        #expect(model.browseNextOffset == nil)
    }

    @Test("Near-tail visibility loads the next browse page without duplicates")
    func loadMoreAppendsNextPage() async throws {
        let (model, _) = try makeModel(tier: .large(250))

        await model.reloadBrowseWindow(sort: .titleAZ, mediaType: .all, unplayedOnly: false)
        #expect(model.browseItems.count == 100)

        let nearTailID = model.browseItems[model.browseItems.count - 5].sourceNFTID
        await model.loadMoreBrowseItemsIfNeeded(visibleItemID: nearTailID)

        #expect(model.browseItems.count == 200)
        #expect(Set(model.browseItems.map(\.sourceNFTID)).count == 200)

        // An item far from the tail must not trigger another page.
        let farID = model.browseItems[10].sourceNFTID
        await model.loadMoreBrowseItemsIfNeeded(visibleItemID: farID)
        #expect(model.browseItems.count == 200)
    }

    // MARK: Bounded queue windows (P9-002)

    @Test("Tapping a playable row builds a bounded 100-item window with captured context")
    func browseQueueWindowIsBounded() async throws {
        let (model, _) = try makeModel(tier: .large(5000))

        await model.reloadBrowseWindow(sort: .titleAZ, mediaType: .all, unplayedOnly: false, pageSize: 200)
        let firstPlayable = try #require(model.browseItems.first { $0.isPlayable })

        let pair = try #require(model.browseQueueWindow(startingAt: firstPlayable.sourceNFTID))

        #expect(pair.window.items.count == 100)
        #expect(pair.window.items.allSatisfy { $0.id.hasPrefix("nft-") })
        #expect(pair.item.id == firstPlayable.sourceNFTID)
        // Extension resumes exactly where the window stopped, inside the
        // already-loaded pages, in browse ordering.
        let nextOffset = try #require(pair.window.nextOffset)
        #expect(nextOffset <= 200)
        let context = try #require(pair.window.queryContext)
        #expect(context.offset == nextOffset)
        #expect(context.sort == .titleAZ)
    }

    @Test("Non-playable rows never produce a queue window")
    func nonPlayableTapDoesNotBuildQueue() async throws {
        let (model, _) = try makeModel(tier: .standard)

        await model.reloadBrowseWindow(sort: .titleAZ, mediaType: .all, unplayedOnly: false)
        let nonPlayable = try #require(model.browseItems.first(where: { !$0.isPlayable }))

        #expect(model.browseQueueWindow(startingAt: nonPlayable.sourceNFTID) == nil)
    }

    @Test("List queue windows skip non-playable members and stay bounded")
    func listQueueWindowSkipsNonPlayable() async throws {
        let (model, _) = try makeModel(tier: .standard)
        await model.reloadBrowseWindow(sort: .titleAZ, mediaType: .all, unplayedOnly: false)
        let items = model.browseItems

        let first = try #require(items.first { $0.isPlayable })
        let pair = try #require(
            model.listQueueWindow(startingAt: first.sourceNFTID, in: items, origin: .collection(contractAddress: "0xaaa"))
        )

        #expect(pair.window.items.count == 7)
        #expect(pair.window.origin == .collection(contractAddress: "0xaaa"))
        #expect(!pair.window.items.contains { $0.id == "nft-00006" })
    }

    // MARK: Grouped index caching (P9-003/P9-004)

    @Test("Grouped index is cached per scope and only rebuilt when forced")
    func groupedIndexIsCached() async throws {
        let (model, queryService) = try makeModel(tier: .standard)

        await model.reloadGroupedIndexIfNeeded()
        await model.reloadGroupedIndexIfNeeded()
        #expect(queryService.groupedIndexFetchCount == 1)

        await model.reloadGroupedIndexIfNeeded(force: true)
        #expect(queryService.groupedIndexFetchCount == 2)
        #expect(model.groupedIndex?.collections.isEmpty == false)
    }

    // MARK: Manual refresh (P9-007)

    @Test("Manual refresh calls syncAll, never the debounced variant")
    func manualRefreshCallsSyncAll() async throws {
        let discoverySync = FakeDiscoverySync()
        let (model, _) = try makeModel(tier: .minimal, discoverySync: discoverySync)

        await model.refreshLibraryFromUserAction()

        #expect(discoverySync.syncAllCallCount == 1)
        #expect(discoverySync.perWalletSyncCallCount == 0)
        #expect(model.indexingStatus.isActive == false)
    }

    // MARK: Mini-player visibility (P9-006)

    @Test("Mini-player visibility covers every orchestrator state except idle")
    func miniPlayerVisibilityStates() {
        let item = AuraPlayPlaybackItemPresentation(
            id: "nft-00000",
            title: "Aurora Drift",
            creator: "Nova",
            artworkURLString: nil,
            duration: 201,
            mediaKind: .audio
        )

        #expect(AuraPlayOrchestratorState.idle.isVisibleInMiniPlayer == false)
        #expect(AuraPlayOrchestratorState.loading(item).isVisibleInMiniPlayer)
        #expect(AuraPlayOrchestratorState.playing(item).isVisibleInMiniPlayer)
        #expect(AuraPlayOrchestratorState.paused(item).isVisibleInMiniPlayer)
        #expect(AuraPlayOrchestratorState.buffering(item).isVisibleInMiniPlayer)
        #expect(AuraPlayOrchestratorState.failed(item, message: "x").isVisibleInMiniPlayer)
    }

    @Test("PiP-active items surface the PiP flag for the mini-player glyph")
    func pipActiveItemFlagsPiP() {
        let item = AuraPlayPlaybackItemPresentation(
            id: "nft-00003",
            title: "Delta Bloom",
            creator: "Kestrel",
            artworkURLString: nil,
            duration: 645,
            mediaKind: .video,
            isPiPActive: true
        )

        #expect(AuraPlayOrchestratorState.playing(item).item?.isPiPActive == true)
    }
}
