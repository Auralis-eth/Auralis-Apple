import Foundation

public enum RemoteCommandEvent: Equatable, Sendable {
    case play
    case pause
    case togglePlayPause
    case next
    case previous
    case skipForward(TimeInterval)
    case skipBackward(TimeInterval)
    case changePlaybackPosition(TimeInterval)
}

public extension RemoteCommandEvent {
    static func skipForward(seconds: TimeInterval) -> RemoteCommandEvent {
        .skipForward(seconds)
    }

    static func skipBackward(seconds: TimeInterval) -> RemoteCommandEvent {
        .skipBackward(seconds)
    }

    static func seek(seconds: TimeInterval) -> RemoteCommandEvent {
        .changePlaybackPosition(seconds)
    }

    @MainActor
    func dispatch(to transport: any MediaTransportControlling) async {
        await MediaRemoteCommandDispatcher(transport: transport).dispatch(self)
    }
}

@MainActor
public protocol MediaTransportControlling: Sendable {
    var isPlaying: Bool { get }
    var currentTime: TimeInterval { get }

    func play() async
    func pause() async
    func seek(to seconds: TimeInterval) async
    func next() async
    func previous() async
}

@MainActor
public extension MediaTransportControlling {
    func skipForward(by seconds: TimeInterval) async {
        await seek(to: currentTime + seconds)
    }

    func skipBackward(by seconds: TimeInterval) async {
        await seek(to: max(0, currentTime - seconds))
    }
}

@MainActor
public struct MediaRemoteCommandDispatcher {
    private let transport: any MediaTransportControlling

    public init(transport: any MediaTransportControlling) {
        self.transport = transport
    }

    public func dispatch(_ command: RemoteCommandEvent) async {
        switch command {
        case .play:
            await transport.play()
        case .pause:
            await transport.pause()
        case .togglePlayPause:
            if transport.isPlaying {
                await transport.pause()
            } else {
                await transport.play()
            }
        case .next:
            await transport.next()
        case .previous:
            await transport.previous()
        case .skipForward(let seconds):
            await transport.skipForward(by: seconds)
        case .skipBackward(let seconds):
            await transport.skipBackward(by: seconds)
        case .changePlaybackPosition(let seconds):
            await transport.seek(to: seconds)
        }
    }
}

public enum NowPlayingMediaType: String, Sendable {
    case audio
    case video
}

public struct NowPlayingState: Equatable, Sendable {
    public let title: String
    public let artist: String?
    public let artworkData: Data?
    public let duration: TimeInterval?
    public let elapsedTime: TimeInterval
    public let playbackRate: Double
    public let mediaType: NowPlayingMediaType

    public init(
        title: String,
        artist: String? = nil,
        artworkData: Data? = nil,
        duration: TimeInterval? = nil,
        elapsedTime: TimeInterval = 0,
        playbackRate: Double = 0,
        mediaType: NowPlayingMediaType = .audio
    ) {
        self.title = title
        self.artist = artist
        self.artworkData = artworkData
        self.duration = duration
        self.elapsedTime = elapsedTime
        self.playbackRate = playbackRate
        self.mediaType = mediaType
    }
}

public struct NowPlayingInfoSnapshot: Equatable, Sendable {
    public let title: String
    public let artist: String?
    public let hasArtwork: Bool
    public let duration: TimeInterval?
    public let elapsedTime: TimeInterval
    public let playbackRate: Double
    public let mediaType: NowPlayingMediaType

    public init(
        title: String,
        artist: String?,
        hasArtwork: Bool,
        duration: TimeInterval?,
        elapsedTime: TimeInterval,
        playbackRate: Double,
        mediaType: NowPlayingMediaType
    ) {
        self.title = title
        self.artist = artist
        self.hasArtwork = hasArtwork
        self.duration = duration
        self.elapsedTime = elapsedTime
        self.playbackRate = playbackRate
        self.mediaType = mediaType
    }
}

public protocol NowPlayingPublishing: Sendable {
    func update(_ state: NowPlayingState) async
    func clear() async
}

public protocol RemoteCommandPublishing: Sendable {
    var events: AsyncStream<RemoteCommandEvent> { get }
}

public protocol MediaNowPlayingPublishing: Sendable {
    func publish(metadata: MediaMetadata, tick: PlaybackTick, isPlaying: Bool) async
    func clear(metadataID: String) async
}

public protocol RemoteCommandStreaming: Sendable {
    var commands: AsyncStream<RemoteCommandEvent> { get }
}
