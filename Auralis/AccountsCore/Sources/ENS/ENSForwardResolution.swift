import Foundation

public struct ENSForwardResolution: Codable, Equatable, Sendable {
    public let ensName: String
    public let address: String
    public let provenance: ENSResolutionProvenance
    public let fetchedAt: Date
    public let isStale: Bool

    public init(
        ensName: String,
        address: String,
        provenance: ENSResolutionProvenance,
        fetchedAt: Date,
        isStale: Bool
    ) {
        self.ensName = ensName
        self.address = address
        self.provenance = provenance
        self.fetchedAt = fetchedAt
        self.isStale = isStale
    }
}
