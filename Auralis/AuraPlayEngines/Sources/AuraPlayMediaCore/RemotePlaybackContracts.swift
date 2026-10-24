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
    func skipForward(by seconds: TimeInterval) async
    func skipBackward(by seconds: TimeInterval) async
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

/// A fully-formed now-playing state, including raw artwork bytes.
///
/// `Equatable` compares `artworkData` byte-for-byte. For frequent
/// change-detection, compare ``NowPlayingInfoSnapshot`` values instead —
/// the snapshot carries `hasArtwork` in place of the bytes.
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

/// Publishes fully-formed now-playing snapshots (`NowPlayingState`) to the system.
///
/// This is the snapshot-based contract used by engines that assemble the complete
/// now-playing state themselves, including artwork data. Engines that only have
/// raw `MediaMetadata` (with an artwork URL still to be fetched) publish through
/// ``MediaNowPlayingPublishing`` instead, delegating assembly to the adapter.
public protocol NowPlayingPublishing: Sendable {
    func update(_ state: NowPlayingState) async
    func clear() async
}

/// Streams system remote-command events (lock screen, control center, headphones)
/// to a playback engine. Shared by audio and video engines.
public protocol RemoteCommandPublishing: Sendable {
    var events: AsyncStream<RemoteCommandEvent> { get }
}

/// Publishes now-playing info from raw metadata and a playback tick.
///
/// This is the metadata-based counterpart of ``NowPlayingPublishing``: the engine
/// hands over `MediaMetadata` (artwork referenced by URL, not yet loaded) and the
/// adapter assembles and publishes the system now-playing state.
public protocol MediaNowPlayingPublishing: Sendable {
    func publish(metadata: MediaMetadata, tick: PlaybackTick, isPlaying: Bool) async
    func clear(metadataID: String) async
}
