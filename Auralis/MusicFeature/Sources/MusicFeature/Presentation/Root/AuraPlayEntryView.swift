import AuralisPrimaryModels
import AuralisPrimaryPersistence
import AuraUI
import Observation
import SwiftData
import SwiftUI

/// Root presentation model for the active AuraPlay Phase 2 persistence seam.
@Observable
@MainActor
public final class AuraPlayRootModel {
    @ObservationIgnored
    let libraryRepository: any AuraPlayLibraryRepository

    @ObservationIgnored
    let librarySyncService: any AuraPlayLibrarySyncing

    @ObservationIgnored
    let nftDiscoverySyncService: any AuraPlayNFTDiscoverySyncing

    @ObservationIgnored
    let syncProgressProvider: any AuraPlaySyncProgressProviding

    @ObservationIgnored
    let semanticSearchService: any AuraPlaySemanticSearching

    @ObservationIgnored
    let embeddingAvailabilityProvider: any AuraPlayEmbeddingAvailabilityProviding

    @ObservationIgnored
    let playlistGenerator: (any AuraPlayPlaylistGenerating)?

    @ObservationIgnored
    let recommendationProvider: any AuraPlayRecommendationProviding

    @ObservationIgnored
    let playlistManager: any AuraPlayPlaylistManaging

    @ObservationIgnored
    public let playbackController: any AuraPlayPlaybackControlling

    @ObservationIgnored
    public let playbackPresenter: (any AuraPlayPlaybackPresenting)?

    @ObservationIgnored
    public let playbackOrchestrator: (any AuraPlayPlaybackOrchestrating)?

    @ObservationIgnored
    public let mediaQueryService: (any AuraPlayMediaItemQuerying)?

    @ObservationIgnored
    let queueCoordinator: any AuraPlayQueueCoordinating

    @ObservationIgnored
    let artworkLoader: any AuraPlayArtworkLoading

    @ObservationIgnored
    let logger: any AuraPlayLogging

    @ObservationIgnored
    let configuration: AuraPlayModuleConfiguration

    @ObservationIgnored
    let urlResolver: URLResolver

    public private(set) var currentAccount: EOAccount?
    public private(set) var currentChain: Chain

    public var libraryItemCount: Int?
    public var upcomingQueueCount: Int
    public var playbackHistoryCount: Int
    public var currentArtworkURL: URL?
    public var lastError: AuraPlayError?
    public var configurationStatus: String
    public var statusMessage: String
    public var semanticSearchText: String
    public private(set) var semanticSearchResults: [AuraPlaySemanticSearchResult]
    public private(set) var isSemanticSearchRunning: Bool
    public private(set) var semanticSearchStatus: String
    public private(set) var indexingStatus: AuraPlayIndexingStatus
    public var searchText: String
    public private(set) var searchSuggestions: [AuraPlaySearchSuggestion]
    public private(set) var searchResults: [AuraPlaySearchResult]
    public private(set) var searchRecentQueries: [String]
    public private(set) var isSearchRunning: Bool
    public private(set) var searchStatus: String
    public private(set) var searchDiagnostics: AuraPlaySearchDiagnostics
    public var searchFilter: MediaItemFilter
    public private(set) var embeddingAvailability: AuraPlayEmbeddingAvailability
    /// False until the first availability probe resolves, so semantic entry points
    /// stay hidden rather than flashing visible under the optimistic default.
    public private(set) var embeddingAvailabilityResolved: Bool
    /// Scoped media IDs that have a stored embedding; drives per-item gating of
    /// the "More Like This" action so it is hidden when the source item has no
    /// vector (P13-002 acceptance criterion C).
    public private(set) var recommendableItemIDs: Set<String>
    public var shouldShowPlaylistPlayground: Bool {
        embeddingAvailabilityResolved && embeddingAvailability.isAvailable
    }
    public var playlistPlaygroundPrompt: String
    public private(set) var playlistPlaygroundPreview: AuraPlayGeneratedPlaylistPreview?
    public private(set) var isPlaylistPlaygroundRunning: Bool
    public private(set) var playlistPlaygroundStatus: String

    /// Reads sync progress live from the `@Observable` provider rather than
    /// snapshotting it at discrete points. `syncProgressProvider` is
    /// `@ObservationIgnored` (its reference never changes), but the provider is
    /// itself `@Observable`, so views that read this property observe the
    /// underlying `progress` and update during foreground sync automatically.
    public var syncProgress: SyncProgress {
        syncProgressProvider.syncProgress
    }

    // Service-backed browse window (P9-002). The view never sorts or filters
    // media arrays itself; it renders these snapshots.
    public private(set) var browseItems: [MediaItemQueryItem] = []
    public private(set) var browseTotalCount: Int?
    public private(set) var browseNextOffset: Int?
    public private(set) var browseContext: MediaItemQueryContext?
    public private(set) var groupedIndex: AuraPlayGroupedLibraryIndex?
    @ObservationIgnored private var groupedIndexScopeKey: String?
    @ObservationIgnored private var lastSyncCompletionDate: Date?
    @ObservationIgnored private var browseLoadTask: Task<Void, Never>?
    @ObservationIgnored private let recentSearchStore: AuraPlayRecentSearchStore
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var searchGeneration = 0

    public init(
        libraryRepository: any AuraPlayLibraryRepository,
        librarySyncService: any AuraPlayLibrarySyncing,
        nftDiscoverySyncService: any AuraPlayNFTDiscoverySyncing,
        syncProgressProvider: any AuraPlaySyncProgressProviding = NoOpAuraPlaySyncProgressProvider(),
        semanticSearchService: any AuraPlaySemanticSearching = NoOpAuraPlaySemanticSearchService(),
        embeddingAvailabilityProvider: any AuraPlayEmbeddingAvailabilityProviding = AlwaysAvailableAuraPlayEmbeddingAvailabilityProvider(),
        playlistGenerator: (any AuraPlayPlaylistGenerating)? = nil,
        recommendationProvider: any AuraPlayRecommendationProviding = NoOpAuraPlayRecommendationProvider(),
        recentSearchStore: AuraPlayRecentSearchStore = AuraPlayRecentSearchStore(),
        playlistManager: any AuraPlayPlaylistManaging,
        playbackController: any AuraPlayPlaybackControlling,
        playbackPresenter: (any AuraPlayPlaybackPresenting)? = nil,
        playbackOrchestrator: (any AuraPlayPlaybackOrchestrating)? = nil,
        mediaQueryService: (any AuraPlayMediaItemQuerying)? = nil,
        queueCoordinator: any AuraPlayQueueCoordinating,
        artworkLoader: any AuraPlayArtworkLoading,
        logger: any AuraPlayLogging,
        configuration: AuraPlayModuleConfiguration,
        urlResolver: URLResolver,
        currentAccount: EOAccount?,
        currentChain: Chain
    ) {
        self.libraryRepository = libraryRepository
        self.librarySyncService = librarySyncService
        self.nftDiscoverySyncService = nftDiscoverySyncService
        self.syncProgressProvider = syncProgressProvider
        self.semanticSearchService = semanticSearchService
        self.embeddingAvailabilityProvider = embeddingAvailabilityProvider
        self.playlistGenerator = playlistGenerator
        self.recommendationProvider = recommendationProvider
        self.recentSearchStore = recentSearchStore
        self.playlistManager = playlistManager
        self.playbackController = playbackController
        self.playbackPresenter = playbackPresenter
        self.playbackOrchestrator = playbackOrchestrator
        self.mediaQueryService = mediaQueryService
        self.queueCoordinator = queueCoordinator
        self.artworkLoader = artworkLoader
        self.logger = logger
        self.configuration = configuration
        self.urlResolver = urlResolver
        self.currentAccount = currentAccount
        self.currentChain = currentChain
        self.upcomingQueueCount = 0
        self.playbackHistoryCount = 0
        self.currentArtworkURL = nil
        self.configurationStatus = Self.makeConfigurationStatus(configuration)
        self.statusMessage = "AuraPlay is ready to play wallet-scoped tracks for the current account and chain."
        self.semanticSearchText = ""
        self.semanticSearchResults = []
        self.isSemanticSearchRunning = false
        self.semanticSearchStatus = "Semantic search is ready."
        self.indexingStatus = AuraPlayIndexingStatus(isActive: false, message: "Index ready")
        let initialScope = AuraPlayLibraryScope(accountAddress: currentAccount?.address, chain: currentChain)
        self.searchText = ""
        self.searchSuggestions = []
        self.searchResults = []
        self.searchRecentQueries = recentSearchStore.queries(scope: initialScope)
        self.isSearchRunning = false
        self.searchStatus = "Search the active AuraPlay library."
        self.searchDiagnostics = AuraPlaySearchDiagnostics()
        self.searchFilter = MediaItemFilter(
            scope: initialScope,
            selectedChains: [currentChain],
            includeNonPlayable: true
        )
        self.embeddingAvailability = .available
        self.embeddingAvailabilityResolved = false
        self.recommendableItemIDs = []
        self.playlistPlaygroundPrompt = ""
        self.playlistPlaygroundPreview = nil
        self.isPlaylistPlaygroundRunning = false
        self.playlistPlaygroundStatus = "Describe a playlist to generate it from this library."
    }

    public var scope: AuraPlayLibraryScope {
        AuraPlayLibraryScope(
            accountAddress: currentAccount?.address,
            chain: currentChain
        )
    }

    public func updateContext(
        currentAccount: EOAccount?,
        currentChain: Chain
    ) {
        let accountChanged = self.currentAccount?.address != currentAccount?.address
        let chainChanged = self.currentChain != currentChain

        guard accountChanged || chainChanged else {
            return
        }

        self.currentAccount = currentAccount
        self.currentChain = currentChain
        configurationStatus = Self.makeConfigurationStatus(configuration)
        clearSemanticSearch()
        clearSearch()
        clearPlaylistPlayground()
        searchFilter = MediaItemFilter(
            scope: scope,
            selectedChains: [scope.chain],
            includeNonPlayable: true
        )
        searchRecentQueries = recentSearchStore.queries(scope: scope)

        browseItems = []
        browseTotalCount = nil
        browseNextOffset = nil
        browseContext = nil
        groupedIndex = nil
        groupedIndexScopeKey = nil
        recommendableItemIDs = []
    }

    public func refreshEmbeddingAvailability() async {
        embeddingAvailability = await embeddingAvailabilityProvider.availability()
        embeddingAvailabilityResolved = true
        await refreshRecommendableItems()
    }

    /// Refreshes the scoped set of items that have an embedding so the UI can
    /// hide "More Like This" per item. Clears when embeddings are unavailable.
    public func refreshRecommendableItems() async {
        guard embeddingAvailability.isAvailable else {
            recommendableItemIDs = []
            return
        }
        do {
            recommendableItemIDs = try await recommendationProvider.embeddedMediaItemIDs(in: scope)
        } catch {
            recommendableItemIDs = []
        }
    }

    /// Whether the "More Like This" action should be offered for a media item.
    public func canRecommend(mediaItemID: String) -> Bool {
        embeddingAvailability.isAvailable && recommendableItemIDs.contains(mediaItemID)
    }

    public func playlistSnapshot(id: String) async -> AuraPlayPlaylistSnapshot? {
        try? await playlistManager.fetchPlaylistSnapshot(id: id)
    }

    public func playlistSnapshots() async throws -> [AuraPlayPlaylistSnapshot] {
        try await playlistManager.fetchPlaylistSnapshots()
    }

    public func refreshLibrarySummary() async {
        await refreshLibrarySummary(syncDiscoveryIfNeeded: true)
    }

    public func refreshLibraryFromUserAction() async {
        // Live token/item counts render automatically while the network fetch
        // phase runs: `syncProgress` reads through to the `@Observable` provider
        // (P9-007), so no manual polling is required.
        indexingStatus = AuraPlayIndexingStatus(isActive: true, message: "Indexing wallet media")

        do {
            // P9-007: manual refresh always bypasses the debounce.
            try await nftDiscoverySyncService.syncAll()
        } catch {
            lastError = AuraPlayError.library(error)
            statusMessage = AuraPlayErrorPresentation.message(for: error, context: .librarySync)
            logger.log(
                AuraPlayLogEvent(
                    category: .sync,
                    level: .error,
                    message: lastError?.localizedDescription ?? "AuraPlay NFT discovery sync failed."
                )
            )
        }

        indexingStatus = AuraPlayIndexingStatus(isActive: false, message: "Index ready")
        await refreshLibrarySummary(syncDiscoveryIfNeeded: false)
        await invalidateAfterSyncCompletion()
    }

    // MARK: - Service-backed browsing (P9-002)

    public func reloadBrowseWindow(
        sort: MediaItemSort,
        mediaType: MediaItemMediaTypeFilter,
        unplayedOnly: Bool,
        pageSize: Int = 100
    ) async {
        guard let mediaQueryService else { return }
        let context = MediaItemQueryContext(
            scope: scope,
            sort: sort,
            filter: MediaItemFilter(
                scope: scope,
                mediaType: mediaType,
                unplayedOnly: unplayedOnly,
                includeNonPlayable: true
            ),
            offset: 0,
            limit: pageSize
        )
        browseContext = context
        do {
            let result = try await mediaQueryService.fetchWindow(context: context)
            guard browseContext == context else { return }
            browseItems = result.items
            browseTotalCount = result.totalCount
            browseNextOffset = result.nextOffset
        } catch {
            lastError = AuraPlayError.library(error)
        }
    }

    public func loadMoreBrowseItemsIfNeeded(visibleItemID: String) async {
        guard let mediaQueryService,
              var context = browseContext,
              let nextOffset = browseNextOffset,
              !isLoadingMoreBrowseItems,
              let index = browseItems.firstIndex(where: { $0.sourceNFTID == visibleItemID }),
              browseItems.count - index <= 20 else {
            return
        }

        isLoadingMoreBrowseItems = true
        defer { isLoadingMoreBrowseItems = false }
        context.offset = nextOffset
        do {
            let result = try await mediaQueryService.fetchWindow(context: context)
            guard browseContext?.filter == context.filter, browseContext?.sort == context.sort else { return }
            let loadedIDs = Set(browseItems.map(\.sourceNFTID))
            browseItems.append(contentsOf: result.items.filter { !loadedIDs.contains($0.sourceNFTID) })
            browseTotalCount = result.totalCount
            browseNextOffset = result.nextOffset
        } catch {
            lastError = AuraPlayError.library(error)
        }
    }

    public func reloadGroupedIndexIfNeeded(force: Bool = false) async {
        guard let mediaQueryService else { return }
        let key = scopeKey
        if !force, groupedIndexScopeKey == key, groupedIndex != nil {
            return
        }
        do {
            groupedIndex = try await mediaQueryService.fetchGroupedIndex(scope: scope)
            groupedIndexScopeKey = key
        } catch {
            lastError = AuraPlayError.library(error)
        }
    }

    public func groupItems(_ group: LibraryGroupKey, sort: MediaItemSort) async -> [MediaItemQueryItem] {
        guard let mediaQueryService else { return [] }
        do {
            return try await mediaQueryService.fetchGroupItems(scope: scope, group: group, sort: sort)
        } catch {
            lastError = AuraPlayError.library(error)
            return []
        }
    }

    public func creatorProfile(
        creatorIdentifier: String,
        accountAddresses: [String],
        sort: MediaItemSort
    ) async -> AuraPlayCreatorProfile? {
        guard let mediaQueryService else { return nil }
        do {
            return try await mediaQueryService.fetchCreatorProfile(
                creatorIdentifier: creatorIdentifier,
                accountAddresses: accountAddresses,
                chains: nil,
                sort: sort
            )
        } catch {
            lastError = AuraPlayError.library(error)
            return nil
        }
    }

    public func items(withIDs ids: [String]) async -> [MediaItemQueryItem] {
        guard let mediaQueryService, !ids.isEmpty else { return [] }
        do {
            return try await mediaQueryService.fetchItems(scope: scope, ids: ids)
        } catch {
            lastError = AuraPlayError.library(error)
            return []
        }
    }

    /// Builds the bounded queue window (default 100 playable items) starting at a tapped
    /// browse row, capturing the query context so the queue can lazily extend later
    /// without reading live view state.
    public func browseQueueWindow(
        startingAt itemID: String,
        windowSize: Int = 100
    ) -> (item: AuraPlayPlaybackItemPresentation, window: AuraPlayQueueWindow)? {
        guard let tappedIndex = browseItems.firstIndex(where: { $0.sourceNFTID == itemID }),
              browseItems[tappedIndex].isPlayable else {
            return nil
        }

        var windowItems: [MediaItemQueryItem] = []
        var lastIncludedIndex = tappedIndex
        for index in tappedIndex..<browseItems.count where browseItems[index].isPlayable {
            windowItems.append(browseItems[index])
            lastIncludedIndex = index
            if windowItems.count == windowSize { break }
        }

        // Continue extension exactly where the window stopped, in browse ordering.
        let extensionOffset: Int? = windowItems.count == windowSize && lastIncludedIndex + 1 < browseItems.count
            ? lastIncludedIndex + 1
            : browseNextOffset
        var extensionContext: MediaItemQueryContext?
        if var context = browseContext, let extensionOffset {
            context.offset = extensionOffset
            extensionContext = context
        }

        let window = AuraPlayQueueWindow(
            items: windowItems.map(\.playbackPresentation),
            startIndex: 0,
            origin: .single(mediaItemID: itemID),
            queryContext: extensionContext,
            windowSize: windowSize,
            nextOffset: extensionOffset
        )
        return (browseItems[tappedIndex].playbackPresentation, window)
    }

    /// Bounded window over a fully known ordered list (collection, creator, playlist).
    public func listQueueWindow(
        startingAt itemID: String,
        in items: [MediaItemQueryItem],
        origin: AuraPlayQueueOriginPresentation,
        windowSize: Int = 100
    ) -> (item: AuraPlayPlaybackItemPresentation, window: AuraPlayQueueWindow)? {
        guard let tappedIndex = items.firstIndex(where: { $0.sourceNFTID == itemID }),
              items[tappedIndex].isPlayable else {
            return nil
        }
        let playable = items[tappedIndex...].filter(\.isPlayable).prefix(windowSize)
        let window = AuraPlayQueueWindow(
            items: playable.map(\.playbackPresentation),
            startIndex: 0,
            origin: origin,
            queryContext: nil,
            windowSize: windowSize,
            nextOffset: nil
        )
        return (items[tappedIndex].playbackPresentation, window)
    }

    private func invalidateAfterSyncCompletion() async {
        // Grouped index and browse pages are cached; rebuild them only after a
        // sync generation completes.
        guard case .complete = syncProgress.state else { return }
        if let lastSyncedAt = syncProgress.lastSyncedAt, lastSyncedAt == lastSyncCompletionDate {
            return
        }
        lastSyncCompletionDate = syncProgress.lastSyncedAt
        await refreshRecommendableItems()
        await reloadGroupedIndexIfNeeded(force: true)
        if let context = browseContext {
            await reloadBrowseWindow(
                sort: context.sort,
                mediaType: context.filter.mediaType,
                unplayedOnly: context.filter.unplayedOnly,
                pageSize: context.limit
            )
        }
    }

    private var scopeKey: String {
        "\(scope.accountAddress ?? "none")|\(scope.chain.rawValue)"
    }

    @ObservationIgnored private var isLoadingMoreBrowseItems = false

    public func runSemanticSearch() async {
        let query = semanticSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            clearSemanticSearch()
            return
        }

        isSemanticSearchRunning = true
        do {
            let results = try await semanticSearchService.search(
                query: query,
                in: scope,
                limit: 8,
                minimumScore: 0.18
            )
            semanticSearchResults = results
            semanticSearchStatus = results.isEmpty
                ? "No semantic matches found."
                : "\(results.count) semantic \(results.count == 1 ? "match" : "matches") found."
        } catch {
            semanticSearchResults = []
            lastError = AuraPlayError.library(error)
            semanticSearchStatus = "Semantic search is unavailable right now."
            logger.log(
                AuraPlayLogEvent(
                    category: .library,
                    level: .error,
                    message: lastError?.localizedDescription ?? "AuraPlay semantic search failed."
                )
            )
        }
        isSemanticSearchRunning = false
    }

    public func clearSemanticSearch() {
        semanticSearchText = ""
        semanticSearchResults = []
        semanticSearchStatus = "Semantic search is ready."
        isSemanticSearchRunning = false
    }

    public var filteredSearchResults: [AuraPlaySearchResult] {
        AuraPlaySearchCoordinator.filtered(searchResults, filter: searchFilter)
    }

    public var suggestedSearchQueries: [String] {
        let recentCount = searchRecentQueries.count
        guard recentCount < 4 else { return [] }
        return Array(AuraPlaySearchCoordinator.suggestedQueries.prefix(4 - recentCount))
    }

    public func refreshSearchRecents() {
        searchRecentQueries = recentSearchStore.queries(scope: scope)
    }

    public func updateSearchText(_ text: String) async {
        searchText = text
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchSuggestions = []
            searchResults = []
            searchDiagnostics = AuraPlaySearchDiagnostics()
            searchStatus = "Search the active AuraPlay library."
            return
        }

        do {
            let items = try await fetchSearchSnapshot()
            searchSuggestions = AuraPlaySearchCoordinator.suggestions(for: trimmed, in: items)
        } catch {
            searchSuggestions = []
        }
    }

    public func submitSearch(_ query: String? = nil) {
        let trimmed = (query ?? searchText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clearSearch()
            return
        }

        searchText = trimmed
        recentSearchStore.record(trimmed, scope: scope)
        refreshSearchRecents()
        searchSuggestions = []
        isSearchRunning = true
        searchStatus = "Searching AuraPlay."
        searchGeneration += 1
        let generation = searchGeneration
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            await performSearch(query: trimmed, generation: generation)
        }
    }

    public func clearSearch() {
        searchTask?.cancel()
        searchText = ""
        searchSuggestions = []
        searchResults = []
        searchDiagnostics = AuraPlaySearchDiagnostics()
        searchStatus = "Search the active AuraPlay library."
        isSearchRunning = false
    }

    public func clearRecentSearches() {
        recentSearchStore.clear(scope: scope)
        refreshSearchRecents()
    }

    public func clearSearchFilters() {
        searchFilter = MediaItemFilter(
            scope: scope,
            selectedChains: [scope.chain],
            includeNonPlayable: true
        )
    }

    public func waitForSearchCompletion() async {
        await searchTask?.value
    }

    public func searchQueueWindow(
        startingAt itemID: String,
        windowSize: Int = 100
    ) -> (item: AuraPlayPlaybackItemPresentation, window: AuraPlayQueueWindow)? {
        AuraPlaySearchCoordinator.queueWindow(
            startingAt: itemID,
            in: filteredSearchResults,
            query: searchText,
            windowSize: windowSize
        )
    }

    public func generatePlaylistPreview(regenerate: Bool = false) async {
        guard embeddingAvailability.isAvailable else {
            playlistPlaygroundPreview = nil
            playlistPlaygroundStatus = embeddingAvailability.explanation
                ?? "Smart playlist features are not available right now."
            return
        }
        guard let playlistGenerator else {
            playlistPlaygroundPreview = nil
            playlistPlaygroundStatus = "Playlist generation is unavailable right now."
            return
        }

        let previousIDs = regenerate
            ? Set(playlistPlaygroundPreview?.items.map(\.sourceNFTID) ?? [])
            : []
        isPlaylistPlaygroundRunning = true
        do {
            let preview = try await playlistGenerator.preview(
                prompt: playlistPlaygroundPrompt,
                scope: scope,
                excludingPreviousIDs: previousIDs
            )
            playlistPlaygroundPreview = preview
            playlistPlaygroundStatus = preview.note
                ?? "\(preview.items.count) candidate \(preview.items.count == 1 ? "track" : "tracks") ready."
        } catch {
            playlistPlaygroundPreview = nil
            playlistPlaygroundStatus = AuraPlayErrorPresentation.message(for: error, context: .playlistGeneration)
            logger.log(
                AuraPlayLogEvent(
                    category: .library,
                    level: .error,
                    message: "AuraPlay playlist generation failed: \(error.localizedDescription)"
                )
            )
        }
        isPlaylistPlaygroundRunning = false
    }

    public func savePlaylistPreview(at date: Date = .now) async {
        guard let preview = playlistPlaygroundPreview, preview.canSave else {
            playlistPlaygroundStatus = "Try a broader prompt before saving."
            return
        }

        do {
            let metadataData = try AuraPlaySmartPlaylistMetadata.metadataData(
                prompt: preview.prompt,
                resultIDs: preview.items.map(\.sourceNFTID),
                minimumScore: AuraPlayIntelligenceSettings.defaultSemanticMinimumScore,
                modelVersion: nil,
                createdAt: date
            )
            _ = try await playlistManager.createSmartPlaylistID(
                name: Self.playlistName(for: preview.prompt),
                mediaItemIDs: preview.items.map(\.sourceNFTID),
                smartQueryData: metadataData,
                at: date
            )
            playlistPlaygroundStatus = "Saved smart playlist."
        } catch {
            playlistPlaygroundStatus = AuraPlayErrorPresentation.message(for: error, context: .playlistSave)
            logger.log(
                AuraPlayLogEvent(
                    category: .library,
                    level: .error,
                    message: "AuraPlay smart playlist save failed: \(error.localizedDescription)"
                )
            )
        }
    }

    public func clearPlaylistPlayground() {
        playlistPlaygroundPrompt = ""
        playlistPlaygroundPreview = nil
        isPlaylistPlaygroundRunning = false
        playlistPlaygroundStatus = "Describe a playlist to generate it from this library."
    }

    public func moreLikeThis(mediaItemID: String, limit: Int = 25) async -> [AuraPlayRecommendationResult] {
        guard embeddingAvailability.isAvailable else { return [] }
        do {
            return try await recommendationProvider.moreLikeThis(
                mediaItemID: mediaItemID,
                in: scope,
                limit: limit,
                minimumScore: AuraPlayIntelligenceSettings.recommendationStrictMinimumScore
            )
        } catch {
            logger.log(
                AuraPlayLogEvent(
                    category: .library,
                    level: .error,
                    message: "AuraPlay recommendations failed: \(error.localizedDescription)"
                )
            )
            return []
        }
    }

    /// Saves a "More Like This" result set as a smart playlist, reusing the same
    /// materialization path as Playlist Playground (P13-002).
    @discardableResult
    public func saveRecommendationsPlaylist(
        sourceTitle: String,
        results: [AuraPlayRecommendationResult],
        at date: Date = .now
    ) async -> Bool {
        let ids = results.map(\.item.sourceNFTID)
        guard !ids.isEmpty else { return false }

        let prompt = "More like \(sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines))"
        do {
            let metadataData = try AuraPlaySmartPlaylistMetadata.metadataData(
                prompt: prompt,
                resultIDs: ids,
                minimumScore: 0.18,
                modelVersion: nil,
                createdAt: date
            )
            _ = try await playlistManager.createSmartPlaylistID(
                name: Self.playlistName(for: prompt),
                mediaItemIDs: ids,
                smartQueryData: metadataData,
                at: date
            )
            return true
        } catch {
            logger.log(
                AuraPlayLogEvent(
                    category: .library,
                    level: .error,
                    message: "AuraPlay recommendation playlist save failed: \(error.localizedDescription)"
                )
            )
            return false
        }
    }

    private static func playlistName(for prompt: String) -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Generated Playlist" }
        return "Smart: \(trimmed.prefix(48))"
    }

    private func performSearch(query: String, generation: Int) async {
        do {
            let snapshot = try await fetchSearchSnapshot()
            try Task.checkCancellation()
            guard generation == searchGeneration else { return }

            let localMatches = AuraPlaySearchCoordinator.localMatches(query: query, in: snapshot)
            let localMerge = AuraPlaySearchCoordinator.merge(
                localItems: localMatches,
                semanticResults: [],
                resolvedSemanticItems: []
            )
            searchResults = localMerge.results
            searchDiagnostics = localMerge.diagnostics
            searchStatus = localMatches.isEmpty ? "Checking semantic matches." : "\(localMatches.count) local match\(localMatches.count == 1 ? "" : "es") found."

            let semanticMatches = try await semanticSearchService.search(
                query: query,
                in: scope,
                limit: 25,
                minimumScore: 0.18
            )
            try Task.checkCancellation()
            guard generation == searchGeneration else { return }

            let resolvedSemanticItems = try await mediaQueryService?.fetchItems(
                scope: scope,
                ids: semanticMatches.map(\.id)
            ) ?? []
            let merged = AuraPlaySearchCoordinator.merge(
                localItems: localMatches,
                semanticResults: semanticMatches,
                resolvedSemanticItems: resolvedSemanticItems
            )
            searchResults = merged.results
            searchDiagnostics = merged.diagnostics
            searchStatus = merged.results.isEmpty
                ? "No AuraPlay matches found."
                : "\(merged.results.count) search match\(merged.results.count == 1 ? "" : "es") found."
            isSearchRunning = false
        } catch is CancellationError {
            return
        } catch {
            guard generation == searchGeneration else { return }
            isSearchRunning = false
            searchStatus = searchResults.isEmpty
                ? AuraPlayErrorPresentation.message(for: error, context: .search)
                : "Semantic search is unavailable; local matches are shown."
            logger.log(
                AuraPlayLogEvent(
                    category: .library,
                    level: .error,
                    message: "AuraPlay search failed: \(error.localizedDescription)"
                )
            )
        }
    }

    private func fetchSearchSnapshot() async throws -> [MediaItemQueryItem] {
        guard let mediaQueryService else { return [] }
        let context = MediaItemQueryContext(
            scope: scope,
            sort: .titleAZ,
            filter: MediaItemFilter(scope: scope, includeNonPlayable: true),
            offset: 0,
            limit: 5_000
        )
        return try await mediaQueryService.fetchWindow(context: context).items
    }

    private func refreshLibrarySummary(syncDiscoveryIfNeeded: Bool) async {
        logger.log(
            AuraPlayLogEvent(
                category: .library,
                level: .info,
                message: "Refreshing AuraPlay library summary for \(scope.accountAddress == nil ? "no active account" : "active account") on \(scope.chain.rawValue)"
            )
        )

        do {
            if syncDiscoveryIfNeeded {
                try await nftDiscoverySyncService.syncAllIfNeeded()
            }
            try await librarySyncService.syncLibrary(
                in: scope,
                accountName: currentAccount?.name
            )
            libraryItemCount = try libraryRepository.itemCount(in: scope)
            lastError = nil
        } catch {
            libraryItemCount = nil
            lastError = AuraPlayError.library(error)
            statusMessage = AuraPlayErrorPresentation.message(for: error, context: .librarySummary)
            logger.log(
                AuraPlayLogEvent(
                    category: .library,
                    level: .error,
                    message: lastError?.localizedDescription ?? "AuraPlay library refresh failed."
                )
            )
        }

        let queueSnapshot = queueCoordinator.snapshot()
        upcomingQueueCount = queueSnapshot.upcomingCount
        playbackHistoryCount = queueSnapshot.historyCount

        do {
            currentArtworkURL = try resolvedArtworkURL(for: playbackController.currentTrack)
        } catch let error as AuraPlayError {
            currentArtworkURL = nil
            lastError = error
            logger.log(
                AuraPlayLogEvent(
                    category: .artwork,
                    level: .error,
                    message: error.localizedDescription
                )
            )
        } catch {
            currentArtworkURL = nil
            let mappedError = AuraPlayError.artwork(error)
            lastError = mappedError
            logger.log(
                AuraPlayLogEvent(
                    category: .artwork,
                    level: .error,
                    message: mappedError.localizedDescription
                )
            )
        }

        if let lastError {
            statusMessage = AuraPlayErrorPresentation.message(for: lastError, context: .librarySummary)
        } else if configuration.missingRequirements.isEmpty {
            statusMessage = "AuraPlay is ready. Library, playback, queue, artwork, and account-scoped storage are available."
        } else {
            statusMessage = "AuraPlay is available, but part of the local media setup needs attention."
        }
    }

    private static func makeConfigurationStatus(_ configuration: AuraPlayModuleConfiguration) -> String {
        if configuration.missingRequirements.isEmpty {
            return "Bundle contract ready"
        }
        return configuration.missingRequirements.joined(separator: " ")
    }

    private func resolvedArtworkURL(for track: AuraPlayTrack?) throws -> URL? {
        if let imageURLString = track?.imageURLString,
           let resolvedURL = urlResolver.resolve(imageURLString) {
            return resolvedURL
        }
        return try artworkLoader.artworkURL(for: track)
    }
}

struct AuraPlayEntryView: View {
    @Bindable var model: AuraPlayRootModel
    let currentAccount: EOAccount?
    let currentChain: Chain
    let onOpenItem: (String) -> Void
    let onOpenCollection: (String, String) -> Void
    let onPlayItem: (String) async -> Void
    let onAddItemToQueue: (String) async -> Void

    @Query private var allLibraryItems: [MusicLibraryItem]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var searchText = ""
    @State private var libraryFilter: AuraPlayLibraryFilter = .all
    @State private var librarySort: AuraPlayLibrarySort = .title

    init(
        model: AuraPlayRootModel,
        currentAccount: EOAccount?,
        currentChain: Chain,
        onOpenItem: @escaping (String) -> Void,
        onOpenCollection: @escaping (String, String) -> Void,
        onPlayItem: @escaping (String) async -> Void,
        onAddItemToQueue: @escaping (String) async -> Void
    ) {
        self.model = model
        self.currentAccount = currentAccount
        self.currentChain = currentChain
        self.onOpenItem = onOpenItem
        self.onOpenCollection = onOpenCollection
        self.onPlayItem = onPlayItem
        self.onAddItemToQueue = onAddItemToQueue

        let sortDescriptors: [SortDescriptor<MusicLibraryItem>] = [
            SortDescriptor(\MusicLibraryItem.normalizedCollectionKey),
            SortDescriptor(\MusicLibraryItem.normalizedArtistKey),
            SortDescriptor(\MusicLibraryItem.normalizedTitleKey),
            SortDescriptor(\MusicLibraryItem.id)
        ]
        _allLibraryItems = Query(sort: sortDescriptors)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                header
                librarySummaryCard
                libraryControls
                semanticSearchSection
                collectionsSection
                tracksSection
                mediaIntegrationSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.background.ignoresSafeArea())
        .navigationTitle("Music")
        .accessibilityIdentifier(A11yID.AuraPlay.root)
        .task(
            id: "\(model.currentAccount?.address ?? "none")|\(model.currentChain.rawValue)"
        ) {
            await model.refreshLibrarySummary()
        }
        .refreshable {
            await model.refreshLibraryFromUserAction()
        }
    }

    private var libraryItems: [MusicLibraryItem] {
        let normalizedAccountAddress = NFT.normalizedScopeComponent(currentAccount?.address) ?? ""
        let chainRawValue = currentChain.rawValue
        return allLibraryItems.filter {
            $0.accountAddressRawValue == normalizedAccountAddress &&
            $0.networkRawValue == chainRawValue
        }
    }

    private var visibleLibraryItems: [MusicLibraryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filteredItems = libraryItems.filter { item in
            libraryFilter.includes(item) && (query.isEmpty || item.matchesLibrarySearch(query))
        }
        return librarySort.sort(filteredItems)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            AuraPill("AuraPlay", systemImage: "waveform.circle", emphasis: .accent)
                AuraSectionHeader(
                    title: "AuraPlay Library",
                    subtitle: "Wallet-scoped tracks, queue controls, recent playback, video preview, and media availability."
                )
        }
    }

    private var librarySummaryCard: some View {
        AuraSurfaceCard(style: .soft, cornerRadius: 28, padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Library Ready", systemImage: "music.note.list")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)

                Text(model.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)

                Divider()
                    .overlay(Color.white.opacity(0.08))

                infoRow(title: "Account", value: currentAccount?.name ?? currentAccount?.address ?? "No active account")
                infoRow(title: "Chain", value: currentChain.routingDisplayName)
                infoRow(title: "Tracks", value: String(libraryItems.count))
                infoRow(title: "Playable", value: String(libraryItems.filter(\.isPlaybackReady).count))
                infoRow(title: "Visible", value: String(visibleLibraryItems.count))
                infoRow(title: "Playback", value: String(describing: model.playbackController.playbackState).capitalized)
                infoRow(title: "Queue", value: "\(model.upcomingQueueCount) upcoming, \(model.playbackHistoryCount) recent")
                infoRow(title: "Bundle", value: model.configurationStatus)
            }
        }
        .accessibilityIdentifier(A11yID.AuraPlay.librarySummary)
    }

    private var libraryControls: some View {
        AuraSurfaceCard(style: .regular, cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.textSecondary)
                        .accessibilityHidden(true)

                    TextField("Search tracks, artists, collections", text: $searchText)
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .disableAutocorrection(true)
                        .accessibilityIdentifier(A11yID.AuraPlay.librarySearch)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))

                Picker("Filter", selection: $libraryFilter) {
                    ForEach(AuraPlayLibraryFilter.allCases) { filter in
                        Label(filter.title, systemImage: filter.systemImage)
                            .tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier(A11yID.AuraPlay.libraryFilter)

                HStack {
                    Label("Showing \(visibleLibraryItems.count) of \(libraryItems.count)", systemImage: "line.3.horizontal.decrease.circle")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)

                    Spacer()

                    Picker("Sort", selection: $librarySort) {
                        ForEach(AuraPlayLibrarySort.allCases) { sort in
                            Text(sort.title).tag(sort)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier(A11yID.AuraPlay.librarySort)
                }
            }
        }
    }

    private var semanticSearchSection: some View {
        AuraPlayLibrarySection(title: "Semantic Search", systemImage: "sparkles") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.textSecondary)
                        .accessibilityHidden(true)

                    TextField("Search by mood, artist, sound, or collection", text: $model.semanticSearchText)
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .disableAutocorrection(true)
                        .submitLabel(.search)
                        .onSubmit {
                            Task { await model.runSemanticSearch() }
                        }
                        .accessibilityIdentifier(A11yID.AuraPlay.semanticSearch)

                    if model.isSemanticSearchRunning {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Semantic search running")
                    } else if !model.semanticSearchText.isEmpty {
                        Button {
                            model.clearSemanticSearch()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .accessibilityHidden(true)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Clear semantic search")
                        .accessibilityIdentifier(A11yID.AuraPlay.semanticSearchClear)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))

                HStack(spacing: 10) {
                    Text(model.semanticSearchStatus)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)

                    Button {
                        Task { await model.runSemanticSearch() }
                    } label: {
                        Label("Search", systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.semanticSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSemanticSearchRunning)
                    .accessibilityIdentifier(A11yID.AuraPlay.semanticSearchRun)
                }

                if !model.semanticSearchResults.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(model.semanticSearchResults) { result in
                            AuraPlaySemanticResultRow(
                                result: result,
                                open: { onOpenItem(result.id) },
                                play: { Task { await onPlayItem(result.id) } },
                                addToQueue: { Task { await onAddItemToQueue(result.id) } }
                            )
                            .accessibilityIdentifier(A11yID.AuraPlay.semanticResult(id: result.id))
                        }
                    }
                    .accessibilityIdentifier(A11yID.AuraPlay.semanticResults)
                }
            }
        }
    }

    @ViewBuilder
    private var collectionsSection: some View {
        let summaries = AuraPlayMusicCollectionSummary.summaries(from: visibleLibraryItems)
        AuraPlayLibrarySection(title: "Collections", systemImage: "square.stack.3d.up") {
            if summaries.isEmpty {
                AuraPlayEmptyLibraryCard(
                    title: "No collections yet",
                    message: "Music NFTs will appear here after the current wallet scope has playable metadata."
                )
            } else {
                ForEach(summaries.prefix(8), id: \.key) { summary in
                    Button {
                        onOpenCollection(summary.key, summary.title)
                    } label: {
                        AuraPlayCollectionRow(summary: summary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(A11yID.AuraPlay.collectionRow(id: summary.key))
                }
            }
        }
        .accessibilityIdentifier(A11yID.AuraPlay.collections)
    }

    @ViewBuilder
    private var tracksSection: some View {
        AuraPlayLibrarySection(title: "Tracks", systemImage: "music.note") {
            if visibleLibraryItems.isEmpty {
                AuraPlayEmptyLibraryCard(
                    title: libraryItems.isEmpty ? "No tracks indexed" : "No matching tracks",
                    message: libraryItems.isEmpty ? "Sync the wallet library to populate AuraPlay tracks for this chain." : "Adjust search, media type, or availability filters to show more library items."
                )
            } else {
                ForEach(visibleLibraryItems.prefix(12)) { item in
                    AuraPlayTrackRow(
                        item: item,
                        open: { onOpenItem(item.sourceNFTID) },
                        play: { Task { await onPlayItem(item.sourceNFTID) } },
                        addToQueue: { Task { await onAddItemToQueue(item.sourceNFTID) } }
                    )
                    .accessibilityIdentifier(A11yID.AuraPlay.trackRow(id: item.id))
                }
            }
        }
        .accessibilityIdentifier(A11yID.AuraPlay.tracks)
    }

    private var mediaIntegrationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AuraPlayLibrarySection(title: "Media Controls", systemImage: "slider.horizontal.3") {
                AuraPlayIntegrationStatusRow(
                    title: "Video player",
                    message: "Wallet-scoped video items open in a real AVPlayer-backed surface with PiP, route, track, chapter, speed, and resume controls when metadata provides them.",
                    systemImage: "play.rectangle",
                    status: "Backed"
                )
                AuraPlayIntegrationStatusRow(
                    title: "Offline cache",
                    message: "Audio playback exposes save, pin, unpin, and cache progress controls from the media cache manager.",
                    systemImage: "arrow.down.circle",
                    status: "Backed"
                )
            }
        }
    }

    private func infoRow(title: String, value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                infoRowTitle(title)
                    .frame(width: dynamicTypeSize.isAccessibilitySize ? 96 : 124, alignment: .leading)

                infoRowValue(value)

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 4) {
                infoRowTitle(title)
                infoRowValue(value)
            }
        }
    }

    private func infoRowTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(Color.textSecondary)
    }

    private func infoRowValue(_ value: String) -> some View {
        Text(value)
            .font(.subheadline)
            .foregroundStyle(Color.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AuraPlayLibrarySection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
                .accessibilityAddTraits(.isHeader)

            content
        }
    }
}

private struct AuraPlayEmptyLibraryCard: View {
    let title: String
    let message: String

    var body: some View {
        AuraSurfaceCard(style: .regular, cornerRadius: 20, padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }
}

private struct AuraPlayCollectionRow: View {
    let summary: AuraPlayMusicCollectionSummary

    var body: some View {
        HStack(spacing: 14) {
            AsyncImage(url: summary.artworkURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.16))
                    .overlay {
                        Image(systemName: "square.stack.3d.up")
                            .foregroundStyle(Color.textSecondary)
                            .accessibilityHidden(true)
                    }
            }
            .frame(width: 56, height: 56)
            .clipShape(.rect(cornerRadius: 12))
            .mediaAccessibility(.decorative)

            VStack(alignment: .leading, spacing: 5) {
                Text(summary.title)
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                Text(summary.subtitle ?? summary.trackCountLabel)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Label(summary.trackCountLabel, systemImage: summary.hasUnavailableTracks ? "exclamationmark.triangle" : "music.note")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .labelStyle(.titleAndIcon)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

private struct AuraPlayTrackRow: View {
    let item: MusicLibraryItem
    let open: () -> Void
    let play: () -> Void
    let addToQueue: () -> Void

    var body: some View {
        AuraSurfaceCard(style: .regular, cornerRadius: 18, padding: 12) {
            HStack(spacing: 12) {
                AsyncImage(url: item.artworkURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.16))
                        .overlay {
                            Image(systemName: "music.note")
                                .foregroundStyle(Color.textSecondary)
                                .accessibilityHidden(true)
                        }
                }
                .frame(width: 52, height: 52)
                .clipShape(.rect(cornerRadius: 10))
                .mediaAccessibility(.decorative)

                Button(action: open) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title)
                            .font(.headline)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(2)
                        Text(item.artistName ?? item.collectionName ?? item.chainTitle)
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                HStack(spacing: 4) {
                    Button(action: play) {
                        Image(systemName: "play.fill")
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(!item.isPlaybackReady)
                    .accessibilityLabel("Play \(item.title)")
                    .accessibilityHint("Starts playback for this track")

                    Button(action: addToQueue) {
                        Image(systemName: "text.badge.plus")
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(!item.isPlaybackReady)
                    .accessibilityLabel("Add \(item.title) to queue")
                    .accessibilityHint("Adds this track to the upcoming queue")
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

private struct AuraPlaySemanticResultRow: View {
    let result: AuraPlaySemanticSearchResult
    let open: () -> Void
    let play: () -> Void
    let addToQueue: () -> Void

    var body: some View {
        AuraSurfaceCard(style: .regular, cornerRadius: 18, padding: 12) {
            HStack(spacing: 12) {
                AsyncImage(url: artworkURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.16))
                        .overlay {
                            Image(systemName: "sparkles")
                                .foregroundStyle(Color.textSecondary)
                                .accessibilityHidden(true)
                        }
                }
                .frame(width: 52, height: 52)
                .clipShape(.rect(cornerRadius: 10))
                .mediaAccessibility(.decorative)

                Button(action: open) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(result.title)
                            .font(.headline)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(2)
                        Text(result.artistName ?? result.collectionName ?? "AuraPlay")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                        Text(scoreLabel)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                HStack(spacing: 4) {
                    Button(action: play) {
                        Image(systemName: "play.fill")
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(!result.isPlayable)
                    .accessibilityLabel("Play \(result.title)")
                    .accessibilityHint("Starts playback for this semantic search result")

                    Button(action: addToQueue) {
                        Image(systemName: "text.badge.plus")
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(!result.isPlayable)
                    .accessibilityLabel("Add \(result.title) to queue")
                    .accessibilityHint("Adds this semantic search result to the upcoming queue")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var artworkURL: URL? {
        result.artworkURLString.flatMap(URL.init(string:))
    }

    private var scoreLabel: String {
        "Match \(Int((result.score * 100).rounded()))%"
    }
}

private enum AuraPlayLibraryFilter: String, CaseIterable, Identifiable {
    case all
    case playable
    case audio
    case video
    case unavailable

    var id: Self { self }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .playable:
            return "Playable"
        case .audio:
            return "Audio"
        case .video:
            return "Video"
        case .unavailable:
            return "Missing"
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            return "square.grid.2x2"
        case .playable:
            return "play.circle"
        case .audio:
            return "music.note"
        case .video:
            return "play.rectangle"
        case .unavailable:
            return "exclamationmark.triangle"
        }
    }

    func includes(_ item: MusicLibraryItem) -> Bool {
        switch self {
        case .all:
            return true
        case .playable:
            return item.isPlaybackReady
        case .audio:
            return item.isAudioCapable
        case .video:
            return item.isVideoCapable
        case .unavailable:
            return !item.isPlaybackReady
        }
    }
}

private enum AuraPlayLibrarySort: String, CaseIterable, Identifiable {
    case title
    case artist
    case collection
    case availability

    var id: Self { self }

    var title: String {
        switch self {
        case .title:
            return "Title"
        case .artist:
            return "Artist"
        case .collection:
            return "Collection"
        case .availability:
            return "Availability"
        }
    }

    func sort(_ items: [MusicLibraryItem]) -> [MusicLibraryItem] {
        items.sorted { lhs, rhs in
            switch self {
            case .title:
                return compare(lhs.normalizedTitleKey, rhs.normalizedTitleKey, lhs.id, rhs.id)
            case .artist:
                return compare(lhs.normalizedArtistKey, rhs.normalizedArtistKey, lhs.normalizedTitleKey, rhs.normalizedTitleKey)
            case .collection:
                return compare(lhs.normalizedCollectionKey, rhs.normalizedCollectionKey, lhs.normalizedTitleKey, rhs.normalizedTitleKey)
            case .availability:
                return compare(lhs.availabilitySortKey, rhs.availabilitySortKey, lhs.normalizedTitleKey, rhs.normalizedTitleKey)
            }
        }
    }

    private func compare(_ lhsPrimary: String, _ rhsPrimary: String, _ lhsFallback: String, _ rhsFallback: String) -> Bool {
        if lhsPrimary == rhsPrimary {
            return lhsFallback.localizedStandardCompare(rhsFallback) == .orderedAscending
        }
        return lhsPrimary.localizedStandardCompare(rhsPrimary) == .orderedAscending
    }
}

private extension MusicLibraryItem {
    var isPlaybackReady: Bool {
        availability == .ready && playbackURLString?.isEmpty == false
    }

    var isAudioCapable: Bool {
        guard let contentType = contentType?.lowercased() else {
            return !isVideoCapable
        }
        return contentType.contains("audio") || contentType.contains("mpeg") || contentType.contains("mp3") || contentType.contains("wav")
    }

    var isVideoCapable: Bool {
        guard let contentType = contentType?.lowercased() else {
            return false
        }
        return contentType.contains("video") || contentType.contains("mp4") || contentType.contains("mpegurl") || contentType.contains("hls")
    }

    var availabilitySortKey: String {
        isPlaybackReady ? "0-ready" : "1-unavailable"
    }

    func matchesLibrarySearch(_ query: String) -> Bool {
        [title, artistName, collectionName, contentType, chainTitle]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains(query) }
    }

    var chainTitle: String {
        Chain(rawValue: networkRawValue)?.routingDisplayName ?? "Current scope"
    }
}

private struct AuraPlayIntegrationStatusRow: View {
    let title: String
    let message: String
    let systemImage: String
    let status: String

    var body: some View {
        AuraSurfaceCard(style: .regular, cornerRadius: 18, padding: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 30)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Color.textPrimary)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()

                Text(status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
            .accessibilityElement(children: .combine)
        }
    }
}
