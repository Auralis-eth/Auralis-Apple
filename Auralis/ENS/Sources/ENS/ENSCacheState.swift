import Foundation

public struct ENSCacheState: Codable, Equatable, Sendable {
    public var forward: [String: ENSForwardCacheEntry]
    public var reverse: [String: ENSReverseCacheEntry]

    public static let empty = ENSCacheState(forward: [:], reverse: [:])

    public init(
        forward: [String: ENSForwardCacheEntry],
        reverse: [String: ENSReverseCacheEntry]
    ) {
        self.forward = forward
        self.reverse = reverse
    }
}
