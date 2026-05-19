import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import OSLog
import SwiftData

/// Errors emitted by playlist persistence helpers.
public enum PlaylistError: Error, LocalizedError, Sendable {
    case notFound
    case invalidData(String)
    case saveFailed(underlying: Error)
    case fetchFailed(underlying: Error)
    case migrationFailed(underlying: Error)
    case corruptData

    /// A user-facing description for the failure.
    public var errorDescription: String? {
        switch self {
        case .notFound:
            return "Playlist not found."
        case .invalidData(let message):
            return "Invalid data: \(message)"
        case .saveFailed(let underlying):
            return "Failed to save data: \(underlying.localizedDescription)"
        case .fetchFailed(let underlying):
            return "Failed to fetch data: \(underlying.localizedDescription)"
        case .migrationFailed(let underlying):
            return "Migration failed: \(underlying.localizedDescription)"
        case .corruptData:
            return "Data is corrupted."
        }
    }
}

/// Lightweight wrapper that exposes a SwiftData container for playlist operations.
public struct PlaylistRepository: Sendable {
    /// The backing SwiftData container.
    public let container: ModelContainer

    /// Creates a repository around an existing SwiftData container.
    public init(container: ModelContainer) {
        self.container = container
    }

    /// Creates a fresh `ModelContext` bound to the repository container.
    public func context() -> ModelContext {
        ModelContext(container)
    }
}

private let logger = Logger(subsystem: "Auralis", category: "PlaylistCRUD")

struct PlaylistMutationSnapshot: Equatable, Sendable {
    let playlistID: UUID
    let title: String
    let itemCount: Int
    let affectedMediaIDs: [String]
}

struct PlaylistModificationSnapshot: Equatable, Sendable {
    let before: PlaylistMutationSnapshot
    let after: PlaylistMutationSnapshot
    let changedFields: [String]
}

@ModelActor
public actor PlaylistPersistenceStore {
    public func createPlaylist(
        title: String,
        description: String? = nil,
        imageRef: String? = nil,
        imageData: Data? = nil,
        trackIDs: [PersistentIdentifier] = []
    ) throws {
        _ = try createPlaylistReceiptSnapshot(
            title: title,
            description: description,
            imageRef: imageRef,
            imageData: imageData,
            trackIDs: trackIDs
        )
    }

    func createPlaylistReceiptSnapshot(
        title: String,
        description: String? = nil,
        imageRef: String? = nil,
        imageData: Data? = nil,
        trackIDs: [PersistentIdentifier] = []
    ) throws -> PlaylistMutationSnapshot {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw PlaylistError.invalidData("Title must not be empty.")
        }

        let tracks = trackIDs.compactMap { modelContext.model(for: $0) as? NFT }

        let playlist = Playlist(
            title: trimmedTitle,
            description: description,
            imageRef: imageRef,
            imageData: imageData,
            tracks: tracks
        )
        modelContext.insert(playlist)

        do {
            try modelContext.save()
            logger.log("Created playlist '\(trimmedTitle, privacy: .public)'.")
            return PlaylistMutationSnapshot(
                playlistID: playlist.id,
                title: playlist.title,
                itemCount: playlist.itemCount,
                affectedMediaIDs: playlist.tracks.map(\.id).sorted()
            )
        } catch {
            logger.error("Failed to create playlist '\(trimmedTitle, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            throw PlaylistError.saveFailed(underlying: error)
        }
    }

    public func deletePlaylist(id: UUID) throws {
        let predicate = #Predicate<Playlist> { $0.id == id }
        let descriptor = FetchDescriptor<Playlist>(predicate: predicate)

        do {
            let results = try modelContext.fetch(descriptor)
            guard let playlist = results.first else {
                logger.error("Failed to delete playlist by id \(id.uuidString, privacy: .public): not found.")
                throw PlaylistError.notFound
            }

            do {
                try modelContext.performRollbackSafeMutation {
                    modelContext.delete(playlist)
                }
                logger.log("Deleted playlist by id \(id.uuidString, privacy: .public).")
            } catch {
                logger.error("Failed to delete playlist by id \(id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
                throw PlaylistError.saveFailed(underlying: error)
            }
        } catch let error as PlaylistError {
            throw error
        } catch {
            logger.error("Failed to fetch playlist for deletion by id \(id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw PlaylistError.fetchFailed(underlying: error)
        }
    }
}

@MainActor
/// Convenience playlist persistence helpers layered onto `ModelContext`.
public extension ModelContext {
    @discardableResult
    internal func createPlaylist(
        title: String,
        description: String? = nil,
        imageRef: String? = nil,
        imageData: Data? = nil,
        tracks: [NFT] = [],
        musicReceiptLogger: MusicReceiptEventLogger,
        receiptContext: MusicReceiptContext
    ) async throws -> PlaylistMutationSnapshot {
        let persistenceStore = PlaylistPersistenceStore(modelContainer: container)
        let snapshot = try await persistenceStore.createPlaylistReceiptSnapshot(
            title: title,
            description: description,
            imageRef: imageRef,
            imageData: imageData,
            trackIDs: tracks.map(\.persistentModelID)
        )

        _ = try await musicReceiptLogger.recordPlaylistCreated(
            playlistID: snapshot.playlistID,
            playlistTitle: snapshot.title,
            affectedMediaIDs: snapshot.affectedMediaIDs,
            itemCount: snapshot.itemCount,
            context: receiptContext
        )

        return snapshot
    }

    @discardableResult
    /// Creates and persists a new playlist.
    func createPlaylist(
        title: String,
        description: String? = nil,
        imageRef: String? = nil,
        imageData: Data? = nil,
        tracks: [NFT] = []
    ) throws -> Playlist {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw PlaylistError.invalidData("Title must not be empty.")
        }
        let playlist = Playlist(
            title: trimmedTitle,
            description: description,
            imageRef: imageRef,
            imageData: imageData,
            tracks: tracks
        )
        insert(playlist)
        do {
            try save()
            logger.log("Created playlist '\(title, privacy: .public)'.")
            return playlist
        } catch {
            logger.error("Failed to create playlist '\(title, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            throw PlaylistError.saveFailed(underlying: error)
        }
    }

    internal func updatePlaylistReceiptSnapshot(
        _ playlist: Playlist,
        title: String? = nil,
        description: String? = nil,
        imageRef: String? = nil,
        items: [NFT]? = nil
    ) throws -> PlaylistModificationSnapshot {
        let before = PlaylistMutationSnapshot(
            playlistID: playlist.id,
            title: playlist.title,
            itemCount: playlist.itemCount,
            affectedMediaIDs: playlist.tracks.map(\.id).sorted()
        )

        if let title {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw PlaylistError.invalidData("Title must not be empty.")
            }
        }
        if let title {
            playlist.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let description {
            playlist.descriptionText = description
        }
        if let imageRef {
            playlist.imageRef = imageRef
        }
        if let items {
            playlist.tracks = items
        }

        let changedFields = [
            title == nil ? nil : "title",
            description == nil ? nil : "description",
            imageRef == nil ? nil : "imageRef",
            items == nil ? nil : "tracks"
        ].compactMap { $0 }

        do {
            try save()
            logger.log("Updated playlist '\(playlist.title, privacy: .public)'.")
            let after = PlaylistMutationSnapshot(
                playlistID: playlist.id,
                title: playlist.title,
                itemCount: playlist.itemCount,
                affectedMediaIDs: playlist.tracks.map(\.id).sorted()
            )
            return PlaylistModificationSnapshot(
                before: before,
                after: after,
                changedFields: changedFields
            )
        } catch {
            logger.error("Failed to update playlist '\(playlist.title, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            throw PlaylistError.saveFailed(underlying: error)
        }
    }

    internal func updatePlaylist(
        _ playlist: Playlist,
        title: String? = nil,
        description: String? = nil,
        imageRef: String? = nil,
        items: [NFT]? = nil,
        musicReceiptLogger: MusicReceiptEventLogger,
        receiptContext: MusicReceiptContext
    ) async throws {
        let snapshot = try updatePlaylistReceiptSnapshot(
            playlist,
            title: title,
            description: description,
            imageRef: imageRef,
            items: items
        )

        _ = try await musicReceiptLogger.recordPlaylistModified(
            playlistID: snapshot.after.playlistID,
            playlistTitle: snapshot.after.title,
            affectedMediaIDs: snapshot.after.affectedMediaIDs,
            beforeSummary: MusicReceiptStateSummary.playlist(
                playlistID: snapshot.before.playlistID,
                playlistTitle: snapshot.before.title,
                itemCount: snapshot.before.itemCount,
                changedFields: snapshot.changedFields
            ),
            afterSummary: MusicReceiptStateSummary.playlist(
                playlistID: snapshot.after.playlistID,
                playlistTitle: snapshot.after.title,
                itemCount: snapshot.after.itemCount,
                changedFields: snapshot.changedFields
            ),
            changedFields: snapshot.changedFields,
            context: receiptContext
        )
    }

    /// Updates mutable playlist fields and persists the changes.
    func updatePlaylist(
        _ playlist: Playlist,
        title: String? = nil,
        description: String? = nil,
        imageRef: String? = nil,
        items: [NFT]? = nil
    ) throws {
        _ = try updatePlaylistReceiptSnapshot(
            playlist,
            title: title,
            description: description,
            imageRef: imageRef,
            items: items
        )
    }

    /// Deletes a playlist and persists the removal.
    func deletePlaylist(_ playlist: Playlist) throws {
        do {
            try PlaylistDeletionService(modelContext: self).deletePlaylist(playlist)
            logger.log("Deleted playlist '\(playlist.title, privacy: .public)'.")
        } catch let error as PlaylistError {
            logger.error("Failed to delete playlist '\(playlist.title, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            throw error
        } catch {
            logger.error("Failed to delete playlist '\(playlist.title, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            throw PlaylistError.saveFailed(underlying: error)
        }
    }
}

/// Fetches all playlists using the provided sort order.
public func fetchAllPlaylists(
    _ context: ModelContext,
    sort: SortDescriptor<Playlist> = SortDescriptor(\.createdAt, order: .reverse)
) throws -> [Playlist] {
    do {
        let playlists = try context.fetch(
            FetchDescriptor<Playlist>(sortBy: [sort])
        )
        logger.log("Fetched all playlists, count: \(playlists.count, privacy: .public).")
        return playlists
    } catch {
        logger.error("Failed to fetch all playlists: \(error.localizedDescription, privacy: .public)")
        throw PlaylistError.fetchFailed(underlying: error)
    }
}

/// Searches playlists by title and description text.
public func searchPlaylists(
    _ context: ModelContext,
    searchText: String
) throws -> [Playlist] {
    do {
        let predicate = #Predicate<Playlist> {
            $0.title.localizedStandardContains(searchText) ||
            ($0.descriptionText ?? "").localizedStandardContains(searchText)
        }
        let fetchDescriptor = FetchDescriptor<Playlist>(predicate: predicate)
        let playlists = try context.fetch(fetchDescriptor)
        logger.log("Searched playlists with '\(searchText, privacy: .public)', found: \(playlists.count, privacy: .public).")
        return playlists
    } catch {
        logger.error("Failed to search playlists with '\(searchText, privacy: .public)': \(error.localizedDescription, privacy: .public)")
        throw PlaylistError.fetchFailed(underlying: error)
    }
}

/// Fetches a playlist by identifier.
public func fetchPlaylist(
    _ context: ModelContext,
    by id: UUID
) throws -> Playlist? {
    do {
        let predicate = #Predicate<Playlist> { $0.id == id }
        let descriptor = FetchDescriptor<Playlist>(predicate: predicate)
        let results = try context.fetch(descriptor)
        logger.log("Fetched playlist by id \(id.uuidString, privacy: .public), found: \(results.first != nil, privacy: .public).")
        return results.first
    } catch {
        logger.error("Failed to fetch playlist by id \(id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        throw PlaylistError.fetchFailed(underlying: error)
    }
}

/// Deletes a playlist by identifier.
public func deletePlaylist(
    _ context: ModelContext,
    by id: UUID
) throws {
    // First, attempt to fetch the playlist by id
    let predicate = #Predicate<Playlist> { $0.id == id }
    let descriptor = FetchDescriptor<Playlist>(predicate: predicate)

    do {
        let results = try context.fetch(descriptor)
        guard let playlist = results.first else {
            logger.error("Failed to delete playlist by id \(id.uuidString, privacy: .public): not found.")
            throw PlaylistError.notFound
        }

        do {
            context.delete(playlist)
            try context.save()
            logger.log("Deleted playlist by id \(id.uuidString, privacy: .public).")
        } catch {
            logger.error("Failed to delete playlist by id \(id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw PlaylistError.saveFailed(underlying: error)
        }
    } catch let error as PlaylistError {
        throw error
    } catch {
        logger.error("Failed to fetch playlist for deletion by id \(id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        throw PlaylistError.fetchFailed(underlying: error)
    }
}
