import Foundation

@MainActor
public struct AuraPlayDependencies {
    public let libraryRepository: any AuraPlayLibraryRepository
    public let librarySyncService: any AuraPlayLibrarySyncing
    public let playbackController: any AuraPlayPlaybackControlling
    public let queueCoordinator: any AuraPlayQueueCoordinating
    public let artworkLoader: any AuraPlayArtworkLoading
    public let logger: any AuraPlayLogging
    public let configuration: AuraPlayModuleConfiguration
    public let urlResolver: URLResolver

    public init(
        libraryRepository: any AuraPlayLibraryRepository,
        librarySyncService: any AuraPlayLibrarySyncing,
        playbackController: any AuraPlayPlaybackControlling,
        queueCoordinator: any AuraPlayQueueCoordinating,
        artworkLoader: any AuraPlayArtworkLoading,
        logger: any AuraPlayLogging,
        configuration: AuraPlayModuleConfiguration,
        urlResolver: URLResolver
    ) {
        self.libraryRepository = libraryRepository
        self.librarySyncService = librarySyncService
        self.playbackController = playbackController
        self.queueCoordinator = queueCoordinator
        self.artworkLoader = artworkLoader
        self.logger = logger
        self.configuration = configuration
        self.urlResolver = urlResolver
    }
}
