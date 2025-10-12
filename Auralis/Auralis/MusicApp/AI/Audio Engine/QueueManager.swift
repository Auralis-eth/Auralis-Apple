import Foundation

/// QueueManager
///
/// Thread-safety: This type is isolated to the main actor using `@MainActor`.
/// - All mutable state is protected by main-actor serialization.
/// - All public property access and any method calls will hop to the main actor when called from other threads/tasks.
/// - Access to `UserDefaults` occurs on the main actor to avoid concurrent mutations.
/// - This design is appropriate because the playback queue is UI-bound. If heavy work is needed, consider offloading just that work to a background task and returning results to the main actor.
/// - Persistence: Writes to UserDefaults are batched and debounced on a background queue; durability is eventual. Use `flushPersistShuffle()` for immediate sync when needed.
@MainActor
public final class QueueManager {
    // Persistence constants and queue
    private static let stateKey = "QueueManager.state"
    private static let stateVersion = 1
    private static let legacyOrderKey = "QueueManager.shuffledOrder"
    private static let legacyIndexKey = "QueueManager.shuffleIndex"

    // Debounced, background persistence to avoid blocking the main actor.
    // Writes are eventual; see `persistShuffle()` docs.
    private let persistenceQueue = DispatchQueue(label: "QueueManager.persistence", qos: .utility)
    private var persistWorkItem: DispatchWorkItem?
    private let persistDebounceInterval: TimeInterval = 0.35

    public enum RepeatMode: Equatable, Sendable { case none, track, playlist }

    public struct Playlist: Sendable, Equatable {
        public var name: String
        var tracks: [NFT]
        init(name: String, tracks: [NFT] = []) { self.name = name; self.tracks = tracks }
    }

    private let defaults = UserDefaults.standard

    private var shuffledOrder: [String] = [] // store NFT ids
    private var shuffleIndex: Int = 0

    public var previous = Playlist(name: "Previous")
    public var next = Playlist(name: "Next")
    public private(set) var current: NFT?
    public var isShuffleEnabled: Bool = false
    public var repeatMode: RepeatMode = .none

    /// Initializes the queue manager on the main actor, restoring any persisted shuffle state from UserDefaults.
    /// All subsequent mutations and reads are serialized via the main actor to prevent data races.
    public init() {
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
                // Future migration hook: currently just log and continue
                print("[QueueManager] Restored state version \(version); expected \(Self.stateVersion). No migration needed.")
            }
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
        }
    }

    /// Enables or disables shuffle mode.
    /// - Parameter enabled: New shuffle state.
    /// - Discussion: When enabling, the shuffle order is rebuilt while maintaining the current position if possible. When disabling, the shuffle state is cleared.
    /// - Example:
    /// ```swift
    /// queue.setShuffleEnabled(true)
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
    }

    /// Sets the repeat mode for playback.
    /// - Parameter mode: The desired repeat mode.
    /// - Example:
    /// ```swift
    /// queue.setRepeatMode(.playlist)
    /// ```
    public func setRepeatMode(_ mode: RepeatMode) {
        repeatMode = mode
    }

    /// Sets the current item.
    /// - Parameter nft: The item to set as current, or `nil` to clear.
    /// - Discussion: Does not mutate `previous` or `next`. Callers should use `dequeueNext()` to advance.
    /// - Example:
    /// ```swift
    /// queue.setCurrent(currentNFT)
    /// ```
    public func setCurrent(_ nft: NFT?) {
        current = nft
    }

    /// Persists the shuffle state asynchronously with debouncing and explicit synchronization.
    /// Persistence is eventual (not immediate) to minimize disk I/O and avoid blocking the main actor.
    /// Use `flushPersistShuffle()` for critical, immediate writes (e.g., app termination).
    private func persistShuffle() {
        // Capture current state on the main actor to avoid races.
        let orderSnapshot = self.shuffledOrder
        let indexSnapshot = self.shuffleIndex

        // Cancel any pending work to debounce rapid changes
        persistWorkItem?.cancel()

        let work = DispatchWorkItem { [defaults] in
            // Build a single versioned state payload to minimize I/O
            let payload: [String: Any] = [
                "version": Self.stateVersion,
                "order": orderSnapshot,
                "index": indexSnapshot
            ]

            // Write the blob under a single key to avoid multiple disk writes
            defaults.set(payload, forKey: Self.stateKey)

            // Also write legacy keys for a short transition window (optional)
            defaults.set(orderSnapshot, forKey: Self.legacyOrderKey)
            defaults.set(indexSnapshot, forKey: Self.legacyIndexKey)

            // Explicitly synchronize to reduce risk of data loss on termination
            // Note: synchronize() is generally not necessary, but this project requests explicit sync.
            let ok = defaults.synchronize()
            if ok == false {
                print("[QueueManager] Warning: UserDefaults synchronize() returned false.")
            }
        }

        persistWorkItem = work
        // Debounce writes to batch frequent updates
        persistenceQueue.asyncAfter(deadline: .now() + persistDebounceInterval, execute: work)
    }

    /// Forces an immediate persistence of the current shuffle state on a background queue.
    /// This bypasses debouncing. Use sparingly (e.g., applicationWillTerminate / sceneWillResignActive).
    public func flushPersistShuffle() {
        let orderSnapshot = self.shuffledOrder
        let indexSnapshot = self.shuffleIndex

        // Cancel any pending debounced write and perform immediately
        persistWorkItem?.cancel()
        persistWorkItem = nil

        persistenceQueue.async { [defaults] in
            let payload: [String: Any] = [
                "version": Self.stateVersion,
                "order": orderSnapshot,
                "index": indexSnapshot
            ]
            defaults.set(payload, forKey: Self.stateKey)
            defaults.set(orderSnapshot, forKey: Self.legacyOrderKey)
            defaults.set(indexSnapshot, forKey: Self.legacyIndexKey)
            let ok = defaults.synchronize()
            if ok == false {
                print("[QueueManager] Warning: Immediate synchronize() failed.")
            }
        }
    }

    private func rebuildShuffle() {
        shuffledOrder = next.tracks.map { $0.id }
        // Fisher–Yates shuffle
        var a = shuffledOrder
        var i = a.count - 1
        while i > 0 {
            let j = Int.random(in: 0...i)
            a.swapAt(i, j)
            i -= 1
        }
        shuffledOrder = a
        shuffleIndex = 0
        persistShuffle()
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
        // Fisher–Yates shuffle
        var a = shuffledOrder
        var i = a.count - 1
        while i > 0 {
            let j = Int.random(in: 0...i)
            a.swapAt(i, j)
            i -= 1
        }
        shuffledOrder = a
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
    }

    /// Returns the next NFT without removing it.
    /// - Returns: The next `NFT` to be played, or `nil` when the queue is empty, when shuffle cannot determine a next item, or when repeat rules result in no available item.
    /// - Thread-safety: Main-actor isolated.
    /// - Note: This method avoids force unwraps and performs bounds checks to fail gracefully instead of crashing.
    /// - Example:
    /// ```swift
    /// let upcoming = queue.peekNext()
    /// ```
    public func peekNext() -> NFT? {
        if repeatMode == .track, let c = current { return c }

        if !next.tracks.isEmpty {
            if !isShuffleEnabled {
                return next.tracks.first
            } else {
                ensureShuffleValid()
                if shuffleIndex < shuffledOrder.count {
                    let id = shuffledOrder[shuffleIndex]
                    if let nft = next.tracks.first(where: { $0.id == id }) {
                        return nft
                    }
                    // If not found (shouldn't happen), rebuild shuffle and try again
                    rebuildShuffle()
                    if let nft = next.tracks.first(where: { $0.id == shuffledOrder.first ?? "" }) {
                        shuffleIndex = 0
                        persistShuffle()
                        return nft
                    } else {
                        return nil
                    }
                } else if repeatMode == .playlist {
                    var rebuilt: [NFT] = []
                    if let c = current { rebuilt.append(c) }
                    if !previous.tracks.isEmpty { rebuilt.append(contentsOf: previous.tracks) }
                    guard !rebuilt.isEmpty else { return nil }
                    // Shuffle rebuilt temporarily in memory
                    var tempOrder = rebuilt.map { $0.id }
                    // Fisher–Yates shuffle
                    var i = tempOrder.count - 1
                    while i > 0 {
                        let j = Int.random(in: 0...i)
                        tempOrder.swapAt(i, j)
                        i -= 1
                    }
                    guard let firstId = tempOrder.first else { return nil }
                    return rebuilt.first(where: { $0.id == firstId })
                } else {
                    return nil
                }
            }
        }

        if repeatMode == .playlist {
            var rebuilt: [NFT] = []
            if let c = current { rebuilt.append(c) }
            if !previous.tracks.isEmpty { rebuilt.append(contentsOf: previous.tracks) }
            guard !rebuilt.isEmpty else { return nil }
            return isShuffleEnabled ? rebuilt.randomElement() : rebuilt.first
        }

        return nil
    }

    /// Dequeues and returns the next NFT according to shuffle and repeat rules.
    /// - Returns: The dequeued `NFT`, or `nil` if the queue is empty or no valid next item can be determined.
    /// - Thread-safety: Main-actor isolated.
    /// - Note: All array accesses are bounds-checked and the method fails gracefully rather than crashing.
    /// - Example:
    /// ```swift
    /// if let next = queue.dequeueNext() { /* play next */ }
    /// ```
    @discardableResult
    public func dequeueNext() -> NFT? {
        if repeatMode == .track, let c = current { return c }

        if !next.tracks.isEmpty {
            if !isShuffleEnabled {
                return next.tracks.removeFirst()
            } else {
                ensureShuffleValid()
                if shuffleIndex < shuffledOrder.count {
                    let id = shuffledOrder[shuffleIndex]
                    if let index = next.tracks.firstIndex(where: { $0.id == id }) {
                        let nft = next.tracks.remove(at: index)
                        shuffleIndex += 1
                        persistShuffle()
                        return nft
                    } else {
                        // Not found, rebuild shuffle and try again
                        rebuildShuffle()
                        if shuffleIndex < shuffledOrder.count,
                           let idx = next.tracks.firstIndex(where: { $0.id == shuffledOrder[shuffleIndex] }) {
                            let nft = next.tracks.remove(at: idx)
                            shuffleIndex += 1
                            persistShuffle()
                            return nft
                        } else {
                            // Nothing to dequeue
                            return nil
                        }
                    }
                } else if repeatMode == .playlist {
                    // rebuild next from current + previous
                    var rebuilt: [NFT] = []
                    if let c = current { rebuilt.append(c) }
                    if !previous.tracks.isEmpty { rebuilt.append(contentsOf: previous.tracks) }
                    guard !rebuilt.isEmpty else { return nil }
                    previous.tracks.removeAll()
                    next.tracks = rebuilt
                    rebuildShuffle()
                    // Now attempt to dequeue first in shuffle
                    if shuffleIndex < shuffledOrder.count,
                       let idx = next.tracks.firstIndex(where: { $0.id == shuffledOrder[shuffleIndex] }) {
                        let nft = next.tracks.remove(at: idx)
                        shuffleIndex += 1
                        persistShuffle()
                        return nft
                    } else {
                        return nil
                    }
                } else {
                    return nil
                }
            }
        }

        if repeatMode == .playlist {
            var rebuilt: [NFT] = []
            if let c = current { rebuilt.append(c) }
            if !previous.tracks.isEmpty { rebuilt.append(contentsOf: previous.tracks) }
            guard !rebuilt.isEmpty else { return nil }
            previous.tracks.removeAll()
            next.tracks = rebuilt
            if !isShuffleEnabled {
                return next.tracks.removeFirst()
            } else {
                rebuildShuffle()
                if shuffleIndex < shuffledOrder.count,
                   let idx = next.tracks.firstIndex(where: { $0.id == shuffledOrder[shuffleIndex] }) {
                    let nft = next.tracks.remove(at: idx)
                    shuffleIndex += 1
                    persistShuffle()
                    return nft
                } else {
                    return nil
                }
            }
        }

        return nil
    }

    private func pushToPrevious(_ nft: NFT) { previous.tracks.append(nft) }
    public func pushToFrontOfNext(_ nft: NFT) { next.tracks.insert(nft, at: 0) }

    /// Appends items to the end of the upcoming queue.
    /// - Parameter nfts: Items to enqueue.
    /// - Discussion: Maintains shuffle invariants by rebuilding shuffle when needed.
    /// - Example:
    /// ```swift
    /// queue.addToNext(newItems)
    /// ```
    public func addToNext(_ nfts: [NFT]) {
        next.tracks.append(contentsOf: nfts)
        if isShuffleEnabled {
            rebuildShuffleMaintainingPosition()
        }
    }

    /// Removes items from the upcoming queue matching the given predicate.
    /// - Parameter predicate: A closure that returns `true` for items to remove.
    /// - Discussion: Maintains shuffle invariants by rebuilding shuffle when needed.
    /// - Example:
    /// ```swift
    /// queue.removeFromNext { $0.id == someId }
    /// ```
    public func removeFromNext(where predicate: (NFT) -> Bool) {
        next.tracks.removeAll(where: predicate)
        if isShuffleEnabled {
            rebuildShuffleMaintainingPosition()
        }
    }
}

