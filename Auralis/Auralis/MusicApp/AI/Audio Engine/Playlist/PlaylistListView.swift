import SwiftUI
import SwiftData
import OSLog

struct PlaylistListView: View {
    @Environment(\.modelContext) var modelContext
    @State private var searchText: String = ""
    @Query(sort: \Playlist.createdAt, order: .reverse) private var playlists: [Playlist]

    @State private var showingNewPlaylist: Bool = false
    @State private var successMessage: String? = nil

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
        .sheet(isPresented: $showingNewPlaylist) {
            NewPlaylistView { createdTitle in
                successMessage = String(format: NSLocalizedString("Created \"%@\"", comment: "Success message after creating playlist"), createdTitle)
            }
        }
        .alert(isPresented: .init(get: { successMessage != nil }, set: { if !$0 { successMessage = nil } })) {
            Alert(title: Text(successMessage ?? ""))
        }
        .toolbar { toolbar }
    }

    private var list: some View {
        List {
            ForEach(filteredPlaylists) { pl in
                HStack(alignment: .center, spacing: 12) {
                    if let data = pl.imageData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                            .accessibilityHidden(true)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.1))
                            .frame(width: 56, height: 56)
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.system(size: 20, weight: .regular))
                                    .foregroundColor(.secondary)
                            )
                            .accessibilityHidden(true)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(pl.title)
                            .font(.headline)
                        if let d = pl.descriptionText, !d.isEmpty {
                            Text(d)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Text("Items: \(pl.itemCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
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
                showingNewPlaylist = true
            } label: {
                Label("Add", systemImage: "plus")
            }
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
