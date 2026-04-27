import Foundation

struct ENSReverseCacheEntry: Codable, Equatable, Sendable {
    let address: String
    let ensName: String
    let isForwardVerified: Bool
    let fetchedAt: Date
}
