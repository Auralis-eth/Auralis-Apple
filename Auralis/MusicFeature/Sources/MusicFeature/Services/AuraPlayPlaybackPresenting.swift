import Foundation

public struct AuraPlayRecentlyPlayedItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let artist: String?
    public let imageURLString: String?
    public let lastPlayed: Date?

    public init(
        id: String,
        title: String,
        artist: String?,
        imageURLString: String?,
        lastPlayed: Date?
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.imageURLString = imageURLString
        self.lastPlayed = lastPlayed
    }
}

@MainActor
public protocol AuraPlayPlaybackPresenting: AnyObject {
    var auraPlayCurrentTrack: AuraPlayTrack? { get }
    var auraPlayPlaybackState: AuraPlayPlaybackState { get }
    var auraPlayProgress: TimeInterval { get }
    var auraPlayNextPreviewTrack: AuraPlayTrack? { get }
    var auraPlayPreviousPreviewTrack: AuraPlayTrack? { get }

    func auraPlayPlay() throws
    func auraPlayPause()
    func auraPlayResume() throws
    func auraPlaySeek(to time: TimeInterval) throws
    func auraPlaySkipForward()
    func auraPlaySkipBackward()
    func auraPlayNext() async
    func auraPlayPrevious() async
    func auraPlayRecentlyPlayed(limit: Int) -> [AuraPlayRecentlyPlayedItem]
    func auraPlayPlayRecentlyPlayed(id: String) async throws
    func auraPlayRemoveRecentlyPlayed(id: String)
    func auraPlayClearRecentlyPlayed()
}
