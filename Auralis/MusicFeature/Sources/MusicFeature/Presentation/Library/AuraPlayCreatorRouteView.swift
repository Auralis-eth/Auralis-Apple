import AuraUI
import SwiftUI

public struct AuraPlayCollectionRouteView: View {
    public let collectionIdentifier: String
    public let fallbackTitle: String
    public let model: AuraPlayRootModel
    public let sort: MediaItemSort
    public let onOpenItem: (String) -> Void
    public let onPlayItem: (String, [MediaItemQueryItem], AuraPlayQueueOriginPresentation) async -> Void
    public let onAddToPlaylist: (String) -> Void

    public init(
        collectionIdentifier: String,
        fallbackTitle: String,
        model: AuraPlayRootModel,
        sort: MediaItemSort = .titleAZ,
        onOpenItem: @escaping (String) -> Void,
        onPlayItem: @escaping (String, [MediaItemQueryItem], AuraPlayQueueOriginPresentation) async -> Void,
        onAddToPlaylist: @escaping (String) -> Void = { _ in }
    ) {
        self.collectionIdentifier = collectionIdentifier
        self.fallbackTitle = fallbackTitle
        self.model = model
        self.sort = sort
        self.onOpenItem = onOpenItem
        self.onPlayItem = onPlayItem
        self.onAddToPlaylist = onAddToPlaylist
    }

    public var body: some View {
        LibraryGroupDetailLoaderView(
            model: model,
            group: .collection(id: collectionIdentifier),
            title: model.groupedIndex?.collections.first(where: { $0.id == collectionIdentifier })?.collectionName ?? fallbackTitle,
            systemImage: "rectangle.stack",
            sort: sort,
            currentTrackID: model.playbackController.currentTrackID,
            origin: .collection(contractAddress: collectionIdentifier),
            onOpenItem: onOpenItem,
            onPlayItem: onPlayItem,
            onAddToPlaylist: onAddToPlaylist
        )
        .accessibilityIdentifier(A11yID.AuraPlay.collectionDetail)
        .task {
            // A deep-linked route builds a fresh model whose grouped index is empty,
            // so the header falls back to the generic title. Populating it resolves
            // the real collection name when the collection is in the active scope.
            await model.reloadGroupedIndexIfNeeded()
        }
    }
}

public struct AuraPlayCreatorRouteView: View {
    public let creatorIdentifier: String
    public let fallbackTitle: String
    public let accountAddresses: [String]
    public let model: AuraPlayRootModel
    public let sort: MediaItemSort
    public let onOpenItem: (String) -> Void
    public let onPlayItem: (String, [MediaItemQueryItem], AuraPlayQueueOriginPresentation) async -> Void
    public let onAddToPlaylist: (String) -> Void

    public init(
        creatorIdentifier: String,
        fallbackTitle: String,
        accountAddresses: [String],
        model: AuraPlayRootModel,
        sort: MediaItemSort = .titleAZ,
        onOpenItem: @escaping (String) -> Void,
        onPlayItem: @escaping (String, [MediaItemQueryItem], AuraPlayQueueOriginPresentation) async -> Void,
        onAddToPlaylist: @escaping (String) -> Void = { _ in }
    ) {
        self.creatorIdentifier = creatorIdentifier
        self.fallbackTitle = fallbackTitle
        self.accountAddresses = accountAddresses
        self.model = model
        self.sort = sort
        self.onOpenItem = onOpenItem
        self.onPlayItem = onPlayItem
        self.onAddToPlaylist = onAddToPlaylist
    }

    public var body: some View {
        CreatorProfileLoaderView(
            model: model,
            creatorIdentifier: creatorIdentifier,
            fallbackTitle: fallbackTitle,
            accountAddresses: accountAddresses,
            sort: sort,
            currentTrackID: model.playbackController.currentTrackID,
            onOpenItem: onOpenItem,
            onPlayItem: onPlayItem,
            onAddToPlaylist: onAddToPlaylist
        )
    }
}
