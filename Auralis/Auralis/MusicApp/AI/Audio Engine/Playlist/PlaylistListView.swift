import SwiftUI
import SwiftData
import OSLog

struct PlaylistListView: View {
    @Environment(\.modelContext) var modelContext
    @State private var searchText: String = ""
    @Query(sort: \Playlist.createdAt, order: .reverse) private var playlists: [Playlist]

    private var filteredPlaylists: [Playlist] {
        let t = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return playlists }
        return playlists.filter { p in
            p.title.localizedStandardContains(t) || (p.descriptionText ?? "").localizedStandardContains(t)
        }
    }

    var body: some View {
        NavigationStack {
            list
        }
        .toolbar { toolbar }
    }

    private var list: some View {
        List {
            ForEach(filteredPlaylists) { pl in
                VStack(alignment: .leading) {
                    Text(pl.title).font(.headline)
                    if let d = pl.descriptionText, !d.isEmpty {
                        Text(d).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text("Items: \(pl.itemCount)")
                }
                .swipeActions {
                    Button(role: .destructive) {
                        delete(pl)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .searchable(text: $searchText)
    }

    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                addSample()
            } label: {
                Label("Add", systemImage: "plus")
            }
        }
    }

    @MainActor private func addSample() {
        do {
            let _ = try modelContext.createPlaylist(title: "New Playlist", description: nil, imageRef: nil, tracks: [])
        } catch {
            Logger(subsystem: "Auralis", category: "PlaylistUI").error("Add failed: \(String(describing: error))")
        }
    }

    @MainActor private func delete(_ pl: Playlist) {
        do {
            try modelContext.deletePlaylist(pl)
        } catch {
            Logger(subsystem: "Auralis", category: "PlaylistUI").error("Delete failed: \(String(describing: error))")
        }
    }
}

#Preview {
    PlaylistListView()
        .modelContainer(for: Playlist.self, inMemory: true)
}
