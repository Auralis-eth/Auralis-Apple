import Foundation

actor ENSResolutionCacheStore {
    private let userDefaults: UserDefaults
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var state: ENSCacheState

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "Auralis.ENSResolutionCache.v1"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? decoder.decode(ENSCacheState.self, from: data) {
            self.state = decoded
        } else {
            self.state = .empty
        }
    }

    func cachedForwardResolution(forENS name: String) -> ENSForwardCacheEntry? {
        state.forward[name]
    }

    func cachedReverseResolution(forAddress address: String) -> ENSReverseCacheEntry? {
        state.reverse[address]
    }

    func storeForwardResolution(_ entry: ENSForwardCacheEntry) {
        state.forward[entry.ensName] = entry
        persist()
    }

    func storeReverseResolution(_ entry: ENSReverseCacheEntry) {
        state.reverse[entry.address] = entry
        persist()
    }

    func clearAll() {
        state = .empty
        userDefaults.removeObject(forKey: storageKey)
    }

    private func persist() {
        guard let data = try? encoder.encode(state) else {
            return
        }

        userDefaults.set(data, forKey: storageKey)
    }
}
