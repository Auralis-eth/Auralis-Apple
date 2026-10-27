import Foundation

public enum MusicLibraryAvailability: String, Codable, Equatable, Sendable {
    case ready
    case unavailable
}

public struct MusicLibraryItemDescriptor: Equatable, Sendable {
    public let id: String
    public let sourceNFTID: String
    public let accountAddressRawValue: String
    public let networkRawValue: String
    public let title: String
    public let artistName: String?
    public let collectionName: String?
    public let normalizedTitleKey: String
    public let normalizedArtistKey: String
    public let normalizedCollectionKey: String
    public let artworkURLString: String?
    public let contentType: String?
    public let playbackURLString: String?
    public let availability: MusicLibraryAvailability
    public let availabilityReason: String?
    public let sourceUpdatedAtRawValue: String?

    public init(
        id: String,
        sourceNFTID: String,
        accountAddressRawValue: String,
        networkRawValue: String,
        title: String,
        artistName: String?,
        collectionName: String?,
        normalizedTitleKey: String,
        normalizedArtistKey: String,
        normalizedCollectionKey: String,
        artworkURLString: String?,
        contentType: String?,
        playbackURLString: String?,
        availability: MusicLibraryAvailability,
        availabilityReason: String?,
        sourceUpdatedAtRawValue: String?
    ) {
        self.id = id
        self.sourceNFTID = sourceNFTID
        self.accountAddressRawValue = accountAddressRawValue
        self.networkRawValue = networkRawValue
        self.title = title
        self.artistName = artistName
        self.collectionName = collectionName
        self.normalizedTitleKey = normalizedTitleKey
        self.normalizedArtistKey = normalizedArtistKey
        self.normalizedCollectionKey = normalizedCollectionKey
        self.artworkURLString = artworkURLString
        self.contentType = contentType
        self.playbackURLString = playbackURLString
        self.availability = availability
        self.availabilityReason = availabilityReason
        self.sourceUpdatedAtRawValue = sourceUpdatedAtRawValue
    }
}
