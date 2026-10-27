import MusicFeature
import AuralisReceipts
import SwiftData
import Testing

@MainActor
struct ReceiptBackedAuraPlayPlaylistManagerTests {
    @Test("Active AuraPlay playlist mutations emit create, modify, and delete receipts")
    func mutationsEmitReceipts() async throws {
        let playlistContainer = try AuraPlayLibrarySeed.makeContainer()
        let receiptStore = SwiftDataReceiptStore(
            modelContext: ModelContext(try MusicFeatureTestModelContainers.receipts())
        )
        let manager = ReceiptBackedAuraPlayPlaylistManager(
            base: AuraPlayPlaylistService(modelContainer: playlistContainer),
            receiptLogger: MusicReceiptEventLogger(receiptStore: receiptStore),
            context: MusicReceiptContext(
                triggerCause: .userInitiated,
                actor: .user,
                correlationID: "active-playlist-flow",
                surface: "music.library.playlist"
            )
        )

        let playlistID = try await manager.createID(name: "Focus", at: .init(timeIntervalSince1970: 1))
        try await manager.add(
            mediaItemID: "track-1",
            toPlaylist: playlistID,
            at: .init(timeIntervalSince1970: 2)
        )
        try await manager.rename(
            id: playlistID,
            name: "Deep Focus",
            at: .init(timeIntervalSince1970: 3)
        )
        try await manager.delete(id: playlistID)

        let receipts = try await receiptStore.receipts(
            forCorrelationID: "active-playlist-flow",
            limit: 10
        )
        #expect(receipts.map(\.trigger) == [
            "music.playlist.deleted",
            "music.playlist.modified",
            "music.playlist.modified",
            "music.playlist.created"
        ])
        #expect(receipts.allSatisfy { receipt in
            receipt.details.values["playlistID"] == .string(playlistID)
        })
        #expect(receipts.first?.details.values["affectedMediaIDs"] == .array([.string("track-1")]))
    }

    @Test("No-op playlist mutations do not emit misleading modification receipts")
    func noOpMutationDoesNotEmitReceipt() async throws {
        let playlistContainer = try AuraPlayLibrarySeed.makeContainer()
        let receiptStore = SwiftDataReceiptStore(
            modelContext: ModelContext(try MusicFeatureTestModelContainers.receipts())
        )
        let manager = ReceiptBackedAuraPlayPlaylistManager(
            base: AuraPlayPlaylistService(modelContainer: playlistContainer),
            receiptLogger: MusicReceiptEventLogger(receiptStore: receiptStore),
            context: MusicReceiptContext(
                triggerCause: .userInitiated,
                actor: .user,
                correlationID: "no-op-playlist-flow"
            )
        )

        let playlistID = try await manager.createID(name: "Focus", at: .init(timeIntervalSince1970: 1))
        try await manager.remove(
            mediaItemID: "missing",
            fromPlaylist: playlistID,
            at: .init(timeIntervalSince1970: 2)
        )

        let receipts = try await receiptStore.receipts(
            forCorrelationID: "no-op-playlist-flow",
            limit: 10
        )
        #expect(receipts.map(\.trigger) == ["music.playlist.created"])
    }

    /// The service accepts these mutations and stamps `updatedAt`, so the snapshots differ even
    /// though nothing a receipt reader can see moved. Whole-snapshot equality would file a
    /// "modified" receipt for both.
    @Test("Accepted mutations that change nothing visible do not emit modification receipts")
    func acceptedButInertMutationsDoNotEmitReceipts() async throws {
        let playlistContainer = try AuraPlayLibrarySeed.makeContainer()
        let receiptStore = SwiftDataReceiptStore(
            modelContext: ModelContext(try MusicFeatureTestModelContainers.receipts())
        )
        let manager = ReceiptBackedAuraPlayPlaylistManager(
            base: AuraPlayPlaylistService(modelContainer: playlistContainer),
            receiptLogger: MusicReceiptEventLogger(receiptStore: receiptStore),
            context: MusicReceiptContext(
                triggerCause: .userInitiated,
                actor: .user,
                correlationID: "inert-playlist-flow"
            )
        )

        let playlistID = try await manager.createID(name: "Focus", at: .init(timeIntervalSince1970: 1))
        try await manager.add(
            mediaItemID: "track-1",
            toPlaylist: playlistID,
            at: .init(timeIntervalSince1970: 2)
        )
        // Renaming to the name it already has.
        try await manager.rename(
            id: playlistID,
            name: "Focus",
            at: .init(timeIntervalSince1970: 3)
        )
        // Reordering the only item onto its own position.
        try await manager.reorderItem(
            playlistID: playlistID,
            fromPosition: 0,
            toPosition: 0,
            at: .init(timeIntervalSince1970: 4)
        )

        let receipts = try await receiptStore.receipts(
            forCorrelationID: "inert-playlist-flow",
            limit: 10
        )
        #expect(receipts.map(\.trigger) == [
            "music.playlist.modified",
            "music.playlist.created"
        ])
    }
}
