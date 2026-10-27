import Foundation
import AuralisRuntime

/// Persists only named observer cursors; event payloads remain in runtime history.
///
/// Writes are coalesced. Both runtime observers checkpoint *every* envelope they process, so a
/// write-through store turned each event into two read-modify-write cycles over a `UserDefaults`
/// dictionary — steady plist churn proportional to event volume. The cursor is instead held in
/// memory and flushed on the first save after a quiet period, then at most once per
/// ``flushInterval`` or every ``flushEverySaveCount`` saves, whichever comes first.
///
/// Losing an unflushed cursor to a crash costs a short replay of already-processed events, which is
/// exactly the case the observers' de-duplication caches exist to absorb — so the trade is a bounded
/// replay against continuous disk traffic. Call ``flush()`` to force durability at a known-good
/// moment (backgrounding, for instance).
public actor PersistentRuntimeEventCheckpointStore: RuntimeEventCheckpointStoring {
    private let defaults: UserDefaults
    private let storageKey: String
    private let flushInterval: TimeInterval
    private let flushEverySaveCount: Int

    /// In-memory source of truth once hydrated. `nil` means "not yet read from `UserDefaults`".
    private var cache: [String: String]?
    private var unflushedSaveCount = 0
    /// `.distantPast` so the very first save of a session always flushes immediately: a lone
    /// checkpoint (the common case in tests and after a single event) must be durable at once.
    private var lastFlush: Date = .distantPast
    private var pendingFlush: Task<Void, Never>?

    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = "com.auralis.runtime-event-checkpoints.v1",
        flushInterval: TimeInterval = 5,
        flushEverySaveCount: Int = 32
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.flushInterval = max(0, flushInterval)
        self.flushEverySaveCount = max(1, flushEverySaveCount)
    }

    public func checkpoint(for subscriberID: String) -> UUID? {
        guard let value = hydratedCache()[subscriberID] else { return nil }
        return UUID(uuidString: value)
    }

    public func saveCheckpoint(_ eventID: UUID, for subscriberID: String) {
        var checkpoints = hydratedCache()
        checkpoints[subscriberID] = eventID.uuidString
        cache = checkpoints
        unflushedSaveCount += 1

        let elapsed = Date().timeIntervalSince(lastFlush)
        if elapsed >= flushInterval || unflushedSaveCount >= flushEverySaveCount {
            flush()
            return
        }
        scheduleDeferredFlush(after: flushInterval - elapsed)
    }

    /// Writes any pending cursor through to `UserDefaults`.
    public func flush() {
        pendingFlush?.cancel()
        pendingFlush = nil
        guard unflushedSaveCount > 0, let cache else { return }
        defaults.set(cache, forKey: storageKey)
        unflushedSaveCount = 0
        lastFlush = Date()
    }

    public func resetAll() {
        pendingFlush?.cancel()
        pendingFlush = nil
        cache = [:]
        unflushedSaveCount = 0
        lastFlush = .distantPast
        defaults.removeObject(forKey: storageKey)
    }

    /// Ensures a coalesced write still lands when the event stream goes quiet, so the last cursor of
    /// a burst is not left in memory indefinitely.
    private func scheduleDeferredFlush(after delay: TimeInterval) {
        guard pendingFlush == nil else { return }
        pendingFlush = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, delay)))
            guard Task.isCancelled == false else { return }
            await self?.flush()
        }
    }

    private func hydratedCache() -> [String: String] {
        if let cache { return cache }
        let loaded = defaults.dictionary(forKey: storageKey) as? [String: String] ?? [:]
        cache = loaded
        return loaded
    }
}
