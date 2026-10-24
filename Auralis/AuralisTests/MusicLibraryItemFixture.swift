import AuralisPrimaryModels
import AuralisTestSupport
import Foundation
import MusicFeature

struct MusicLibraryItemFixture: @unchecked Sendable {
    static let music = MusicLibraryItemFixture()

    var id: String
    var sourceNFTID: String
    var accountAddress: String
    var network: Chain
    var title: String
    var artistName: String?
    var collectionName: String?
    var artworkURLString: String?
    var contentType: String?
    var playbackURLString: String?
    var availability: MusicFeature.MusicLibraryAvailability
    var availabilityReason: String?
    var sourceUpdatedAtRawValue: String?
    var indexedAt: Date

    init(
        id: String = "fixture-track",
        sourceNFTID: String = "fixture-source-nft",
        accountAddress: String = Fixture.Accounts.primary,
        network: Chain = .ethMainnet,
        title: String = "Fixture Track",
        artistName: String? = "Fixture Artist",
        collectionName: String? = "Fixture Collection",
        artworkURLString: String? = nil,
        contentType: String? = "audio/mpeg",
        playbackURLString: String? = "https://example.com/fixture-track.mp3",
        availability: MusicFeature.MusicLibraryAvailability = .ready,
        availabilityReason: String? = nil,
        sourceUpdatedAtRawValue: String? = nil,
        indexedAt: Date = Fixture.referenceDate
    ) {
        self.id = id
        self.sourceNFTID = sourceNFTID
        self.accountAddress = accountAddress
        self.network = network
        self.title = title
        self.artistName = artistName
        self.collectionName = collectionName
        self.artworkURLString = artworkURLString
        self.contentType = contentType
        self.playbackURLString = playbackURLString
        self.availability = availability
        self.availabilityReason = availabilityReason
        self.sourceUpdatedAtRawValue = sourceUpdatedAtRawValue
        self.indexedAt = indexedAt
    }

    func with(_ transform: (inout MusicLibraryItemFixture) -> Void) -> MusicLibraryItemFixture {
        var copy = self
        transform(&copy)
        return copy
    }

    func build() -> MusicLibraryItem {
        MusicLibraryItem(
            id: id,
            sourceNFTID: sourceNFTID,
            accountAddressRawValue: accountAddress,
            networkRawValue: network.rawValue,
            title: title,
            artistName: artistName,
            collectionName: collectionName,
            normalizedTitleKey: title.lowercased(),
            normalizedArtistKey: artistName?.lowercased() ?? "",
            normalizedCollectionKey: collectionName?.lowercased() ?? "",
            artworkURLString: artworkURLString ?? "https://example.com/\(id).png",
            contentType: contentType,
            playbackURLString: playbackURLString,
            availability: availability,
            availabilityReason: availabilityReason,
            sourceUpdatedAtRawValue: sourceUpdatedAtRawValue,
            indexedAt: indexedAt
        )
    }
}
