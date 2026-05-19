import Foundation
import AuralisPrimaryModels
import SwiftData

@Model
public final class MusicLibraryItem {
    #Index<MusicLibraryItem>(
        [\.accountAddressRawValue, \.networkRawValue, \.normalizedArtistKey, \.normalizedTitleKey, \.id],
        [\.accountAddressRawValue, \.networkRawValue, \.sourceNFTID]
    )

    @Attribute(.unique) public var id: String
    public var sourceNFTID: String
    public var accountAddressRawValue: String
    public var networkRawValue: String
    public var title: String
    public var artistName: String?
    public var collectionName: String?
    public var normalizedTitleKey: String
    public var normalizedArtistKey: String
    public var normalizedCollectionKey: String
    public var artworkURLString: String?
    public var contentType: String?
    public var playbackURLString: String?
    public var availabilityRawValue: String
    public var availabilityReason: String?
    public var sourceUpdatedAtRawValue: String?
    public var indexedAt: Date

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
        sourceUpdatedAtRawValue: String?,
        indexedAt: Date = .now
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
        self.availabilityRawValue = availability.rawValue
        self.availabilityReason = availabilityReason
        self.sourceUpdatedAtRawValue = sourceUpdatedAtRawValue
        self.indexedAt = indexedAt
    }

    public var availability: MusicLibraryAvailability {
        get { MusicLibraryAvailability(rawValue: availabilityRawValue) ?? .unavailable }
        set { availabilityRawValue = newValue.rawValue }
    }

    public var artworkURL: URL? {
        guard let artworkURLString, !artworkURLString.isEmpty else {
            return nil
        }

        return URL(string: artworkURLString)
    }

    public func matchesScope(accountAddress: String?, chain: Chain) -> Bool {
        let normalizedAccountAddress = NFT.normalizedScopeComponent(accountAddress) ?? ""
        return accountAddressRawValue == normalizedAccountAddress && networkRawValue == chain.rawValue
    }

    public func apply(_ descriptor: MusicLibraryItemDescriptor, indexedAt: Date) {
        title = descriptor.title
        artistName = descriptor.artistName
        collectionName = descriptor.collectionName
        normalizedTitleKey = descriptor.normalizedTitleKey
        normalizedArtistKey = descriptor.normalizedArtistKey
        normalizedCollectionKey = descriptor.normalizedCollectionKey
        artworkURLString = descriptor.artworkURLString
        contentType = descriptor.contentType
        playbackURLString = descriptor.playbackURLString
        availability = descriptor.availability
        availabilityReason = descriptor.availabilityReason
        sourceUpdatedAtRawValue = descriptor.sourceUpdatedAtRawValue
        self.indexedAt = indexedAt
    }
}
