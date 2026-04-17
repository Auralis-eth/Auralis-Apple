import Foundation

struct ENSCacheState: Codable, Equatable, Sendable {
    var forward: [String: ENSForwardCacheEntry]
    var reverse: [String: ENSReverseCacheEntry]

    static let empty = ENSCacheState(forward: [:], reverse: [:])
}
