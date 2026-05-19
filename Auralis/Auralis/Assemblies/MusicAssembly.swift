import Foundation
import MusicFeature
import NFTKit
import ReceiptsCore
import SwiftData

struct MusicRuntime {
    let audioEngine: AudioEngine?
    let audioEngineInitializationErrorMessage: String?
    let auraPlayModelContainer: ModelContainer?
    let auraPlayInitializationErrorMessage: String?

    var unavailableMessage: String? {
        [audioEngineInitializationErrorMessage, auraPlayInitializationErrorMessage]
            .compactMap { $0 }
            .joined(separator: " ")
            .nilIfEmpty
    }
}

@MainActor
struct MusicAssembly {
    private let providerAssembly: ProviderAssembly
    private let receiptAssembly: ReceiptAssembly

    init(
        providerAssembly: ProviderAssembly,
        receiptAssembly: ReceiptAssembly
    ) {
        self.providerAssembly = providerAssembly
        self.receiptAssembly = receiptAssembly
    }

    func makeNFTService() -> NFTService {
        NFTService(
            nftFetcher: NFTFetcher(
                nftProviderFactory: { [providerAssembly] chain in
                    try providerAssembly.makeNFTInventoryProvider(for: chain)
                }
            ),
            eventRecorderFactory: { [receiptAssembly] modelContext in
                receiptAssembly.makeNFTRefreshEventRecorder(modelContext: modelContext)
            }
        )
    }

    func makeRuntime() -> MusicRuntime {
        let auraPlayResult: (ModelContainer?, String?)
        do {
            auraPlayResult = (try AuraPlayModelContainer.make(inMemory: false), nil)
        } catch {
            auraPlayResult = (nil, "AuraPlay storage could not be opened on this launch.")
        }

        let audioResult: (AudioEngine?, String?)
        do {
            audioResult = (try AudioEngine(), nil)
        } catch {
            audioResult = (nil, error.localizedDescription)
        }

        return MusicRuntime(
            audioEngine: audioResult.0,
            audioEngineInitializationErrorMessage: audioResult.1,
            auraPlayModelContainer: auraPlayResult.0,
            auraPlayInitializationErrorMessage: auraPlayResult.1
        )
    }

    func configureReceiptLogger(audioEngine: AudioEngine?, modelContext: ModelContext) {
        audioEngine?.configureMusicReceiptLogger(
            MusicReceiptEventLogger(
                receiptStore: receiptAssembly.makeReceiptStore(modelContext: modelContext)
            )
        )
    }

    func makeMusicLibraryIndexer(modelContext: ModelContext) -> any MusicLibraryIndexing {
        SwiftDataMusicLibraryIndexer(modelContext: modelContext)
    }

    func makeMusicFeatureDependencies(
        audioEngine: AudioEngine,
        auraPlayModelContainer: ModelContainer,
        accountModelContext: ModelContext,
        musicLibraryIndexer: any MusicLibraryIndexing
    ) -> AuraPlayDependencies {
        let logger = LiveAuraPlayLogger()
        return AuraPlayDependencies(
            libraryRepository: LiveAuraPlayLibraryRepository(
                indexer: musicLibraryIndexer,
                receiptEventLogger: receiptAssembly.makeReceiptEventLogger(modelContext: accountModelContext),
                auraPlayModelContainer: auraPlayModelContainer,
                accountModelContext: accountModelContext
            ),
            librarySyncService: LiveAuraPlayLibrarySyncService(
                sourceModelContext: accountModelContext,
                auraPlayModelContainer: auraPlayModelContainer,
                musicReceiptLogger: MusicReceiptEventLogger(
                    receiptStore: receiptAssembly.makeReceiptStore(modelContext: accountModelContext)
                ),
                logger: logger
            ),
            playbackController: AuraPlayAudioEnginePlaybackController(audioEngine: audioEngine),
            queueCoordinator: AuraPlayAudioEngineQueueCoordinator(audioEngine: audioEngine),
            artworkLoader: AuraPlayTrackArtworkLoader(),
            logger: logger,
            configuration: AuraPlayModuleConfiguration.live(
                infoDictionary: Bundle.main.infoDictionary ?? [:]
            )
        )
    }
}
