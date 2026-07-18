import Foundation
import SwiftData

@Model
public final class AuraPlayPlaylist {
    #Index<AuraPlayPlaylist>(
        [\.updatedAt],
        [\.name]
    )

    @Attribute(.unique) public var id: String
    public var name: String
    public var coverImageURLString: String?
    public var isSmart: Bool
    public var smartQueryData: Data?
    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \AuraPlayPlaylistItem.playlist)
    public var items: [AuraPlayPlaylistItem]

    public init(
        id: String = UUID().uuidString,
        name: String,
        coverImageURLString: String? = nil,
        isSmart: Bool = false,
        smartQueryData: Data? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        items: [AuraPlayPlaylistItem] = []
    ) {
        self.id = id
        self.name = name
        self.coverImageURLString = coverImageURLString
        self.isSmart = isSmart
        self.smartQueryData = smartQueryData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.items = items
    }
}
