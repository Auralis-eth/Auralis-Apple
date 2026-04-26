import Foundation
import OSLog

actor ENSResolutionCacheStore {
    private let logger = Logger(subsystem: "Auralis", category: "ENSResolutionCacheStore")
    private let userDefaults: UserDefaults
    private let storageKey: String
    private let retentionTTL: TimeInterval
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var state: ENSCacheState

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "Auralis.ENSResolutionCache.v1",
        retentionTTL: TimeInterval = 60 * 60 * 24 * 7
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.retentionTTL = retentionTTL
        if let data = userDefaults.data(forKey: storageKey) {
            do {
                let decodedState = try decoder.decode(ENSCacheState.self, from: data)
                let prunedState = Self.prunedState(
                    from: decodedState,
                    retentionTTL: retentionTTL
                )
                self.state = prunedState
                if prunedState != decodedState {
                    if prunedState.forward.isEmpty && prunedState.reverse.isEmpty {
                        userDefaults.removeObject(forKey: storageKey)
                    } else if let encodedPrunedState = try? encoder.encode(prunedState) {
                        userDefaults.set(encodedPrunedState, forKey: storageKey)
                    }
                }
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
        pruneExpiredEntriesAndPersistIfNeeded()
        return state.forward[name]
    }

    func cachedReverseResolution(forAddress address: String) -> ENSReverseCacheEntry? {
        pruneExpiredEntriesAndPersistIfNeeded()
        return state.reverse[address]
    }

    func storeForwardResolution(_ entry: ENSForwardCacheEntry) {
        pruneExpiredEntriesAndPersistIfNeeded()
        state.forward[entry.ensName] = entry
        persist()
    }

    func removeForwardResolution(forENS name: String) {
        state.forward.removeValue(forKey: name)
        persist()
    }

    func storeReverseResolution(_ entry: ENSReverseCacheEntry) {
        pruneExpiredEntriesAndPersistIfNeeded()
        state.reverse[entry.address] = entry
        persist()
    }

    func clearAll() {
        state = .empty
        userDefaults.removeObject(forKey: storageKey)
    }

    private static func prunedState(
        from state: ENSCacheState,
        retentionTTL: TimeInterval,
        referenceDate: Date = .now
    ) -> ENSCacheState {
        guard retentionTTL > 0 else {
            return .empty
        }

        let cutoffDate = referenceDate.addingTimeInterval(-retentionTTL)
        return ENSCacheState(
            forward: state.forward.filter { _, entry in
                entry.fetchedAt >= cutoffDate
            },
            reverse: state.reverse.filter { _, entry in
                entry.fetchedAt >= cutoffDate
            }
        )
    }

    private func pruneExpiredEntriesAndPersistIfNeeded(referenceDate: Date = .now) {
        let originalState = state
        state = Self.prunedState(
            from: state,
            retentionTTL: retentionTTL,
            referenceDate: referenceDate
        )

        guard state != originalState else {
            return
        }

        if state.forward.isEmpty && state.reverse.isEmpty {
            userDefaults.removeObject(forKey: storageKey)
        } else {
            persist()
        }
    }

    private func persist() {
        guard let data = try? encoder.encode(state) else {
            logger.error("Failed to encode ENS cache state for key \(self.storageKey, privacy: .public)")
            return
        }

        userDefaults.set(data, forKey: storageKey)
    }
}
