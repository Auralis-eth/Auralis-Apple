import AuraUI
import SwiftData
import SwiftUI

/// Fetches a collection/creator detail item list through the typed query
/// service, then renders the shared detail list.
struct LibraryGroupDetailLoaderView: View {
    let model: AuraPlayRootModel
    let group: LibraryGroupKey
    let title: String
    let systemImage: String
    let sort: MediaItemSort
    let currentTrackID: String?
    let origin: AuraPlayQueueOriginPresentation
    let onOpenItem: (String) -> Void
    let onPlayItem: (String, [MediaItemQueryItem], AuraPlayQueueOriginPresentation) async -> Void
    let onAddToPlaylist: (String) -> Void

    @State private var items: [MediaItemQueryItem] = []

    var body: some View {
        LibraryGroupDetailView(
            title: title,
            subtitle: "\(items.count) media items",
            systemImage: systemImage,
            items: items,
            currentTrackID: currentTrackID,
            onOpenItem: onOpenItem,
            onPlayItem: { id in await onPlayItem(id, items, origin) },
            onAddToPlaylist: onAddToPlaylist
        )
        .task(id: taskKey) {
            items = await model.groupItems(group, sort: sort)
        }
    }

    private var taskKey: String {
        let groupKey: String
        switch group {
        case .collection(let id):
            groupKey = "collection|\(id)"
        case .creator(let id):
            groupKey = "creator|\(id)"
        }
        return "\(groupKey)|\(sort.rawValue)"
    }
}

/// Resolves playlist rows into ordered query items before rendering.
public struct LibraryPlaylistDetailLoaderView: View {
    let model: AuraPlayRootModel
    let playlist: AuraPlayPlaylistSnapshot
    let currentTrackID: String?
    let rename: (() -> Void)?
    let delete: (() -> Void)?
    let onOpenItem: (String) -> Void
    let onPlayItem: (String, [MediaItemQueryItem], AuraPlayQueueOriginPresentation) async -> Void
    let onRemoveItem: ((String) -> Void)?
    let onMoveItem: ((Int, Int) -> Void)?

    @State private var items: [MediaItemQueryItem] = []

    public init(
        model: AuraPlayRootModel,
        playlist: AuraPlayPlaylistSnapshot,
        currentTrackID: String?,
        rename: (() -> Void)? = nil,
        delete: (() -> Void)? = nil,
        onOpenItem: @escaping (String) -> Void,
        onPlayItem: @escaping (String, [MediaItemQueryItem], AuraPlayQueueOriginPresentation) async -> Void,
        onRemoveItem: ((String) -> Void)? = nil,
        onMoveItem: ((Int, Int) -> Void)? = nil
    ) {
        self.model = model
        self.playlist = playlist
        self.currentTrackID = currentTrackID
        self.rename = rename
        self.delete = delete
        self.onOpenItem = onOpenItem
        self.onPlayItem = onPlayItem
        self.onRemoveItem = onRemoveItem
        self.onMoveItem = onMoveItem
    }

    public var body: some View {
        LibraryPlaylistDetailView(
            playlist: playlist,
            items: items,
            currentTrackID: currentTrackID,
            rename: rename,
            delete: delete,
            onOpenItem: onOpenItem,
            onPlayItem: { id in await onPlayItem(id, items, .playlist(id: playlist.id)) },
            onRemoveItem: onRemoveItem,
            onMoveItem: onMoveItem
        )
        .task(id: taskKey) {
            let fetched = await model.items(withIDs: playlist.itemIDs)
            items = playlist.itemIDs.compactMap { mediaItemID in
                fetched.first { $0.sourceNFTID == mediaItemID || $0.id == mediaItemID }
            }
        }
    }

    private var taskKey: String {
        "\(playlist.id)|\(playlist.updatedAt.timeIntervalSince1970)|\(playlist.itemCount)"
    }
}

struct CreatorProfileLoaderView: View {
    let model: AuraPlayRootModel
    let creatorIdentifier: String
    let fallbackTitle: String
    let accountAddresses: [String]
    let sort: MediaItemSort
    let currentTrackID: String?
    let onOpenItem: (String) -> Void
    let onPlayItem: (String, [MediaItemQueryItem], AuraPlayQueueOriginPresentation) async -> Void
    let onAddToPlaylist: (String) -> Void

    @State private var profile: AuraPlayCreatorProfile?

    var body: some View {
        CreatorProfileView(
            profile: profile,
            fallbackTitle: fallbackTitle,
            currentTrackID: currentTrackID,
            onOpenItem: onOpenItem,
            onPlayItem: { id, items in
                await onPlayItem(id, items, .creator(id: creatorIdentifier))
            },
            onAddToPlaylist: onAddToPlaylist
        )
        .task(id: taskKey) {
            profile = await model.creatorProfile(
                creatorIdentifier: creatorIdentifier,
                accountAddresses: accountAddresses,
                sort: sort
            )
        }
    }

    private var taskKey: String {
        "\(creatorIdentifier)|\(sort.rawValue)|\(accountAddresses.sorted().joined(separator: ","))"
    }
}

struct CreatorProfileView: View {
    let profile: AuraPlayCreatorProfile?
    let fallbackTitle: String
    let currentTrackID: String?
    let onOpenItem: (String) -> Void
    let onPlayItem: (String, [MediaItemQueryItem]) async -> Void
    let onAddToPlaylist: (String) -> Void

    var body: some View {
        List {
            if let profile {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("\(profile.itemCount) media items", systemImage: "rectangle.stack")
                        Label("\(profile.playedItemCount) played locally", systemImage: "clock.arrow.circlepath")
                        if !profile.chains.isEmpty {
                            Text(profile.chains.map(\.routingDisplayName).joined(separator: ", "))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                } header: {
                    Text("Cross-wallet summary")
                        .textCase(nil)
                }

                Section {
                    ForEach(profile.items, id: \.sourceNFTID) { item in
                        LibraryDetailItemRow(
                            item: item,
                            isCurrent: currentTrackID == item.sourceNFTID,
                            onOpen: { onOpenItem(item.sourceNFTID) },
                            onPlay: { Task { await onPlayItem(item.sourceNFTID, profile.items) } },
                            onAddToPlaylist: { onAddToPlaylist(item.sourceNFTID) }
                        )
                    }
                } header: {
                    Text("All connected wallets")
                        .textCase(nil)
                }
            } else {
                AuraEmptyState(
                    title: "No Local Creator Media",
                    message: "You don't have any AuraPlay media from this creator in your connected wallets yet.",
                    systemImage: "person.crop.square"
                )
                .listRowBackground(Color.clear)
                .accessibilityIdentifier(A11yID.AuraPlay.creatorProfileEmpty)
            }
        }
        .auraPlayInsetGroupedListStyle()
        .navigationTitle(profile?.displayName ?? fallbackTitle)
        .auraPlayInlineNavigationTitle()
        .accessibilityIdentifier(A11yID.AuraPlay.creatorProfile)
    }
}

struct LibraryGroupDetailView: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let items: [MediaItemQueryItem]
    let currentTrackID: String?
    let onOpenItem: (String) -> Void
    let onPlayItem: (String) async -> Void
    let onAddToPlaylist: (String) -> Void

    var body: some View {
        List {
            if items.isEmpty {
                AuraEmptyState(
                    title: "No Local Collection Media",
                    message: "You don't have any NFTs from this collection yet.",
                    systemImage: systemImage
                )
                .listRowBackground(Color.clear)
                .accessibilityIdentifier(A11yID.AuraPlay.collectionDetailEmpty)
            } else {
                Section {
                    ForEach(items, id: \.sourceNFTID) { item in
                        LibraryDetailItemRow(
                            item: item,
                            isCurrent: currentTrackID == item.sourceNFTID,
                            onOpen: { onOpenItem(item.sourceNFTID) },
                            onPlay: { Task { await onPlayItem(item.sourceNFTID) } },
                            onAddToPlaylist: { onAddToPlaylist(item.sourceNFTID) }
                        )
                    }
                } header: {
                    Label(subtitle, systemImage: systemImage)
                        .textCase(nil)
                }
            }
        }
        .auraPlayInsetGroupedListStyle()
        .navigationTitle(title)
        .auraPlayInlineNavigationTitle()
        .toolbar {
            if let firstPlayable = items.first(where: \.isPlayable) {
                ToolbarItem(placement: .auraPlayBarTrailing) {
                    Button("Play All", systemImage: "play.fill") {
                        Task { await onPlayItem(firstPlayable.sourceNFTID) }
                    }
                    .accessibilityIdentifier(A11yID.AuraPlay.collectionPlayAll)
                }
            }
        }
    }
}

struct LibraryPlaylistDetailView: View {
    let playlist: AuraPlayPlaylistSnapshot
    let items: [MediaItemQueryItem]
    let currentTrackID: String?
    let rename: (() -> Void)?
    let delete: (() -> Void)?
    let onOpenItem: (String) -> Void
    let onPlayItem: (String) async -> Void
    let onRemoveItem: ((String) -> Void)?
    let onMoveItem: ((Int, Int) -> Void)?

    var body: some View {
        List {
            if items.isEmpty {
                AuraEmptyState(
                    title: "Empty Playlist",
                    message: "Add media from the library item menu.",
                    systemImage: "music.note.list"
                )
                .listRowBackground(Color.clear)
                .accessibilityIdentifier(A11yID.AuraPlay.playlists)
            } else {
                Section {
                    if isEditable {
                        ForEach(items, id: \.sourceNFTID) { item in
                            playlistRow(for: item)
                        }
                        .onDelete { offsets in
                            guard let onRemoveItem else { return }
                            for index in offsets {
                                guard items.indices.contains(index) else { continue }
                                onRemoveItem(items[index].sourceNFTID)
                            }
                        }
                        .onMove { source, destination in
                            guard let onMoveItem else { return }
                            guard let first = source.first else { return }
                            onMoveItem(first, destination)
                        }
                    } else {
                        ForEach(items, id: \.sourceNFTID) { item in
                            playlistRow(for: item)
                        }
                    }
                } header: {
                    Text("\(items.count) items")
                        .textCase(nil)
                }
            }
        }
        .auraPlayInsetGroupedListStyle()
        .navigationTitle(playlist.name)
        .auraPlayInlineNavigationTitle()
        .toolbar {
            if rename != nil || delete != nil {
                ToolbarItem(placement: .auraPlayBarTrailing) {
                    Menu {
                        if let rename {
                            Button("Rename", systemImage: "pencil", action: rename)
                        }
                        if let delete {
                            Button("Delete", systemImage: "trash", role: .destructive, action: delete)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Playlist actions")
                }
            }
            #if os(iOS)
            if isEditable {
                ToolbarItem(placement: .auraPlayBarBottom) {
                    EditButton()
                }
            }
            #endif
        }
    }

    private var isEditable: Bool {
        onRemoveItem != nil || onMoveItem != nil
    }

    private func playlistRow(for item: MediaItemQueryItem) -> some View {
        LibraryDetailItemRow(
            item: item,
            isCurrent: currentTrackID == item.sourceNFTID,
            onOpen: { onOpenItem(item.sourceNFTID) },
            onPlay: { Task { await onPlayItem(item.sourceNFTID) } },
            onAddToPlaylist: {},
            onRemove: onRemoveItem.map { remove in
                { remove(item.sourceNFTID) }
            }
        )
        .accessibilityIdentifier(A11yID.AuraPlay.playlistItem(id: item.sourceNFTID))
    }
}

private struct LibraryDetailItemRow: View {
    let item: MediaItemQueryItem
    let isCurrent: Bool
    let onOpen: () -> Void
    let onPlay: () -> Void
    let onAddToPlaylist: () -> Void
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPlay) {
                Image(systemName: isCurrent ? "waveform.circle.fill" : "play.circle")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isCurrent ? "Now playing" : "Play")

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title.isEmpty ? "Untitled" : item.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                    Text(item.artistName?.isEmpty == false ? item.artistName ?? "Unknown Creator" : "Unknown Creator")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(item.hasVideo ? "Video" : "Audio")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .contextMenu {
            Button("Open", systemImage: "arrow.up.forward.square", action: onOpen)
            Button("Add to Playlist", systemImage: "text.badge.plus", action: onAddToPlaylist)
            if let onRemove {
                Button("Remove from Playlist", systemImage: "minus.circle", role: .destructive, action: onRemove)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title.isEmpty ? "Untitled" : item.title), \(item.hasVideo ? "Video" : "Audio")")
        .accessibilityIdentifier(A11yID.AuraPlay.collectionTrack(id: item.sourceNFTID))
    }
}

struct PlaylistNameEditorSheet: View {
    let title: String
    let initialName: String
    let submitTitle: String
    let submit: (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var isSaving = false

    init(
        title: String,
        initialName: String,
        submitTitle: String,
        submit: @escaping (String) async -> Void
    ) {
        self.title = title
        self.initialName = initialName
        self.submitTitle = submitTitle
        self.submit = submit
        _name = State(initialValue: initialName)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Playlist name", text: $name)
                    .auraPlayWordsAutocapitalization()
                    .accessibilityIdentifier(A11yID.AuraPlay.playlistNameEditor)
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(submitTitle) {
                        Task {
                            isSaving = true
                            await submit(name)
                            isSaving = false
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
    }
}

struct AddToPlaylistSheet: View {
    let playlists: [AuraPlayPlaylistSnapshot]
    let mediaItemID: String
    let createAndAdd: (String) async -> Void
    let toggle: (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var newPlaylistName = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            List {
                Section("Create") {
                    TextField("Playlist name", text: $newPlaylistName)
                        .auraPlayWordsAutocapitalization()
                    Button("Create and Add", systemImage: "plus") {
                        Task {
                            isSaving = true
                            await createAndAdd(newPlaylistName)
                            isSaving = false
                            dismiss()
                        }
                    }
                    .disabled(newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }

                Section("Playlists") {
                    if playlists.isEmpty {
                        Text("No playlists yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(playlists) { playlist in
                            let isMember = contains(playlist)
                            Button {
                                Task {
                                    isSaving = true
                                    await toggle(playlist.id)
                                    isSaving = false
                                }
                            } label: {
                                HStack {
                                    Label(playlist.name, systemImage: "music.note.list")
                                    Spacer()
                                    if isMember {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                            .accessibilityHidden(true)
                                    }
                                }
                            }
                            .disabled(isSaving)
                            .accessibilityValue(isMember ? "Added" : "Not added")
                            .accessibilityHint(isMember ? "Removes from playlist" : "Adds to playlist")
                        }
                    }
                }
            }
            .navigationTitle("Add to Playlist")
            .accessibilityIdentifier(A11yID.AuraPlay.addToPlaylistSheet)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func contains(_ playlist: AuraPlayPlaylistSnapshot) -> Bool {
        playlist.itemIDs.contains(mediaItemID)
    }
}
