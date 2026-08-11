import AuralisPrimaryPersistence
import AuraPlayMediaCore
import Foundation
import MusicFeature
import Observation

/// App-target adapter that maps the app-private Phase 8 `PlaybackOrchestrator`
/// (via `AuraPlayPlaybackRuntime`) into the public MusicFeature
/// `AuraPlayPlaybackOrchestrating` boundary. `MusicFeature` observes state and
/// issues commands through this type without seeing engine internals.
@MainActor
@Observable
final class AuraPlayOrchestratorAdapter: AuraPlayPlaybackOrchestrating {
    @ObservationIgnored private let runtime: AuraPlayPlaybackRuntime
    @ObservationIgnored private let resolveNFTs: @MainActor ([String]) -> [NFT]
    @ObservationIgnored private let openVideoPlayer: @MainActor () -> Void

    init(
        runtime: AuraPlayPlaybackRuntime,
        resolveNFTs: @escaping @MainActor ([String]) -> [NFT],
        openVideoPlayer: @escaping @MainActor () -> Void
    ) {
        self.runtime = runtime
        self.resolveNFTs = resolveNFTs
        self.openVideoPlayer = openVideoPlayer
    }

    var state: AuraPlayOrchestratorState {
        switch runtime.phase8OrchestratorState {
        case .idle:
            .idle
        case .loading(let item):
            .loading(presentation(for: item))
        case .playing(let item):
            .playing(presentation(for: item))
        case .paused(let item):
            .paused(presentation(for: item))
        case .buffering(let item):
            .buffering(presentation(for: item))
        case .failed(let item, let message):
            .failed(presentation(for: item), message: message)
        }
    }

    var currentTime: TimeInterval {
        runtime.auraPlayProgress
    }

    func togglePlayPause() async {
        switch runtime.auraPlayPlaybackState {
        case .playing:
            runtime.auraPlayPause()
        case .paused:
            try? runtime.auraPlayResume()
        default:
            try? runtime.auraPlayPlay()
        }
    }

    func pause() async {
        runtime.auraPlayPause()
    }

    func play(
        item: AuraPlayPlaybackItemPresentation,
        queue: AuraPlayQueueWindow?,
        startAt index: Int,
        origin: AuraPlayQueueOriginPresentation
    ) async {
        let presentationItems = queue?.items ?? [item]
        let mediaItems = presentationItems.compactMap { mediaItem(for: $0) }
        guard let startingItem = mediaItem(for: item), !mediaItems.isEmpty else {
            runtime.presentAuraPlayPlaybackFailure(AuraPlayError.invalidMediaURL(URL(fileURLWithPath: item.id)))
            return
        }

        if startingItem.contentKind == .video {
            openVideoPlayer()
            let didMountVideoControls = await runtime.waitForVideoRemoteControls()
            guard didMountVideoControls else {
                runtime.presentAuraPlayPlaybackFailure(AuraPlayError.engineStartFailed)
                return
            }
        }

        do {
            try await runtime.playPlaybackWindow(
                item: startingItem,
                queue: mediaItems,
                startAt: index,
                queryContext: queue?.queryContext,
                nextOffset: queue?.nextOffset,
                origin: mapOrigin(origin, fallbackMediaID: item.id)
            )
        } catch {
            runtime.presentAuraPlayPlaybackFailure(error)
        }
    }

    /// Maps the package-level queue-origin presentation onto the app-target
    /// runtime `QueueOrigin`. `.unknown` has no runtime equivalent, so it falls
    /// back to a single-item origin keyed by the starting media ID.
    private func mapOrigin(
        _ presentation: AuraPlayQueueOriginPresentation,
        fallbackMediaID: String
    ) -> QueueOrigin {
        switch presentation {
        case .playlist(let id):
            return .playlist(id: id)
        case .collection(let contractAddress):
            return .collection(contractAddress: contractAddress)
        case .creator(let id):
            return .creator(id: id)
        case .search(let query):
            return .search(query: query)
        case .moreLikeThis(let sourceID):
            return .moreLikeThis(sourceID: sourceID)
        case .single(let mediaItemID):
            return .single(mediaItemID: mediaItemID)
        case .restored:
            return .restored
        case .unknown:
            return .single(mediaItemID: fallbackMediaID)
        }
    }

    func restoreVideoPresentation() {
        runtime.auraPlayRestorePiP()
    }

    /// Resolver output is not order-guaranteed; the queue must preserve the
    /// captured window ordering exactly.
    private func orderedResolvedNFTs(for ids: [String]) -> [NFT] {
        let resolved = resolveNFTs(ids)
        let byID = Dictionary(resolved.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    private func mediaItem(for item: AuraPlayPlaybackItemPresentation) -> AuraPlayableMediaItem? {
        guard let playbackURLString = item.playbackURLString,
              let sourceURL = URL(string: playbackURLString) else {
            return nil
        }

        return AuraPlayableMediaItem(
            id: item.id,
            sourceURL: sourceURL,
            declaredFormat: item.declaredFormat ?? sourceURL.pathExtension.nilIfEmpty,
            contentKind: item.mediaKind == .video ? .video : .music,
            metadata: MediaMetadata(
                id: item.id,
                title: item.title,
                artist: item.creator,
                artworkURL: item.artworkURLString.flatMap(URL.init(string:))
            )
        )
    }

    private func presentation(for item: AuraPlayableMediaItem) -> AuraPlayPlaybackItemPresentation {
        AuraPlayPlaybackItemPresentation(
            id: item.id,
            title: item.metadata.title,
            creator: item.metadata.artist,
            artworkURLString: item.metadata.artworkURL?.absoluteString,
            playbackURLString: item.sourceURL.absoluteString,
            declaredFormat: item.declaredFormat,
            duration: nil,
            mediaKind: item.contentKind == .video ? .video : .audio,
            isPiPActive: runtime.auraPlayVideoCapabilities?.isPiPActive ?? false
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
