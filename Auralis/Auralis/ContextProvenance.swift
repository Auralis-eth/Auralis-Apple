import Foundation

enum ContextProvenance: String, Equatable, Sendable {
    case userProvided = "user_provided"
    case onChain = "on_chain"
    case localCache = "local_cache"
}
