import Foundation

public enum AuraPlayPlayerPlaybackState: String, Codable, Equatable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case buffering
    case failed
}

public enum AuraPlayPlayerContentKind: String, Codable, Equatable, Sendable {
    case audio
    case video
}

public struct AuraPlayPlayerItemPresentation: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let creator: String?
    public let collection: String?
    public let artworkURLString: String?
    public let mediaKind: AuraPlayPlayerContentKind
    public let chainDisplayName: String?
    public let contractAddress: String?
    public let tokenID: String?

    public init(
        id: String,
        title: String,
        creator: String?,
        collection: String?,
        artworkURLString: String?,
        mediaKind: AuraPlayPlayerContentKind,
        chainDisplayName: String? = nil,
        contractAddress: String? = nil,
        tokenID: String? = nil
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
    }
}

public struct AuraPlayPlayerPositionPresentation: Codable, Equatable, Sendable {
    public let currentSeconds: TimeInterval
    public let durationSeconds: TimeInterval?
    public let isBuffering: Bool

    public init(currentSeconds: TimeInterval, durationSeconds: TimeInterval?, isBuffering: Bool = false) {
        self.currentSeconds = max(0, currentSeconds)
        self.durationSeconds = durationSeconds.map { max(0, $0) }
        self.isBuffering = isBuffering
    }
}

public struct AuraPlayPlayerQueueEntryPresentation: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let mediaItemID: String
    public let title: String
    public let creator: String?
    public let artworkURLString: String?

    public init(
        id: String,
        mediaItemID: String,
        title: String,
        creator: String?,
        artworkURLString: String?
    ) {
        self.id = id
        self.mediaItemID = mediaItemID
        self.title = title
        self.creator = creator
        self.artworkURLString = artworkURLString
    }
}

public struct AuraPlayPlayerQueuePresentation: Codable, Equatable, Sendable {
    public let current: AuraPlayPlayerQueueEntryPresentation?
    public let upcoming: [AuraPlayPlayerQueueEntryPresentation]
    public let history: [AuraPlayPlayerQueueEntryPresentation]
    public let isShuffleEnabled: Bool
    public let repeatModeTitle: String

    public init(
        current: AuraPlayPlayerQueueEntryPresentation?,
        upcoming: [AuraPlayPlayerQueueEntryPresentation],
        history: [AuraPlayPlayerQueueEntryPresentation],
        isShuffleEnabled: Bool = false,
        repeatModeTitle: String = "Off"
    ) {
        self.current = current
        self.upcoming = upcoming
        self.history = history
        self.isShuffleEnabled = isShuffleEnabled
        self.repeatModeTitle = repeatModeTitle
    }
}

public struct AuraPlayPlayerAudioCapabilities: Equatable, Sendable {
    public let tuning: AuraPlayAudioTuningPresentation

    public init(tuning: AuraPlayAudioTuningPresentation = AuraPlayAudioTuningPresentation()) {
        self.tuning = tuning
    }
}

public struct AuraPlayPlayerVideoCapabilities: Codable, Equatable, Sendable {
    public let isPiPAvailable: Bool
    public let isPiPActive: Bool
    public let hasRoutePicker: Bool
    public let subtitleOptions: [String]
    public let audioDescriptionOptions: [String]
    public let speedOptions: [Double]
    public let selectedSpeed: Double
    public let canChangeAspect: Bool

    public init(
        isPiPAvailable: Bool = false,
        isPiPActive: Bool = false,
        hasRoutePicker: Bool = false,
        subtitleOptions: [String] = [],
        audioDescriptionOptions: [String] = [],
        speedOptions: [Double] = [0.75, 1, 1.25, 1.5, 2],
        selectedSpeed: Double = 1,
        canChangeAspect: Bool = false
    ) {
        self.isPiPAvailable = isPiPAvailable
        self.isPiPActive = isPiPActive
        self.hasRoutePicker = hasRoutePicker
        self.subtitleOptions = subtitleOptions
        self.audioDescriptionOptions = audioDescriptionOptions
        self.speedOptions = speedOptions
        self.selectedSpeed = selectedSpeed
        self.canChangeAspect = canChangeAspect
    }
}

public struct AuraPlayPlayerPresentation: Equatable, Sendable {
    public let item: AuraPlayPlayerItemPresentation?
    public let playbackState: AuraPlayPlayerPlaybackState
    public let position: AuraPlayPlayerPositionPresentation
    public let queue: AuraPlayPlayerQueuePresentation
    public let audioCapabilities: AuraPlayPlayerAudioCapabilities?
    public let videoCapabilities: AuraPlayPlayerVideoCapabilities?
    public let failureMessage: String?

    public init(
        item: AuraPlayPlayerItemPresentation?,
        playbackState: AuraPlayPlayerPlaybackState,
        position: AuraPlayPlayerPositionPresentation,
        queue: AuraPlayPlayerQueuePresentation,
        audioCapabilities: AuraPlayPlayerAudioCapabilities? = nil,
        videoCapabilities: AuraPlayPlayerVideoCapabilities? = nil,
        failureMessage: String? = nil
    ) {
        self.item = item
        self.playbackState = playbackState
        self.position = position
        self.queue = queue
        self.audioCapabilities = audioCapabilities
        self.videoCapabilities = videoCapabilities
        self.failureMessage = failureMessage
    }
}
