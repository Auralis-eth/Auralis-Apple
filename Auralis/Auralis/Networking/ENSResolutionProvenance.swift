import Foundation

enum ENSResolutionProvenance: String, Codable, Equatable, Sendable {
    case network
    case networkOffchainLookupAllowed
    case cache
    case staleCache
}
