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

    init(
        runtime: AuraPlayPlaybackRuntime,
        resolveNFTs: @escaping @MainActor ([String]) -> [NFT]
    ) {
        self.runtime = runtime
        self.resolveNFTs = resolveNFTs
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
        let windowIDs = queue?.items.map(\.id) ?? [item.id]
        let orderedNFTs = orderedResolvedNFTs(for: windowIDs)
        guard !orderedNFTs.isEmpty else { return }
        try? await runtime.playLibraryWindow(
            id: item.id,
            in: orderedNFTs,
            queryContext: queue?.queryContext,
            nextOffset: queue?.nextOffset,
            origin: mapOrigin(origin, fallbackMediaID: item.id)
        )
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

    private func presentation(for item: AuraPlayableMediaItem) -> AuraPlayPlaybackItemPresentation {
        AuraPlayPlaybackItemPresentation(
            id: item.id,
            title: item.metadata.title,
            creator: item.metadata.artist,
            artworkURLString: item.metadata.artworkURL?.absoluteString,
            duration: nil,
            mediaKind: item.contentKind == .video ? .video : .audio,
            isPiPActive: runtime.auraPlayVideoCapabilities?.isPiPActive ?? false
        )
    }
}
