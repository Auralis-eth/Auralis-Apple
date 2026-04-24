import Foundation
import OSLog

actor ENSResolutionCacheStore {
    private let logger = Logger(subsystem: "Auralis", category: "ENSResolutionCacheStore")
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
        if let data = userDefaults.data(forKey: storageKey) {
            do {
                self.state = try decoder.decode(ENSCacheState.self, from: data)
            } catch {
                self.state = .empty
                userDefaults.removeObject(forKey: storageKey)
                logger.error("Discarded corrupt ENS cache blob for key \(storageKey, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
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

    func removeForwardResolution(forENS name: String) {
        state.forward.removeValue(forKey: name)
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
            logger.error("Failed to encode ENS cache state for key \(self.storageKey, privacy: .public)")
            return
        }

        userDefaults.set(data, forKey: storageKey)
    }
}
