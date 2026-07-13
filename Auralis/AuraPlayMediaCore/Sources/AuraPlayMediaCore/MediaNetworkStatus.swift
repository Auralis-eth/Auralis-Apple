import Foundation

public protocol MediaNetworkStatusProviding: Sendable {
    var isOffline: Bool { get }
}

/// Reports a fixed network status. Useful as a default when no live
/// reachability source is wired up, and as a fixture in tests.
public struct FixedMediaNetworkStatusProvider: MediaNetworkStatusProviding {
    public let isOffline: Bool

    public init(isOffline: Bool = false) {
        self.isOffline = isOffline
    }
}
