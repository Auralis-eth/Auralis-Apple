import Foundation
import OSLog

public struct ENSCacheUserDefaults: @unchecked Sendable {
    let userDefaults: UserDefaults

    public init(_ userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }
}

public actor ENSResolutionCacheStore {
    public static let storageDecisionIdentifier = "Auralis.ENSResolutionCache.v1"

    private let logger = Logger(subsystem: "Auralis", category: "ENSResolutionCacheStore")
    private let userDefaults: UserDefaults
    private let storageKey: String
    private let retentionTTL: TimeInterval
    private let nowProvider: @Sendable () -> Date
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var state: ENSCacheState

    public init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = ENSResolutionCacheStore.storageDecisionIdentifier,
        retentionTTL: TimeInterval = 60 * 60 * 24 * 7,
        nowProvider: @escaping @Sendable () -> Date = { .now }
    ) {
        self.init(
            userDefaultsStore: ENSCacheUserDefaults(userDefaults),
            storageKey: storageKey,
            retentionTTL: retentionTTL,
            nowProvider: nowProvider
        )
    }

    public init(
        userDefaultsStore: ENSCacheUserDefaults,
        storageKey: String = ENSResolutionCacheStore.storageDecisionIdentifier,
        retentionTTL: TimeInterval = 60 * 60 * 24 * 7,
        nowProvider: @escaping @Sendable () -> Date = { .now }
    ) {
        let userDefaults = userDefaultsStore.userDefaults
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.retentionTTL = retentionTTL
        self.nowProvider = nowProvider
        if let data = userDefaults.data(forKey: storageKey) {
            do {
                let decodedState = try decoder.decode(ENSCacheState.self, from: data)
                let prunedState = Self.prunedState(
                    from: decodedState,
                    retentionTTL: retentionTTL,
                    referenceDate: nowProvider()
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

    public func cachedForwardResolution(forENS name: String) -> ENSForwardCacheEntry? {
        pruneExpiredEntriesAndPersistIfNeeded(referenceDate: nowProvider())
        return state.forward[name]
    }

    public func cachedReverseResolution(forAddress address: String) -> ENSReverseCacheEntry? {
        pruneExpiredEntriesAndPersistIfNeeded(referenceDate: nowProvider())
        return state.reverse[address]
    }

    public func storeForwardResolution(_ entry: ENSForwardCacheEntry) {
        pruneExpiredEntriesAndPersistIfNeeded(referenceDate: nowProvider())
        state.forward[entry.ensName] = entry
        persist()
    }

    public func removeForwardResolution(forENS name: String) {
        state.forward.removeValue(forKey: name)
        persist()
    }

    public func storeReverseResolution(_ entry: ENSReverseCacheEntry) {
        pruneExpiredEntriesAndPersistIfNeeded(referenceDate: nowProvider())
        state.reverse[entry.address] = entry
        persist()
    }

    public func clearAll() {
        state = .empty
        userDefaults.removeObject(forKey: storageKey)
    }

    private static func prunedState(
        from state: ENSCacheState,
        retentionTTL: TimeInterval,
        referenceDate: Date
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

    private func pruneExpiredEntriesAndPersistIfNeeded(referenceDate: Date) {
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
