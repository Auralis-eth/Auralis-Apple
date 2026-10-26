import Foundation
import SwiftData

public protocol AuraPlayPlaylistManaging: Sendable {
    func fetchPlaylistSnapshots() async throws -> [AuraPlayPlaylistSnapshot]
    func fetchPlaylistSnapshot(id: String) async throws -> AuraPlayPlaylistSnapshot?
    func createID(name: String, at date: Date) async throws -> String
    func createSmartPlaylistID(
        name: String,
        mediaItemIDs: [String],
        smartQueryData: Data,
        at date: Date
    ) async throws -> String
    func rename(id: String, name: String, at date: Date) async throws
    func delete(id: String) async throws
    func add(mediaItemID: String, toPlaylist playlistID: String, at date: Date) async throws
    func remove(mediaItemID: String, fromPlaylist playlistID: String, at date: Date) async throws
    func reorderItem(playlistID: String, fromPosition: Int, toPosition: Int, at date: Date) async throws
    func toggle(mediaItemID: String, playlistID: String, at date: Date) async throws
    func createAndAddID(name: String, mediaItemID: String, at date: Date) async throws -> String
}

@ModelActor
public actor AuraPlayPlaylistService: AuraPlayPlaylistManaging {
    @discardableResult
    public func create(name: String, at date: Date = .now) throws -> AuraPlayPlaylist {
        let playlist = AuraPlayPlaylist(
            name: Self.cleanedName(name),
            createdAt: date,
            updatedAt: date
        )
        modelContext.insert(playlist)
        try modelContext.save()
        return playlist
    }

    @discardableResult
    public func createID(name: String, at date: Date = .now) throws -> String {
        try create(name: name, at: date).id
    }

    @discardableResult
    public func createSmartPlaylist(
        name: String,
        mediaItemIDs: [String],
        smartQueryData: Data,
        at date: Date = .now
    ) throws -> AuraPlayPlaylist {
        let playlist = AuraPlayPlaylist(
            name: Self.cleanedName(name),
            isSmart: true,
            smartQueryData: smartQueryData,
            createdAt: date,
            updatedAt: date
        )
        modelContext.insert(playlist)
        for (index, mediaItemID) in Self.uniqueMediaItemIDs(mediaItemIDs).enumerated() {
            let item = AuraPlayPlaylistItem(
                playlistID: playlist.id,
                mediaItemID: mediaItemID,
                position: index,
                addedAt: date.addingTimeInterval(Double(index) / 1_000),
                playlist: playlist
            )
            modelContext.insert(item)
        }
        try modelContext.save()
        return playlist
    }

    @discardableResult
    public func createSmartPlaylistID(
        name: String,
        mediaItemIDs: [String],
        smartQueryData: Data,
        at date: Date = .now
    ) throws -> String {
        try createSmartPlaylist(
            name: name,
            mediaItemIDs: mediaItemIDs,
            smartQueryData: smartQueryData,
            at: date
        ).id
    }

    public func rename(id: String, name: String, at date: Date = .now) throws {
        guard let playlist = try fetchPlaylist(id: id) else { return }
        playlist.name = Self.cleanedName(name)
        playlist.updatedAt = date
        try modelContext.save()
    }

    public func delete(id: String) throws {
        guard let playlist = try fetchPlaylist(id: id) else { return }
        modelContext.delete(playlist)
        try modelContext.save()
    }

    public func fetchPlaylists() throws -> [AuraPlayPlaylist] {
        let descriptor = FetchDescriptor<AuraPlayPlaylist>(
            sortBy: [
                SortDescriptor(\.updatedAt, order: .reverse),
                SortDescriptor(\.name),
                SortDescriptor(\.id)
            ]
        )
        return try modelContext.fetch(descriptor)
    }

    public func fetchPlaylistSnapshots() throws -> [AuraPlayPlaylistSnapshot] {
        try fetchPlaylists().map(AuraPlayPlaylistSnapshot.init)
    }

    public func fetchPlaylistSnapshot(id: String) throws -> AuraPlayPlaylistSnapshot? {
        try fetchPlaylist(id: id).map(AuraPlayPlaylistSnapshot.init)
    }

    public func fetchItems(playlistID: String) throws -> [AuraPlayPlaylistItem] {
        try fetchPlaylistItems(playlistID: playlistID)
    }

    public func fetchItemSnapshots(playlistID: String) throws -> [AuraPlayPlaylistItemSnapshot] {
        try fetchPlaylistItems(playlistID: playlistID).map(AuraPlayPlaylistItemSnapshot.init)
    }

    public func add(mediaItemID: String, toPlaylist playlistID: String, at date: Date = .now) throws {
        guard let playlist = try fetchPlaylist(id: playlistID) else { return }
        var items = try fetchPlaylistItems(playlistID: playlistID)
        guard !items.contains(where: { $0.mediaItemID == mediaItemID }) else { return }

        let item = AuraPlayPlaylistItem(
            playlistID: playlistID,
            mediaItemID: mediaItemID,
            position: items.count,
            addedAt: date,
            playlist: playlist
        )
        modelContext.insert(item)
        items.append(item)
        normalize(items)
        playlist.updatedAt = date
        try modelContext.save()
    }

    public func remove(mediaItemID: String, fromPlaylist playlistID: String, at date: Date = .now) throws {
        guard let playlist = try fetchPlaylist(id: playlistID) else { return }
        var items = try fetchPlaylistItems(playlistID: playlistID)
        guard let item = items.first(where: { $0.mediaItemID == mediaItemID }) else { return }
        modelContext.delete(item)
        items.removeAll { $0.id == item.id }
        normalize(items)
        playlist.updatedAt = date
        try modelContext.save()
    }

    public func reorderItem(
        playlistID: String,
        fromPosition: Int,
        toPosition: Int,
        at date: Date = .now
    ) throws {
        guard let playlist = try fetchPlaylist(id: playlistID) else { return }
        var items = try fetchPlaylistItems(playlistID: playlistID)
        guard items.indices.contains(fromPosition) else { return }
        let item = items.remove(at: fromPosition)
        let destination = min(max(0, toPosition), items.count)
        items.insert(item, at: destination)
        normalize(items)
        playlist.updatedAt = date
        try modelContext.save()
    }

    public func toggle(mediaItemID: String, playlistID: String, at date: Date = .now) throws {
        let items = try fetchPlaylistItems(playlistID: playlistID)
        if items.contains(where: { $0.mediaItemID == mediaItemID }) {
            try remove(mediaItemID: mediaItemID, fromPlaylist: playlistID, at: date)
        } else {
            try add(mediaItemID: mediaItemID, toPlaylist: playlistID, at: date)
        }
    }

    @discardableResult
    public func createAndAdd(name: String, mediaItemID: String, at date: Date = .now) throws -> AuraPlayPlaylist {
        let playlist = try create(name: name, at: date)
        try add(mediaItemID: mediaItemID, toPlaylist: playlist.id, at: date)
        return playlist
    }

    @discardableResult
    public func createAndAddID(name: String, mediaItemID: String, at date: Date = .now) throws -> String {
        try createAndAdd(name: name, mediaItemID: mediaItemID, at: date).id
    }

    private func fetchPlaylist(id: String) throws -> AuraPlayPlaylist? {
        var descriptor = FetchDescriptor<AuraPlayPlaylist>(
            predicate: #Predicate<AuraPlayPlaylist> { playlist in
                playlist.id == id
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchPlaylistItems(playlistID: String) throws -> [AuraPlayPlaylistItem] {
        let descriptor = FetchDescriptor<AuraPlayPlaylistItem>(
            predicate: #Predicate<AuraPlayPlaylistItem> { item in
                item.playlistID == playlistID
            },
            sortBy: [
                SortDescriptor(\.position),
                SortDescriptor(\.addedAt),
                SortDescriptor(\.id)
            ]
        )
        return try modelContext.fetch(descriptor)
    }

    private func normalize(_ items: [AuraPlayPlaylistItem]) {
        for (index, item) in items.enumerated() {
            item.position = index
        }
    }

    private static func cleanedName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Playlist" : trimmed
    }

    private static func uniqueMediaItemIDs(_ ids: [String]) -> [String] {
        var seen: Set<String> = []
        return ids.filter { id in
            seen.insert(id).inserted
        }
    }
}

public struct AuraPlayPlaylistSnapshot: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let coverImageURLString: String?
    public let isSmart: Bool
    public let createdAt: Date
    public let updatedAt: Date
    public let itemIDs: [String]

    public var itemCount: Int {
        itemIDs.count
    }

    public init(playlist: AuraPlayPlaylist) {
        self.id = playlist.id
        self.name = playlist.name
        self.coverImageURLString = playlist.coverImageURLString
        self.isSmart = playlist.isSmart
        self.createdAt = playlist.createdAt
        self.updatedAt = playlist.updatedAt
        self.itemIDs = playlist.items
            .sorted { $0.position < $1.position }
            .map(\.mediaItemID)
    }
}

public struct AuraPlayPlaylistItemSnapshot: Identifiable, Equatable, Sendable {
    public let id: String
    public let playlistID: String
    public let mediaItemID: String
    public let position: Int
    public let addedAt: Date

    public init(item: AuraPlayPlaylistItem) {
        self.id = item.id
        self.playlistID = item.playlistID
        self.mediaItemID = item.mediaItemID
        self.position = item.position
        self.addedAt = item.addedAt
    }
}
