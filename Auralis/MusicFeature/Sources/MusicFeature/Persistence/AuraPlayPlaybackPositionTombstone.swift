import Foundation
import SwiftData

@Model
public final class AuraPlayPlaybackPositionTombstone {
    #Index<AuraPlayPlaybackPositionTombstone>(
        [\.accountAddressRawValue, \.chainRawValue, \.contractAddressRawValue, \.tokenID],
        [\.lastPlayedAt],
        [\.capturedAt]
    )

    @Attribute(.unique) public var id: String
    public var originalMediaID: String
    public var accountAddressRawValue: String
    public var chainRawValue: String
    public var contractAddressRawValue: String?
    public var tokenID: String
    public var positionMilliseconds: Int
    public var durationMilliseconds: Int?
    public var lastPlayedAt: Date
    public var completedAt: Date?
    public var playCount: Int
    public var capturedAt: Date
    public var consumedAt: Date?

    public init(
        id: String = UUID().uuidString,
        originalMediaID: String,
        accountAddressRawValue: String,
        chainRawValue: String,
        contractAddressRawValue: String?,
        tokenID: String,
        positionMilliseconds: Int,
        durationMilliseconds: Int?,
        lastPlayedAt: Date,
        completedAt: Date?,
        playCount: Int = 0,
        capturedAt: Date = .now,
        consumedAt: Date? = nil
    ) {
        self.id = id
        self.originalMediaID = originalMediaID
        self.accountAddressRawValue = accountAddressRawValue
        self.chainRawValue = chainRawValue
        self.contractAddressRawValue = contractAddressRawValue
        self.tokenID = tokenID
        self.positionMilliseconds = max(0, positionMilliseconds)
        self.durationMilliseconds = durationMilliseconds.map { max(0, $0) }
        self.lastPlayedAt = lastPlayedAt
        self.completedAt = completedAt
        self.playCount = max(0, playCount)
        self.capturedAt = capturedAt
        self.consumedAt = consumedAt
    }
}
