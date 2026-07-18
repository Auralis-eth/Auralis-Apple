import Foundation

@MainActor
public struct AuraPlayDependencies {
    public let libraryRepository: any AuraPlayLibraryRepository
    public let librarySyncService: any AuraPlayLibrarySyncing
    public let nftDiscoverySyncService: any AuraPlayNFTDiscoverySyncing
    public let syncProgressProvider: any AuraPlaySyncProgressProviding
    public let semanticSearchService: any AuraPlaySemanticSearching
    public let playlistManager: any AuraPlayPlaylistManaging
    public let playbackController: any AuraPlayPlaybackControlling
    public let playbackPresenter: (any AuraPlayPlaybackPresenting)?
    public let playbackOrchestrator: (any AuraPlayPlaybackOrchestrating)?
    public let mediaQueryService: (any AuraPlayMediaItemQuerying)?
    public let queueCoordinator: any AuraPlayQueueCoordinating
    public let artworkLoader: any AuraPlayArtworkLoading
    public let logger: any AuraPlayLogging
    public let configuration: AuraPlayModuleConfiguration
    public let urlResolver: URLResolver

    public init(
        libraryRepository: any AuraPlayLibraryRepository,
        librarySyncService: any AuraPlayLibrarySyncing,
        nftDiscoverySyncService: any AuraPlayNFTDiscoverySyncing = NoOpAuraPlayNFTDiscoverySyncService(),
        syncProgressProvider: any AuraPlaySyncProgressProviding = NoOpAuraPlaySyncProgressProvider(),
        semanticSearchService: any AuraPlaySemanticSearching = NoOpAuraPlaySemanticSearchService(),
        playlistManager: any AuraPlayPlaylistManaging,
        playbackController: any AuraPlayPlaybackControlling,
        playbackPresenter: (any AuraPlayPlaybackPresenting)? = nil,
        playbackOrchestrator: (any AuraPlayPlaybackOrchestrating)? = nil,
        mediaQueryService: (any AuraPlayMediaItemQuerying)? = nil,
        queueCoordinator: any AuraPlayQueueCoordinating,
        artworkLoader: any AuraPlayArtworkLoading,
        logger: any AuraPlayLogging,
        configuration: AuraPlayModuleConfiguration,
        urlResolver: URLResolver
    ) {
        self.libraryRepository = libraryRepository
        self.librarySyncService = librarySyncService
        self.nftDiscoverySyncService = nftDiscoverySyncService
        self.syncProgressProvider = syncProgressProvider
        self.semanticSearchService = semanticSearchService
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
    }
}
