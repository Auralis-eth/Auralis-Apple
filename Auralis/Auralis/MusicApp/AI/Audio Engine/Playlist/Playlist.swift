//
//  Playlist.swift
//  Auralis
//
//  Created by Daniel Bell on 10/14/25.
//

/// Note: `Playlist` is a SwiftData-persisted model (@Model) representing a playlist in the app's library.
/// It also retains legacy compatibility with QueueManager via the in-memory `tracks` array to avoid a
/// widespread refactor. App logic should prefer QueueManager state for playback sequencing, while this
/// model persists library metadata and associated items.
///
/// Migration/Refactor note:
/// - Historically, a separate transient container and a `LibraryPlaylist` model were used. This type
///   now serves as the unified persisted model. If a future refactor reintroduces a dedicated transient
///   queue container, consider renaming that type (or this one) to avoid confusion.

import Foundation
import SwiftData

@Model
/// A persisted playlist model that stores library metadata and compatible queue items.
public final class Playlist: Equatable {
    /// Stable identifier for the playlist.
    public var id: UUID = UUID()

    /// User-visible playlist title.
    public var title: String
    /// Optional descriptive text shown alongside the playlist.
    public var descriptionText: String?
    /// Optional reference to a remote image asset.
    public var imageRef: String?
    /// Optional locally persisted artwork data.
    @Attribute(.externalStorage) public var imageData: Data? = nil
    /// Creation timestamp.
    public var createdAt: Date = Date()
    /// Last mutation timestamp.
    public var updatedAt: Date = Date()

    // Transient QueueManager compatibility (kept to avoid widespread refactor)
    // Note: This array was previously used by QueueManager as an in-memory queue container.
    // It remains available for compatibility, but app logic should prefer `QueueManager` state for playback sequencing.
    /// Persisted NFT items associated with the playlist.
    public var tracks: [NFT] = []

    // MARK: - Computed properties (Library)
    /// Number of items currently in the playlist.
    public var itemCount: Int { tracks.count }

    /// Aggregate duration placeholder until track durations are available.
    public var duration: TimeInterval { 0 }

    // MARK: - Initializers
    /// Legacy initializer used by QueueManager. Maps `name` to `title` and `textBlurb` to `descriptionText`.
    init(name: String) {
        self.title = name
        self.descriptionText = nil
        self.imageRef = nil
        self.imageData = nil
        self.tracks = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Legacy initializer with tracks. Maps to unified fields.
    init(name: String, tracks: [NFT] = [], id: UUID = UUID(), textBlurb: String? = nil) {
        self.id = id
        self.title = name
        self.descriptionText = textBlurb
        self.imageRef = nil
        self.imageData = nil
        self.tracks = tracks
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Library-style initializer (formerly on LibraryPlaylist).
    /// Creates a persisted playlist using library-facing metadata.
    public init(
        title: String,
        description: String? = nil,
        imageRef: String? = nil,
        imageData: Data? = nil,
        tracks: [NFT] = [],
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.title = title
        self.descriptionText = description
        self.imageRef = imageRef
        self.imageData = imageData
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tracks = tracks
    }

    // MARK: - Library mutators (update timestamps)
    /// Updates the playlist title and refreshes the modification timestamp.
    public func setTitle(_ new: String) {
        title = new
        touch()
    }

    /// Updates the playlist description and refreshes the modification timestamp.
    public func setDescription(_ new: String?) {
        descriptionText = new
        touch()
    }

    /// Updates the remote artwork reference and refreshes the modification timestamp.
    public func setImageRef(_ new: String?) {
        imageRef = new
        touch()
    }

    /// Updates the local artwork data and refreshes the modification timestamp.
    public func setImageData(_ new: Data?) {
        imageData = new
        touch()
    }

    /// Replaces all playlist items and refreshes the modification timestamp.
    public func replaceItems(_ new: [NFT]) {
        tracks = new
        touch()
    }

    /// Appends items to the playlist and refreshes the modification timestamp.
    public func appendItems(_ more: [NFT]) {
        tracks.append(contentsOf: more)
        touch()
    }

    /// Removes matching items from the playlist and refreshes the modification timestamp.
    public func removeItems(where predicate: (NFT) -> Bool) {
        tracks.removeAll(where: predicate)
        touch()
    }

    private func touch() { updatedAt = Date() }

    // MARK: - QueueManager compatibility API (unchanged behavior)
    func _append(_ nfts: [NFT]) { tracks.append(contentsOf: nfts) }
    func _insertFront(_ nft: NFT) { tracks.insert(nft, at: 0) }
    func _removeAll(where predicate: (NFT) -> Bool) { tracks.removeAll(where: predicate) }
    func _removeFirst() -> NFT { tracks.removeFirst() }
    func _remove(at index: Int) -> NFT { tracks.remove(at: index) }
    func _clear() { tracks.removeAll() }
    func _replace(with tracks: [NFT]) { self.tracks = tracks }

    // MARK: - Equatable
    /// Returns whether two playlists have matching identity and persisted content.
    public static func == (lhs: Playlist, rhs: Playlist) -> Bool {
        return lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.descriptionText == rhs.descriptionText &&
        lhs.imageRef == rhs.imageRef &&
        lhs.imageData == rhs.imageData &&
        lhs.tracks == rhs.tracks &&
        lhs.createdAt == rhs.createdAt &&
        lhs.updatedAt == rhs.updatedAt
    }
}
