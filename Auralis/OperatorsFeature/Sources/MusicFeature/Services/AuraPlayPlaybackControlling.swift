import Foundation

public enum AuraPlayPlaybackState: Equatable, Sendable, Codable {
    case stopped
    case playing
    case paused
    case loading
    case error
}

public struct AuraPlayTrack: Identifiable, Equatable, Hashable, Codable, Sendable {
    public let id: String
    public let title: String?
    public let artist: String?
    public let duration: TimeInterval
    public let imageURLString: String?

    public init(
        id: String,
        title: String?,
        artist: String?,
        duration: TimeInterval,
        imageURLString: String?
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.duration = duration
        self.imageURLString = imageURLString
    }
}

@MainActor
/// Abstracts playback controls so AuraPlay can talk to the shared engine through a testable contract.
public protocol AuraPlayPlaybackControlling {
    var playbackState: AuraPlayPlaybackState { get }
    var currentTrack: AuraPlayTrack? { get }
    var currentTrackID: String? { get }
    var currentTime: TimeInterval { get }

    func play() throws
    func pause()
    func resume() throws
    func seek(to time: TimeInterval) throws
    func playNext() async
    func playPrevious() async
}
