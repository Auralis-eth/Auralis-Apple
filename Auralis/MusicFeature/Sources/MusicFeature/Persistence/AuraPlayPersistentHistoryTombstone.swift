import Foundation

public struct AuraPlayPersistentHistoryTokenIdentity: Equatable, Sendable {
    public let accountAddressRawValue: String
    public let chainRawValue: String
    public let contractAddressRawValue: String?
    public let tokenID: String

    public init(
        accountAddressRawValue: String,
        chainRawValue: String,
        contractAddressRawValue: String?,
        tokenID: String
    ) {
        self.accountAddressRawValue = accountAddressRawValue
        self.chainRawValue = chainRawValue
        self.contractAddressRawValue = contractAddressRawValue
        self.tokenID = tokenID
    }
}

public enum AuraPlayPersistentHistoryTombstonePolicy {
    public static let resumeWindow: TimeInterval = 7 * 24 * 60 * 60

    public static func recencyCutoff(before date: Date) -> Date {
        date.addingTimeInterval(-resumeWindow)
    }
}

/// AuraPlay's local Persistent History tombstone contract for recoverable playback state.
///
/// The stored implementation is `AuraPlayPlaybackPositionTombstone`; this protocol keeps
/// Phase 13's persistent-history language explicit without replacing the existing SwiftData row.
public protocol AuraPlayPersistentHistoryPlaybackTombstone: AnyObject {
    var accountAddressRawValue: String { get }
    var chainRawValue: String { get }
    var contractAddressRawValue: String? { get }
    var tokenID: String { get }
    var lastPlayedAt: Date { get }
}

public extension AuraPlayPersistentHistoryPlaybackTombstone {
    var persistentHistoryIdentity: AuraPlayPersistentHistoryTokenIdentity {
        AuraPlayPersistentHistoryTokenIdentity(
            accountAddressRawValue: accountAddressRawValue,
            chainRawValue: chainRawValue,
            contractAddressRawValue: contractAddressRawValue,
            tokenID: tokenID
        )
    }

    func isInsidePersistentHistoryResumeWindow(at date: Date) -> Bool {
        lastPlayedAt >= AuraPlayPersistentHistoryTombstonePolicy.recencyCutoff(before: date)
    }
}

extension AuraPlayPlaybackPositionTombstone: AuraPlayPersistentHistoryPlaybackTombstone {}
