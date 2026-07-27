import Foundation
import SwiftData

@Model
public final class AuraPlayPlaybackPositionState {
    #Index<AuraPlayPlaybackPositionState>(
        [\.mediaID],
        [\.lastPlayedAt]
    )

    @Attribute(.unique) public var mediaID: String
    public var positionMilliseconds: Int
    public var durationMilliseconds: Int?
    public var lastPlayedAt: Date
    public var completedAt: Date?
    /// Number of completed plays; drives Smart Shuffle's play-count downweight.
    /// The declaration-site default lets SwiftData lightweight-migrate existing
    /// stores that predate this attribute instead of failing to open.
    public var playCount: Int = 0
    public var updatedAt: Date

    public init(
        mediaID: String,
        positionMilliseconds: Int,
        durationMilliseconds: Int?,
        lastPlayedAt: Date = .now,
        completedAt: Date? = nil,
        playCount: Int = 0,
        updatedAt: Date = .now
    ) {
        self.mediaID = mediaID
        self.positionMilliseconds = max(0, positionMilliseconds)
        self.durationMilliseconds = durationMilliseconds.map { max(0, $0) }
        self.lastPlayedAt = lastPlayedAt
        self.completedAt = completedAt
        self.playCount = max(0, playCount)
        self.updatedAt = updatedAt
    }
}

public struct AuraPlayPlaybackPositionStateSnapshot: Equatable, Sendable {
    public let mediaID: String
    public let positionMilliseconds: Int
    public let durationMilliseconds: Int?
    public let lastPlayedAt: Date
    public let completedAt: Date?

    public init(
        mediaID: String,
        positionMilliseconds: Int,
        durationMilliseconds: Int?,
        lastPlayedAt: Date,
        completedAt: Date?
    ) {
        self.mediaID = mediaID
        self.positionMilliseconds = max(0, positionMilliseconds)
        self.durationMilliseconds = durationMilliseconds.map { max(0, $0) }
        self.lastPlayedAt = lastPlayedAt
        self.completedAt = completedAt
    }

    public var isResumable: Bool {
        guard positionMilliseconds > 5_000 else { return false }
        if let durationMilliseconds,
           durationMilliseconds - positionMilliseconds <= 5_000 {
            return false
        }
        return true
    }
}
