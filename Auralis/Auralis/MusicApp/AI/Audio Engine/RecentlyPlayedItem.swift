import Foundation
import SwiftData

@Model
final class RecentlyPlayedItem {
    @Attribute(.unique) var id: UUID
    var nftId: String
    var nftTitle: String
    var nftThumbnailURL: String?
    var playedAt: Date
    var playbackPosition: TimeInterval
    var duration: TimeInterval
    var playbackSource: String

    init(
        id: UUID = UUID(),
        nftId: String,
        nftTitle: String,
        nftThumbnailURL: String? = nil,
        playedAt: Date = .now,
        playbackPosition: TimeInterval = 0,
        duration: TimeInterval = 0,
        playbackSource: String
    ) {
        self.id = id
        self.nftId = nftId
        self.nftTitle = nftTitle
        self.nftThumbnailURL = nftThumbnailURL
        self.playedAt = playedAt
        self.playbackPosition = playbackPosition
        self.duration = duration
        self.playbackSource = playbackSource
    }
}
