import Foundation
import SwiftData

@Model
/// A persisted playlist model that stores library metadata and compatible queue items.
public final class Playlist: Equatable {
    #Index<Playlist>([\.createdAt], [\.title])
    @Attribute(.unique) public var id: UUID = UUID()
    public var title: String
    public var descriptionText: String?
    public var imageRef: String?
    @Attribute(.externalStorage) public var imageData: Data?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    @Relationship(deleteRule: .nullify, inverse: \NFT.playlists) public var tracks: [NFT] = []

    public var itemCount: Int { tracks.count }
    public var duration: TimeInterval { 0 }

    public init(name: String) {
        self.title = name
        self.descriptionText = nil
        self.imageRef = nil
        self.imageData = nil
        self.tracks = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    public init(name: String, tracks: [NFT] = [], id: UUID = UUID(), textBlurb: String? = nil) {
        self.id = id
        self.title = name
        self.descriptionText = textBlurb
        self.imageRef = nil
        self.imageData = nil
        self.tracks = tracks
        self.createdAt = Date()
        self.updatedAt = Date()
    }

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

    private func touch() {
        updatedAt = Date()
    }

    public func _append(_ nfts: [NFT]) { tracks.append(contentsOf: nfts) }
    public func _insertFront(_ nft: NFT) { tracks.insert(nft, at: 0) }
    public func _removeAll(where predicate: (NFT) -> Bool) { tracks.removeAll(where: predicate) }
    public func _removeFirst() -> NFT { tracks.removeFirst() }
    public func _remove(at index: Int) -> NFT { tracks.remove(at: index) }
    public func _clear() { tracks.removeAll() }
    public func _replace(with tracks: [NFT]) { self.tracks = tracks }

    public static func == (lhs: Playlist, rhs: Playlist) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.descriptionText == rhs.descriptionText &&
        lhs.imageRef == rhs.imageRef &&
        lhs.imageData == rhs.imageData &&
        lhs.tracks == rhs.tracks &&
        lhs.createdAt == rhs.createdAt &&
        lhs.updatedAt == rhs.updatedAt
    }
}
