import AuralisPrimaryModels
import AuralisPrimaryPersistence
import SwiftData

@MainActor
protocol PlaylistDeleting {
    func deletePlaylist(_ playlist: Playlist) throws
}

@MainActor
struct PlaylistDeletionService: PlaylistDeleting {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func deletePlaylist(_ playlist: Playlist) throws {
        do {
            let undoSnapshot = Playlist(
                title: playlist.title,
                description: playlist.descriptionText,
                imageRef: playlist.imageRef,
                imageData: playlist.imageData,
                tracks: playlist.tracks,
                id: playlist.id,
                createdAt: playlist.createdAt,
                updatedAt: playlist.updatedAt
            )

            try modelContext.performUndoableMutation(named: "Delete Playlist") {
                modelContext.delete(playlist)
            }

            modelContext.undoManager?.registerUndo(withTarget: modelContext) { context in
                context.insert(undoSnapshot)
                try? context.save()
            }
        } catch {
            throw PlaylistError.saveFailed(underlying: error)
        }
    }
}
