import Foundation

public enum TokenHoldingsMetadataFreshnessPolicy {
    public static let ttl: TimeInterval = 60 * 60 * 12

    public static func isStale(updatedAt: Date, now: Date = .now) -> Bool {
        max(0, now.timeIntervalSince(updatedAt)) >= ttl
    }
}
