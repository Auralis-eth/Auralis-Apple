import Foundation

public final class QueueManager {
    public enum RepeatMode: Equatable, Sendable { case none, track, playlist }

    public struct Playlist: Sendable, Equatable {
        public var name: String
        var tracks: [NFT]
        init(name: String, tracks: [NFT] = []) { self.name = name; self.tracks = tracks }
    }

    public var previous = Playlist(name: "Previous")
    public var next = Playlist(name: "Next")
    var current: NFT?
    public var isShuffleEnabled: Bool = false
    public var repeatMode: RepeatMode = .none

    public init() {}

    func peekNext() -> NFT? {
        if repeatMode == .track, let c = current { return c }
        if !next.tracks.isEmpty { return isShuffleEnabled ? next.tracks.randomElement() : next.tracks.first }
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
            if isShuffleEnabled { return next.tracks.remove(at: Int.random(in: 0..<next.tracks.count)) }
            return next.tracks.removeFirst()
        }
        if repeatMode == .playlist {
            var rebuilt: [NFT] = []
            if let c = current { rebuilt.append(c) }
            if !previous.tracks.isEmpty { rebuilt.append(contentsOf: previous.tracks) }
            guard !rebuilt.isEmpty else { return nil }
            previous.tracks.removeAll()
            next.tracks = rebuilt
            if isShuffleEnabled { return next.tracks.remove(at: Int.random(in: 0..<next.tracks.count)) }
            return next.tracks.removeFirst()
        }
        return nil
    }

    func pushToPrevious(_ nft: NFT) { previous.tracks.append(nft) }
    func pushToFrontOfNext(_ nft: NFT) { next.tracks.insert(nft, at: 0) }
}
