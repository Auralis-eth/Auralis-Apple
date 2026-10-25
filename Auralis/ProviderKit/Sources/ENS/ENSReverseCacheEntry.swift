import Foundation

public struct ENSReverseCacheEntry: Codable, Equatable, Sendable {
    public let address: String
    public let ensName: String
    public let isForwardVerified: Bool
    public let fetchedAt: Date

    public init(
        address: String,
        ensName: String,
        isForwardVerified: Bool,
        fetchedAt: Date
    ) {
        self.address = address
        self.ensName = ensName
        self.isForwardVerified = isForwardVerified
        self.fetchedAt = fetchedAt
    }
}
