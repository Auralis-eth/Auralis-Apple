import Foundation

@MainActor
struct AuraPlayDependencies {
    let libraryRepository: any AuraPlayLibraryRepository
    let playbackController: any AuraPlayPlaybackControlling
    let queueCoordinator: any AuraPlayQueueCoordinating
    let artworkLoader: any AuraPlayArtworkLoading
    let logger: any AuraPlayLogging
    let configuration: AuraPlayModuleConfiguration
}
