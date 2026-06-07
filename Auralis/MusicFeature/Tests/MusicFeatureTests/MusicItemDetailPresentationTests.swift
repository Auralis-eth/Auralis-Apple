import AuralisTestSupport
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import MusicFeature
import Testing

struct MusicItemDetailPresentationTests {
    @Test("item detail prefers source NFT identity while using indexed playback metadata")
    func presentationUsesCanonicalNFTAndIndexedPlaybackFields() throws {
        let nft = NFTFixture(
            tokenId: "1",
            id: "track-1",
            accountAddress: "",
            contractAddress: Fixture.Accounts.primary,
            collectionName: "Sky Archive",
            network: .baseMainnet,
            tokenType: "ERC721",
            name: "Aurora Echo",
            nftDescription: "A test track.",
            contentType: "audio/flac",
            artistName: "DJ Nimbus",
            audioUrl: "https://example.com/audio.flac",
            includeOwnedChildren: true
        ).build()
        let item = MusicLibraryItemFixture(
            id: "library-\(nft.id)",
            sourceNFTID: nft.id,
            accountAddress: "",
            network: .baseMainnet,
            title: "Indexed Aurora Echo",
            artistName: "Indexed Nimbus",
            collectionName: "Indexed Sky Archive",
            contentType: "audio/flac",
            playbackURLString: "https://example.com/indexed.flac",
            availability: .ready,
            availabilityReason: nil
        ).build()

        let presentation = try #require(AuraPlayMusicItemDetailPresentation(nft: nft, libraryItem: item))

        let summary = try #require(presentation.playbackSummary)
        #expect(presentation.title == "Aurora Echo")
        #expect(presentation.artist == "Indexed Nimbus")
        #expect(presentation.collection == "Indexed Sky Archive")
        #expect(summary.title == "Playback Available")
        #expect(presentation.contentType == "audio/flac")
        #expect(presentation.metadataStatus == nil)
    }

    @Test("item detail degrades honestly when metadata is partial")
    func presentationDegradesCleanlyForSparseMetadata() throws {
        let nft = NFTFixture(
            tokenId: "1",
            id: "track-2",
            accountAddress: "",
            contractAddress: Fixture.Accounts.primary,
            collectionName: nil,
            network: .baseMainnet,
            tokenType: "ERC721",
            name: "",
            nftDescription: nil,
            contentType: nil,
            artistName: nil,
            audioUrl: nil,
            includeOwnedChildren: true
        ).build()
        let item = MusicLibraryItemFixture(
            id: "library-\(nft.id)",
            sourceNFTID: nft.id,
            accountAddress: "",
            network: .baseMainnet,
            title: "Recovered Track",
            artistName: nil,
            collectionName: nil,
            contentType: nil,
            playbackURLString: nil,
            availability: .unavailable,
            availabilityReason: "Provider did not return a playable source."
        ).build()

        let presentation = try #require(AuraPlayMusicItemDetailPresentation(nft: nft, libraryItem: item))

        let summary = try #require(presentation.playbackSummary)
        #expect(presentation.title == "Recovered Track")
        #expect(presentation.artist == nil)
        #expect(presentation.collection == nil)
        #expect(presentation.metadataStatus == "Some music metadata is still sparse for this item.")
        #expect(summary.title == "Playback Unavailable")
        #expect(summary.message == "Provider did not return a playable source.")
    }

    @Test("item detail still renders from indexed metadata when the source NFT is gone")
    func presentationFallsBackToIndexedMetadataWhenNFTIsMissing() throws {
        let item = MusicLibraryItemFixture(
            id: "library-track-3",
            sourceNFTID: "track-3",
            accountAddress: "",
            network: .baseMainnet,
            title: "Indexed Only",
            artistName: "Offline Artist",
            collectionName: "Cached Vault",
            contentType: "audio/mpeg",
            playbackURLString: nil,
            availability: .ready,
            availabilityReason: nil
        ).build()

        let presentation = try #require(AuraPlayMusicItemDetailPresentation(nft: nil, libraryItem: item))

        let summary = try #require(presentation.playbackSummary)
        #expect(presentation.title == "Indexed Only")
        #expect(presentation.artist == "Offline Artist")
        #expect(presentation.collection == "Cached Vault")
        #expect(presentation.metadataStatus == "Showing indexed music metadata because the source NFT is not currently available in this scope.")
        #expect(summary.title == "Metadata Ready")
    }

}
