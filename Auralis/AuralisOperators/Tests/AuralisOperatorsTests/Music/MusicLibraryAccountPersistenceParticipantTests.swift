import Foundation
import AuralisOperators
import SwiftData
import Testing

@MainActor
struct MusicLibraryAccountPersistenceParticipantTests {
    @Test("music model keeps its persisted schema identity in the owner target")
    func modelKeepsPersistedSchemaIdentity() throws {
        let entity = try #require(Schema([MusicLibraryItem.self]).entity(for: MusicLibraryItem.self))

        #expect(entity.name == "MusicLibraryItem")
    }

    @Test("account lifecycle snapshot round-trips every persisted music field")
    func snapshotRoundTripsEveryPersistedField() throws {
        let context = try makeContext()
        let accountAddress = "0x1111111111111111111111111111111111111111"
        let indexedAt = Date(timeIntervalSince1970: 123)
        context.insert(
            MusicLibraryItem(
                id: "music-1",
                sourceNFTID: "nft-1",
                accountAddressRawValue: accountAddress,
                networkRawValue: "eth-mainnet",
                title: "Track",
                artistName: "Artist",
                collectionName: "Collection",
                normalizedTitleKey: "track",
                normalizedArtistKey: "artist",
                normalizedCollectionKey: "collection",
                artworkURLString: "https://example.com/art.png",
                contentType: "audio/mpeg",
                playbackURLString: "https://example.com/track.mp3",
                availability: .ready,
                availabilityReason: "available",
                sourceUpdatedAtRawValue: "2026-10-24T00:00:00Z",
                indexedAt: indexedAt
            )
        )
        try context.save()

        let snapshot = try MusicLibraryAccountPersistenceParticipant.capture(
            scope: accountAddress,
            in: context
        )
        try MusicLibraryAccountPersistenceParticipant.delete(scope: accountAddress, in: context)
        #expect(try context.fetch(FetchDescriptor<MusicLibraryItem>()).isEmpty)

        try MusicLibraryAccountPersistenceParticipant.restore(snapshot, in: context)
        let restored = try #require(context.fetch(FetchDescriptor<MusicLibraryItem>()).first)

        #expect(restored.id == "music-1")
        #expect(restored.sourceNFTID == "nft-1")
        #expect(restored.accountAddressRawValue == accountAddress)
        #expect(restored.networkRawValue == "eth-mainnet")
        #expect(restored.title == "Track")
        #expect(restored.artistName == "Artist")
        #expect(restored.collectionName == "Collection")
        #expect(restored.normalizedTitleKey == "track")
        #expect(restored.normalizedArtistKey == "artist")
        #expect(restored.normalizedCollectionKey == "collection")
        #expect(restored.artworkURLString == "https://example.com/art.png")
        #expect(restored.contentType == "audio/mpeg")
        #expect(restored.playbackURLString == "https://example.com/track.mp3")
        #expect(restored.availability == .ready)
        #expect(restored.availabilityReason == "available")
        #expect(restored.sourceUpdatedAtRawValue == "2026-10-24T00:00:00Z")
        #expect(restored.indexedAt == indexedAt)
    }

    @Test("account lifecycle operations affect only the requested account")
    func participantScopesMutationsToRequestedAccount() throws {
        let context = try makeContext()
        context.insert(makeItem(id: "selected", accountAddress: "selected"))
        context.insert(makeItem(id: "other", accountAddress: "other"))
        try context.save()

        let snapshot = try MusicLibraryAccountPersistenceParticipant.capture(
            scope: "selected",
            in: context
        )
        try MusicLibraryAccountPersistenceParticipant.delete(scope: "selected", in: context)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<MusicLibraryItem>()).map(\.id) == ["other"])

        try MusicLibraryAccountPersistenceParticipant.restore(snapshot, in: context)
        try context.save()

        #expect(Set(try context.fetch(FetchDescriptor<MusicLibraryItem>()).map(\.id)) == ["selected", "other"])
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema([MusicLibraryItem.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    private func makeItem(id: String, accountAddress: String) -> MusicLibraryItem {
        MusicLibraryItem(
            id: id,
            sourceNFTID: "nft-\(id)",
            accountAddressRawValue: accountAddress,
            networkRawValue: "eth-mainnet",
            title: id,
            artistName: nil,
            collectionName: nil,
            normalizedTitleKey: id,
            normalizedArtistKey: "",
            normalizedCollectionKey: "",
            artworkURLString: nil,
            contentType: nil,
            playbackURLString: nil,
            availability: .unavailable,
            availabilityReason: nil,
            sourceUpdatedAtRawValue: nil
        )
    }
}
