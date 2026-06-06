import AuralisPrimaryModels
import MusicFeature
import ReceiptStorage
import ReceiptsCore
import SwiftData
import Testing

struct MusicReceiptEventLoggerTests {
    @MainActor
    private func makeReceiptStore() throws -> SwiftDataReceiptStore {
        let container = try MusicFeatureTestModelContainers.receipts()
        return SwiftDataReceiptStore(
            modelContext: ModelContext(container),
            sequenceAllocator: ReceiptSequenceAllocator()
        )
    }

    @Test("playlist creation writes namespaced music receipt fields")
    @MainActor
    func playlistCreationWritesMusicReceiptFields() async throws {
        let receiptStore = try makeReceiptStore()
        let logger = MusicReceiptEventLogger(receiptStore: receiptStore)
        let playlistID = UUID()

        _ = try await logger.recordPlaylistCreated(
            playlistID: playlistID,
            playlistTitle: "Night Drive",
            affectedMediaIDs: ["track-2", "track-1", "track-2"],
            itemCount: 2,
            context: MusicReceiptContext(
                triggerCause: .userInitiated,
                actor: .user,
                correlationID: "playlist-flow",
                surface: "music.playlist.new"
            )
        )

        let receipt = try #require(try await receiptStore.receipts(forCorrelationID: "playlist-flow", limit: 1).first)

        #expect(receipt.trigger == "music.playlist.created")
        #expect(receipt.scope == "music.playlist")
        #expect(receipt.summary == "Created playlist")
        #expect(receipt.details.values["eventType"] == .string("music.playlist.created"))
        #expect(receipt.details.values["capabilityUsed"] == .string("playlist_management"))
        #expect(receipt.details.values["policyDecision"] == .string("allowed"))
        #expect(receipt.details.values["surface"] == .string("music.playlist.new"))
        #expect(receipt.details.values["playlistID"] == .string(playlistID.uuidString))
        #expect(receipt.details.values["playlistTitle"] == .string("Night Drive"))
        #expect(receipt.details.values["affectedMediaIDs"] == .array([.string("track-1"), .string("track-2")]))
    }

    @Test("auto-organization dry runs emit dry-run receipts through the shared store")
    @MainActor
    func autoOrganizationDryRunWritesReceipt() async throws {
        let receiptStore = try makeReceiptStore()
        let logger = MusicReceiptEventLogger(receiptStore: receiptStore)
        let service = MusicAutoOrganizationReceiptService(receiptLogger: logger)

        let result = try await service.runDryRun(
            proposal: MusicAutoOrganizationDryRunProposal(
                affectedMediaIDs: ["track-2", "track-1", "track-2"],
                beforeSummary: .autoOrganization(candidateCount: 2, collectionCount: 1),
                proposedSummary: .autoOrganization(candidateCount: 2, collectionCount: 2),
                reason: "Previewing playlist grouping suggestions."
            ),
            context: MusicReceiptContext(
                triggerCause: .dryRun,
                actor: .system,
                correlationID: "auto-org",
                surface: "music.library.auto_organization"
            )
        )

        let receipt = try #require(try await receiptStore.receipts(forCorrelationID: "auto-org", limit: 1).first)

        #expect(result.dryRun)
        #expect(result.affectedMediaIDs == ["track-1", "track-2"])
        #expect(receipt.trigger == "music.auto_organization.run")
        #expect(receipt.details.values["policyDecision"] == .string("dry_run"))
        #expect(receipt.details.values["dryRun"] == .bool(true))
        #expect(receipt.details.values["surface"] == .string("music.library.auto_organization"))
    }
}
