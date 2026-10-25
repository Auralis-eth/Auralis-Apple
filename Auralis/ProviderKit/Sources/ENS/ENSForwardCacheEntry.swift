import Foundation

public struct ENSForwardCacheEntry: Codable, Equatable, Sendable {
    public let ensName: String
    public let address: String
    public let fetchedAt: Date

    public init(ensName: String, address: String, fetchedAt: Date) {
        self.ensName = ensName
        self.address = address
        self.fetchedAt = fetchedAt
    }
}
