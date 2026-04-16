import Foundation

enum NFTProviderFailureKind: String, Equatable {
    case offline
    case rateLimited
    case invalidResponse
    case invalidScope
    case misconfigured
    case busy
    case unavailable
}
