import ReceiptsCore
import AuralisPrimaryModels
import SwiftUI
import SwiftData

/// Root seam for the shipping AuraPlay music experience.
struct AuraPlayTabRootView: View {
    let currentAccount: EOAccount?
    let currentChain: Chain
    let nftService: NFTService
    let appModelContext: ModelContext
    let musicLibraryIndexer: any MusicLibraryIndexing
    let musicLibraryReceiptLogger: ReceiptEventLogger
    private let dependencies: AuraPlayDependencies

    init(
        audioEngine: AudioEngine,
        currentAccount: EOAccount?,
        currentChain: Chain,
        nftService: NFTService,
        appModelContext: ModelContext,
        auraPlayModelContainer: ModelContainer,
        musicLibraryIndexer: any MusicLibraryIndexing,
        musicLibraryReceiptLogger: ReceiptEventLogger
    ) {
        self.currentAccount = currentAccount
        self.currentChain = currentChain
        self.nftService = nftService
        self.appModelContext = appModelContext
        self.musicLibraryIndexer = musicLibraryIndexer
        self.musicLibraryReceiptLogger = musicLibraryReceiptLogger
        let logger = LiveAuraPlayLogger()
        self.dependencies = AuraPlayDependencies(
            libraryRepository: LiveAuraPlayLibraryRepository(
                indexer: musicLibraryIndexer,
                receiptEventLogger: musicLibraryReceiptLogger,
                auraPlayModelContainer: auraPlayModelContainer,
                accountModelContext: appModelContext
            ),
            librarySyncService: LiveAuraPlayLibrarySyncService(
                sourceModelContext: appModelContext,
                auraPlayModelContainer: auraPlayModelContainer,
                musicReceiptLogger: MusicReceiptEventLogger(
                    receiptStore: ReceiptStores.live(modelContext: appModelContext)
                ),
                logger: logger
            ),
            playbackController: AuraPlayAudioEnginePlaybackController(audioEngine: audioEngine),
            queueCoordinator: AuraPlayAudioEngineQueueCoordinator(audioEngine: audioEngine),
            artworkLoader: AuraPlayTrackArtworkLoader(),
            logger: logger,
            configuration: AuraPlayModuleConfiguration.live(
                infoDictionary: Bundle.main.infoDictionary ?? [:]
            ),
            modelContainer: auraPlayModelContainer
        )
    }

    var body: some View {
        AuraPlayCompositionRoot(
                currentAccount: currentAccount,
                currentChain: currentChain,
                dependencies: dependencies
            )
    }
}
