import Foundation
import MusicFeature
import SwiftData
import Testing

/// P9-005 playlist persistence: contiguous positions, duplicate names,
/// membership toggle, and the full round trip against in-memory SwiftData.
@MainActor
struct PlaylistServiceTests {
    private func makeFixture() throws -> (service: AuraPlayPlaylistService, container: ModelContainer) {
        let container = try AuraPlayLibrarySeed.makeContainer()
        return (AuraPlayPlaylistService(modelContainer: container), container)
    }

    /// Reads playlists on the main actor; the service's model-typed fetch is
    /// actor-bound and cannot cross into the test.
    private func playlistNames(in container: ModelContainer) throws -> [String] {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<AuraPlayPlaylist>(sortBy: [SortDescriptor(\.name), SortDescriptor(\.id)])
        return try context.fetch(descriptor).map(\.name)
    }

    private let fixedDate = Date(timeIntervalSince1970: 1_750_100_000)

    @Test("Duplicate playlist names are allowed")
    func duplicateNamesSucceed() async throws {
        let (service, container) = try makeFixture()

        let firstID = try await service.createID(name: "Focus", at: fixedDate)
        let secondID = try await service.createID(name: "Focus", at: fixedDate.addingTimeInterval(1))

        let names = try playlistNames(in: container)
        #expect(names == ["Focus", "Focus"])
        #expect(firstID != secondID)
    }

    @Test("Positions stay contiguous and zero-based through add, remove, and reorder")
    func positionsStayContiguous() async throws {
        let (service, _) = try makeFixture()
        let playlistID = try await service.createID(name: "Order", at: fixedDate)

        for (offset, mediaID) in ["a", "b", "c", "d"].enumerated() {
            try await service.add(
                mediaItemID: mediaID,
                toPlaylist: playlistID,
                at: fixedDate.addingTimeInterval(Double(offset))
            )
        }

        try await service.reorderItem(playlistID: playlistID, fromPosition: 3, toPosition: 0, at: fixedDate)
        var snapshots = try await service.fetchItemSnapshots(playlistID: playlistID)
        #expect(snapshots.map(\.mediaItemID) == ["d", "a", "b", "c"])
        #expect(snapshots.map(\.position) == [0, 1, 2, 3])

        try await service.remove(mediaItemID: "a", fromPlaylist: playlistID, at: fixedDate)
        snapshots = try await service.fetchItemSnapshots(playlistID: playlistID)
        #expect(snapshots.map(\.mediaItemID) == ["d", "b", "c"])
        #expect(snapshots.map(\.position) == [0, 1, 2])
    }

    @Test("Toggle adds missing members and removes existing members")
    func toggleAddsAndRemoves() async throws {
        let (service, _) = try makeFixture()
        let playlistID = try await service.createID(name: "Toggle", at: fixedDate)

        try await service.toggle(mediaItemID: "track-1", playlistID: playlistID, at: fixedDate)
        var snapshots = try await service.fetchItemSnapshots(playlistID: playlistID)
        #expect(snapshots.map(\.mediaItemID) == ["track-1"])

        try await service.toggle(mediaItemID: "track-1", playlistID: playlistID, at: fixedDate)
        snapshots = try await service.fetchItemSnapshots(playlistID: playlistID)
        #expect(snapshots.isEmpty)
    }

    @Test("Adding an existing member is a no-op instead of a duplicate row")
    func addingTwiceDoesNotDuplicate() async throws {
        let (service, _) = try makeFixture()
        let playlistID = try await service.createID(name: "Unique", at: fixedDate)

        try await service.add(mediaItemID: "track-1", toPlaylist: playlistID, at: fixedDate)
        try await service.add(mediaItemID: "track-1", toPlaylist: playlistID, at: fixedDate)

        let snapshots = try await service.fetchItemSnapshots(playlistID: playlistID)
        #expect(snapshots.count == 1)
    }

    @Test("Full round trip: create, add, rename, reorder, create-and-add, delete")
    func fullRoundTrip() async throws {
        let (service, container) = try makeFixture()

        let playlistID = try await service.createID(name: "Road Trip", at: fixedDate)
        try await service.add(mediaItemID: "track-1", toPlaylist: playlistID, at: fixedDate)
        try await service.add(mediaItemID: "track-2", toPlaylist: playlistID, at: fixedDate)
        try await service.rename(id: playlistID, name: "Long Road Trip", at: fixedDate.addingTimeInterval(10))
        try await service.reorderItem(playlistID: playlistID, fromPosition: 1, toPosition: 0, at: fixedDate)

        let otherID = try await service.createAndAddID(
            name: "Spin-off",
            mediaItemID: "track-9",
            at: fixedDate.addingTimeInterval(20)
        )

        var names = try playlistNames(in: container)
        #expect(Set(names) == ["Long Road Trip", "Spin-off"])
        let roadTripItems = try await service.fetchItemSnapshots(playlistID: playlistID)
        #expect(roadTripItems.map(\.mediaItemID) == ["track-2", "track-1"])
        let spinOffItems = try await service.fetchItemSnapshots(playlistID: otherID)
        #expect(spinOffItems.map(\.mediaItemID) == ["track-9"])

        try await service.delete(id: playlistID)
        names = try playlistNames(in: container)
        #expect(names == ["Spin-off"])
        let orphanedItems = try await service.fetchItemSnapshots(playlistID: playlistID)
        #expect(orphanedItems.isEmpty)
    }
}
