import AuralisPrimaryModels
import SwiftUI

/// Composition root for the rebuilt music tab.
struct AuraPlayCompositionRoot: View {
    let currentAccount: EOAccount?
    let currentChain: Chain
    let dependencies: AuraPlayDependencies

    @State private var model: AuraPlayRootModel

    init(
        currentAccount: EOAccount?,
        currentChain: Chain,
        dependencies: AuraPlayDependencies
    ) {
        self.currentAccount = currentAccount
        self.currentChain = currentChain
        self.dependencies = dependencies
        _model = State(
            initialValue: AuraPlayRootModel(
                libraryRepository: dependencies.libraryRepository,
                librarySyncService: dependencies.librarySyncService,
                playbackController: dependencies.playbackController,
                queueCoordinator: dependencies.queueCoordinator,
                artworkLoader: dependencies.artworkLoader,
                logger: dependencies.logger,
                configuration: dependencies.configuration,
                currentAccount: currentAccount,
                currentChain: currentChain
            )
        )
    }

    var body: some View {
        AuraPlayEntryView(model: model)
            .task(id: "\(currentAccount?.address ?? "none")|\(currentChain.rawValue)") {
                model.updateContext(
                    currentAccount: currentAccount,
                    currentChain: currentChain
                )
            }
    }
}
