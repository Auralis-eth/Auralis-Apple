import SwiftUI
import SwiftData

/// Root swap seam that keeps the Music tab pointed at either the legacy or AuraPlay implementation.
struct AuraPlayTabRootView: View {
    let stage: AuraPlayMigrationStage
    let currentAccount: EOAccount?
    let currentChain: Chain
    let nftService: NFTService
    let appModelContext: ModelContext
    let refreshAction: @MainActor () async -> Void
    let onOpenNFT: (NFT) -> Void
    let onOpenCollection: (MusicCollectionSummary) -> Void
    let musicLibraryIndexer: any MusicLibraryIndexing
    let musicLibraryReceiptLogger: ReceiptEventLogger
    private let legacyAudioEngine: AudioEngine
    private let dependencies: AuraPlayDependencies
    private let modelContainer: ModelContainer

    private static func makeModelContainer() -> ModelContainer {
        do {
            return try AppModelContainer.make(inMemory: false)
        } catch {
            fatalError("Failed to create AuraPlay model container: \(error.localizedDescription)")
        }
    }

    init(
        stage: AuraPlayMigrationStage,
        audioEngine: AudioEngine,
        currentAccount: EOAccount?,
        currentChain: Chain,
        nftService: NFTService,
        appModelContext: ModelContext,
        refreshAction: @escaping @MainActor () async -> Void,
        onOpenNFT: @escaping (NFT) -> Void,
        onOpenCollection: @escaping (MusicCollectionSummary) -> Void,
        musicLibraryIndexer: any MusicLibraryIndexing,
        musicLibraryReceiptLogger: ReceiptEventLogger
    ) {
        self.stage = stage
        self.legacyAudioEngine = audioEngine
        self.currentAccount = currentAccount
        self.currentChain = currentChain
        self.nftService = nftService
        self.appModelContext = appModelContext
        self.refreshAction = refreshAction
        self.onOpenNFT = onOpenNFT
        self.onOpenCollection = onOpenCollection
        self.musicLibraryIndexer = musicLibraryIndexer
        self.musicLibraryReceiptLogger = musicLibraryReceiptLogger
        self.modelContainer = Self.makeModelContainer()
        let logger = LiveAuraPlayLogger()
        self.dependencies = AuraPlayDependencies(
            libraryRepository: LiveAuraPlayLibraryRepository(
                indexer: musicLibraryIndexer,
                receiptEventLogger: musicLibraryReceiptLogger,
                modelContainer: modelContainer
            ),
            librarySyncService: LiveAuraPlayLibrarySyncService(
                sourceModelContext: appModelContext,
                modelContainer: modelContainer,
                logger: logger
            ),
            playbackController: AuraPlayAudioEnginePlaybackController(audioEngine: audioEngine),
            queueCoordinator: AuraPlayAudioEngineQueueCoordinator(audioEngine: audioEngine),
            artworkLoader: AuraPlayTrackArtworkLoader(),
            logger: logger,
            configuration: AuraPlayModuleConfiguration.live(
                infoDictionary: Bundle.main.infoDictionary ?? [:]
            ),
            modelContainer: modelContainer
        )
    }

    var body: some View {
        switch stage {
        case .legacy:
            NFTMusicPlayerApp(
                audioEngine: legacyAudioEngine,
                currentAccount: currentAccount,
                currentChain: currentChain,
                nftService: nftService,
                refreshAction: refreshAction,
                onOpenNFT: onOpenNFT,
                onOpenCollection: onOpenCollection,
                musicLibraryIndexer: musicLibraryIndexer,
                musicLibraryReceiptLogger: musicLibraryReceiptLogger
            )

        case .phase2Persistence:
            AuraPlayCompositionRoot(
                currentAccount: currentAccount,
                currentChain: currentChain,
                dependencies: dependencies
            )
        }
    }
}
