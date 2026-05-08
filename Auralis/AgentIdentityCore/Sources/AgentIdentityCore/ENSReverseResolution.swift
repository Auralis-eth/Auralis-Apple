import Foundation

public struct ENSReverseResolution: Codable, Equatable, Sendable {
    public let address: String
    public let ensName: String
    public let provenance: ENSResolutionProvenance
    public let fetchedAt: Date
    public let isStale: Bool
    public let isForwardVerified: Bool

    public init(
        address: String,
        ensName: String,
        provenance: ENSResolutionProvenance,
        fetchedAt: Date,
        isStale: Bool,
        isForwardVerified: Bool
    ) {
        self.address = address
        self.ensName = ensName
        self.provenance = provenance
        self.fetchedAt = fetchedAt
        self.isStale = isStale
        self.isForwardVerified = isForwardVerified
    }
}
