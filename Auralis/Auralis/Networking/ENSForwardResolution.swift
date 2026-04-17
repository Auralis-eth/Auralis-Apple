import Foundation

struct ENSForwardResolution: Codable, Equatable, Sendable {
    let ensName: String
    let address: String
    let provenance: ENSResolutionProvenance
    let fetchedAt: Date
    let isStale: Bool
}
