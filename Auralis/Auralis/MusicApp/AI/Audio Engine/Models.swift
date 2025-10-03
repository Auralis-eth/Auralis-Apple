import Foundation
import AVFoundation
import MediaPlayer

public enum PlaybackState: Equatable, Sendable, Codable {
    case stopped
    case playing
    case paused
    case loading
    case error
}

public struct Track: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var title: String?
    public var artist: String?
    public var duration: TimeInterval
    public var imageUrl: String?

    public init(id: UUID = UUID(), title: String?, artist: String?, duration: TimeInterval, imageUrl: String?) {
        self.id = id
        self.title = title
        self.artist = artist
        self.duration = duration
        self.imageUrl = imageUrl
    }
}

public struct PlaybackSnapshot: Equatable, Hashable, Codable, Sendable {
    public var state: PlaybackState
    public var track: Track?
    public var elapsed: TimeInterval
    public var duration: TimeInterval
    public var canSkipNext: Bool
    public var canSkipPrevious: Bool

    public init(state: PlaybackState, track: Track?, elapsed: TimeInterval, duration: TimeInterval, canSkipNext: Bool, canSkipPrevious: Bool) {
        self.state = state
        self.track = track
        self.elapsed = elapsed
        self.duration = duration
        self.canSkipNext = canSkipNext
        self.canSkipPrevious = canSkipPrevious
    }
}
