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
            try modelContext.performUndoableMutation(named: "Delete Playlist") {
                modelContext.delete(playlist)
            }
        } catch {
            throw PlaylistError.saveFailed(underlying: error)
        }
    }
}
