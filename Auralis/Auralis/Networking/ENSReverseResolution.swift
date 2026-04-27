import Foundation

struct ENSReverseResolution: Codable, Equatable, Sendable {
    let address: String
    let ensName: String
    let provenance: ENSResolutionProvenance
    let fetchedAt: Date
    let isStale: Bool
    let isForwardVerified: Bool
}
