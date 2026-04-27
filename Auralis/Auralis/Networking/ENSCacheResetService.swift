import Foundation

protocol ENSCacheResetting: Sendable {
    func resetCache() async
}

struct ENSCacheResetService: ENSCacheResetting {
    private let cacheStore: ENSResolutionCacheStore

    init(cacheStore: ENSResolutionCacheStore = ENSResolutionCacheStore()) {
        self.cacheStore = cacheStore
    }

    func resetCache() async {
        await cacheStore.clearAll()
    }
}
