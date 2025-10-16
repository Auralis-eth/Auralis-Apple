import Foundation

/// QueueManager
///
/// Thread-safety: This type is isolated to the main actor using `@MainActor`.
/// - All mutable state is protected by main-actor serialization.
/// - All public property access and any method calls will hop to the main actor when called from other threads/tasks.
/// - Access to `UserDefaults` occurs on the main actor to avoid concurrent mutations.
/// - This design is appropriate because the playback queue is UI-bound. If heavy work is needed, consider offloading just that work to a background task and returning results to the main actor.
/// - Persistence: Writes to UserDefaults are debounced on a background queue and guarded by a generation counter to prevent stale writes. Use `flushPersistShuffleNow()` for a synchronous write before termination, or `flushPersistShuffle(completion:)` / `await flushPersistShuffle()` to wait for completion.
@MainActor
public final class QueueManager {
    // Persistence constants and queue
    private static let stateKey = "QueueManager.state"
    private static let stateVersion = 1
    private static let legacyOrderKey = "QueueManager.shuffledOrder"
    private static let legacyIndexKey = "QueueManager.shuffleIndex"
    private static let legacyMigratedKey = "QueueManager.migratedToBlob"
    
    /// Controls whether invariant violations crash the process.
    /// Enabled by default; define `QUEUE_MANAGER_DISABLE_STRICT_VALIDATION` to opt out (for special builds/tests).
    private static var strictValidationEnabled: Bool {
        #if QUEUE_MANAGER_DISABLE_STRICT_VALIDATION
        return false
        #else
        return true
        #endif
    }
    
    /// Main-actor monotonic generation counter
    private var stateGeneration: Int = 0
    
    // Debounced, background persistence to avoid blocking the main actor.
    // Writes are eventual; see `persistShuffle()` docs.
    private let persistenceQueue = DispatchQueue(label: "QueueManager.persistence", qos: .utility)
    private var persistWorkItem: DispatchWorkItem?
    private let persistDebounceInterval: TimeInterval = 0.35

    // Isolated storage for last-committed generation; only access on `persistenceQueue`.
    private final class GenerationStorage {
        private var value: Int = 0
        func get() -> Int { value }
        func set(_ newValue: Int) { value = newValue }
    }
    private let generationStore = GenerationStorage()

    public enum RepeatMode: Equatable, Sendable { case none, track, playlist }

    private let defaults = UserDefaults.standard

    private var shuffledOrder: [String] = [] // store NFT ids
    private var shuffleIndex: Int = 0

    public var previous = Playlist(name: "Previous")
    // In-memory timestamps for when items were moved into `previous` (most recent play moment)
    private var previousTimestamps: [String: Date] = [:]
    public var next = Playlist(name: "Next")
    public private(set) var current: NFT?
    public var isShuffleEnabled: Bool = false
    public var repeatMode: RepeatMode = .none

    /// Maximum number of tracks to retain in the `previous` history. Set to `nil` for unlimited. Default: 50.
    public var previousMaxCount: Int? = 50 {
        didSet {
            // Treat negative values as unlimited
            if let v = previousMaxCount, v < 0 { previousMaxCount = nil }
            enforcePreviousLimit()
            validateInvariants(context: "previousMaxCount.didSet")
        }
    }

    /// Read-only access to previously played tracks for UI display.
    public var previousTracks: [NFT] { previous.tracks }

    /// Returns the recently played items (most-recent-first) from the in-memory history.
    /// - Parameter limit: Optional maximum number of items to return. If nil, returns all.
    /// - Returns: An array of `NFT` ordered most-recent-first.
    public func getRecentlyPlayed(limit: Int? = nil) -> [NFT] {
        let items = previous.tracks
        guard let limit, limit >= 0 else { return items }
        return Array(items.prefix(limit))
    }
    
    /// Returns the last time an NFT was recorded into `previous` during this app session.
    /// This is in-memory only and does not persist across launches.
    public func lastPlayedDate(for nftId: String) -> Date? {
        return previousTimestamps[nftId]
    }

    /// Clears the previously played history.
    public func clearPreviousHistory() {
        previous._clear()
        previousTimestamps.removeAll()
        validateInvariants(context: "clearPreviousHistory")
    }

    /// Ensures the `previous` history does not exceed `previousMaxCount`.
    private func enforcePreviousLimit() {
        guard let limit = previousMaxCount else { return }
        if limit < 0 { return }
        let count = previous.tracks.count
        if count > limit {
            let removeCount = count - limit
            // Collect IDs to remove timestamps for
            let removedSlice = previous.tracks.suffix(removeCount)
            let removedIds = removedSlice.map { $0.id }
            // Remove the oldest items (at the end) to keep most-recent-first ordering
            previous.tracks.removeLast(removeCount)
            // Clean up timestamps for removed items
            for id in removedIds { previousTimestamps.removeValue(forKey: id) }
        }
    }

    /// Records the current track into `previous` (most-recent-first) and sets a new current.
    private func recordPreviousAndSetCurrent(_ newCurrent: NFT) {
        if let c = current {
            // Deduplicate: remove any existing occurrences of the current track from history
            previous._removeAll(where: { $0.id == c.id })
            // Insert most recent at the front
            previous._insertFront(c)
            // Stamp last played time
            previousTimestamps[c.id] = Date()
            enforcePreviousLimit()
        }
        current = newCurrent
    }

    /// Initializes the queue manager on the main actor, restoring any persisted shuffle state from UserDefaults.
    /// All subsequent mutations and reads are serialized via the main actor to prevent data races.
    public init() {
        // local store reference for generation
        let store = self.generationStore
        
        // Attempt to restore from versioned state blob first
        if let state = defaults.dictionary(forKey: Self.stateKey) {
            let version = state["version"] as? Int ?? 0
            let order = state["order"] as? [String] ?? []
            let index = state["index"] as? Int ?? 0
            
            // Basic validation and clamping
            shuffledOrder = order
            if index < 0 {
                shuffleIndex = 0
            } else if index > order.count {
                shuffleIndex = order.count
            } else {
                shuffleIndex = index
            }
            
            if version != Self.stateVersion {
                // Future migration hook: version mismatch detected; no migration needed currently.
            }
            // Read generation from state blob
            let gen = state["generation"] as? Int ?? 0
            persistenceQueue.sync { store.set(gen) }
            defaults.set(true, forKey: Self.legacyMigratedKey)
        } else {
            // Fallback to legacy keys for backward compatibility
            if let saved = defaults.array(forKey: Self.legacyOrderKey) as? [String] {
                shuffledOrder = saved
            } else {
                shuffledOrder = []
            }
            let idx = defaults.integer(forKey: Self.legacyIndexKey)
            if idx < 0 {
                shuffleIndex = 0
            } else if idx > shuffledOrder.count {
                shuffleIndex = shuffledOrder.count
            } else {
                shuffleIndex = idx
            }

            // Immediately migrate to new blob format in the background
            persistShuffle()
            persistenceQueue.sync { store.set(0) }
        }
        validateInvariants(context: "init")
    }

    /// Enables or disables shuffle mode.
    ///
    /// Thread-safety: `@MainActor` — calls from other threads hop to the main actor.
    /// Mutation: Mutates internal shuffle state, may rebuild or clear shuffle order, and persists state (debounced).
    /// - Parameter enabled: `true` to enable shuffle; `false` to disable.
    /// - Discussion: When enabling, the shuffle order is rebuilt while maintaining the current position if possible. When disabling, the shuffle state is cleared and the index is reset.
    /// - Example:
    /// ```swift
    /// await MainActor.run { queue.setShuffleEnabled(true) }
    /// ```
    public func setShuffleEnabled(_ enabled: Bool) {
        guard enabled != isShuffleEnabled else { return }
        isShuffleEnabled = enabled
        if enabled {
            rebuildShuffleMaintainingPosition()
        } else {
            shuffledOrder.removeAll()
            shuffleIndex = 0
            persistShuffle()
        }
        validateInvariants(context: "setShuffleEnabled")
    }

    /// Sets the repeat mode for playback.
    ///
    /// Thread-safety: `@MainActor`.
    /// Mutation: Updates repeat mode only.
    /// - Parameter mode: The desired repeat mode (`.none`, `.track`, `.playlist`).
    /// - Example:
    /// ```swift
    /// await MainActor.run { queue.setRepeatMode(.playlist) }
    /// ```
    public func setRepeatMode(_ mode: RepeatMode) {
        repeatMode = mode
        validateInvariants(context: "setRepeatMode")
    }

    /// Sets the current item.
    ///
    /// Thread-safety: `@MainActor`.
    /// Mutation: Sets the `current` item only; does not mutate `previous` or `next`.
    /// - Parameter nft: The item to set as current, or `nil` to clear.
    /// - Discussion: Callers should use `dequeueNext()` to advance playback.
    /// - Example:
    /// ```swift
    /// await MainActor.run { queue.setCurrent(currentNFT) }
    /// ```
    public func setCurrent(_ nft: NFT?) {
        current = nft
        validateInvariants(context: "setCurrent")
    }

    /// Persists the shuffle state asynchronously with debouncing.
    /// Persistence is eventual (not immediate) to minimize disk I/O and avoid blocking the main actor.
    /// Use `flushPersistShuffle()` for critical, immediate writes (e.g., app termination).
    /// The work items carry a generation counter and stale writes are skipped based on it.
    private func persistShuffle() {
        // Capture current state on the main actor to avoid races.
        let orderSnapshot = self.shuffledOrder
        let indexSnapshot = self.shuffleIndex
        
        // Increment generation
        stateGeneration += 1
        let generation = stateGeneration
        let store = self.generationStore

        // Cancel any pending work to debounce rapid changes
        persistWorkItem?.cancel()

        let work = DispatchWorkItem { [defaults] in
            let last = store.get()
            if generation <= last {
                return
            }
            
            // Build a single versioned state payload to minimize I/O
            let payload: [String: Any] = [
                "version": Self.stateVersion,
                "order": orderSnapshot,
                "index": indexSnapshot,
                "generation": generation
            ]

            // Write the blob under a single key to avoid multiple disk writes
            defaults.set(payload, forKey: Self.stateKey)

            // Write legacy keys only once during migration
            if defaults.bool(forKey: Self.legacyMigratedKey) == false {
                defaults.set(orderSnapshot, forKey: Self.legacyOrderKey)
                defaults.set(indexSnapshot, forKey: Self.legacyIndexKey)
                defaults.set(true, forKey: Self.legacyMigratedKey)
            }
            
            store.set(generation)
        }

        persistWorkItem = work
        // Debounce writes to batch frequent updates
        persistenceQueue.asyncAfter(deadline: .now() + persistDebounceInterval, execute: work)
    }

    /// Forces an immediate synchronous write of the current shuffle state.
    ///
    /// Thread-safety: `@MainActor` for snapshot; performs a blocking write on the persistence queue.
    /// Mutation: Does not change logical queue state; persists it durably.
    /// - Important: This call blocks until the write completes. Use for termination or backgrounding where durability is critical.
    /// - Example:
    /// ```swift
    /// // In applicationWillTerminate or scene phase change
    /// queue.flushPersistShuffleNow()
    /// ```
    public func flushPersistShuffleNow() {
        // Capture snapshot on main actor
        let orderSnapshot = self.shuffledOrder
        let indexSnapshot = self.shuffleIndex
        
        // Increment generation
        stateGeneration += 1
        let generation = stateGeneration
        
        // Cancel any pending debounced write and perform immediately
        persistWorkItem?.cancel()
        persistWorkItem = nil
        let store = self.generationStore
        
        persistenceQueue.sync {
            let last = store.get()
            if generation <= last {
                return
            }
            
            let payload: [String: Any] = [
                "version": Self.stateVersion,
                "order": orderSnapshot,
                "index": indexSnapshot,
                "generation": generation
            ]
            defaults.set(payload, forKey: Self.stateKey)
            
            // Write legacy keys only once during migration
            if defaults.bool(forKey: Self.legacyMigratedKey) == false {
                defaults.set(orderSnapshot, forKey: Self.legacyOrderKey)
                defaults.set(indexSnapshot, forKey: Self.legacyIndexKey)
                defaults.set(true, forKey: Self.legacyMigratedKey)
            }
            
            store.set(generation)
        }
    }
    
    /// Forces an immediate asynchronous write of the current shuffle state and calls completion when done.
    ///
    /// Thread-safety: `@MainActor` for snapshot; write occurs on the persistence queue; completion is invoked on the main actor.
    /// Mutation: Does not change logical queue state; persists it durably.
    /// - Parameter completion: Invoked on the main actor after the write completes.
    /// - Example:
    /// ```swift
    /// queue.flushPersistShuffle {
    ///     // Safe to proceed; state is persisted
    /// }
    /// ```
    public func flushPersistShuffle(completion: @escaping () -> Void) {
        // Capture snapshot on main actor
        let orderSnapshot = self.shuffledOrder
        let indexSnapshot = self.shuffleIndex
        
        // Increment generation
        stateGeneration += 1
        let generation = stateGeneration
        let store = self.generationStore
        
        // Cancel any pending debounced write and perform immediately async
        persistWorkItem?.cancel()
        persistWorkItem = nil
        
        persistenceQueue.async { [defaults] in
            let last = store.get()
            if generation <= last {
                DispatchQueue.main.async {
                    completion()
                }
                return
            }
            
            let payload: [String: Any] = [
                "version": Self.stateVersion,
                "order": orderSnapshot,
                "index": indexSnapshot,
                "generation": generation
            ]
            defaults.set(payload, forKey: Self.stateKey)
            
            // Write legacy keys only once during migration
            if defaults.bool(forKey: Self.legacyMigratedKey) == false {
                defaults.set(orderSnapshot, forKey: Self.legacyOrderKey)
                defaults.set(indexSnapshot, forKey: Self.legacyIndexKey)
                defaults.set(true, forKey: Self.legacyMigratedKey)
            }
            
            store.set(generation)
            
            DispatchQueue.main.async {
                completion()
            }
        }
    }
    
    /// Forces an immediate write of the current shuffle state and awaits completion.
    ///
    /// Thread-safety: `@MainActor` for snapshot; write occurs on the persistence queue.
    /// Mutation: Does not change logical queue state; persists it durably.
    /// - Example:
    /// ```swift
    /// await queue.flushPersistShuffle()
    /// ```
    public func flushPersistShuffle() async {
        await withCheckedContinuation { continuation in
            flushPersistShuffle {
                continuation.resume()
            }
        }
    }

    /// Reconciles the shuffled order deterministically after modifications to `next.tracks`.
    /// - Behavior:
    ///   - Removes IDs from `shuffledOrder` that are no longer present in `next.tracks`.
    ///   - Preserves the relative order of remaining IDs.
    ///   - Appends any new IDs (present in `next.tracks` but not in `shuffledOrder`) at the end, in the order of `next.tracks`.
    ///   - Keeps `shuffleIndex` as a position; if out of bounds after reconciliation, clamps to `newOrder.count`.
    ///   - Persists changes asynchronously (debounced).
    private func reconcileShuffleAfterNextChange() {
        let nextIds = next.tracks.map { $0.id }
        let nextSet = Set(nextIds)

        // 1) Filter out removed ids while preserving order
        var newOrder: [String] = []
        newOrder.reserveCapacity(shuffledOrder.count)
        for id in shuffledOrder where nextSet.contains(id) {
            newOrder.append(id)
        }

        // 2) Append any new ids at the end in stable order of next.tracks
        let existing = Set(newOrder)
        for id in nextIds where !existing.contains(id) {
            newOrder.append(id)
        }

        // 3) Adjust index: keep position; clamp if needed
        if shuffleIndex < 0 { shuffleIndex = 0 }
        if shuffleIndex > newOrder.count { shuffleIndex = newOrder.count }

        shuffledOrder = newOrder
        persistShuffle()
    }

    /// Validates and repairs queue/shuffle state.
    ///
    /// Thread-safety: `@MainActor`.
    /// Mutation: May reconcile shuffle state and clamp indices; persists if repairs were needed.
    /// - Returns: An array of human-readable notes describing any repairs performed. Empty if state was valid.
    /// - Example:
    /// ```swift
    /// let notes = await MainActor.run { queue.validateAndRepairState() }
    /// if !notes.isEmpty { /* log or surface notes */ }
    /// ```
    @discardableResult
    public func validateAndRepairState() -> [String] {
        var notes: [String] = []

        if shuffleIndex < 0 {
            notes.append("Clamped negative shuffleIndex to 0.")
            shuffleIndex = 0
        }
        if shuffleIndex > shuffledOrder.count {
            notes.append("Clamped shuffleIndex from \(shuffleIndex) to \(shuffledOrder.count).")
            shuffleIndex = shuffledOrder.count
        }

        if isShuffleEnabled {
            // Ensure the shuffled suffix (from shuffleIndex onward) matches next.tracks
            let remainingShuffled = Array(shuffledOrder.dropFirst(shuffleIndex))
            let nextIds = next.tracks.map { $0.id }
            let remainingSet = NSCountedSet(array: remainingShuffled)
            let nextSet = NSCountedSet(array: nextIds)
            if remainingSet != nextSet {
                notes.append("Reconciled shuffled suffix to match next.tracks.")
                reconcileShuffleAfterNextChange()
            } else {
                // Still persist clamped index if needed
                persistShuffle()
            }
        }

        return notes
    }

    /// Validates internal invariants and attempts graceful recovery if violated.
    /// - Parameter context: Optional label to help identify when validation occurred.
    /// - Discussion:
    ///   In DEBUG builds, violations will trigger an assertion failure to surface bugs early.
    ///   In production, we log and attempt to repair state deterministically.
    private func validateInvariants(context: String = "") {
        var violations: [String] = []

        // 1) Index bounds
        if shuffleIndex < 0 {
            violations.append("shuffleIndex < 0; clamping to 0")
            shuffleIndex = 0
        }
        if shuffleIndex > shuffledOrder.count {
            violations.append("shuffleIndex > shuffledOrder.count; clamping to count")
            shuffleIndex = shuffledOrder.count
        }

        // 2) Shuffle-enabled multiset consistency
        if isShuffleEnabled {
            let remainingShuffled = Array(shuffledOrder.dropFirst(shuffleIndex))
            let nextIds = next.tracks.map { $0.id }
            let orderSet = NSCountedSet(array: remainingShuffled)
            let nextSet = NSCountedSet(array: nextIds)
            if orderSet != nextSet {
                violations.append("shuffled suffix multiset != next.tracks ids; reconciling")
                // Deterministically repair
                reconcileShuffleAfterNextChange()
            }
            // Ensure the current pointed id (if any) actually exists after repair
            if shuffleIndex < shuffledOrder.count {
                let id = shuffledOrder[shuffleIndex]
                if next.tracks.first(where: { $0.id == id }) == nil {
                    violations.append("shuffleIndex points to missing id; reconciling and clamping")
                    reconcileShuffleAfterNextChange()
                    if shuffleIndex > shuffledOrder.count { shuffleIndex = shuffledOrder.count }
                }
            }
        } else {
            // When shuffle is disabled, index should be 0 or at most shuffledOrder.count.
            // We already clamp above; optionally clear stale order to reduce confusion.
            if !shuffledOrder.isEmpty {
                // Keep non-empty order to allow quick re-enable, but ensure index is safe.
            }
        }

        if !violations.isEmpty {
            let prefix = context.isEmpty ? "[QueueManager] Invariant violations:" : "[QueueManager] Invariant violations (\(context)):"
            let message = prefix + " " + violations.joined(separator: "; ")
            if Self.strictValidationEnabled {
                preconditionFailure(message)
            }
        }
    }

    /// Fisher–Yates shuffle (a.k.a. Knuth shuffle)
    /// - Complexity: O(n)
    /// - Reference: https://en.wikipedia.org/wiki/Fisher%E2%80%93Yates_shuffle
    /// - Note: Provides a reusable implementation to avoid duplication and reduce bug risk.
    private static func fisherYatesShuffle<T, R: RandomNumberGenerator>(_ array: [T], using rng: inout R) -> [T] {
        var a = array
        if a.count > 1 {
            var i = a.count - 1
            while i > 0 {
                let j = Int.random(in: 0...i, using: &rng)
                if i != j { a.swapAt(i, j) }
                i -= 1
            }
        }
        return a
    }

    private static func fisherYatesShuffle<T>(_ array: [T]) -> [T] {
        var rng = SystemRandomNumberGenerator()
        return fisherYatesShuffle(array, using: &rng)
    }

    private func rebuildShuffle() {
        shuffledOrder = next.tracks.map { $0.id }
        shuffledOrder = Self.fisherYatesShuffle(shuffledOrder)
        shuffleIndex = 0
        persistShuffle()
        validateInvariants(context: "rebuildShuffle")
    }

    private func ensureShuffleValid() {
        // Check if shuffledOrder suffix from shuffleIndex matches next.tracks ids (multiset)
        let remainingShuffled = Array(shuffledOrder.dropFirst(shuffleIndex))
        let nextIds = next.tracks.map { $0.id }

        // Quick check of counts
        if remainingShuffled.count != nextIds.count {
            rebuildShuffle()
            return
        }

        // Check multisets equality
        let remainingSet = NSCountedSet(array: remainingShuffled)
        let nextSet = NSCountedSet(array: nextIds)
        if remainingSet != nextSet {
            rebuildShuffle()
        }
    }

    private func rebuildShuffleMaintainingPosition() {
        let currentId: String? = shuffleIndex < shuffledOrder.count ? shuffledOrder[shuffleIndex] : nil
        shuffledOrder = next.tracks.map { $0.id }
        shuffledOrder = Self.fisherYatesShuffle(shuffledOrder)
        shuffleIndex = 0

        if let currentId = currentId, let newIndex = shuffledOrder.firstIndex(of: currentId) {
            // Rotate so that currentId is at shuffleIndex (which is 0 here)
            if newIndex != 0 {
                let left = shuffledOrder[0..<newIndex]
                let right = shuffledOrder[newIndex..<shuffledOrder.count]
                shuffledOrder = Array(right) + Array(left)
            }
            shuffleIndex = 0
        } else {
            // Clamp shuffleIndex to valid range
            if shuffleIndex > shuffledOrder.count {
                shuffleIndex = shuffledOrder.count
            }
        }
        persistShuffle()
        validateInvariants(context: "rebuildShuffleMaintainingPosition")
    }

    /// Returns the next NFT without removing it.
    ///
    /// Thread-safety: `@MainActor`.
    /// Mutation: Read-only.
    /// - Returns: The next `NFT` to be played, or `nil` when the queue is empty, when shuffle cannot determine a next item, or when repeat rules result in no available item.
    /// - Example:
    /// ```swift
    /// let upcoming = await MainActor.run { queue.peekNext() }
    /// ```
    public func peekNext() -> NFT? {
        if repeatMode == .track, let c = current { return c }
        if !next.tracks.isEmpty {
            return isShuffleEnabled ? peekNextWithShuffle() : next.tracks.first
        }
        if repeatMode == .playlist {
            return peekNextFromPlaylistRepeat()
        }
        return nil
    }

    private func peekNextWithShuffle() -> NFT? {
        ensureShuffleValid()
        guard shuffleIndex < shuffledOrder.count else {
            // Defer to playlist repeat behavior if applicable
            return repeatMode == .playlist ? peekNextFromPlaylistRepeat() : nil
        }
        let id = shuffledOrder[shuffleIndex]
        if let nft = next.tracks.first(where: { $0.id == id }) {
            return nft
        }
        // If not found, rebuild once and try again
        rebuildShuffle()
        guard let firstId = shuffledOrder.first,
              let nft = next.tracks.first(where: { $0.id == firstId }) else { return nil }
        shuffleIndex = 0
        persistShuffle()
        return nft
    }

    private func peekNextFromPlaylistRepeat() -> NFT? {
        var rebuilt: [NFT] = []
        if let c = current { rebuilt.append(c) }
        if !previous.tracks.isEmpty { rebuilt.append(contentsOf: previous.tracks) }
        guard !rebuilt.isEmpty else { return nil }
        if isShuffleEnabled {
            let tempOrder = Self.fisherYatesShuffle(rebuilt.map { $0.id })
            guard let firstId = tempOrder.first else { return nil }
            return rebuilt.first(where: { $0.id == firstId })
        } else {
            return rebuilt.first
        }
    }

    /// Dequeues and returns the next NFT according to shuffle and repeat rules.
    ///
    /// Thread-safety: `@MainActor`.
    /// Mutation: Removes the returned item from `next` (when applicable) and advances shuffle index.
    /// - Returns: The dequeued `NFT`, or `nil` if the queue is empty or no valid next item can be determined.
    /// - Example:
    /// ```swift
    /// if let next = await MainActor.run({ queue.dequeueNext() }) {
    ///     // play next
    /// }
    /// ```
    @discardableResult
    public func dequeueNext() -> NFT? {
        if repeatMode == .track, let c = current { return c }
        if !next.tracks.isEmpty {
            let result = isShuffleEnabled ? dequeueNextWithShuffleFromNonEmpty() : dequeueNextWithoutShuffleFromNonEmpty()
            if let newCurrent = result {
                recordPreviousAndSetCurrent(newCurrent)
            }
            validateInvariants(context: "dequeueNext")
            return result
        }
        if repeatMode == .playlist {
            let rebuilt = rebuildNextFromPlaylistSources()
            guard rebuilt else { validateInvariants(context: "dequeueNext"); return nil }
            let result = isShuffleEnabled ? dequeueNextWithShuffleFromNonEmpty() : dequeueNextWithoutShuffleFromNonEmpty()
            if let newCurrent = result {
                recordPreviousAndSetCurrent(newCurrent)
            }
            validateInvariants(context: "dequeueNext")
            return result
        }
        validateInvariants(context: "dequeueNext")
        return nil
    }

    /// Advances to the next item but only records the previous track if the current
    /// track has been played for at least `minSecondsPlayed`.
    ///
    /// Thread-safety: `@MainActor`.
    /// Mutation:
    /// - Mutates `next` (removes dequeued item), advances shuffle index when applicable.
    /// - Updates `current` to the returned item.
    /// - Records to `previous` only when `currentProgress >= minSecondsPlayed`.
    /// - Persists shuffle state as needed via existing helpers.
    /// - Returns: The advanced `NFT`, or `nil` if none is available under current rules.
    @discardableResult
    public func advanceNextRespectingThreshold(minSecondsPlayed: TimeInterval,
                                               currentProgress: TimeInterval) -> NFT? {
        // Repeat single track: do not change current, just return it
        if repeatMode == .track, let c = current { return c }

        // Fast path: non-empty next
        if !next.tracks.isEmpty {
            let result = isShuffleEnabled ? dequeueNextWithShuffleFromNonEmpty() : dequeueNextWithoutShuffleFromNonEmpty()
            if let newCurrent = result {
                if let _ = current, currentProgress >= minSecondsPlayed {
                    // Record previous + set current
                    recordPreviousAndSetCurrent(newCurrent)
                } else {
                    // Do not record previous; only set current
                    setCurrent(newCurrent)
                }
            }
            validateInvariants(context: "advanceNextRespectingThreshold")
            return result
        }

        // Playlist repeat case when next is empty
        if repeatMode == .playlist {
            let rebuilt = rebuildNextFromPlaylistSources()
            guard rebuilt else { validateInvariants(context: "advanceNextRespectingThreshold"); return nil }
            let result = isShuffleEnabled ? dequeueNextWithShuffleFromNonEmpty() : dequeueNextWithoutShuffleFromNonEmpty()
            if let newCurrent = result {
                if let _ = current, currentProgress >= minSecondsPlayed {
                    recordPreviousAndSetCurrent(newCurrent)
                } else {
                    setCurrent(newCurrent)
                }
            }
            validateInvariants(context: "advanceNextRespectingThreshold")
            return result
        }

        validateInvariants(context: "advanceNextRespectingThreshold")
        return nil
    }

    /// Returns what `dequeueNext()` would return, but without performing any mutations or persistence.
    ///
    /// Thread-safety: `@MainActor`.
    /// Side effects: None. This method does not modify `next`, `previous`, `current`, `shuffledOrder`, or `shuffleIndex`, and does not persist state.
    /// - Returns: The NFT that would be dequeued next according to current settings, or `nil` if none is available.
    /// - Discussion:
    ///   - Unlike `peekNext()`, this method does not attempt to validate or repair shuffle state (no calls to `ensureShuffleValid()`),
    ///     and will not rebuild shuffle order. If the `shuffleIndex` points to an ID not present in `next.tracks`, it simply returns `nil`.
    ///   - This is intended as a pure, no-side-effects view into what `dequeueNext()` would choose.
    @discardableResult
    public func dequeueNextPreview() -> NFT? {
        // Repeat single track
        if repeatMode == .track, let c = current { return c }

        // If upcoming queue has items
        if !next.tracks.isEmpty {
            if isShuffleEnabled {
                // Pure read: do not validate or rebuild; just use current shuffled pointer if valid
                guard shuffleIndex < shuffledOrder.count else { return nil }
                let id = shuffledOrder[shuffleIndex]
                return next.tracks.first(where: { $0.id == id })
            } else {
                return next.tracks.first
            }
        }

        // Playlist repeat case when `next` is empty: compute a local, non-mutating view
        if repeatMode == .playlist {
            var rebuilt: [NFT] = []
            if let c = current { rebuilt.append(c) }
            if !previous.tracks.isEmpty { rebuilt.append(contentsOf: previous.tracks) }
            guard !rebuilt.isEmpty else { return nil }
            if isShuffleEnabled {
                // Choose a candidate deterministically without mutating global shuffle state.
                // We avoid randomization to keep this a stable, side-effect-free view.
                // Here we simply return the first element as a predictable preview.
                return rebuilt.first
            } else {
                return rebuilt.first
            }
        }

        return nil
    }

    private func dequeueNextWithoutShuffleFromNonEmpty() -> NFT? {
        return next._removeFirst()
    }

    private func dequeueNextWithShuffleFromNonEmpty() -> NFT? {
        ensureShuffleValid()
        guard shuffleIndex < shuffledOrder.count else { return nil }
        let id = shuffledOrder[shuffleIndex]
        if let index = next.tracks.firstIndex(where: { $0.id == id }) {
            let nft = next._remove(at: index)
            shuffleIndex += 1
            persistShuffle()
            return nft
        }
        // Not found, rebuild and try once
        rebuildShuffle()
        guard shuffleIndex < shuffledOrder.count,
              let idx = next.tracks.firstIndex(where: { $0.id == shuffledOrder[shuffleIndex] }) else { return nil }
        let nft = next._remove(at: idx)
        shuffleIndex += 1
        persistShuffle()
        return nft
    }

    private func rebuildNextFromPlaylistSources() -> Bool {
        var rebuilt: [NFT] = []
        if let c = current { rebuilt.append(c) }
        if !previous.tracks.isEmpty { rebuilt.append(contentsOf: previous.tracks) }
        guard !rebuilt.isEmpty else { return false }
        previous._clear()
        previousTimestamps.removeAll()
        next._replace(with: rebuilt)
        if isShuffleEnabled { rebuildShuffle() }
        return true
    }

    /// Pushes an item to the front of the upcoming queue.
    ///
    /// Thread-safety: `@MainActor`.
    /// Mutation: Inserts the item at the front of `next` and reconciles shuffle if enabled.
    /// - Parameter nft: The item to enqueue at the front.
    /// - Example:
    /// ```swift
    /// await MainActor.run { queue.pushToFrontOfNext(nft) }
    /// ```
    public func pushToFrontOfNext(_ nft: NFT) { 
        next._insertFront(nft)
        if isShuffleEnabled { reconcileShuffleAfterNextChange() }
        validateInvariants(context: "pushToFrontOfNext")
    }

    /// Appends items to the end of the upcoming queue.
    ///
    /// Thread-safety: `@MainActor`.
    /// Mutation: Appends to `next` and reconciles shuffle if enabled.
    /// - Parameter nfts: Items to enqueue.
    /// - Example:
    /// ```swift
    /// await MainActor.run { queue.addToNext(newItems) }
    /// ```
    public func addToNext(_ nfts: [NFT]) {
        next._append(nfts)
        if isShuffleEnabled {
            reconcileShuffleAfterNextChange()
        }
        validateInvariants(context: "addToNext")
    }

    /// Removes items from the upcoming queue matching the given predicate.
    ///
    /// Thread-safety: `@MainActor`.
    /// Mutation: Removes matching items from `next` and reconciles shuffle if enabled.
    /// - Parameter predicate: A closure that returns `true` for items to remove.
    /// - Discussion:
    ///   - Deterministic behavior: When shuffle is enabled, the internal `shuffledOrder` is reconciled by removing missing IDs and preserving relative order of remaining items. New items (if any) are appended in the order of `next.tracks`.
    ///   - The `shuffleIndex` is preserved as a position. If the item at the current shuffle position was removed, the index now points to the item that shifted into that slot. If the index is beyond the end after reconciliation, it's clamped to the array's count.
    ///   - This avoids random reshuffles, prevents skipped tracks, and ensures no crashes from out-of-bounds indices.
    /// - Example:
    /// ```swift
    /// await MainActor.run { queue.removeFromNext { $0.id == someId } }
    /// ```
    public func removeFromNext(where predicate: (NFT) -> Bool) {
        // Remove from upcoming list
        next._removeAll(where: predicate)

        // When shuffle is enabled, reconcile deterministically rather than rebuilding randomly
        if isShuffleEnabled {
            reconcileShuffleAfterNextChange()
        }
        validateInvariants(context: "removeFromNext")
    }

    /// Removes a specific item from the previously played history.
    /// - Parameter id: The NFT identifier to remove from `previous`.
    public func removeFromPrevious(id: String) {
        previous._removeAll(where: { $0.id == id })
        previousTimestamps.removeValue(forKey: id)
        validateInvariants(context: "removeFromPrevious")
    }
}

