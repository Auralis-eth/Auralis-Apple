import Foundation

public enum AuraPlayQueueItemRole: String, Equatable, Sendable {
    case history
    case current
    case upcoming
}

public struct AuraPlayQueuePresentationItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let artist: String?
    public let imageURLString: String?
    public let role: AuraPlayQueueItemRole

    public init(
        id: String,
        title: String,
        artist: String?,
        imageURLString: String?,
        role: AuraPlayQueueItemRole
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.imageURLString = imageURLString
        self.role = role
    }
}

public struct AuraPlayCurrentItemPresentation: Equatable, Sendable {
    public let id: String
    public let title: String
    public let creator: String?
    public let collection: String?
    public let artworkURLString: String?
    public let mediaKind: AuraPlayPlayerContentKind
    public let chainDisplayName: String?
    public let contractAddress: String?
    public let tokenID: String?
    public let shareURL: URL?
    public let explorerURL: URL?

    public init(
        id: String,
        title: String,
        creator: String?,
        collection: String?,
        artworkURLString: String?,
        mediaKind: AuraPlayPlayerContentKind,
        chainDisplayName: String? = nil,
        contractAddress: String? = nil,
        tokenID: String? = nil,
        shareURL: URL? = nil,
        explorerURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.creator = creator
        self.collection = collection
        self.artworkURLString = artworkURLString
        self.mediaKind = mediaKind
        self.chainDisplayName = chainDisplayName
        self.contractAddress = contractAddress
        self.tokenID = tokenID
        self.shareURL = shareURL
        self.explorerURL = explorerURL
    }
}

public enum AuraPlayCachePresentationState: String, Equatable, Sendable {
    case unavailable
    case notCached
    case queued
    case downloading
    case partial
    case cached
    case pinned
    case error
}

public struct AuraPlayCachePresentation: Equatable, Sendable {
    public let state: AuraPlayCachePresentationState
    public let progressFraction: Double?
    public let message: String
    public let canSaveOffline: Bool
    public let canPin: Bool
    public let canUnpin: Bool

    public init(
        state: AuraPlayCachePresentationState,
        progressFraction: Double?,
        message: String,
        canSaveOffline: Bool,
        canPin: Bool,
        canUnpin: Bool
    ) {
        self.state = state
        self.progressFraction = progressFraction
        self.message = message
        self.canSaveOffline = canSaveOffline
        self.canPin = canPin
        self.canUnpin = canUnpin
    }
}

public struct AuraPlaySystemIntegrationPresentation: Equatable, Sendable {
    public let routeMode: String
    public let nowPlayingStatus: String
    public let remoteCommandStatus: String
    public let spatialAudioStatus: String

    public init(
        routeMode: String,
        nowPlayingStatus: String,
        remoteCommandStatus: String,
        spatialAudioStatus: String
    ) {
        self.routeMode = routeMode
        self.nowPlayingStatus = nowPlayingStatus
        self.remoteCommandStatus = remoteCommandStatus
        self.spatialAudioStatus = spatialAudioStatus
    }
}

public struct AuraPlayVisualizationPresentation: Equatable, Sendable {
    public let levels: [Double]
    public let isLive: Bool
    public let message: String

    public init(
        levels: [Double] = Array(repeating: 0.08, count: 18),
        isLive: Bool = false,
        message: String = "Load and play a track to see live meter activity."
    ) {
        self.levels = levels.map { min(1, max(0, $0)) }
        self.isLive = isLive
        self.message = message
    }
}

public enum AuraPlayEQPresetID: String, CaseIterable, Identifiable, Equatable, Sendable {
    case flat
    case bassBoost
    case vocalClarity
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .flat:
            "Flat"
        case .bassBoost:
            "Bass Boost"
        case .vocalClarity:
            "Vocal Clarity"
        case .custom:
            "Custom"
        }
    }
}

public struct AuraPlayAudioTuningPresentation: Equatable, Sendable {
    public let eqPreset: AuraPlayEQPresetID
    public let isNormalizationEnabled: Bool
    public let normalizationStatus: String
    public let crossfadeDuration: Double
    public let customEQGains: [Float]
    public let transitionStatus: String
    public let recoveryStatus: String
    public let contentProcessingStatus: String

    public init(
        eqPreset: AuraPlayEQPresetID = .flat,
        isNormalizationEnabled: Bool = true,
        normalizationStatus: String = "Normalization is ready.",
        crossfadeDuration: Double = 0,
        customEQGains: [Float] = AuraPlayAudioSettings.defaultCustomEQGains,
        transitionStatus: String = "Hard cut",
        recoveryStatus: String = "Ready",
        contentProcessingStatus: String = "Music dynamics preserved"
    ) {
        self.eqPreset = eqPreset
        self.isNormalizationEnabled = isNormalizationEnabled
        self.normalizationStatus = normalizationStatus
        self.crossfadeDuration = min(8, max(0, crossfadeDuration))
        self.customEQGains = AuraPlayAudioSettings.normalizedCustomEQGains(customEQGains)
        self.transitionStatus = transitionStatus
        self.recoveryStatus = recoveryStatus
        self.contentProcessingStatus = contentProcessingStatus
    }
}

public struct AuraPlayPlaybackAlertPresentation: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let message: String

    public init(id: UUID = UUID(), title: String, message: String) {
        self.id = id
        self.title = title
        self.message = message
    }
}

@MainActor
public protocol AuraPlayPlaybackPresenting: AnyObject {
    var auraPlayCurrentTrack: AuraPlayTrack? { get }
    var auraPlayPlaybackState: AuraPlayPlaybackState { get }
    var auraPlayProgress: TimeInterval { get }
    var auraPlayNextPreviewTrack: AuraPlayTrack? { get }
    var auraPlayPreviousPreviewTrack: AuraPlayTrack? { get }
    var auraPlayCachePresentation: AuraPlayCachePresentation { get }
    var auraPlaySystemIntegrationPresentation: AuraPlaySystemIntegrationPresentation { get }
    var auraPlayVisualizationPresentation: AuraPlayVisualizationPresentation { get }
    var auraPlayAudioTuningPresentation: AuraPlayAudioTuningPresentation { get }
    var auraPlayPlaybackAlert: AuraPlayPlaybackAlertPresentation? { get }

    func auraPlayPlay() throws
    func auraPlayPause()
    func auraPlayResume() throws
    func auraPlaySeek(to time: TimeInterval) throws
    func auraPlaySkipForward()
    func auraPlaySkipBackward()
    func auraPlayNext() async
    func auraPlayPrevious() async
    func auraPlayQueueItems() -> [AuraPlayQueuePresentationItem]
    func auraPlayRemoveQueueItem(id: String)
    func auraPlayMoveQueueItem(id: String, toUpcomingIndex: Int)
    func auraPlayClearUpcomingQueue()
    func auraPlaySaveOffline() async
    func auraPlayPinOffline() async
    func auraPlayUnpinOffline() async
    func auraPlaySetEQPreset(_ preset: AuraPlayEQPresetID)
    func auraPlaySetCustomEQBand(index: Int, gain: Float)
    func auraPlaySetNormalizationEnabled(_ isEnabled: Bool)
    func auraPlaySetCrossfadeDuration(_ duration: Double)
    func auraPlayDismissPlaybackAlert()
    func auraPlayStartVisualization() async
    func auraPlayStopVisualization() async
}

@MainActor
public final class AnyAuraPlayPlaybackPresenter: AuraPlayPlaybackPresenting {
    private let base: any AuraPlayPlaybackPresenting

    public init(_ base: any AuraPlayPlaybackPresenting) {
        self.base = base
    }

    public var auraPlayCurrentTrack: AuraPlayTrack? { base.auraPlayCurrentTrack }
    public var auraPlayPlaybackState: AuraPlayPlaybackState { base.auraPlayPlaybackState }
    public var auraPlayProgress: TimeInterval { base.auraPlayProgress }
    public var auraPlayNextPreviewTrack: AuraPlayTrack? { base.auraPlayNextPreviewTrack }
    public var auraPlayPreviousPreviewTrack: AuraPlayTrack? { base.auraPlayPreviousPreviewTrack }
    public var auraPlayCachePresentation: AuraPlayCachePresentation { base.auraPlayCachePresentation }
    public var auraPlaySystemIntegrationPresentation: AuraPlaySystemIntegrationPresentation { base.auraPlaySystemIntegrationPresentation }
    public var auraPlayVisualizationPresentation: AuraPlayVisualizationPresentation { base.auraPlayVisualizationPresentation }
    public var auraPlayAudioTuningPresentation: AuraPlayAudioTuningPresentation { base.auraPlayAudioTuningPresentation }
    public var auraPlayPlaybackAlert: AuraPlayPlaybackAlertPresentation? { base.auraPlayPlaybackAlert }

    public func auraPlayPlay() throws { try base.auraPlayPlay() }
    public func auraPlayPause() { base.auraPlayPause() }
    public func auraPlayResume() throws { try base.auraPlayResume() }
    public func auraPlaySeek(to time: TimeInterval) throws { try base.auraPlaySeek(to: time) }
    public func auraPlaySkipForward() { base.auraPlaySkipForward() }
    public func auraPlaySkipBackward() { base.auraPlaySkipBackward() }
    public func auraPlayNext() async { await base.auraPlayNext() }
    public func auraPlayPrevious() async { await base.auraPlayPrevious() }
    public func auraPlayQueueItems() -> [AuraPlayQueuePresentationItem] { base.auraPlayQueueItems() }
    public func auraPlayRemoveQueueItem(id: String) { base.auraPlayRemoveQueueItem(id: id) }
    public func auraPlayMoveQueueItem(id: String, toUpcomingIndex: Int) { base.auraPlayMoveQueueItem(id: id, toUpcomingIndex: toUpcomingIndex) }
    public func auraPlayClearUpcomingQueue() { base.auraPlayClearUpcomingQueue() }
    public func auraPlaySaveOffline() async { await base.auraPlaySaveOffline() }
    public func auraPlayPinOffline() async { await base.auraPlayPinOffline() }
    public func auraPlayUnpinOffline() async { await base.auraPlayUnpinOffline() }
    public func auraPlaySetEQPreset(_ preset: AuraPlayEQPresetID) { base.auraPlaySetEQPreset(preset) }
    public func auraPlaySetCustomEQBand(index: Int, gain: Float) { base.auraPlaySetCustomEQBand(index: index, gain: gain) }
    public func auraPlaySetNormalizationEnabled(_ isEnabled: Bool) { base.auraPlaySetNormalizationEnabled(isEnabled) }
    public func auraPlaySetCrossfadeDuration(_ duration: Double) { base.auraPlaySetCrossfadeDuration(duration) }
    public func auraPlayDismissPlaybackAlert() { base.auraPlayDismissPlaybackAlert() }
    public func auraPlayStartVisualization() async { await base.auraPlayStartVisualization() }
    public func auraPlayStopVisualization() async { await base.auraPlayStopVisualization() }
}

@MainActor
public protocol AuraPlayPlaybackItemPresenting: AnyObject {
    var auraPlayCurrentItemPresentation: AuraPlayCurrentItemPresentation? { get }
}

@MainActor
public protocol AuraPlayPlaybackModePresenting: AnyObject {
    var auraPlayShuffleEnabled: Bool { get }
    var auraPlayRepeatModeTitle: String { get }

    func auraPlaySetShuffleEnabled(_ isEnabled: Bool)
    func auraPlayCycleRepeatMode()
}

@MainActor
public protocol AuraPlayPlayerVideoPresenting: AnyObject {
    var auraPlayVideoCapabilities: AuraPlayPlayerVideoCapabilities? { get }

    func auraPlayStartPiP()
    func auraPlayStopPiP()
    func auraPlayRestorePiP()
    func auraPlaySelectSubtitle(_ title: String?) async
    func auraPlaySetPlaybackSpeed(_ speed: Double) async
    func auraPlayToggleVideoGravity() async
}

public extension AuraPlayPlaybackPresenting {
    func auraPlayMoveQueueItem(id: String, toUpcomingIndex: Int) {}
}
