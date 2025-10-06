import Foundation

public final class QueueManager {
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
    var current: NFT?
    public var isShuffleEnabled: Bool = false
    public var repeatMode: RepeatMode = .none

    public init() {
        if let saved = defaults.array(forKey: "QueueManager.shuffledOrder") as? [String] {
            shuffledOrder = saved
        }
        shuffleIndex = defaults.integer(forKey: "QueueManager.shuffleIndex")
    }

    private func persistShuffle() {
        defaults.set(shuffledOrder, forKey: "QueueManager.shuffledOrder")
        defaults.set(shuffleIndex, forKey: "QueueManager.shuffleIndex")
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

    func peekNext() -> NFT? {
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
                    let firstId = tempOrder.first!
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

    @discardableResult
    func dequeueNext() -> NFT? {
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

    func pushToPrevious(_ nft: NFT) { previous.tracks.append(nft) }
    func pushToFrontOfNext(_ nft: NFT) { next.tracks.insert(nft, at: 0) }

    func addToNext(_ nfts: [NFT]) {
        next.tracks.append(contentsOf: nfts)
        if isShuffleEnabled {
            rebuildShuffleMaintainingPosition()
        }
    }

    func removeFromNext(where predicate: (NFT) -> Bool) {
        next.tracks.removeAll(where: predicate)
        if isShuffleEnabled {
            rebuildShuffleMaintainingPosition()
        }
    }
}
