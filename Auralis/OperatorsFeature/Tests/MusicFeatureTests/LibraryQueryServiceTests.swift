import AuralisPrimaryModels
import Foundation
import MusicFeature
import SwiftData
import Testing

/// P9-002 typed query surface: window fetches, sort/filter behavior, grouped
/// index, and queue-window extension all run through the service, never views.
@MainActor
struct LibraryQueryServiceTests {
    private func makeService(tier: AuraPlayLibrarySeed.Tier) throws -> AuraPlayMediaItemService {
        let container = try AuraPlayLibrarySeed.makeContainer()
        try AuraPlayLibrarySeed.seed(container, tier: tier)
        return AuraPlayMediaItemService(modelContainer: container)
    }

    @Test("Window fetch includes non-playable rows only when the filter asks for them")
    func windowFetchHonorsIncludeNonPlayable() async throws {
        let service = try makeService(tier: .standard)

        let browseContext = MediaItemQueryContext(
            scope: AuraPlayLibrarySeed.scope,
            filter: MediaItemFilter(scope: AuraPlayLibrarySeed.scope, includeNonPlayable: true)
        )
        let browseResult = try await service.fetchWindow(context: browseContext)
        #expect(browseResult.items.count == 8)
        #expect(browseResult.items.contains { !$0.isPlayable })

        let queueContext = MediaItemQueryContext(scope: AuraPlayLibrarySeed.scope)
        let queueResult = try await service.fetchWindow(context: queueContext)
        #expect(queueResult.items.count == 7)
        #expect(queueResult.items.allSatisfy { $0.isPlayable })
    }

    @Test("All sort cases order deterministically")
    func sortCasesAreDeterministic() async throws {
        let service = try makeService(tier: .standard)

        func titles(_ sort: MediaItemSort) async throws -> [String] {
            let context = MediaItemQueryContext(scope: AuraPlayLibrarySeed.scope, sort: sort)
            return try await service.fetchWindow(context: context).items.map(\.title)
        }

        let titleSorted = try await titles(.titleAZ)
        #expect(titleSorted == [
            "Aurora Drift", "Basalt", "Cinder Loop", "Delta Bloom", "Ember Signal", "Fen Static", "Halcyon"
        ])
        let dateSorted = try await titles(.dateAdded)
        #expect(dateSorted.first == "Halcyon")
        let durationSorted = try await titles(.duration)
        #expect(durationSorted.first == "Ember Signal")
        let lastPlayedSorted = try await titles(.lastPlayed)
        #expect(lastPlayedSorted.first == "Aurora Drift")
        let creatorSorted = try await titles(.creatorAZ)
        #expect(creatorSorted.prefix(2) == ["Cinder Loop", "Delta Bloom"])
    }

    @Test("Media type and unplayed filters run in the service")
    func mediaTypeAndUnplayedFilters() async throws {
        let service = try makeService(tier: .standard)

        let videoContext = MediaItemQueryContext(
            scope: AuraPlayLibrarySeed.scope,
            filter: MediaItemFilter(scope: AuraPlayLibrarySeed.scope, mediaType: .video)
        )
        let videoItems = try await service.fetchWindow(context: videoContext).items
        #expect(videoItems.map(\.title) == ["Delta Bloom"])

        let unplayedContext = MediaItemQueryContext(
            scope: AuraPlayLibrarySeed.scope,
            filter: MediaItemFilter(scope: AuraPlayLibrarySeed.scope, unplayedOnly: true)
        )
        let unplayedItems = try await service.fetchWindow(context: unplayedContext).items
        #expect(!unplayedItems.contains { $0.title == "Aurora Drift" })
    }

    @Test("A 500-item library pages through service windows with stable offsets")
    func fiveHundredItemPaging() async throws {
        let service = try makeService(tier: .large(500))

        var context = MediaItemQueryContext(scope: AuraPlayLibrarySeed.scope, sort: .titleAZ, offset: 0, limit: 100)
        var collected: [String] = []
        var pages = 0
        while true {
            let result = try await service.fetchWindow(context: context)
            collected.append(contentsOf: result.items.map(\.sourceNFTID))
            pages += 1
            guard let nextOffset = result.nextOffset else { break }
            context.offset = nextOffset
        }

        let playableCount = 500 - 45 // every 11th index ending in 10 is non-playable
        #expect(collected.count == playableCount)
        #expect(Set(collected).count == collected.count)
        #expect(pages == 5)
    }

    @Test("A 5000-item library materializes only one bounded window per fetch")
    func fiveThousandItemBoundedWindow() async throws {
        let service = try makeService(tier: .large(5000))

        let context = MediaItemQueryContext(scope: AuraPlayLibrarySeed.scope, offset: 0, limit: 100)
        let result = try await service.fetchWindow(context: context)

        #expect(result.items.count == 100)
        #expect(result.nextOffset == 100)
        #expect(result.totalCount > 4000)
    }

    @Test("Grouped index keeps same-name collections on different contracts distinct")
    func groupedIndexDoesNotMergeCollectionsByName() async throws {
        let service = try makeService(tier: .standard)
        let index = try await service.fetchGroupedIndex(scope: AuraPlayLibrarySeed.scope)

        let wavesGroups = index.collections.filter { $0.collectionName == "Waves" }
        #expect(wavesGroups.count == 2)
        #expect(Set(wavesGroups.compactMap(\.contractAddress)) == ["0xaaa", "0xbbb"])
        // The non-playable row does not count toward its collection.
        #expect(wavesGroups.first { $0.contractAddress == "0xaaa" }?.itemCount == 3)
    }

    @Test("Grouped index keeps same display-name creators with distinct identifiers separate")
    func groupedIndexDoesNotMergeCreatorsByDisplayName() async throws {
        let service = try makeService(tier: .standard)
        let index = try await service.fetchGroupedIndex(scope: AuraPlayLibrarySeed.scope)

        let sameNameGroups = index.creators.filter { $0.displayName == "Same Name" }
        #expect(sameNameGroups.count == 2)
        #expect(Set(sameNameGroups.map(\.id)) == ["eth:artist:one", "eth:artist:two"])
    }

    @Test("Group item fetch returns exactly the seeded matching items in deterministic order")
    func groupItemFetchMatchesSeeds() async throws {
        let service = try makeService(tier: .standard)
        let index = try await service.fetchGroupedIndex(scope: AuraPlayLibrarySeed.scope)
        let waves = try #require(index.collections.first { $0.contractAddress == "0xbbb" })

        let items = try await service.fetchGroupItems(
            scope: AuraPlayLibrarySeed.scope,
            group: .collection(id: waves.id),
            sort: .titleAZ
        )
        #expect(items.map(\.title) == ["Cinder Loop"])
    }

    @Test("Fetch by IDs resolves playlist members regardless of playability")
    func fetchByIDsIncludesNonPlayable() async throws {
        let service = try makeService(tier: .standard)
        let items = try await service.fetchItems(
            scope: AuraPlayLibrarySeed.scope,
            ids: ["nft-00006", "nft-00000"]
        )
        #expect(Set(items.map(\.title)) == ["Ghost Format", "Aurora Drift"])
    }

    @Test("Queue window provider maps playable rows in order and preserves the extension offset")
    func queueWindowProviderMapsPlayableRows() async throws {
        let service = try makeService(tier: .standard)
        let provider = AuraPlayMediaQueueWindowProvider(queryService: service)

        var context = MediaItemQueryContext(scope: AuraPlayLibrarySeed.scope, sort: .titleAZ, offset: 0, limit: 4)
        context.filter.includeNonPlayable = true
        let window = try await provider.fetchNextWindow(from: context)

        #expect(window.items.allSatisfy { $0.mediaKind == .audio || $0.mediaKind == .video })
        #expect(window.items.map(\.title) == ["Aurora Drift", "Basalt", "Cinder Loop", "Delta Bloom"])
        #expect(window.nextOffset == 4)
        #expect(window.queryContext == context)
    }
}
