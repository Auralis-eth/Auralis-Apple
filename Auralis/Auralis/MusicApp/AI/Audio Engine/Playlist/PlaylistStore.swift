import Foundation
import SwiftData
import OSLog

private let playlistStoreLogger = Logger(subsystem: "Auralis", category: "PlaylistStore")

/// Errors emitted while mutating playlist items.
public enum PlaylistItemError: Error, LocalizedError, Sendable {
    case duplicateItem
    case indexOutOfBounds
    case notFound
    case invalidOperation(String)
    case saveFailed(underlying: Error)
    case fetchFailed(underlying: Error)

    /// A user-facing description for the failure.
    public var errorDescription: String? {
        switch self {
        case .duplicateItem:
            return "Item already exists in the playlist."
        case .indexOutOfBounds:
            return "Index is out of bounds for the playlist."
        case .notFound:
            return "Item not found."
        case .invalidOperation(let message):
            return message
        case .saveFailed(let underlying):
            return "Failed to save: \(underlying.localizedDescription)"
        case .fetchFailed(let underlying):
            return "Failed to fetch: \(underlying.localizedDescription)"
        }
    }
}

@MainActor
/// Main-actor wrapper for mutating playlist membership safely through SwiftData.
public final class PlaylistStore {
    private let context: ModelContext
    private let allowDuplicates: Bool

    /// Creates a playlist store for a specific model context.
    public init(context: ModelContext, allowDuplicates: Bool = false) {
        self.context = context
        self.allowDuplicates = allowDuplicates
    }
}

private extension PlaylistStore {
    func fetchNFT(by id: String) throws -> NFT? {
        do {
            let predicate = #Predicate<NFT> { $0.id == id }
            let fd = FetchDescriptor<NFT>(predicate: predicate)
            return try context.fetch(fd).first
        } catch {
            throw PlaylistItemError.fetchFailed(underlying: error)
        }
    }

    func ensurePlaylistExists(_ playlist: Playlist) throws {
        do {
            let pid = playlist.id
            let predicate = #Predicate<Playlist> { $0.id == pid }
            let fd = FetchDescriptor<Playlist>(predicate: predicate)
            let exists = try context.fetch(fd).first != nil
            if !exists { throw PlaylistError.notFound }
        } catch let err as PlaylistError {
            throw err
        } catch {
            throw PlaylistItemError.fetchFailed(underlying: error)
        }
    }
}

public extension PlaylistStore {
    @discardableResult
    /// Adds a single NFT to a playlist.
    func addItem(trackId: String, to playlist: Playlist, at index: Int? = nil) async throws -> Playlist {
        try ensurePlaylistExists(playlist)
        guard let nft = try fetchNFT(by: trackId) else { throw PlaylistItemError.notFound }

        // Duplicate prevention (unless allowed)
        if !allowDuplicates, playlist.tracks.contains(where: { $0.id == trackId }) {
            throw PlaylistItemError.duplicateItem
        }

        // Optimistic update
        let previous = playlist.tracks
        let previousUpdatedAt = playlist.updatedAt
        if let idx = index {
            guard idx >= 0 && idx <= previous.count else { throw PlaylistItemError.indexOutOfBounds }
            playlist.tracks.insert(nft, at: idx)
        } else {
            playlist.tracks.append(nft)
        }
        playlist.updatedAt = Date()

        do {
            try context.save()
            playlistStoreLogger.log("Added item \(trackId, privacy: .public) to playlist \(playlist.title, privacy: .public)")
            return playlist
        } catch {
            // Rollback
            playlist.tracks = previous
            playlist.updatedAt = previousUpdatedAt
            throw PlaylistItemError.saveFailed(underlying: error)
        }
    }

    @discardableResult
    /// Removes a single NFT from a playlist using its track identifier.
    func removeItem(trackId: String, from playlist: Playlist) async throws -> Playlist {
        try ensurePlaylistExists(playlist)
        guard let idx = playlist.tracks.firstIndex(where: { $0.id == trackId }) else {
            throw PlaylistItemError.notFound
        }
        return try await removeItem(at: idx, from: playlist)
    }

    @discardableResult
    /// Removes a single NFT from a playlist using its current index.
    func removeItem(at index: Int, from playlist: Playlist) async throws -> Playlist {
        try ensurePlaylistExists(playlist)
        let count = playlist.tracks.count
        guard index >= 0 && index < count else { throw PlaylistItemError.indexOutOfBounds }

        // Optimistic update
        let previous = playlist.tracks
        let previousUpdatedAt = playlist.updatedAt
        playlist.tracks.remove(at: index)
        playlist.updatedAt = Date()

        do {
            try context.save()
            playlistStoreLogger.log("Removed item at index \(index) from playlist \(playlist.title, privacy: .public)")
            return playlist
        } catch {
            // Rollback
            playlist.tracks = previous
            playlist.updatedAt = previousUpdatedAt
            throw PlaylistItemError.saveFailed(underlying: error)
        }
    }

    @discardableResult
    /// Moves one item to a new index inside the playlist.
    func moveItem(in playlist: Playlist, from sourceIndex: Int, to destinationIndex: Int) async throws -> Playlist {
        try ensurePlaylistExists(playlist)
        let count = playlist.tracks.count
        guard sourceIndex >= 0 && sourceIndex < count else { throw PlaylistItemError.indexOutOfBounds }
        guard destinationIndex >= 0 && destinationIndex <= count else { throw PlaylistItemError.indexOutOfBounds }
        guard sourceIndex != destinationIndex else { return playlist }

        let previous = playlist.tracks
        let previousUpdatedAt = playlist.updatedAt

        // Perform stable move similar to SwiftUI List move behavior
        var items = playlist.tracks
        let moving = items.remove(at: sourceIndex)
        items.insert(moving, at: min(destinationIndex, items.count))
        playlist.tracks = items
        playlist.updatedAt = Date()

        do {
            try context.save()
            playlistStoreLogger.log("Moved item in playlist \(playlist.title, privacy: .public) from \(sourceIndex) to \(destinationIndex)")
            return playlist
        } catch {
            playlist.tracks = previous
            playlist.updatedAt = previousUpdatedAt
            throw PlaylistItemError.saveFailed(underlying: error)
        }
    }

    @discardableResult
    /// Moves a block of items to a new destination index inside the playlist.
    func moveItems(in playlist: Playlist, from sourceIndices: IndexSet, to destinationIndex: Int) async throws -> Playlist {
        try ensurePlaylistExists(playlist)

        let count = playlist.tracks.count
        guard destinationIndex >= 0 && destinationIndex <= count else { throw PlaylistItemError.indexOutOfBounds }
        guard !sourceIndices.isEmpty else { return playlist }

        // Validate all source indices
        let maxIndex = count - 1
        guard sourceIndices.allSatisfy({ $0 >= 0 && $0 <= maxIndex }) else { throw PlaylistItemError.indexOutOfBounds }

        // Optimistic update
        let previous = playlist.tracks
        let previousUpdatedAt = playlist.updatedAt

        var items = playlist.tracks

        // Remove selected items in descending order to keep indices valid during removal
        let removedInSourceOrder: [NFT] = sourceIndices.sorted(by: >).map { items.remove(at: $0) }.reversed()

        // Adjust destination to account for items removed before the destination
        let adjustedDestination = destinationIndex - sourceIndices.filter { $0 < destinationIndex }.count

        // Insert the removed block preserving original relative order
        items.insert(contentsOf: removedInSourceOrder, at: adjustedDestination)

        playlist.tracks = items
        playlist.updatedAt = Date()

        do {
            try context.save()
            playlistStoreLogger.log("Batch moved items in playlist \(playlist.title, privacy: .public) to index \(destinationIndex)")
            return playlist
        } catch {
            // Rollback
            playlist.tracks = previous
            playlist.updatedAt = previousUpdatedAt
            throw PlaylistItemError.saveFailed(underlying: error)
        }
    }
}

public extension PlaylistStore {
    @discardableResult
    /// Adds multiple NFTs to a playlist in order.
    func addItems(trackIds: [String], to playlist: Playlist, at index: Int? = nil) async throws -> Playlist {
        try ensurePlaylistExists(playlist)
        if !allowDuplicates {
            // Filter out IDs that already exist
            let existing = Set(playlist.tracks.map { $0.id })
            let filtered = trackIds.filter { !existing.contains($0) }
            return try await addResolvedItems(ids: filtered, to: playlist, at: index)
        } else {
            return try await addResolvedItems(ids: trackIds, to: playlist, at: index)
        }
    }

    private func addResolvedItems(ids: [String], to playlist: Playlist, at index: Int?) async throws -> Playlist {
        // Resolve all NFTs first
        var resolved: [NFT] = []
        resolved.reserveCapacity(ids.count)
        for id in ids {
            guard let nft = try fetchNFT(by: id) else { throw PlaylistItemError.notFound }
            resolved.append(nft)
        }

        let previous = playlist.tracks
        let previousUpdatedAt = playlist.updatedAt
        if let idx = index {
            guard idx >= 0 && idx <= previous.count else { throw PlaylistItemError.indexOutOfBounds }
            playlist.tracks.insert(contentsOf: resolved, at: idx)
        } else {
            playlist.tracks.append(contentsOf: resolved)
        }
        playlist.updatedAt = Date()

        do {
            try context.save()
            playlistStoreLogger.log("Batch-added \(ids.count) items to playlist \(playlist.title, privacy: .public)")
            return playlist
        } catch {
            playlist.tracks = previous
            playlist.updatedAt = previousUpdatedAt
            throw PlaylistItemError.saveFailed(underlying: error)
        }
    }
}
