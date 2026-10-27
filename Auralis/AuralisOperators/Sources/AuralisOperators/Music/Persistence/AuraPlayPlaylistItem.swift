import Foundation
import SwiftData

@Model
public final class AuraPlayPlaylistItem {
    #Index<AuraPlayPlaylistItem>(
        [\.playlistID, \.position],
        [\.playlistID, \.mediaItemID]
    )

    @Attribute(.unique) public var id: String
    public var playlistID: String
    public var mediaItemID: String
    public var position: Int
    public var addedAt: Date

    public var playlist: AuraPlayPlaylist?

    public init(
        id: String = UUID().uuidString,
        playlistID: String,
        mediaItemID: String,
        position: Int,
        addedAt: Date = .now,
        playlist: AuraPlayPlaylist? = nil
    ) {
        self.id = id
        self.playlistID = playlistID
        self.mediaItemID = mediaItemID
        self.position = max(0, position)
        self.addedAt = addedAt
        self.playlist = playlist
    }
}
