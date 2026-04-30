import SwiftUI

/// Root swap seam that keeps the Music tab pointed at either the legacy or AuraPlay implementation.
struct AuraPlayTabRootView: View {
    let stage: AuraPlayMigrationStage
    let currentAccount: EOAccount?
    let currentChain: Chain
    let nftService: NFTService
    let refreshAction: @MainActor () async -> Void
    let onOpenNFT: (NFT) -> Void
    let onOpenCollection: (MusicCollectionSummary) -> Void
    let musicLibraryIndexer: any MusicLibraryIndexing
    let musicLibraryReceiptLogger: ReceiptEventLogger
    private let legacyAudioEngine: AudioEngine
    private let dependencies: AuraPlayDependencies

    init(
        stage: AuraPlayMigrationStage,
        audioEngine: AudioEngine,
        currentAccount: EOAccount?,
        currentChain: Chain,
        nftService: NFTService,
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
        self.refreshAction = refreshAction
        self.onOpenNFT = onOpenNFT
        self.onOpenCollection = onOpenCollection
        self.musicLibraryIndexer = musicLibraryIndexer
        self.musicLibraryReceiptLogger = musicLibraryReceiptLogger
        self.dependencies = AuraPlayDependencies(
            libraryRepository: LiveAuraPlayLibraryRepository(
                indexer: musicLibraryIndexer,
                receiptEventLogger: musicLibraryReceiptLogger
            ),
            playbackController: AuraPlayAudioEnginePlaybackController(audioEngine: audioEngine),
            queueCoordinator: AuraPlayAudioEngineQueueCoordinator(audioEngine: audioEngine),
            artworkLoader: AuraPlayTrackArtworkLoader(),
            logger: LiveAuraPlayLogger(),
            configuration: AuraPlayModuleConfiguration.live(
                infoDictionary: Bundle.main.infoDictionary ?? [:]
            )
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

        case .phase1Foundation:
            AuraPlayCompositionRoot(
                currentAccount: currentAccount,
                currentChain: currentChain,
                dependencies: dependencies
            )
        }
    }
}
