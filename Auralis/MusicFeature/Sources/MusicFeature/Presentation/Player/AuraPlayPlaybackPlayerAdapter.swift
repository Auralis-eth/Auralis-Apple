import AuralisPrimaryModels
import Foundation
import SwiftUI

/// Typed share payload so the package never hands `[Any]` across the app
/// boundary. The app-side presenter attaches the artwork image when the URL
/// resolves from the shared cache.
public struct AuraPlayShareRequest: Equatable, Sendable {
    public let text: String
    public let url: URL?
    public let artworkURLString: String?

    public init(text: String, url: URL?, artworkURLString: String?) {
        self.text = text
        self.url = url
        self.artworkURLString = artworkURLString
    }
}

/// Presentation intents for share/explorer/copy. The live implementation is
/// app-owned (UIKit share sheet, `SFSafariViewController`, pasteboard) and is
/// injected through the SwiftUI environment; the package default is a no-op.
@MainActor
public struct AuraPlayPlayerContextActionHandler: Sendable {
    public let share: @MainActor @Sendable (AuraPlayShareRequest) async -> Void
    public let open: @MainActor @Sendable (URL) async -> Void
    public let copy: @MainActor @Sendable (String) async -> Void

    public init(
        share: @escaping @MainActor @Sendable (AuraPlayShareRequest) async -> Void,
        open: @escaping @MainActor @Sendable (URL) async -> Void,
        copy: @escaping @MainActor @Sendable (String) async -> Void
    ) {
        self.share = share
        self.open = open
        self.copy = copy
    }

    public static var noop: AuraPlayPlayerContextActionHandler {
        AuraPlayPlayerContextActionHandler(share: { _ in }, open: { _ in }, copy: { _ in })
    }
}

private struct AuraPlayContextActionsKey: EnvironmentKey {
    static let defaultValue: AuraPlayPlayerContextActionHandler? = nil
}

/// App-provided explorer URL policy (ChainRegistry-backed). The package only
/// consumes the resolved URL; it never builds explorer URLs itself.
public struct AuraPlayExplorerURLResolving: Sendable {
    public let nftURL: @Sendable (AuralisPrimaryModels.Chain, String?, String?) -> URL?

    public init(nftURL: @escaping @Sendable (AuralisPrimaryModels.Chain, String?, String?) -> URL?) {
        self.nftURL = nftURL
    }
}

private struct AuraPlayExplorerResolverKey: EnvironmentKey {
    static let defaultValue: AuraPlayExplorerURLResolving? = nil
}

public extension EnvironmentValues {
    var auraPlayContextActions: AuraPlayPlayerContextActionHandler? {
        get { self[AuraPlayContextActionsKey.self] }
        set { self[AuraPlayContextActionsKey.self] = newValue }
    }

    var auraPlayExplorerResolver: AuraPlayExplorerURLResolving? {
        get { self[AuraPlayExplorerResolverKey.self] }
        set { self[AuraPlayExplorerResolverKey.self] = newValue }
    }
}

@MainActor
public final class AuraPlayPlaybackPlayerAdapter<Presenter: AuraPlayPlaybackPresenting>: AuraPlayPlayerCommanding, @unchecked Sendable {
    private let presenter: Presenter
    private let contextActions: AuraPlayPlayerContextActionHandler

    public init(
        presenter: Presenter,
        contextActions: AuraPlayPlayerContextActionHandler = .noop
    ) {
        self.presenter = presenter
        self.contextActions = contextActions
    }

    public var presentation: AuraPlayPlayerPresentation {
        let track = presenter.auraPlayCurrentTrack
        let currentItem = (presenter as? any AuraPlayPlaybackItemPresenting)?.auraPlayCurrentItemPresentation
        let queueItems = presenter.auraPlayQueueItems()
        let modes = presenter as? any AuraPlayPlaybackModePresenting
        let video = presenter as? any AuraPlayPlayerVideoPresenting
        return AuraPlayPlayerPresentation(
            item: currentItem.map(AuraPlayPlayerItemPresentation.init(currentItem:))
                ?? track.map(AuraPlayPlayerItemPresentation.init(track:)),
            playbackState: AuraPlayPlayerPlaybackState(presenter.auraPlayPlaybackState),
            position: AuraPlayPlayerPositionPresentation(
                currentSeconds: presenter.auraPlayProgress,
                durationSeconds: track?.duration,
                isBuffering: presenter.auraPlayPlaybackState == .loading
            ),
            queue: AuraPlayPlayerQueuePresentation(
                current: track.map { AuraPlayPlayerQueueEntryPresentation(track: $0) },
                upcoming: queueItems
                    .filter { $0.role == .upcoming }
                    .map(AuraPlayPlayerQueueEntryPresentation.init(queueItem:)),
                history: queueItems
                    .filter { $0.role == .history }
                    .map(AuraPlayPlayerQueueEntryPresentation.init(queueItem:)),
                isShuffleEnabled: modes?.auraPlayShuffleEnabled ?? false,
                repeatModeTitle: modes?.auraPlayRepeatModeTitle ?? "Off"
            ),
            audioCapabilities: AuraPlayPlayerAudioCapabilities(
                tuning: presenter.auraPlayAudioTuningPresentation
            ),
            videoCapabilities: video?.auraPlayVideoCapabilities,
            failureMessage: presenter.auraPlayPlaybackAlert?.message
        )
    }

    public func togglePlayPause() async {
        switch presenter.auraPlayPlaybackState {
        case .playing:
            presenter.auraPlayPause()
        case .paused:
            try? presenter.auraPlayResume()
        default:
            try? presenter.auraPlayPlay()
        }
    }

    public func skipNext() async {
        await presenter.auraPlayNext()
    }

    public func skipPrevious() async {
        await presenter.auraPlayPrevious()
    }

    public func seek(to seconds: TimeInterval) async {
        try? presenter.auraPlaySeek(to: seconds)
    }

    public func reorderQueueEntry(id: String, toIndex: Int) async {
        presenter.auraPlayMoveQueueItem(id: id, toUpcomingIndex: toIndex)
    }

    public func removeQueueEntry(id: String) async {
        presenter.auraPlayRemoveQueueItem(id: id)
    }

    public func setShuffleEnabled(_ isEnabled: Bool) async {
        (presenter as? any AuraPlayPlaybackModePresenting)?.auraPlaySetShuffleEnabled(isEnabled)
    }

    public func cycleRepeatMode() async {
        (presenter as? any AuraPlayPlaybackModePresenting)?.auraPlayCycleRepeatMode()
    }

    public func setEQPreset(_ preset: AuraPlayEQPresetID) async {
        presenter.auraPlaySetEQPreset(preset)
    }

    public func setCustomEQBand(index: Int, gain: Float) async {
        presenter.auraPlaySetCustomEQBand(index: index, gain: gain)
    }

    public func setNormalizationEnabled(_ isEnabled: Bool) async {
        presenter.auraPlaySetNormalizationEnabled(isEnabled)
    }

    public func setCrossfadeDuration(_ duration: Double) async {
        presenter.auraPlaySetCrossfadeDuration(duration)
    }

    public func startPiP() async {
        (presenter as? any AuraPlayPlayerVideoPresenting)?.auraPlayStartPiP()
    }

    public func stopPiP() async {
        (presenter as? any AuraPlayPlayerVideoPresenting)?.auraPlayStopPiP()
    }

    public func restorePiP() async {
        (presenter as? any AuraPlayPlayerVideoPresenting)?.auraPlayRestorePiP()
    }

    public func selectSubtitle(_ title: String?) async {
        await (presenter as? any AuraPlayPlayerVideoPresenting)?.auraPlaySelectSubtitle(title)
    }

    public func setPlaybackSpeed(_ speed: Double) async {
        await (presenter as? any AuraPlayPlayerVideoPresenting)?.auraPlaySetPlaybackSpeed(speed)
    }

    public func toggleVideoGravity() async {
        await (presenter as? any AuraPlayPlayerVideoPresenting)?.auraPlayToggleVideoGravity()
    }

    public func shareCurrentItem() async {
        guard let item = currentContextItem else { return }
        await contextActions.share(
            AuraPlayShareRequest(
                text: shareText(for: item),
                url: item.shareURL ?? item.explorerURL,
                artworkURLString: item.artworkURLString
            )
        )
    }

    public func viewOnExplorer() async {
        guard let url = currentContextItem?.explorerURL else { return }
        await contextActions.open(url)
    }

    public func copyContractAddress() async {
        guard let contractAddress = currentContextItem?.contractAddress else { return }
        await contextActions.copy(contractAddress)
    }

    private var currentContextItem: AuraPlayCurrentItemPresentation? {
        (presenter as? any AuraPlayPlaybackItemPresenting)?.auraPlayCurrentItemPresentation
    }

    private func shareText(for item: AuraPlayCurrentItemPresentation) -> String {
        [item.title, item.creator, item.collection]
            .compactMap { $0?.nilIfEmpty }
            .joined(separator: " - ")
    }
}

private extension AuraPlayPlayerPlaybackState {
    init(_ state: AuraPlayPlaybackState) {
        switch state {
        case .stopped:
            self = .idle
        case .playing:
            self = .playing
        case .paused:
            self = .paused
        case .loading:
            self = .loading
        case .error:
            self = .failed
        }
    }
}

private extension AuraPlayPlayerQueueEntryPresentation {
    init(track: AuraPlayTrack) {
        self.init(
            id: track.id,
            mediaItemID: track.id,
            title: track.title?.nilIfEmpty ?? "Unknown Title",
            creator: track.artist?.nilIfEmpty,
            artworkURLString: track.imageURLString
        )
    }

    init(queueItem: AuraPlayQueuePresentationItem) {
        self.init(
            id: queueItem.id,
            mediaItemID: queueItem.id,
            title: queueItem.title,
            creator: queueItem.artist,
            artworkURLString: queueItem.imageURLString
        )
    }
}

private extension AuraPlayPlayerItemPresentation {
    init(track: AuraPlayTrack) {
        self.init(
            id: track.id,
            title: track.title?.nilIfEmpty ?? "Unknown Title",
            creator: track.artist?.nilIfEmpty,
            collection: nil,
            artworkURLString: track.imageURLString,
            mediaKind: .audio
        )
    }

    init(currentItem: AuraPlayCurrentItemPresentation) {
        self.init(
            id: currentItem.id,
            title: currentItem.title,
            creator: currentItem.creator,
            collection: currentItem.collection,
            artworkURLString: currentItem.artworkURLString,
            mediaKind: currentItem.mediaKind,
            chainDisplayName: currentItem.chainDisplayName,
            contractAddress: currentItem.contractAddress,
            tokenID: currentItem.tokenID
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
