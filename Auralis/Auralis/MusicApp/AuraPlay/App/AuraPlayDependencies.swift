import Foundation
import SwiftData

@MainActor
struct AuraPlayDependencies {
    let libraryRepository: any AuraPlayLibraryRepository
    let librarySyncService: any AuraPlayLibrarySyncing
    let playbackController: any AuraPlayPlaybackControlling
    let queueCoordinator: any AuraPlayQueueCoordinating
    let artworkLoader: any AuraPlayArtworkLoading
    let logger: any AuraPlayLogging
    let configuration: AuraPlayModuleConfiguration
    let modelContainer: ModelContainer
}
