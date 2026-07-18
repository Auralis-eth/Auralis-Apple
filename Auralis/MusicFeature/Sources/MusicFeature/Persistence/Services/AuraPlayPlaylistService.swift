import Foundation
import SwiftData

public protocol AuraPlayPlaylistManaging: Sendable {
    func createID(name: String, at date: Date) async throws -> String
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
