import AuralisPrimaryModels
import AuralisPrimaryPersistence
import SwiftUI

/// Composition root for the rebuilt music tab.
public struct MusicFeatureRootView: View {
    public let currentAccount: EOAccount?
    public let currentChain: Chain
    public let dependencies: AuraPlayDependencies
    public let onOpenItem: (String) -> Void
    public let onOpenCollection: (String, String) -> Void
    public let onPlayItem: (String) async -> Void
    public let onAddItemToQueue: (String) async -> Void
    public let openWalletPicker: () -> Void

    @State private var model: AuraPlayRootModel

    public init(
        currentAccount: EOAccount?,
        currentChain: Chain,
        dependencies: AuraPlayDependencies,
        onOpenItem: @escaping (String) -> Void = { _ in },
        onOpenCollection: @escaping (String, String) -> Void = { _, _ in },
        onPlayItem: @escaping (String) async -> Void = { _ in },
        onAddItemToQueue: @escaping (String) async -> Void = { _ in },
        openWalletPicker: @escaping () -> Void = {}
    ) {
        self.currentAccount = currentAccount
        self.currentChain = currentChain
        self.dependencies = dependencies
        self.onOpenItem = onOpenItem
        self.onOpenCollection = onOpenCollection
        self.onPlayItem = onPlayItem
        self.onAddItemToQueue = onAddItemToQueue
        self.openWalletPicker = openWalletPicker
        _model = State(
            initialValue: AuraPlayRootModel(
                libraryRepository: dependencies.libraryRepository,
                librarySyncService: dependencies.librarySyncService,
                nftDiscoverySyncService: dependencies.nftDiscoverySyncService,
                syncProgressProvider: dependencies.syncProgressProvider,
                semanticSearchService: dependencies.semanticSearchService,
                embeddingAvailabilityProvider: dependencies.embeddingAvailabilityProvider,
                playlistGenerator: dependencies.playlistGenerator,
                recommendationProvider: dependencies.recommendationProvider,
                playlistManager: dependencies.playlistManager,
                playbackController: dependencies.playbackController,
                playbackPresenter: dependencies.playbackPresenter,
                playbackOrchestrator: dependencies.playbackOrchestrator,
                mediaQueryService: dependencies.mediaQueryService,
                queueCoordinator: dependencies.queueCoordinator,
                artworkLoader: dependencies.artworkLoader,
                logger: dependencies.logger,
                configuration: dependencies.configuration,
                urlResolver: dependencies.urlResolver,
                currentAccount: currentAccount,
                currentChain: currentChain
            )
        )
    }

    public var body: some View {
        LibraryRootView(
            model: model,
            currentAccount: currentAccount,
            currentChain: currentChain,
            onOpenItem: onOpenItem,
            onOpenCollection: onOpenCollection,
            onPlayItem: onPlayItem,
            onAddItemToQueue: onAddItemToQueue,
            openWalletPicker: openWalletPicker
        )
            .task(id: "\(currentAccount?.address ?? "none")|\(currentChain.rawValue)") {
                model.updateContext(
                    currentAccount: currentAccount,
                    currentChain: currentChain
                )
            }
    }
}
