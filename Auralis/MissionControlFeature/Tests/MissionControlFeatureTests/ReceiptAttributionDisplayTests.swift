import AuralisPrimaryModels
import Foundation
@testable import MissionControlFeature
import ReceiptsCore
import AuralisRuntime
import Testing

/// P0.5-601/602 — the structured attribution has to be *readable*, not just stored. These pin what a
/// person actually sees on a receipt, including that no raw serialization value leaks through.
@Suite("Receipt attribution display")
struct ReceiptAttributionDisplayTests {
    private func record(
        actor: ReceiptActor = .system,
        actorDetail: ReceiptActorDetail? = nil,
        authorityDetail: ReceiptAuthorityDetail? = nil
    ) -> ReceiptRecord {
        ReceiptRecord(
            id: UUID(),
            sequenceID: 1,
            createdAt: .now,
            actor: actor,
            actorDetail: actorDetail,
            authorityDetail: authorityDetail,
            mode: .observe,
            trigger: "tool.executed",
            scope: "runtime",
            summary: "Did the thing",
            provenance: "local",
            isSuccess: true,
            correlationID: "corr-1",
            accountSequenceID: 1,
            payloadHash: "p",
            previousReceiptHash: "g",
            chainHash: "c",
            details: ReceiptPayload(values: [:])
        )
    }

    @Test("a named routine reads as its kind and name, not \"system\"")
    func routineActorReadsAsNameNotSystem() {
        let subject = record(
            actorDetail: ReceiptActorDetail(
                kind: "scheduledRoutine",
                identifier: "morning.brief",
                displayName: "Morning Brief"
            )
        )
        #expect(ReceiptAttributionDisplay.actorLabel(for: subject) == "Scheduled routine — Morning Brief")
    }

    @Test("an operator falls back to its identifier when it has no display name")
    func operatorFallsBackToIdentifier() {
        let subject = record(actorDetail: ReceiptActorDetail(kind: "operator", identifier: "operator.research.brief"))
        #expect(ReceiptAttributionDisplay.actorLabel(for: subject) == "Operator — operator.research.brief")
    }

    @Test("a kind with no identity at all reads as just the kind title")
    func bareKindReadsAsTitle() {
        #expect(ReceiptAttributionDisplay.actorLabel(for: record(actorDetail: ReceiptActorDetail(kind: "human"))) == "Human")
    }

    /// Receipts written before the structured column must still render something sensible.
    @Test("legacy receipts fall back to the coarse actor")
    func legacyReceiptFallsBackToCoarseActor() {
        #expect(ReceiptAttributionDisplay.actorLabel(for: record(actor: .system)) == "System")
        #expect(ReceiptAttributionDisplay.actorLabel(for: record(actor: .user)) == "User")
    }

    /// An unknown kind (a receipt written by a newer build) must not crash or blank out.
    @Test("an unrecognized kind degrades to the stored string")
    func unknownKindDegradesGracefully() {
        let subject = record(actorDetail: ReceiptActorDetail(kind: "futureKind", identifier: "x"))
        #expect(ReceiptAttributionDisplay.actorLabel(for: subject) == "futureKind — x")
    }

    @Test("model inference reads as a privacy-facing label")
    func inferenceReadsAsPrivacyLabel() {
        let remote = record(
            actorDetail: ReceiptActorDetail(
                kind: "model",
                identifier: "opus",
                inferenceLocality: "remote",
                inferenceProvider: "anthropic"
            )
        )
        #expect(ReceiptAttributionDisplay.inferenceLabel(for: remote) == "Off-device · anthropic")

        let localNoProvider = record(
            actorDetail: ReceiptActorDetail(kind: "model", identifier: "afm", inferenceLocality: "local")
        )
        #expect(ReceiptAttributionDisplay.inferenceLabel(for: localNoProvider) == "On-device")

        // No model ran: nothing to show, rather than a misleading blank row.
        #expect(ReceiptAttributionDisplay.inferenceLabel(for: record(actorDetail: ReceiptActorDetail(kind: "human"))) == nil)
    }

    /// The authority row must show a capability *title*, never the snake_case wire value.
    @Test("a lease authority reads as a human capability title")
    func leaseAuthorityReadsAsCapabilityTitle() {
        let subject = record(
            authorityDetail: ReceiptAuthorityDetail(
                source: "lease",
                leaseID: UUID().uuidString,
                capability: "playback_queue",
                scope: "execution",
                reason: "Planner may queue playback."
            )
        )
        let label = ReceiptAttributionDisplay.authorityLabel(for: subject)
        #expect(label?.hasPrefix("Capability lease — ") == true)
        #expect(label?.contains("_") == false, "must not leak the snake_case wire value")
        #expect(ReceiptAttributionDisplay.authorityReason(for: subject) == "Planner may queue playback.")
    }

    @Test("the other authority sources read plainly")
    func otherAuthoritySourcesRead() {
        #expect(
            ReceiptAttributionDisplay.authorityLabel(for: record(authorityDetail: ReceiptAuthorityDetail(source: "humanApproval")))
                == "Approved by you"
        )
        #expect(
            ReceiptAttributionDisplay.authorityLabel(for: record(authorityDetail: ReceiptAuthorityDetail(source: "policyDefault")))
                == "Allowed by standing policy"
        )
    }

    /// A receipt with no recorded authority shows no authority row at all — better than implying one.
    @Test("no recorded authority shows nothing")
    func missingAuthorityShowsNothing() {
        #expect(ReceiptAttributionDisplay.authorityLabel(for: record()) == nil)
        #expect(ReceiptAttributionDisplay.authorityReason(for: record()) == nil)
    }
}
