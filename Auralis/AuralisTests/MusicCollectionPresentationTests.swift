@testable import Auralis
import Testing

@Suite
struct MusicCollectionPresentationTests {
    @Test("collection summaries group scoped library items by normalized collection key")
    func summariesGroupItemsByCollection() {
        let summaries = MusicCollectionSummary.summaries(
            from: [
                makeItem(id: "1", title: "Track A", artistName: "Artist One", collectionName: "Sky Archive", normalizedCollectionKey: "sky-archive", availability: .ready),
                makeItem(id: "2", title: "Track B", artistName: "Artist One", collectionName: "Sky Archive", normalizedCollectionKey: "sky-archive", availability: .unavailable),
                makeItem(id: "3", title: "Track C", artistName: "Artist Two", collectionName: "Night Garden", normalizedCollectionKey: "night-garden", availability: .ready)
            ]
        )

        #expect(summaries.count == 2)
        #expect(summaries.first?.key == "sky-archive")
        #expect(summaries.first?.title == "Sky Archive")
        #expect(summaries.first?.trackCount == 2)
        #expect(summaries.first?.hasUnavailableTracks == true)
    }

    @Test("collection summaries fall back honestly when collection names are sparse")
    func summariesFallbackWhenCollectionNameIsMissing() {
        let summaries = MusicCollectionSummary.summaries(
            from: [
                makeItem(id: "4", title: "Track D", artistName: "Only Artist", collectionName: nil, normalizedCollectionKey: "", availability: .ready)
            ]
        )

        #expect(summaries.count == 1)
        #expect(summaries[0].title == "Only Artist")
        #expect(summaries[0].key == "__ungrouped__")
    }

    @Test("collection detail presentation reports sparse metadata without pretending the collection is fully resolved")
    func detailPresentationReportsSparseMetadata() {
        let summary = MusicCollectionSummary(
            key: "sky-archive",
            title: "Sky Archive",
            subtitle: nil,
            artworkURL: nil,
            trackCount: 1,
            hasUnavailableTracks: false
        )

        let presentation = MusicCollectionDetailPresentation(
            summary: summary,
            items: [makeItem(id: "5", title: "Track E", artistName: nil, collectionName: "Sky Archive", normalizedCollectionKey: "sky-archive", availability: .ready)],
            chain: .baseMainnet
        )

        #expect(presentation.title == "Sky Archive")
        #expect(presentation.trackCountLabel == "1 track")
        #expect(presentation.chainTitle == Chain.baseMainnet.routingDisplayName)
        #expect(presentation.metadataStatus == "Some collection metadata is still being inferred from local music index fields.")
    }

    private func makeItem(
        id: String,
        title: String,
        artistName: String?,
        collectionName: String?,
        normalizedCollectionKey: String,
        availability: MusicLibraryAvailability
    ) -> MusicLibraryItem {
        MusicLibraryItem(
            id: id,
            sourceNFTID: "nft-\(id)",
            accountAddressRawValue: "",
            networkRawValue: Chain.baseMainnet.rawValue,
            title: title,
            artistName: artistName,
            collectionName: collectionName,
            normalizedTitleKey: title.lowercased(),
            normalizedArtistKey: (artistName ?? "").lowercased(),
            normalizedCollectionKey: normalizedCollectionKey,
            artworkURLString: "https://example.com/\(id).png",
            contentType: "audio/mpeg",
            playbackURLString: "https://example.com/\(id).mp3",
            availability: availability,
            availabilityReason: nil,
            sourceUpdatedAtRawValue: nil
        )
    }
}
