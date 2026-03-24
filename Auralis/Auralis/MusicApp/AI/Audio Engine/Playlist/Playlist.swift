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
public final class Playlist: Equatable {
    // Unified identifier (persisted)
    public var id: UUID = UUID()

    // Library (persisted) fields
    public var title: String
    public var descriptionText: String?
    public var imageRef: String?
    @Attribute(.externalStorage) public var imageData: Data? = nil
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    // Transient QueueManager compatibility (kept to avoid widespread refactor)
    // Note: This array was previously used by QueueManager as an in-memory queue container.
    // It remains available for compatibility, but app logic should prefer `QueueManager` state for playback sequencing.
    public var tracks: [NFT] = []

    // MARK: - Computed properties (Library)
    public var itemCount: Int { tracks.count }

    public var duration: TimeInterval { 0 } // Placeholder until durations available

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
    public func setTitle(_ new: String) {
        title = new
        touch()
    }

    public func setDescription(_ new: String?) {
        descriptionText = new
        touch()
    }

    public func setImageRef(_ new: String?) {
        imageRef = new
        touch()
    }

    public func setImageData(_ new: Data?) {
        imageData = new
        touch()
    }

    public func replaceItems(_ new: [NFT]) {
        tracks = new
        touch()
    }

    public func appendItems(_ more: [NFT]) {
        tracks.append(contentsOf: more)
        touch()
    }

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
