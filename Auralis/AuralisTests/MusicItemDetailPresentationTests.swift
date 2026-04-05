import Foundation
import Testing
@testable import Auralis

@Suite
struct MusicItemDetailPresentationTests {
    @Test("item detail prefers source NFT identity while using indexed playback metadata")
    func presentationUsesCanonicalNFTAndIndexedPlaybackFields() {
        let nft = makeNFT(
            id: "track-1",
            name: "Aurora Echo",
            description: "A test track.",
            contentType: "audio/flac",
            collectionName: "Sky Archive",
            artistName: "DJ Nimbus",
            audioURL: "https://example.com/audio.flac"
        )
        let item = makeLibraryItem(
            sourceNFTID: nft.id,
            title: "Indexed Aurora Echo",
            artistName: "Indexed Nimbus",
            collectionName: "Indexed Sky Archive",
            contentType: "audio/flac",
            playbackURLString: "https://example.com/indexed.flac",
            availability: .ready,
            availabilityReason: nil
        )

        let presentation = MusicItemDetailPresentation(nft: nft, libraryItem: item)

        #expect(presentation?.title == "Aurora Echo")
        #expect(presentation?.artist == "Indexed Nimbus")
        #expect(presentation?.collection == "Indexed Sky Archive")
        #expect(presentation?.playbackSummary?.title == "Playback Available")
        #expect(presentation?.contentType == "audio/flac")
        #expect(presentation?.metadataStatus == nil)
    }

    @Test("item detail degrades honestly when metadata is partial")
    func presentationDegradesCleanlyForSparseMetadata() {
        let nft = makeNFT(
            id: "track-2",
            name: nil,
            description: nil,
            contentType: nil,
            collectionName: nil,
            artistName: nil,
            audioURL: nil
        )
        let item = makeLibraryItem(
            sourceNFTID: nft.id,
            title: "Recovered Track",
            artistName: nil,
            collectionName: nil,
            contentType: nil,
            playbackURLString: nil,
            availability: .unavailable,
            availabilityReason: "Provider did not return a playable source."
        )

        let presentation = MusicItemDetailPresentation(nft: nft, libraryItem: item)

        #expect(presentation?.title == "Recovered Track")
        #expect(presentation?.artist == nil)
        #expect(presentation?.collection == nil)
        #expect(presentation?.metadataStatus == "Some music metadata is still sparse for this item.")
        #expect(presentation?.playbackSummary?.title == "Playback Unavailable")
        #expect(presentation?.playbackSummary?.message == "Provider did not return a playable source.")
    }

    @Test("item detail still renders from indexed metadata when the source NFT is gone")
    func presentationFallsBackToIndexedMetadataWhenNFTIsMissing() {
        let item = makeLibraryItem(
            sourceNFTID: "track-3",
            title: "Indexed Only",
            artistName: "Offline Artist",
            collectionName: "Cached Vault",
            contentType: "audio/mpeg",
            playbackURLString: nil,
            availability: .ready,
            availabilityReason: nil
        )

        let presentation = MusicItemDetailPresentation(nft: nil, libraryItem: item)

        #expect(presentation?.title == "Indexed Only")
        #expect(presentation?.artist == "Offline Artist")
        #expect(presentation?.collection == "Cached Vault")
        #expect(presentation?.metadataStatus == "Showing indexed music metadata because the source NFT is not currently available in this scope.")
        #expect(presentation?.playbackSummary?.title == "Metadata Ready")
    }

    private func makeNFT(
        id: String,
        name: String?,
        description: String?,
        contentType: String?,
        collectionName: String?,
        artistName: String?,
        audioURL: String?
    ) -> NFT {
        NFT(
            id: id,
            contract: NFT.Contract(address: "0x1111111111111111111111111111111111111111"),
            tokenId: "1",
            tokenType: "ERC721",
            name: name,
            nftDescription: description,
            image: NFT.Image(
                originalUrl: "https://example.com/\(id).png",
                thumbnailUrl: "https://example.com/\(id)-thumb.png"
            ),
            collection: collectionName.map { NFT.Collection(name: $0) },
            network: .baseMainnet,
            contentType: contentType,
            collectionName: collectionName,
            artistName: artistName,
            audioUrl: audioURL
        )
    }

    private func makeLibraryItem(
        sourceNFTID: String,
        title: String,
        artistName: String?,
        collectionName: String?,
        contentType: String?,
        playbackURLString: String?,
        availability: MusicLibraryAvailability,
        availabilityReason: String?
    ) -> MusicLibraryItem {
        MusicLibraryItem(
            id: "library-\(sourceNFTID)",
            sourceNFTID: sourceNFTID,
            accountAddressRawValue: "",
            networkRawValue: Chain.baseMainnet.rawValue,
            title: title,
            artistName: artistName,
            collectionName: collectionName,
            normalizedTitleKey: title.lowercased(),
            normalizedArtistKey: (artistName ?? "").lowercased(),
            normalizedCollectionKey: (collectionName ?? "").lowercased(),
            artworkURLString: "https://example.com/\(sourceNFTID)-art.png",
            contentType: contentType,
            playbackURLString: playbackURLString,
            availability: availability,
            availabilityReason: availabilityReason,
            sourceUpdatedAtRawValue: nil
        )
    }
}
