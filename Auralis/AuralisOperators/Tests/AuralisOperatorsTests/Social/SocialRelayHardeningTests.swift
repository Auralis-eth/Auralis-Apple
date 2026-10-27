import Foundation
@testable import AuralisOperators
import Testing

/// Social v1 relay-hardening gate.
///
/// Every test here is an attack or a failure mode the package accepted before this suite existed.
/// The relay seals envelopes with one *shared* per-session key, so possession of the invite — not
/// authorship — is all the transport proves; each case below is something an invite holder, or a
/// hostile relay, could previously have done to a session.
@Suite("Social relay hardening")
struct SocialRelayHardeningTests {
    private let sessionID = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!

    private func identity(
        _ id: String,
        role: SharedRole = .collaborator,
        state: SocialParticipantVerificationState = .verified,
        account: String? = nil
    ) -> SocialParticipantIdentity {
        SocialParticipantIdentity(
            participantID: id,
            caip10Account: account ?? "eip155:1:0x\(id)",
            displayName: id,
            role: role,
            verificationState: state
        )
    }

    private func envelope(
        _ author: String,
        _ event: SocialEvent,
        at seconds: TimeInterval,
        account: String? = nil
    ) -> SocialEventEnvelope {
        SocialEventEnvelope(
            id: UUID(),
            sessionID: sessionID,
            authorParticipantID: author,
            authorCAIP10Account: account,
            createdAt: Date(timeIntervalSince1970: seconds),
            event: event
        )
    }

    /// Owner + verified collaborator.
    private var membership: [SocialEventEnvelope] {
        [
            envelope("owner", .sessionCreated(title: "Trip", correlationID: "corr"), at: 0),
            envelope("owner", .participantJoined(identity("owner", role: .owner)), at: 1),
            envelope("owner", .participantJoined(identity("collab")), at: 2)
        ]
    }

    /// Reduces `membership` plus `extra`, with the membership records marked as ones this
    /// installation established.
    ///
    /// The projection's defaults trust nothing: a relay-delivered `.verified` identity is downgraded
    /// to `.pending` and so carries no binding authority, and no participant can bootstrap the owner
    /// role. A fixture built from a bare envelope array therefore has no members who can share,
    /// vote, or resolve anything. This suite models the installation that *created* the session, and
    /// for that installation the real ``SocialEventLogStore`` records exactly these envelopes as
    /// locally minted — so supplying the provenance is what makes the fixture match a live log
    /// rather than weakening it. `extra` stays relay-delivered, which is what keeps every attack
    /// below an attack.
    /// `extraFromThisInstallation` defaults to `false` because this suite is *about* the wire: most
    /// tests below are relay attacks and must stay relay-delivered.
    ///
    /// It exists because that default is wrong for the tests whose subject is an authority rule
    /// rather than provenance — the approval quorum and the self-removal guard. Those were feeding
    /// relay-delivered envelopes authored as the owner, which the projection now refuses as
    /// `.impersonatedAuthor` before the rule under test is ever reached. Leaving them that way would
    /// have kept them green while silently retiring the coverage they are named for.
    private func reduce(
        adding extra: [SocialEventEnvelope] = [],
        locallyMinted: Set<UUID> = [],
        extraFromThisInstallation: Bool = false
    ) -> SocialSessionProjection {
        // Captured once: `membership` mints fresh envelope ids on every access.
        let base = membership
        let extraIDs = extraFromThisInstallation ? Set(extra.map(\.id)) : []
        return SocialSessionProjection.reduce(
            base + extra,
            sessionID: sessionID,
            locallyMintedEventIDs: Set(base.map(\.id)).union(locallyMinted).union(extraIDs)
        )
    }

    // MARK: - `.local` trust state is not transportable

    @Test("a relay-delivered `.local` identity is refused authoring authority")
    func localIdentityFromTheWireIsRejected() {
        let attack = envelope("mallory", .participantJoined(identity("mallory", state: .local)), at: 10)
        let projection = reduce(adding: [attack])

        #expect(projection.participants["mallory"] == nil)
        #expect(
            reduce()
                .rejectionReason(for: attack) == .untrustedLocalIdentity
        )
    }

    /// The whole point of the rejection: `.local` clears `canAuthorBindingEvents`, so admitting it
    /// off the wire handed an invite holder the authority a wallet proof is supposed to gate.
    @Test("a relay-delivered `.local` identity cannot then share a receipt")
    func localIdentityCannotShareReceipts() {
        let receiptID = UUID()
        let projection = reduce(
            adding: [
                envelope("mallory", .participantJoined(identity("mallory", state: .local)), at: 10),
                envelope("mallory", .receiptShared(receiptID), at: 11)
            ]
        )

        #expect(projection.sharedReceiptIDs.isEmpty)
    }

    @Test("an installation's own `.local` identity is still admitted")
    func trustedLocalIdentityIsAdmitted() {
        let mine = envelope("me", .participantJoined(identity("me", state: .local)), at: 10)
        let projection = reduce(
            adding: [mine],
            locallyMinted: [mine.id]
        )

        #expect(projection.participants["me"]?.verificationState == .local)
        #expect(projection.participants["me"]?.canAuthorBindingEvents == true)
    }

    /// The distinction is per-envelope, not per-participant: an attacker who knows a locally-minted
    /// participant's ID must not be able to ride on it from the relay.
    @Test("a relay envelope cannot reuse a locally-minted participant's `.local` identity")
    func relayCannotReuseLocalParticipantID() {
        let mine = envelope("me", .participantJoined(identity("me", state: .local)), at: 10)
        let spoofed = envelope("me", .participantUpdated(identity("me", role: .owner, state: .local)), at: 11)
        let projection = reduce(
            adding: [mine, spoofed],
            locallyMinted: [mine.id]
        )

        #expect(projection.participants["me"]?.role == .collaborator)
    }

    // MARK: - Collaborative approval quorum

    @Test("a collaborator cannot force-resolve an approval it lacks the votes for")
    func collaboratorCannotForceApproval() {
        let approvalID = UUID()
        let projection = reduce(
            adding: [
                envelope("collab", .approvalOpened(
                    SocialApprovalDraft(id: approvalID, prompt: "Send funds?", requiredApprovals: 3)
                ), at: 10),
                envelope("collab", .approvalResolved(approvalID: approvalID, resolution: .approved), at: 11)
            ],
            extraFromThisInstallation: true
        )

        #expect(projection.approvals[approvalID]?.resolution == .pending)
    }

    @Test("force-resolving an approval is rejected as ownerRequired")
    func forcedResolutionReasonIsOwnerRequired() {
        let approvalID = UUID()
        let projection = reduce(
            adding: [
                envelope("collab", .approvalOpened(
                    SocialApprovalDraft(id: approvalID, prompt: "Send funds?", requiredApprovals: 3)
                ), at: 10)
            ],
            extraFromThisInstallation: true
        )
        let attack = envelope("collab", .approvalResolved(approvalID: approvalID, resolution: .approved), at: 11)

        // Asked as locally minted so the diagnosis is the owner-authority one. A relay-delivered
        // copy of the same envelope is refused earlier and for a different reason — pinned by
        // `relayEnvelopeCannotImpersonateTheOwnerToResolveAnApproval` below.
        #expect(projection.rejectionReason(for: attack, isLocallyMinted: true) == .ownerRequired)
    }

    /// The provenance half of the quorum rule. `approvalResolved` writes `explicitResolution`, which
    /// outranks the vote tally, so an impersonated owner resolution force-approves a 3-of-3 with
    /// zero votes cast — defeating the entire multi-party sign-off primitive.
    ///
    /// **The approval is opened locally, and that is the whole point of the fixture.** An earlier
    /// form of this test delivered *both* envelopes over the relay and asserted only
    /// `approvals[approvalID] == nil` — which is a statement about the `approvalOpened` envelope
    /// being refused, not about the resolution. The attack has no reason to open its own approval:
    /// the owner opens one legitimately and the attacker force-resolves *that*. So the test was
    /// green against the force-resolve path never being exercised at all, and would have stayed
    /// green if the provenance gate on `approvalResolved` were lifted.
    @Test("a relay envelope cannot force-resolve an approval by naming the owner as its author")
    func relayEnvelopeCannotImpersonateTheOwnerToResolveAnApproval() {
        let approvalID = UUID()
        // Opened by the owner on the owner's own device: a real, pending 3-of-3 sign-off.
        let opened = envelope("owner", .approvalOpened(
            SocialApprovalDraft(id: approvalID, prompt: "Send funds?", requiredApprovals: 3)
        ), at: 10)
        // Sealed with the shared session key every invite holder has, naming the owner as author.
        let forced = envelope("owner", .approvalResolved(approvalID: approvalID, resolution: .approved), at: 11)

        let projection = reduce(adding: [opened, forced], locallyMinted: [opened.id])

        // The approval exists, is still pending, and has no votes — so the refusal is of the
        // resolution itself, not of the approval ever having been opened.
        #expect(projection.approvals[approvalID] != nil, "the fixture never opened the approval")
        #expect(projection.approvals[approvalID]?.votes.isEmpty == true)
        #expect(
            projection.approvals[approvalID]?.resolution == .pending,
            "a relay envelope force-approved a 3-of-3 with zero votes cast"
        )
        #expect(projection.rejectionReason(for: forced) == .impersonatedAuthor)

        // And the open side stays refused too, so neither half of the original attack is lost.
        let relayOpened = envelope("owner", .approvalOpened(
            SocialApprovalDraft(id: UUID(), prompt: "Send funds?", requiredApprovals: 3)
        ), at: 12)
        #expect(projection.rejectionReason(for: relayOpened) == .impersonatedAuthor)
    }

    /// Payload-level author binding, which is a separate rule from the envelope-level one above and
    /// had no coverage at all.
    ///
    /// `approvalVoteCast`, `queueVoteCast` and `queueProposalCreated` each carry a participant id
    /// *inside* the payload, and each is checked against `authorParticipantID`. Removing any of the
    /// three left all 178 tests green, which is what makes them worth pinning: the vote payload's id
    /// is the key `SocialApprovalState.record(_:)` stores under, so an envelope whose payload names
    /// a different participant casts that participant's vote — one actor resolving a multi-party
    /// sign-off on another's behalf.
    ///
    /// Asked as locally minted, because that is the only way these events reach the rule at all: off
    /// the wire they are refused earlier as `.impersonatedAuthor`. So this is the rule's one
    /// reachable surface, not a hypothetical one.
    @Test("payload author ids are bound to the envelope's author")
    func payloadAuthorIDsAreBoundToTheEnvelopeAuthor() {
        let approvalID = UUID()
        let projection = reduce(
            adding: [
                envelope("collab", .approvalOpened(
                    SocialApprovalDraft(id: approvalID, prompt: "Ship?", requiredApprovals: 2)
                ), at: 10)
            ],
            extraFromThisInstallation: true
        )

        // A vote cast in the owner's name by an envelope `collab` authored.
        let forgedApprovalVote = envelope("collab", .approvalVoteCast(
            approvalID: approvalID,
            vote: SocialApprovalVote(participantID: "owner", approved: true)
        ), at: 11)
        #expect(
            projection.rejectionReason(for: forgedApprovalVote, isLocallyMinted: true) == .mismatchedAuthor,
            "one participant cast another participant's approval vote"
        )

        let forgedQueueVote = envelope("collab", .queueVoteCast(
            SocialQueueVote(proposalID: UUID(), participantID: "owner", approved: true)
        ), at: 12)
        #expect(
            projection.rejectionReason(for: forgedQueueVote, isLocallyMinted: true) == .mismatchedAuthor
        )

        let forgedProposal = envelope("collab", .queueProposalCreated(
            SocialQueueProposal(mediaItemID: "song.1", title: "Song 1", proposedByParticipantID: "owner")
        ), at: 13)
        #expect(
            projection.rejectionReason(for: forgedProposal, isLocallyMinted: true) == .mismatchedAuthor
        )

        // The direction that must stay open, so the rule cannot be satisfied by refusing everything.
        let ownVote = envelope("collab", .approvalVoteCast(
            approvalID: approvalID,
            vote: SocialApprovalVote(participantID: "collab", approved: true)
        ), at: 14)
        #expect(projection.rejectionReason(for: ownVote, isLocallyMinted: true) == nil)
    }

    @Test("the owner may still resolve an unopposed approval")
    func ownerCanResolveUnopposedApproval() {
        let approvalID = UUID()
        let projection = reduce(
            adding: [
                envelope("owner", .approvalOpened(
                    SocialApprovalDraft(id: approvalID, prompt: "Ship?", requiredApprovals: 3)
                ), at: 10),
                envelope("owner", .approvalResolved(approvalID: approvalID, resolution: .approved), at: 11)
            ],
            extraFromThisInstallation: true
        )

        #expect(projection.approvals[approvalID]?.resolution == .approved)
    }

    /// "A single objection blocks" is the documented conservative default; an owner override must not
    /// be able to quietly turn a recorded "no" into an approval.
    @Test("an owner's approval cannot override a cast objection")
    func objectionOutranksOwnerResolution() {
        let approvalID = UUID()
        let projection = reduce(
            adding: [
                envelope("owner", .approvalOpened(
                    SocialApprovalDraft(id: approvalID, prompt: "Ship?", requiredApprovals: 1)
                ), at: 10),
                envelope("collab", .approvalVoteCast(
                    approvalID: approvalID,
                    vote: SocialApprovalVote(participantID: "collab", approved: false)
                ), at: 11),
                envelope("owner", .approvalResolved(approvalID: approvalID, resolution: .approved), at: 12)
            ],
            extraFromThisInstallation: true
        )

        #expect(projection.approvals[approvalID]?.resolution == .rejected)
    }

    @Test("a vote on an approval that was never opened is diagnosable, not silent")
    func unknownApprovalIsDiagnosable() {
        let projection = reduce()
        let orphan = envelope("collab", .approvalVoteCast(
            approvalID: UUID(),
            vote: SocialApprovalVote(participantID: "collab", approved: true)
        ), at: 10)

        // Locally minted, so the diagnosis is about the *approval* being unknown rather than about
        // the envelope's origin. The point of this test is that a vote under clock skew is
        // diagnosable instead of vanishing, and that reason only surfaces once the author passes.
        #expect(projection.rejectionReason(for: orphan, isLocallyMinted: true) == .unknownApproval)

        // The `.approvalResolved` arm of the same rule, which had no test — deleting it left the
        // suite green. The outcome is inert either way (`apply` resolves through `approvals[id]?`),
        // so what is lost is only the diagnosis; but these reasons exist precisely so each refusal
        // is individually diagnosable, and without this a resolution arriving under clock skew
        // vanishes from relay diagnostics instead of being reported.
        //
        // Authored by the owner, so the envelope clears the `.ownerAuthor` requirement and the
        // unknown approval is the reason that actually answers.
        let orphanResolution = envelope("owner", .approvalResolved(
            approvalID: UUID(),
            resolution: .approved
        ), at: 11)
        #expect(
            projection.rejectionReason(for: orphanResolution, isLocallyMinted: true) == .unknownApproval
        )
    }

    // MARK: - Owner self-removal cannot strand the session

    @Test("the owner cannot remove itself")
    func ownerCannotSelfRemove() {
        let attack = envelope("owner", .participantRemoved(participantID: "owner"), at: 10)
        let projection = reduce(adding: [attack], extraFromThisInstallation: true)

        #expect(projection.participants["owner"]?.role == .owner)
        #expect(projection.removedParticipantIDs.isEmpty)
        // Locally minted: the owner really is trying to remove itself on its own device, which is
        // the case the guard exists for. Refusing it off the wire proves nothing about this rule.
        #expect(
            reduce()
                .rejectionReason(for: attack, isLocallyMinted: true) == .selfRemoval
        )
    }

    /// The reason self-removal matters: an ownerless session reopens the bootstrap exemption, and
    /// whoever is left can self-promote into the owner-only authority.
    @Test("owner self-removal cannot be chained into a takeover")
    func selfRemovalCannotBeChainedIntoTakeover() {
        let projection = reduce(
            adding: [
                envelope("owner", .participantRemoved(participantID: "owner"), at: 10),
                envelope("collab", .participantUpdated(identity("collab", role: .owner)), at: 11),
                envelope("collab", .sessionEnded(endedAt: Date(timeIntervalSince1970: 12)), at: 12)
            ],
            // Locally minted so the chain is refused on its *authority* at every link — self-removal,
            // then escalation, then owner-only. Off the wire the first link is already an
            // impersonation, which would make this pass without exercising the chain it is named for.
            extraFromThisInstallation: true
        )

        #expect(projection.participants["collab"]?.role == .collaborator)
        #expect(projection.endedAt == nil)
    }

    /// The `removedParticipantIDs.isEmpty` half of ``ownerBootstrapIsOpen``, which had no test.
    ///
    /// `selfRemovalCannotBeChainedIntoTakeover` above advertises this chain but cannot reach it: its
    /// first link is refused as `.selfRemoval`, so `removedParticipantIDs` stays empty and
    /// `hasOwner` stays true — the escalation is refused by the `!hasOwner` conjunct and the removal
    /// conjunct is never consulted. Deleting that conjunct left all 184 tests green.
    ///
    /// Reaching it needs an ownerless session that *used* to have an owner, by a route the
    /// self-removal guard does not cover. The owner removes a third party, then demotes *itself* —
    /// accepted, because `describesAuthor` holds and `roleEscalation` only fires on a `.owner` claim.
    /// Now `hasOwner` is false and a removal has happened, which is the aftermath of a removal rather
    /// than a fresh session, and the exemption must stay shut: otherwise whoever is left self-promotes
    /// into the owner-only authority (`sessionEnded`, `participantRemoved`, `approvalResolved`) that
    /// the removal was an exercise of.
    ///
    /// Every envelope is locally minted, so the chain is refused on its *authority* rather than on
    /// provenance — off the wire each link is already an impersonation and the test would pass
    /// without exercising the clause it is named for.
    @Test("an ownerless session that saw a removal does not reopen owner bootstrap")
    func removalKeepsOwnerBootstrapClosed() {
        let third = envelope("owner", .participantJoined(identity("third")), at: 3)
        let removal = envelope("owner", .participantRemoved(participantID: "third"), at: 4)
        let selfDemotion = envelope("owner", .participantUpdated(identity("owner", role: .viewer)), at: 5)
        let selfPromotion = envelope("collab", .participantUpdated(identity("collab", role: .owner)), at: 6)

        let projection = reduce(
            adding: [third, removal, selfDemotion],
            extraFromThisInstallation: true
        )

        // The preconditions the clause is about, asserted so this cannot pass for another reason.
        #expect(projection.removedParticipantIDs.contains("third"))
        #expect(projection.participants["owner"]?.role == .viewer)
        #expect(projection.participants.values.contains { $0.role == .owner } == false)

        #expect(
            projection.rejectionReason(for: selfPromotion, isLocallyMinted: true) == .roleEscalation
        )
    }

    // MARK: - CAIP-10 identity binding

    @Test("an envelope cannot attribute work to another participant's account")
    func forgedAuthorAccountIsRejected() {
        let receiptID = UUID()
        let attack = envelope(
            "collab",
            .receiptShared(receiptID),
            at: 10,
            account: "eip155:1:0xVICTIM"
        )
        let projection = reduce(adding: [attack])

        #expect(projection.sharedReceiptIDs.isEmpty)
        #expect(
            reduce()
                .rejectionReason(for: attack) == .mismatchedAccount
        )
    }

    /// EIP-55 capitalization is a checksum, not identity: the same address in checksummed and
    /// lowercase form is the same account and must not read as an impersonation attempt.
    @Test("EIP-55 capitalization differences are not treated as a different account")
    func checksumCaseIsNotAnIdentityChange() {
        let checksummed = "eip155:1:0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"
        let lowercased = "eip155:1:0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed"
        let receiptID = UUID()

        // Alice's own installation: her record is locally minted, so she is genuinely verified and
        // the share below is a binding event she is entitled to author. The question under test is
        // purely whether the two spellings of her address read as one account.
        let joined = envelope(
            "alice",
            .participantJoined(identity("alice", account: checksummed)),
            at: 1,
            account: checksummed
        )
        let shared = envelope("alice", .receiptShared(receiptID), at: 2, account: lowercased)
        let projection = SocialSessionProjection.reduce(
            [joined, shared],
            sessionID: sessionID,
            // The share is minted here too: it is Alice's own installation, so this is the shape a
            // live log holds. Marking only the join left the share relay-delivered, which the author
            // binding now refuses before the two spellings are ever compared.
            locallyMintedEventIDs: [joined.id, shared.id]
        )

        #expect(projection.sharedReceiptIDs == [receiptID])
    }

    @Test("an envelope that claims no account is still accepted")
    func absentAuthorAccountIsAllowed() {
        let receiptID = UUID()
        let projection = reduce(
            adding: [envelope("collab", .receiptShared(receiptID), at: 10)],
            // The subject is the *absent account* case, not provenance.
            extraFromThisInstallation: true
        )

        #expect(projection.sharedReceiptIDs == [receiptID])
    }
}

/// Provenance is decided by how an envelope entered the log, not by anything inside it.
///
/// This is the seam that lets a purely local ritual keep its `.local` author while a relay-delivered
/// `.local` claim is still refused — the two cases are byte-identical on the wire.
@Suite("Social event provenance")
struct SocialEventProvenanceTests {
    private let sessionID = UUID(uuidString: "00000000-0000-0000-0000-0000000000CC")!

    private func localOwnerJoin() -> SocialEventEnvelope {
        SocialEventEnvelope(
            sessionID: sessionID,
            authorParticipantID: "me",
            createdAt: Date(timeIntervalSince1970: 1),
            event: .participantJoined(
                SocialParticipantIdentity(
                    participantID: "me",
                    caip10Account: "auralis:local:me",
                    displayName: "Me",
                    role: .owner,
                    verificationState: .local
                )
            )
        )
    }

    private func ritualRun(at seconds: TimeInterval) -> SocialEventEnvelope {
        SocialEventEnvelope(
            sessionID: sessionID,
            authorParticipantID: "me",
            createdAt: Date(timeIntervalSince1970: seconds),
            event: .ritualRunChanged(
                ritualID: "ritual.collaborative-listening",
                status: .completed,
                artifactIDs: [],
                receiptIDs: []
            )
        )
    }

    /// The local ritual flow: `appendLocal` mints, so the `.local` author is trusted and the run it
    /// authored projects. This is the case that regressed when provenance was a caller-supplied list.
    @Test("a locally appended `.local` author can file a ritual run")
    func locallyAppendedLocalAuthorProjects() async {
        let store = SocialEventLogStore()
        await store.appendLocal([localOwnerJoin(), ritualRun(at: 2)])

        let projection = await store.projection(sessionID: sessionID)

        #expect(projection.participants["me"]?.verificationState == .local)
        #expect(projection.ritualRunDetails["ritual.collaborative-listening"]?.status == .completed)
    }

    /// Publishing our own events over the relay does not make them someone else's.
    @Test("an outbound-queued `.local` author is still locally minted")
    func enqueuedOutboundLocalAuthorProjects() async {
        let store = SocialEventLogStore()
        await store.enqueueOutbound([localOwnerJoin(), ritualRun(at: 2)])

        let projection = await store.projection(sessionID: sessionID)

        #expect(projection.ritualRunDetails["ritual.collaborative-listening"]?.status == .completed)
    }

    /// The identical bytes arriving from a relay are refused.
    @Test("the same `.local` author delivered by a relay is refused")
    func relayDeliveredLocalAuthorIsRefused() async {
        let store = SocialEventLogStore()
        await store.appendInbound(localOwnerJoin(), topic: "topic-a")
        await store.appendInbound(ritualRun(at: 2), topic: "topic-a")

        let projection = await store.projection(sessionID: sessionID)

        #expect(projection.participants["me"] == nil)
        #expect(projection.ritualRunDetails.isEmpty)
    }

    @Test("provenance survives a persistence round-trip")
    func provenanceRoundTripsThroughPersistence() async throws {
        let store = SocialEventLogStore()
        await store.appendLocal([localOwnerJoin(), ritualRun(at: 2)])
        let snapshot = await store.currentSnapshot()

        let decoded = try JSONDecoder().decode(
            SocialEventLogSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )

        #expect(decoded.locallyMintedEventIDs == snapshot.locallyMintedEventIDs)
        #expect(decoded.projection(sessionID: sessionID).ritualRunDetails.isEmpty == false)
    }

    /// A payload written before provenance existed cannot be reconstructed, so it decodes as "none
    /// of it is mine" — losing historical display rather than granting authority.
    @Test("a pre-provenance payload decodes fail-closed")
    func legacyPayloadDecodesFailClosed() throws {
        // `syncStates` is keyed by UUID, so it encodes as a flat array rather than an object.
        let legacy = Data(#"{"envelopes":[],"pendingOutboundEventIDs":[],"invites":[],"replayCursors":{},"syncStates":[]}"#.utf8)

        let decoded = try JSONDecoder().decode(SocialEventLogSnapshot.self, from: legacy)

        #expect(decoded.locallyMintedEventIDs.isEmpty)
    }
}

/// Replay-cursor and join-challenge hardening (Social v1).
@Suite("Social replay and join hardening")
struct SocialReplayHardeningTests {
    private func envelope(
        sessionID: UUID = UUID(),
        at seconds: TimeInterval
    ) -> SocialEventEnvelope {
        SocialEventEnvelope(
            sessionID: sessionID,
            authorParticipantID: "alice",
            createdAt: Date(timeIntervalSince1970: seconds),
            event: .workflowShared("w.\(seconds)")
        )
    }

    /// One hostile envelope used to push the watermark to year 4001, after which every resume asked
    /// the relay for events "since 4001" and skipped all genuine traffic — a permanent sync kill.
    @Test("a future-dated envelope cannot push the replay cursor past local time")
    func futureDatedEnvelopeCannotStallSync() async {
        let store = SocialEventLogStore()
        let receivedAt = Date(timeIntervalSince1970: 1_000)
        let hostile = SocialEventEnvelope(
            sessionID: UUID(),
            authorParticipantID: "mallory",
            createdAt: .distantFuture,
            event: .workflowShared("hostile")
        )

        await store.appendInbound(hostile, topic: "topic-a", receivedAt: receivedAt)
        let cursor = await store.currentSnapshot().replayCursors["topic-a"]

        #expect(cursor?.lastReceivedAt == receivedAt)
    }

    /// And a genuine event arriving afterwards must still advance the cursor rather than being
    /// stranded behind a poisoned watermark.
    @Test("a genuine event still advances the cursor after a hostile future-dated one")
    func genuineEventStillAdvancesAfterHostileOne() async {
        let store = SocialEventLogStore()
        let hostile = SocialEventEnvelope(
            sessionID: UUID(),
            authorParticipantID: "mallory",
            createdAt: .distantFuture,
            event: .workflowShared("hostile")
        )
        let genuine = envelope(at: 2_000)

        await store.appendInbound(hostile, topic: "topic-a", receivedAt: Date(timeIntervalSince1970: 1_000))
        await store.appendInbound(genuine, topic: "topic-a", receivedAt: Date(timeIntervalSince1970: 2_000))
        let cursor = await store.currentSnapshot().replayCursors["topic-a"]

        #expect(cursor?.lastReceivedAt == Date(timeIntervalSince1970: 2_000))
        #expect(cursor?.lastEventID == genuine.id)
    }

    @Test("a backdated envelope cannot rewind the replay cursor")
    func backdatedEnvelopeCannotRewindCursor() async {
        let store = SocialEventLogStore()
        let fresh = envelope(at: 2_000)
        let stale = envelope(at: 500)

        await store.appendInbound(fresh, topic: "topic-a", receivedAt: Date(timeIntervalSince1970: 2_000))
        await store.appendInbound(stale, topic: "topic-a", receivedAt: Date(timeIntervalSince1970: 2_001))
        let cursor = await store.currentSnapshot().replayCursors["topic-a"]

        #expect(cursor?.lastReceivedAt == Date(timeIntervalSince1970: 2_000))
        #expect(cursor?.lastEventID == fresh.id)
    }

    /// A joiner consumes and removes its invite, which is the normal flow. Pruning must not read
    /// "no invite for this topic" as "this topic is finished" and delete its replay progress.
    @Test("pruning keeps the replay cursor of a live session whose invite was consumed")
    func pruneKeepsLiveSessionCursor() async {
        let store = SocialEventLogStore()
        let activeSessionID = UUID()
        let now = Date(timeIntervalSince1970: 10_000)

        await store.appendInbound(
            envelope(sessionID: activeSessionID, at: 9_000),
            topic: "topic-live",
            receivedAt: now
        )
        // The joiner consumed its invite, so no invite maps `topic-live` back to the session.
        await store.removeInvite(sessionID: activeSessionID)
        await store.prune(now: now, policy: SocialRetentionPolicy(terminalSessionRetention: 0, expiredInviteRetention: 0))

        #expect(await store.currentSnapshot().replayCursors["topic-live"] != nil)
    }
}

/// Join-challenge canonicalization and nonce scoping.
@Suite("Social join challenge hardening")
struct SocialJoinChallengeHardeningTests {
    private func invite(
        sessionID: UUID = UUID(),
        relayTopic: String = "irn:topic",
        nonce: String = "nonce-a"
    ) -> SocialInvite {
        SocialInvite(
            sessionID: sessionID,
            relayTopic: relayTopic,
            encryptedSessionKey: "ciphertext",
            inviterParticipantID: "alice",
            expiresAt: Date(timeIntervalSince1970: 100),
            nonce: nonce
        )
    }

    /// `signingMessage` is a newline-delimited `key:value` block, so a line break in a value forges a
    /// field and makes one signature valid for a challenge the signer never saw.
    @Test("a line break in the relay topic makes the signing message ambiguous")
    func newlineInRelayTopicIsNonCanonical() {
        let hostile = invite(relayTopic: "t1\naccount:eip155:1:0xVICTIM\nnonce:n1\nexpires:x\ntopic:")
        let challenge = SocialJoinChallenge(invite: hostile, caip10Account: "eip155:1:0xalice")

        #expect(challenge.hasCanonicalFields == false)
    }

    @Test("a non-canonical challenge is refused a proof")
    func nonCanonicalChallengeIsRefusedAProof() {
        let hostile = invite(relayTopic: "t1\naccount:eip155:1:0xVICTIM")
        let challenge = SocialJoinChallenge(invite: hostile, caip10Account: "eip155:1:0xalice")
        var validator = SocialJoinChallengeValidator()

        #expect(throws: SocialJoinChallengeError.malformedChallengeField) {
            try validator.acceptVerifiedSignature(
                invite: hostile,
                challenge: challenge,
                verificationMethod: "0xsig",
                signatureVerified: true,
                now: Date(timeIntervalSince1970: 10)
            )
        }
    }

    @Test("a line break in the account is refused a proof")
    func newlineInAccountIsRefusedAProof() {
        let hostileInvite = invite()
        let challenge = SocialJoinChallenge(
            invite: hostileInvite,
            caip10Account: "eip155:1:0xalice\nnonce:forged"
        )
        var validator = SocialJoinChallengeValidator()

        #expect(challenge.hasCanonicalFields == false)
        #expect(throws: SocialJoinChallengeError.malformedChallengeField) {
            try validator.acceptVerifiedSignature(
                invite: hostileInvite,
                challenge: challenge,
                verificationMethod: "0xsig",
                signatureVerified: true,
                now: Date(timeIntervalSince1970: 10)
            )
        }
    }

    /// A nonce is only meaningful inside the session that issued it. Keying the consumed set globally
    /// let one session's join burn the identical nonce for an unrelated session.
    @Test("the same nonce in a different session is not a replay")
    func nonceIsScopedToItsSession() throws {
        let first = invite(sessionID: UUID(), nonce: "shared-nonce")
        let second = invite(sessionID: UUID(), nonce: "shared-nonce")
        var validator = SocialJoinChallengeValidator()
        let now = Date(timeIntervalSince1970: 10)

        _ = try validator.acceptVerifiedSignature(
            invite: first,
            challenge: SocialJoinChallenge(invite: first, caip10Account: "eip155:1:0xalice"),
            verificationMethod: "0xsig",
            signatureVerified: true,
            now: now
        )
        let secondProof = try validator.acceptVerifiedSignature(
            invite: second,
            challenge: SocialJoinChallenge(invite: second, caip10Account: "eip155:1:0xbob"),
            verificationMethod: "0xsig",
            signatureVerified: true,
            now: now
        )

        #expect(secondProof.challenge.sessionID == second.sessionID)
    }

    @Test("replaying a nonce within its own session is still refused")
    func nonceReplayWithinSessionIsStillRefused() throws {
        let only = invite(nonce: "shared-nonce")
        let challenge = SocialJoinChallenge(invite: only, caip10Account: "eip155:1:0xalice")
        var validator = SocialJoinChallengeValidator()
        let now = Date(timeIntervalSince1970: 10)

        _ = try validator.acceptVerifiedSignature(
            invite: only,
            challenge: challenge,
            verificationMethod: "0xsig",
            signatureVerified: true,
            now: now
        )

        #expect(throws: SocialJoinChallengeError.replayedNonce) {
            try validator.acceptVerifiedSignature(
                invite: only,
                challenge: challenge,
                verificationMethod: "0xsig",
                signatureVerified: true,
                now: now
            )
        }
    }
}
