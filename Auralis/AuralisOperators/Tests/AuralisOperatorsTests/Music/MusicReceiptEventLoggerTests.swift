import AuralisCrypto
import Foundation
import AuralisOperators
import AuralisReceipts
import SwiftData
import Testing

struct MusicReceiptEventLoggerTests {
    @MainActor
    private func makeReceiptStore() throws -> SwiftDataReceiptStore {
        let container = try MusicFeatureTestModelContainers.receipts()
        return SwiftDataReceiptStore(
            modelContext: ModelContext(container)
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
        // The playlist's own id, not a placeholder. This assertion used to pin
        // `<redacted-opaque-token>`, which meant two different playlists produced byte-identical
        // identity fields and the `delete_playlist` rollback this receipt advertises could not be
        // targeted. The sanitizer was classifying any 24+ character `[A-Za-z0-9_-]` run as an
        // opaque token *before* honouring the declared `.label` kind, and a UUID string matches.
        #expect(receipt.details.values["playlistID"] == .string(playlistID.uuidString))
        #expect(receipt.details.values["playlistTitle"] == .string("Night Drive"))
        // The media ids themselves, not placeholders. This assertion used to pin
        // `<redacted-unexpected-string>` as correct, which meant the field a music receipt exists to
        // record — *which* items an action touched — was never actually on disk. `stringArray`
        // accepted `kind: .label` and discarded it, so each element was classified as `.array`.
        #expect(receipt.details.values["affectedMediaIDs"] == .array([.string("track-1"), .string("track-2")]))
    }

    /// `MusicReceiptStateSummary.playlist(…)` nests `playlistID` inside the before/after objects,
    /// where the sanitizer has no writer-declared kind to honour and must infer one from the key.
    /// Until the inference exempted UUIDs the top-level field named the playlist while both
    /// summaries said `<redacted-opaque-token>` — one receipt contradicting itself about whether it
    /// knows what it changed, which is also what made the `manual_reverse_change` rollback it
    /// advertises impossible to target.
    @Test("playlist modification receipts name the same playlist at top level and in both summaries")
    @MainActor
    func playlistModificationSummariesNameThePlaylist() async throws {
        let receiptStore = try makeReceiptStore()
        let logger = MusicReceiptEventLogger(receiptStore: receiptStore)
        let playlistID = UUID()

        _ = try await logger.recordPlaylistModified(
            playlistID: playlistID,
            playlistTitle: "Night Drive",
            affectedMediaIDs: ["track-1"],
            beforeSummary: .playlist(playlistID: playlistID, playlistTitle: "Night Drive", itemCount: 1),
            afterSummary: .playlist(playlistID: playlistID, playlistTitle: "Night Drive", itemCount: 2),
            changedFields: ["itemCount"],
            context: MusicReceiptContext(
                triggerCause: .userInitiated,
                actor: .user,
                correlationID: "playlist-modify",
                surface: "music.playlist.detail"
            )
        )

        let receipt = try #require(
            try await receiptStore.receipts(forCorrelationID: "playlist-modify", limit: 1).first
        )

        #expect(receipt.details.values["playlistID"] == .string(playlistID.uuidString))
        for key in ["beforeSummary", "afterSummary"] {
            guard case .object(let summary)? = receipt.details.values[key] else {
                Issue.record("Expected \(key) to be an object")
                return
            }
            #expect(summary["playlistID"] == .string(playlistID.uuidString))
            #expect(summary["playlistID"] == receipt.details.values["playlistID"])
        }
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

    /// `MusicReceiptActorValue` is a *kind*, not an identity. Derived alone it stamps every operator
    /// pack with the in-tree `music.operator` id, so a lease, denial or rate limit keyed on that
    /// identity binds the wrong principal and the audit chain names the wrong pack. The context's
    /// `actorDetail` is the injection point for callers that know the real id; the second half pins
    /// the fallback, because the override must not quietly become mandatory for the in-app call
    /// sites that have no identity to offer.
    @Test("an explicit actorDetail names the acting pack; its absence keeps the derived default")
    @MainActor
    func explicitActorDetailOverridesDerivedPackIdentity() async throws {
        let receiptStore = try makeReceiptStore()
        let logger = MusicReceiptEventLogger(receiptStore: receiptStore)

        _ = try await logger.recordPlaylistCreated(
            playlistID: UUID(),
            playlistTitle: "Pack Picks",
            affectedMediaIDs: ["track-1"],
            itemCount: 1,
            context: MusicReceiptContext(
                triggerCause: .operatorAction,
                actor: .operator,
                actorDetail: .operatorPack("acme.tunes"),
                correlationID: "pack-explicit",
                surface: "music.playlist.new"
            )
        )

        let explicit = try #require(
            try await receiptStore.receipts(forCorrelationID: "pack-explicit", limit: 1).first
        )

        #expect(explicit.actorDetail?.identifier == "acme.tunes")
        #expect(explicit.actorDetail?.kind == "operator")
        // The coarse column still derives from the detail actually written, so overriding one cannot
        // leave the two disagreeing about whether a human acted.
        #expect(explicit.actor == .system)

        _ = try await logger.recordPlaylistCreated(
            playlistID: UUID(),
            playlistTitle: "House Picks",
            affectedMediaIDs: ["track-2"],
            itemCount: 1,
            context: MusicReceiptContext(
                triggerCause: .operatorAction,
                actor: .operator,
                correlationID: "pack-derived",
                surface: "music.playlist.new"
            )
        )

        let derived = try #require(
            try await receiptStore.receipts(forCorrelationID: "pack-derived", limit: 1).first
        )

        #expect(derived.actorDetail?.identifier == "music.operator")
        #expect(derived.actorDetail?.kind == "operator")
    }
}
