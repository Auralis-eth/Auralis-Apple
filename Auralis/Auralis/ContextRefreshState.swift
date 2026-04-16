import Foundation

enum ContextRefreshState: String, Equatable, Sendable {
    case idle
    case refreshing
    case unknown
}
