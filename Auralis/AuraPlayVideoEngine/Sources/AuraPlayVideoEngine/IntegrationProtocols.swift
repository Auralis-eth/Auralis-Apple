import Foundation

public protocol VideoGatewayResolving: Sendable {
    func nextResolvedURL(after failedURL: URL) async throws -> URL?
}

public protocol VideoPlaybackStateStoring: Sendable {
    func storedPosition(for mediaID: String) async throws -> StoredVideoPlaybackPosition?
    func writePosition(_ position: StoredVideoPlaybackPosition) async throws
    func markCompleted(mediaID: String) async throws
}

public protocol VideoNowPlayingPublishing: Sendable {
    func publishVideo(metadata: VideoMediaMetadata, tick: PlaybackTick, isPlaying: Bool) async
    func clearVideo(metadataID: String) async
}

public enum VideoRemoteCommand: Equatable, Sendable {
    case play
    case pause
    case skipForward(seconds: Double)
    case skipBackward(seconds: Double)
    case seek(seconds: Double)
}

public protocol VideoRemoteCommandStreaming: Sendable {
    var commands: AsyncStream<VideoRemoteCommand> { get }
}

public enum VideoMediaSessionEvent: Equatable, Sendable {
    case shouldPause
    case interruptionEndedShouldResume
    case enteredBackground
    case willStop
}

public protocol VideoMediaSessionManaging: Sendable {
    var events: AsyncStream<VideoMediaSessionEvent> { get }
    func configureForVideoPlayback() async throws
}

public protocol VideoArtworkCaching: Sendable {
    func cachedPoster(for mediaID: String) async -> PlatformImage?
    func storePoster(_ image: PlatformImage, for mediaID: String) async
}

public protocol VideoEngineLogging: Sendable {
    func info(_ message: String)
    func error(_ message: String)
}

public struct NoOpVideoEngineLogger: VideoEngineLogging {
    public init() {}

    public func info(_ message: String) {}
    public func error(_ message: String) {}
}
