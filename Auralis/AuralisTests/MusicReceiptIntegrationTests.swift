@testable import Auralis
import AuralisFoundation
import Foundation
import MusicFeature
import AuralisPolicy
import AuralisReceipts
import SwiftData
import Testing

struct MusicReceiptIntegrationTests {
    @Test("playlist creation and modification emit namespaced music receipts through the shared receipt store")
    @MainActor
    func playlistMutationsWriteMusicReceipts() async throws {
        let container = try TestModelContainers.primary()
        let context = ModelContext(container)
        let receiptStore = SwiftDataReceiptStore(
            modelContext: context
        )
        let logger = MusicReceiptEventLogger(receiptStore: receiptStore)
        let creationContext = MusicReceiptContext(
            triggerCause: .userInitiated,
            actor: .user,
            correlationID: "playlist-flow",
            surface: "music.playlist.new"
        )

        let creationSnapshot = try await context.createPlaylist(
            title: "Night Drive",
            description: "City lights",
            tracks: [],
            musicReceiptLogger: logger,
            receiptContext: creationContext
        )
        let playlist = try #require(try fetchPlaylist(context, by: creationSnapshot.playlistID))

        try await context.updatePlaylist(
            playlist,
            title: "Night Drive Deluxe",
            description: "City lights at 2AM",
            musicReceiptLogger: logger,
            receiptContext: MusicReceiptContext(
                triggerCause: .userInitiated,
                actor: .user,
                correlationID: "playlist-flow",
                surface: "music.playlist.detail"
            )
        )

        let receipts = try await receiptStore.receipts(forCorrelationID: "playlist-flow", limit: 10)

        #expect(receipts.map(\.trigger) == [
            "music.playlist.modified",
            "music.playlist.created"
        ])

        let createdReceipt = try #require(receipts.first(where: { $0.trigger == "music.playlist.created" }))
        let modifiedReceipt = try #require(receipts.first(where: { $0.trigger == "music.playlist.modified" }))

        #expect(createdReceipt.scope == "music.playlist")
        #expect(createdReceipt.summary == "Created playlist")
        #expect(createdReceipt.details.values["eventType"] == .string("music.playlist.created"))
        #expect(createdReceipt.details.values["capabilityUsed"] == .string("playlist_management"))
        #expect(createdReceipt.details.values["policyDecision"] == .string("allowed"))
        #expect(createdReceipt.details.values["surface"] == .string("music.playlist.new"))
        #expect(createdReceipt.details.values["beforeSummary"] == .null)
        #expect(createdReceipt.details.values["playlistTitle"] == .string("Night Drive"))
        #expect(modifiedReceipt.details.values["eventType"] == .string("music.playlist.modified"))
        #expect(modifiedReceipt.details.values["surface"] == .string("music.playlist.detail"))
        #expect(modifiedReceipt.details.values["operation"] == .string("description,title"))
        #expect(modifiedReceipt.details.values["rollbackAvailability"] == .string("manual_reverse_change"))

        guard case .object(let afterSummary)? = modifiedReceipt.details.values["afterSummary"] else {
            Issue.record("Expected afterSummary object for playlist modification receipt.")
            return
        }

        #expect(afterSummary["playlistTitle"] == .string("Night Drive Deluxe"))
        #expect(afterSummary["itemCount"] == .number(0))
    }

    @Test("auto-organization dry runs emit dry-run receipts through the shared store")
    @MainActor
    func autoOrganizationDryRunWritesReceipt() async throws {
        let container = try TestModelContainers.primary()
        let context = ModelContext(container)
        let receiptStore = SwiftDataReceiptStore(
            modelContext: context
        )
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
