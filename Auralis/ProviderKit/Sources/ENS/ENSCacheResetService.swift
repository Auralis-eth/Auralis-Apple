import Foundation

public protocol ENSCacheResetting: Sendable {
    func resetCache() async
}

public struct ENSCacheResetService: ENSCacheResetting {
    private let cacheStore: ENSResolutionCacheStore

    public init(cacheStore: ENSResolutionCacheStore = ENSResolutionCacheStore()) {
        self.cacheStore = cacheStore
    }

    public func resetCache() async {
        await cacheStore.clearAll()
    }
}
