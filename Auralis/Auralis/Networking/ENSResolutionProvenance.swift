import Foundation

enum ENSResolutionProvenance: String, Codable, Equatable, Sendable {
    case network
    case cache
    case staleCache
}
