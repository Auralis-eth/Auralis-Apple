import Foundation

public protocol MediaNetworkStatusProviding: Sendable {
    var isOffline: Bool { get }
}

public typealias NetworkStatusProviding = MediaNetworkStatusProviding

public struct AlwaysOnlineMediaNetworkStatusProvider: MediaNetworkStatusProviding {
    public let isOffline: Bool

    public init(isOffline: Bool = false) {
        self.isOffline = isOffline
    }
}

public typealias AlwaysOnlineNetworkStatusProvider = AlwaysOnlineMediaNetworkStatusProvider

