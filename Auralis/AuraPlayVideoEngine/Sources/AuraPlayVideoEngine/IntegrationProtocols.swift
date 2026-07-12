import AuraPlayMediaCore
import Foundation

public typealias VideoGatewayResolving = MediaGatewayFallbackResolving

public protocol VideoPlaybackStateStoring: Sendable {
    func storedPosition(for mediaID: String) async throws -> StoredVideoPlaybackPosition?
    func writePosition(_ position: StoredVideoPlaybackPosition) async throws
    func markCompleted(mediaID: String) async throws
}

public typealias VideoNowPlayingPublishing = MediaNowPlayingPublishing

public typealias VideoRemoteCommand = RemoteCommandEvent

public typealias VideoRemoteCommandStreaming = RemoteCommandStreaming

public typealias VideoMediaTransportControlling = MediaTransportControlling

public typealias VideoRemoteCommandDispatcher = MediaRemoteCommandDispatcher

public typealias VideoMediaSessionEvent = MediaSessionEvent

public typealias VideoMediaSessionManaging = MediaSessionManaging

@MainActor
public protocol VideoPictureInPictureControlling: AnyObject {
    var state: PiPState { get }

    func start()
    func stop()
}

public struct VideoCoordinatedPlaybackConfiguration: Equatable, Sendable {
    public let sessionIdentity: SharedMediaSessionIdentity

    /// Indicates that coordinated playback should be eligible for AVKit's automatic inline PiP transition.
    /// The coordinator does not manually start PiP after the app has entered the background.
    public let startsPictureInPictureWhenEnteringBackground: Bool

    public init(
        sessionIdentity: SharedMediaSessionIdentity,
        startsPictureInPictureWhenEnteringBackground: Bool = true
    ) {
        self.sessionIdentity = sessionIdentity
        self.startsPictureInPictureWhenEnteringBackground = startsPictureInPictureWhenEnteringBackground
    }
}

public enum VideoAVKitImmersiveExperience: Equatable, Sendable {
    case expanded(disableAutomaticImmersiveTransition: Bool)
    case immersive
}

public struct VideoAVKitImmersiveHandoffRequest: Equatable, Sendable {
    public let playbackURL: URL
    public let metadata: VideoMediaMetadata?
    public let capabilities: VideoPlaybackCapabilities
    public let requestedExperience: VideoAVKitImmersiveExperience

    public init(
        playbackURL: URL,
        metadata: VideoMediaMetadata? = nil,
        capabilities: VideoPlaybackCapabilities,
        requestedExperience: VideoAVKitImmersiveExperience
    ) {
        self.playbackURL = playbackURL
        self.metadata = metadata
        self.capabilities = capabilities
        self.requestedExperience = requestedExperience
    }
}

public protocol VideoAVKitImmersiveHandoffPresenting: Sendable {
    func presentAVKitImmersivePlayback(_ request: VideoAVKitImmersiveHandoffRequest) async throws
}

public protocol VideoArtworkCaching: Sendable {
    func cachedPoster(for mediaID: String) async -> PlatformImage?
    func storePoster(_ image: PlatformImage, for mediaID: String) async
}

public typealias VideoEngineLogging = MediaEngineLogging

public typealias NoOpVideoEngineLogger = NoOpMediaEngineLogger
