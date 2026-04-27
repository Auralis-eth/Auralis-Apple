import Foundation

struct ENSForwardCacheEntry: Codable, Equatable, Sendable {
    let ensName: String
    let address: String
    let fetchedAt: Date
}
