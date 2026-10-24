import Foundation
@testable import SocialCore
import Testing

@Suite("Social sync projection")
struct SocialSyncTests {
    @Test("Invites expire at their boundary")
    func inviteExpiry() {
        let sessionID = UUID()
        let expiry = Date(timeIntervalSince1970: 100)
        let invite = SocialInvite(
            sessionID: sessionID,
            relayTopic: "irn:topic",
            encryptedSessionKey: "encrypted",
            inviterParticipantID: "alice",
            expiresAt: expiry,
            nonce: "nonce"
        )

        #expect(!invite.isExpired(now: expiry.addingTimeInterval(-1)))
        #expect(invite.isExpired(now: expiry))
        #expect(invite.isExpired(now: expiry.addingTimeInterval(1)))
    }

    @Test("Projection deduplicates relay events and shared context")
    func projectionDeduplicatesRelayEventsAndSharedContext() {
        let fixture = SyncFixture()
        let receiptID = UUID()
        let artifactID = UUID()
        let firstEventID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!

        let events = [
            fixture.joined(fixture.verifiedParticipant("alice"), at: 1, id: firstEventID),
            fixture.joined(fixture.verifiedParticipant("alice"), at: 1, id: firstEventID),
            fixture.event(author: "alice", at: 2, event: .receiptShared(receiptID)),
            fixture.event(author: "alice", at: 3, event: .receiptShared(receiptID)),
            fixture.event(author: "alice", at: 4, event: .artifactShared(artifactID)),
            fixture.event(author: "alice", at: 5, event: .artifactShared(artifactID)),
            fixture.event(author: "alice", at: 6, event: .workflowShared("workflow.review")),
            fixture.event(author: "alice", at: 7, event: .workflowShared("workflow.review")),
            fixture.event(author: "alice", at: 8, event: .playlistShared("playlist.sesh")),
            fixture.event(author: "alice", at: 9, event: .playlistShared("playlist.sesh"))
        ]

        let projection = fixture.reduce(events)

        #expect(projection.participants.keys.sorted() == ["alice"])
        #expect(projection.sharedReceiptIDs == [receiptID])
        #expect(projection.sharedArtifactIDs == [artifactID])
        #expect(projection.sharedWorkflowIDs == ["workflow.review"])
        #expect(projection.sharedPlaylistIDs == ["playlist.sesh"])
    }

    @Test("Unverified participants cannot author binding shared-state events")
    func unverifiedParticipantsCannotAuthorBindingEvents() {
        let fixture = SyncFixture()
        let approvalID = UUID()
        let item = SocialQueueItem(mediaItemID: "song.1", title: "Song 1")
        let pending = fixture.participant("mallory", verificationState: .pending)

        let events = [
            fixture.joined(pending, at: 1),
            fixture.event(author: "mallory", at: 2, event: .approvalOpened(
                SocialApprovalDraft(id: approvalID, prompt: "Approve?", requiredApprovals: 1)
            )),
            fixture.event(author: "mallory", at: 3, event: .approvalVoteCast(
                approvalID: approvalID,
                vote: SocialApprovalVote(participantID: "mallory", approved: true)
            )),
            fixture.event(author: "mallory", at: 4, event: .queueProposalCreated(
                SocialQueueProposal(mediaItemID: "song.1", title: "Song 1", proposedByParticipantID: "mallory")
            )),
            fixture.event(author: "mallory", at: 5, event: .queueMutationAccepted(.acceptProposal(
                proposalID: UUID(),
                item: item
            )))
        ]

        let projection = fixture.reduce(events)

        #expect(projection.participants["mallory"]?.verificationState == .pending)
        #expect(projection.approvals[approvalID] == nil)
        #expect(projection.queueProposals.isEmpty)
        #expect(projection.queueItems.isEmpty)
    }

    @Test("Verified participants can vote and later votes replace prior votes")
    func verifiedParticipantsCanVoteAndReplacePriorVotes() {
        let fixture = SyncFixture()
        let approvalID = UUID()

        let events = [
            fixture.joined(fixture.verifiedParticipant("alice"), at: 1),
            fixture.joined(fixture.verifiedParticipant("bob"), at: 2),
            fixture.event(author: "alice", at: 3, event: .approvalOpened(
                SocialApprovalDraft(id: approvalID, prompt: "Ship?", requiredApprovals: 2)
            )),
            fixture.event(author: "alice", at: 4, event: .approvalVoteCast(
                approvalID: approvalID,
                vote: SocialApprovalVote(participantID: "alice", approved: true, castAt: fixture.date(4))
            )),
            fixture.event(author: "bob", at: 5, event: .approvalVoteCast(
                approvalID: approvalID,
                vote: SocialApprovalVote(participantID: "bob", approved: true, castAt: fixture.date(5))
            )),
            fixture.event(author: "bob", at: 6, event: .approvalVoteCast(
                approvalID: approvalID,
                vote: SocialApprovalVote(participantID: "bob", approved: false, castAt: fixture.date(6))
            ))
        ]

        let projection = fixture.reduce(events)
        let approval = projection.approvals[approvalID]

        #expect(approval?.votes.count == 2)
        #expect(approval?.votes.first { $0.participantID == "bob" }?.approved == false)
        #expect(approval?.resolution == .rejected)
    }

    @Test("Ended sessions ignore later mutating events")
    func endedSessionsIgnoreLaterMutatingEvents() {
        let fixture = SyncFixture()
        let receiptID = UUID()
        let laterReceiptID = UUID()

        let events = [
            // Alice owns the session; ending it is an owner-only authority (see SocialOwnerAuthorityTests).
            fixture.joined(fixture.verifiedParticipant("alice", role: .owner), at: 1),
            fixture.event(author: "alice", at: 2, event: .receiptShared(receiptID)),
            fixture.event(author: "alice", at: 3, event: .sessionEnded(endedAt: fixture.date(3))),
            fixture.event(author: "alice", at: 4, event: .receiptShared(laterReceiptID))
        ]

        let projection = fixture.reduce(events)

        #expect(projection.endedAt == fixture.date(3))
        #expect(projection.sharedReceiptIDs == [receiptID])
    }

    @Test("Queue mutations converge deterministically")
    func queueMutationsConvergeDeterministically() {
        let fixture = SyncFixture()
        let proposalA = UUID()
        let proposalB = UUID()
        let itemA = SocialQueueItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!,
            mediaItemID: "song.a",
            title: "Song A",
            acceptedProposalID: proposalA,
            acceptedAt: fixture.date(4)
        )
        let itemB = SocialQueueItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000302")!,
            mediaItemID: "song.b",
            title: "Song B",
            acceptedProposalID: proposalB,
            acceptedAt: fixture.date(5)
        )

        let events = [
            fixture.joined(fixture.verifiedParticipant("alice"), at: 1),
            fixture.event(author: "alice", at: 2, event: .queueProposalCreated(
                SocialQueueProposal(id: proposalA, mediaItemID: "song.a", title: "Song A", proposedByParticipantID: "alice")
            )),
            fixture.event(author: "alice", at: 3, event: .queueProposalCreated(
                SocialQueueProposal(id: proposalB, mediaItemID: "song.b", title: "Song B", proposedByParticipantID: "alice")
            )),
            fixture.event(author: "alice", at: 4, event: .queueMutationAccepted(.acceptProposal(proposalID: proposalA, item: itemA))),
            fixture.event(author: "alice", at: 5, event: .queueMutationAccepted(.acceptProposal(proposalID: proposalB, item: itemB))),
            fixture.event(author: "alice", at: 6, event: .queueMutationAccepted(.reorder(itemID: itemB.id, destinationIndex: 0))),
            fixture.event(author: "alice", at: 7, event: .queueMutationAccepted(.removeItem(itemID: itemA.id)))
        ].reversed()

        let projection = fixture.reduce(Array(events))

        #expect(projection.queueItems.map(\.id) == [itemB.id])
        #expect(projection.queueProposals.keys.sorted { $0.uuidString < $1.uuidString } == [proposalA, proposalB].sorted { $0.uuidString < $1.uuidString })
    }

    @Test("Event log stores inbound events, pending outbound events, invites, and replay cursors")
    func eventLogStorePersistsSyncState() async {
        let fixture = SyncFixture()
        let persistence = InMemorySocialEventLogPersistence()
        let store = SocialEventLogStore(persistence: persistence)
        let invite = SocialInvite(
            sessionID: fixture.sessionID,
            relayTopic: "topic-a",
            encryptedSessionKey: "ciphertext",
            inviterParticipantID: "alice",
            expiresAt: fixture.date(100),
            nonce: "nonce-a"
        )
        let joined = fixture.joined(fixture.verifiedParticipant("alice"), at: 1)
        let receipt = fixture.event(author: "alice", at: 2, event: .receiptShared(UUID()))

        await store.saveInvite(invite)
        await store.appendInbound(joined, topic: "topic-a")
        await store.appendInbound(joined, topic: "topic-a")
        await store.enqueueOutbound(receipt)

        var snapshot = await persistence.load()
        #expect(snapshot.invites == [invite])
        #expect(snapshot.envelopes.map(\.id) == [joined.id, receipt.id])
        #expect(snapshot.pendingOutboundEventIDs == [receipt.id])
        #expect(snapshot.replayCursors["topic-a"]?.lastEventID == joined.id)

        await store.markPublished(eventID: receipt.id)
        snapshot = await persistence.load()
        #expect(snapshot.pendingOutboundEventIDs.isEmpty)
    }

    @Test("Join challenge accepts verified signatures once and rejects replays")
    func joinChallengeValidatorRejectsReplayedNonce() throws {
        let fixture = SyncFixture()
        let invite = SocialInvite(
            sessionID: fixture.sessionID,
            relayTopic: "topic-a",
            encryptedSessionKey: "ciphertext",
            inviterParticipantID: "alice",
            expiresAt: fixture.date(100),
            nonce: "nonce-a"
        )
        let challenge = SocialJoinChallenge(invite: invite, caip10Account: "eip155:1:0xalice")
        var validator = SocialJoinChallengeValidator()

        let proof = try validator.acceptVerifiedSignature(
            invite: invite,
            challenge: challenge,
            verificationMethod: "0xsig",
            signatureVerified: true,
            now: fixture.date(10)
        )

        #expect(proof.challenge.signingMessage.contains("Auralis shared session join"))
        #expect(proof.challenge.signingMessage.contains("session:\(fixture.sessionID.uuidString)"))
        #expect(throws: SocialJoinChallengeError.replayedNonce) {
            try validator.acceptVerifiedSignature(
                invite: invite,
                challenge: challenge,
                verificationMethod: "0xsig",
                signatureVerified: true,
                now: fixture.date(11)
            )
        }
    }

    @Test("Join challenge rejects expired invites and rejected signatures")
    func joinChallengeValidatorRejectsBadProofs() {
        let fixture = SyncFixture()
        let invite = SocialInvite(
            sessionID: fixture.sessionID,
            relayTopic: "topic-a",
            encryptedSessionKey: "ciphertext",
            inviterParticipantID: "alice",
            expiresAt: fixture.date(100),
            nonce: "nonce-a"
        )
        let challenge = SocialJoinChallenge(invite: invite, caip10Account: "eip155:1:0xalice")
        var validator = SocialJoinChallengeValidator()

        #expect(throws: SocialJoinChallengeError.signatureRejected) {
            try validator.acceptVerifiedSignature(
                invite: invite,
                challenge: challenge,
                verificationMethod: "0xsig",
                signatureVerified: false,
                now: fixture.date(10)
            )
        }
        #expect(throws: SocialJoinChallengeError.expiredInvite) {
            try validator.acceptVerifiedSignature(
                invite: invite,
                challenge: challenge,
                verificationMethod: "0xsig",
                signatureVerified: true,
                now: fixture.date(100)
            )
        }
    }

    /// The challenge is what the wallet actually signs, so every field in it has to be pinned to the
    /// invite the person scanned. Only the nonce and the expiry were covered; session, topic, and
    /// account were not — and an unpinned session or topic means a signature collected for one
    /// session is presentable as proof of membership in another.
    @Test("Join challenge pins every field to the scanned invite")
    func joinChallengeValidatorPinsChallengeToInvite() {
        let fixture = SyncFixture()
        let invite = SocialInvite(
            sessionID: fixture.sessionID,
            relayTopic: "topic-a",
            encryptedSessionKey: "ciphertext",
            inviterParticipantID: "alice",
            expiresAt: fixture.date(100),
            nonce: "nonce-a"
        )
        var validator = SocialJoinChallengeValidator()
        let account = "eip155:1:0xalice"

        func accept(_ challenge: SocialJoinChallenge) throws {
            _ = try validator.acceptVerifiedSignature(
                invite: invite,
                challenge: challenge,
                verificationMethod: "0xsig",
                signatureVerified: true,
                now: fixture.date(10)
            )
        }

        #expect(throws: SocialJoinChallengeError.wrongSession) {
            try accept(
                SocialJoinChallenge(
                    sessionID: UUID(),
                    relayTopic: invite.relayTopic,
                    caip10Account: account,
                    nonce: invite.nonce,
                    expiresAt: invite.expiresAt
                )
            )
        }
        #expect(throws: SocialJoinChallengeError.wrongRelayTopic) {
            try accept(
                SocialJoinChallenge(
                    sessionID: invite.sessionID,
                    relayTopic: "topic-b",
                    caip10Account: account,
                    nonce: invite.nonce,
                    expiresAt: invite.expiresAt
                )
            )
        }
        #expect(throws: SocialJoinChallengeError.wrongAccount) {
            try accept(
                SocialJoinChallenge(
                    sessionID: invite.sessionID,
                    relayTopic: invite.relayTopic,
                    caip10Account: "   ",
                    nonce: invite.nonce,
                    expiresAt: invite.expiresAt
                )
            )
        }

        // None of the refusals above may burn the invite's nonce — otherwise one malformed attempt
        // (or anyone who merely saw the QR) permanently denies the genuine join.
        #expect(throws: Never.self) {
            try accept(SocialJoinChallenge(invite: invite, caip10Account: account))
        }
    }

    /// A signature the wallet layer rejected is a retryable failure, not a spent invite. Burning the
    /// nonce on it would make a single mistyped-password or wrong-account attempt unrecoverable
    /// without rescanning.
    @Test("A rejected signature does not consume the join nonce")
    func rejectedSignatureDoesNotConsumeTheNonce() throws {
        let fixture = SyncFixture()
        let invite = SocialInvite(
            sessionID: fixture.sessionID,
            relayTopic: "topic-a",
            encryptedSessionKey: "ciphertext",
            inviterParticipantID: "alice",
            expiresAt: fixture.date(100),
            nonce: "nonce-a"
        )
        let challenge = SocialJoinChallenge(invite: invite, caip10Account: "eip155:1:0xalice")
        var validator = SocialJoinChallengeValidator()

        #expect(throws: SocialJoinChallengeError.signatureRejected) {
            try validator.acceptVerifiedSignature(
                invite: invite,
                challenge: challenge,
                verificationMethod: "0xbad",
                signatureVerified: false,
                now: fixture.date(10)
            )
        }
        #expect(validator.consumedNonces.isEmpty, "a rejected signature spent the invite's nonce")

        let proof = try validator.acceptVerifiedSignature(
            invite: invite,
            challenge: challenge,
            verificationMethod: "0xsig",
            signatureVerified: true,
            now: fixture.date(11)
        )
        #expect(proof.verificationMethod == "0xsig")
    }

    @Test("Only verified participants can share bounded agent context")
    func agentContextRequiresVerifiedMembership() {
        let fixture = SyncFixture()
        let context = SharedAgentContext(
            title: "Listening context",
            summary: "A bounded summary backed by an artifact.",
            provenance: "runtime.context-bundle",
            dataClassNames: ["public"],
            artifactIDs: [UUID()]
        )
        let events = [
            fixture.joined(fixture.verifiedParticipant("alice"), at: 1),
            fixture.joined(fixture.participant("mallory", verificationState: .pending), at: 2),
            fixture.event(author: "mallory", at: 3, event: .agentContextShared(context)),
            fixture.event(author: "alice", at: 4, event: .agentContextShared(context))
        ]

        let projection = fixture.reduce(events)

        #expect(projection.sharedAgentContexts == [context])
    }

    /// `apply` drops an agent context whose `expiresAt` has already passed at the moment its envelope
    /// claims to have been authored. Shared context is the one payload here that carries a deliberate
    /// lifetime — it is a privacy bound, not a cosmetic one — so a context that arrives (or replays)
    /// after its own expiry must not land in the projection.
    @Test("an agent context that expired before its envelope does not project")
    func expiredAgentContextDoesNotProject() {
        let fixture = SyncFixture()
        let live = SharedAgentContext(
            title: "Live context",
            summary: "Still within its lifetime.",
            provenance: "runtime.context-bundle",
            expiresAt: Date(timeIntervalSince1970: 100)
        )
        let stale = SharedAgentContext(
            title: "Stale context",
            summary: "Past its lifetime by the time it is shared.",
            provenance: "runtime.context-bundle",
            expiresAt: Date(timeIntervalSince1970: 2)
        )
        let events = [
            fixture.joined(fixture.verifiedParticipant("alice"), at: 1),
            fixture.event(author: "alice", at: 3, event: .agentContextShared(stale)),
            fixture.event(author: "alice", at: 4, event: .agentContextShared(live))
        ]

        let projection = fixture.reduce(events)

        #expect(projection.sharedAgentContexts == [live])
        #expect(stale.isExpired(at: Date(timeIntervalSince1970: 3)))
        #expect(live.isExpired(at: Date(timeIntervalSince1970: 4)) == false)
    }

    @Test("Agent context enforces payload bounds")
    func agentContextEnforcesPayloadBounds() {
        let context = SharedAgentContext(
            title: String(repeating: "t", count: 200),
            summary: String(repeating: "s", count: 3_000),
            provenance: String(repeating: "p", count: 400),
            dataClassNames: Array(repeating: String(repeating: "d", count: 100), count: 40),
            artifactIDs: Array(repeating: UUID(), count: 120)
        )

        #expect(context.title.count == 120)
        #expect(context.summary.count == 2_000)
        #expect(context.provenance.count == 240)
        #expect(context.dataClassNames.count == 32)
        #expect(context.dataClassNames.allSatisfy { $0.count == 80 })
        #expect(context.artifactIDs.count == 100)
    }
}

@Suite("Social retention and rejection diagnostics")
struct SocialRetentionTests {
    @Test("Old terminal sessions prune as a complete graph while active history survives")
    func prunesOnlyOldTerminalSessions() async {
        let store = SocialEventLogStore()
        let now = Date(timeIntervalSince1970: 10_000)
        let endedSessionID = UUID()
        let activeSessionID = UUID()
        let owner = SocialParticipantIdentity(
            participantID: "owner",
            caip10Account: "eip155:1:owner",
            displayName: "Owner",
            role: .owner,
            verificationState: .verified
        )
        await store.appendLocal(SocialEventEnvelope(
            sessionID: endedSessionID,
            authorParticipantID: "owner",
            createdAt: now.addingTimeInterval(-200),
            event: .participantJoined(owner)
        ))
        await store.appendLocal(SocialEventEnvelope(
            sessionID: endedSessionID,
            authorParticipantID: "owner",
            createdAt: now.addingTimeInterval(-100),
            event: .sessionEnded(endedAt: now.addingTimeInterval(-100))
        ))
        await store.appendLocal(SocialEventEnvelope(
            sessionID: activeSessionID,
            authorParticipantID: "owner",
            createdAt: now.addingTimeInterval(-200),
            event: .participantJoined(owner)
        ))

        let result = await store.prune(
            now: now,
            policy: SocialRetentionPolicy(terminalSessionRetention: 50, expiredInviteRetention: 0)
        )

        #expect(result.removedSessionCount == 1)
        #expect(await store.allEnvelopes().map(\.sessionID) == [activeSessionID])
    }

    /// A joined session's owner is anchored by the invite it was joined from, but an invite is a
    /// short-lived credential and retention deletes it: `SocialInviteMint.defaultTTL` is 7 days and
    /// `expiredInviteRetention` is another 7, so every joined session reaches a day where the only
    /// out-of-band record of who vouched for it is pruned. If the anchor dies with the invite, the
    /// owner's relay-delivered record stops projecting, everything the owner shared is refused as
    /// `.unverifiedAuthor`, and the session can never be ended — or pruned — again.
    ///
    /// The anchor's lifetime is therefore the *session graph's*, not the invite's.
    @Test("pruning an expired invite does not strip the owner of a live joined session")
    func pruningExpiredInviteKeepsJoinedSessionOwner() async {
        let store = SocialEventLogStore()
        let sessionID = UUID()
        let now = Date(timeIntervalSince1970: 10_000)
        // The shape production mints for a wallet-verified participant: one CAIP-10 value is both
        // the participant id and the account. The anchored-bootstrap rule requires that
        // self-description, because the anchor alone only names *who* may own the session and
        // cannot authenticate an unsigned wire envelope as having come from them.
        let ownerID = "eip155:1:0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed"
        let owner = SocialParticipantIdentity(
            participantID: ownerID,
            caip10Account: ownerID,
            displayName: "Owner",
            role: .owner,
            verificationState: .verified
        )
        await store.saveInvite(SocialInvite(
            sessionID: sessionID,
            relayTopic: "topic-joined",
            encryptedSessionKey: "key",
            inviterParticipantID: ownerID,
            expiresAt: now.addingTimeInterval(-5_000),
            nonce: "nonce"
        ))
        // Relay-delivered, like every record in a session you joined rather than created.
        await store.appendInbound(
            SocialEventEnvelope(
                sessionID: sessionID,
                authorParticipantID: ownerID,
                createdAt: now.addingTimeInterval(-100),
                event: .participantJoined(owner)
            ),
            topic: "topic-joined",
            receivedAt: now
        )
        #expect(await store.projection(sessionID: sessionID).participants[ownerID]?.role == .owner)

        let result = await store.prune(
            now: now,
            policy: SocialRetentionPolicy(terminalSessionRetention: 90 * 86_400, expiredInviteRetention: 0)
        )

        #expect(result.removedInviteCount == 1)
        let projection = await store.projection(sessionID: sessionID)
        #expect(projection.participants[ownerID]?.role == .owner)
    }

    /// Same invariant through the explicit forget path. `removeInvite(sessionID:)` drops the invite's
    /// relay secrets; it is not a statement that the inviter never vouched for the session.
    @Test("forgetting a consumed invite does not strip the owner of a joined session")
    func removingInviteKeepsJoinedSessionOwner() async {
        let store = SocialEventLogStore()
        let sessionID = UUID()
        // The shape production mints for a wallet-verified participant: one CAIP-10 value is both
        // the participant id and the account. The anchored-bootstrap rule requires that
        // self-description, because the anchor alone only names *who* may own the session and
        // cannot authenticate an unsigned wire envelope as having come from them.
        let ownerID = "eip155:1:0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed"
        let owner = SocialParticipantIdentity(
            participantID: ownerID,
            caip10Account: ownerID,
            displayName: "Owner",
            role: .owner,
            verificationState: .verified
        )
        await store.saveInvite(SocialInvite(
            sessionID: sessionID,
            relayTopic: "topic-joined",
            encryptedSessionKey: "key",
            inviterParticipantID: ownerID,
            expiresAt: Date(timeIntervalSince1970: 20_000),
            nonce: "nonce"
        ))
        await store.appendInbound(
            SocialEventEnvelope(
                sessionID: sessionID,
                authorParticipantID: ownerID,
                createdAt: Date(timeIntervalSince1970: 1_000),
                event: .participantJoined(owner)
            ),
            topic: "topic-joined"
        )
        await store.removeInvite(sessionID: sessionID)

        let projection = await store.projection(sessionID: sessionID)
        #expect(projection.participants[ownerID]?.role == .owner)
    }

    /// The ceiling evicts; it must never refuse.
    ///
    /// A wall here would be strictly worse than the unbounded growth it replaces: `.unsupported` is
    /// accepted with no author check by design, so any invite holder could reach the cap and from
    /// then on **every** genuine inbound envelope for the session would be discarded — permanently,
    /// because a joined session never derives an `endedAt` for `prune` to act on. One peer could
    /// silence a session for everyone else, unrecoverably short of a full reset.
    @Test("a flood at the ceiling costs history, not the session")
    func inboundCeilingEvictsRatherThanRefusing() async {
        let policy = SocialRetentionPolicy(maximumStoredEnvelopesPerSession: 4)
        let store = SocialEventLogStore(retentionPolicy: policy)
        let sessionID = UUID()

        for index in 0..<12 {
            await store.appendInbound(
                SocialEventEnvelope(
                    sessionID: sessionID,
                    authorParticipantID: "flooder",
                    createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                    event: .unsupported(kind: "flood.\(index)")
                ),
                topic: "topic"
            )
        }

        let genuine = SocialEventEnvelope(
            sessionID: sessionID,
            authorParticipantID: "peer",
            createdAt: Date(timeIntervalSince1970: 100),
            event: .receiptShared(UUID())
        )
        await store.appendInbound(genuine, topic: "topic")

        let held = await store.currentSnapshot().envelopes.filter { $0.sessionID == sessionID }
        #expect(held.count == policy.maximumStoredEnvelopesPerSession)
        // The genuine event got in — that is the whole point.
        #expect(held.contains { $0.id == genuine.id })
        // And the oldest flood entries are the ones that went.
        #expect(held.contains { $0.event == .unsupported(kind: "flood.0") } == false)
    }

    /// Locally-minted content is this installation's own record and the root of the authority
    /// model, so it is never evicted to make room for a relay envelope.
    @Test("the ceiling never evicts locally minted or pending-outbound envelopes")
    func inboundCeilingNeverEvictsOurOwnRecord() async {
        let policy = SocialRetentionPolicy(maximumStoredEnvelopesPerSession: 2)
        let store = SocialEventLogStore(retentionPolicy: policy)
        let sessionID = UUID()
        let mine = SocialEventEnvelope(
            sessionID: sessionID,
            authorParticipantID: "me",
            createdAt: Date(timeIntervalSince1970: 0),
            event: .sessionCreated(title: "Mine", correlationID: "corr")
        )
        await store.appendLocal(mine)
        let queued = SocialEventEnvelope(
            sessionID: sessionID,
            authorParticipantID: "me",
            createdAt: Date(timeIntervalSince1970: 1),
            event: .receiptShared(UUID())
        )
        await store.enqueueOutbound(queued)

        for index in 0..<6 {
            await store.appendInbound(
                SocialEventEnvelope(
                    sessionID: sessionID,
                    authorParticipantID: "flooder",
                    createdAt: Date(timeIntervalSince1970: TimeInterval(10 + index)),
                    event: .unsupported(kind: "flood.\(index)")
                ),
                topic: "topic"
            )
        }

        let held = await store.currentSnapshot().envelopes.filter { $0.sessionID == sessionID }
        #expect(held.contains { $0.id == mine.id })
        #expect(held.contains { $0.id == queued.id })
        // The ceiling counts relay-delivered rows only, which is what the policy says it bounds.
        // Counting our own content too left nothing evictable and refused every inbound envelope
        // permanently — the exact wall this ceiling exists not to be.
        #expect(held.contains { $0.event == .unsupported(kind: "flood.5") })
    }

    /// Eviction must follow *arrival* order, never `createdAt`.
    ///
    /// `envelopes` is not in insertion order: every mutation ends in `normalized()`, which sorts by
    /// `createdAt` — a wire field. So "the first evictable index" was the earliest timestamp the
    /// sender chose to claim. A flood claiming a far-future `createdAt` sorts *last*, which means
    /// every eviction fell on the session's genuine history while the flood itself was never
    /// touched: the attacker picked which rows died, and kept its own.
    ///
    /// Fails against the pre-fix code, where the session could never hold more than one genuine
    /// envelope again — each new one evicted the previous one.
    @Test("a pre-flood with future timestamps cannot pin genuine history out of the log")
    func inboundCeilingEvictsByArrivalNotByClaimedTimestamp() async {
        let policy = SocialRetentionPolicy(maximumStoredEnvelopesPerSession: 3)
        let store = SocialEventLogStore(retentionPolicy: policy)
        let sessionID = UUID()

        // Arrives first, claims to be from the far future so it sorts to the end of the array.
        for index in 0..<3 {
            await store.appendInbound(
                SocialEventEnvelope(
                    sessionID: sessionID,
                    authorParticipantID: "flooder",
                    createdAt: Date(timeIntervalSince1970: 10_000_000 + TimeInterval(index)),
                    event: .unsupported(kind: "flood.\(index)")
                ),
                topic: "topic"
            )
        }

        var genuine: [SocialEventEnvelope] = []
        for index in 0..<3 {
            let envelope = SocialEventEnvelope(
                sessionID: sessionID,
                authorParticipantID: "peer",
                createdAt: Date(timeIntervalSince1970: TimeInterval(100 + index)),
                event: .receiptShared(UUID())
            )
            genuine.append(envelope)
            await store.appendInbound(envelope, topic: "topic")
        }

        let held = await store.currentSnapshot().envelopes.filter { $0.sessionID == sessionID }
        #expect(held.count == policy.maximumStoredEnvelopesPerSession)
        // The flood arrived first, so the flood is what goes.
        for envelope in genuine {
            #expect(held.contains { $0.id == envelope.id })
        }
        #expect(held.contains { if case .unsupported = $0.event { return true } else { return false } } == false)
    }

    /// The mirror of the test above, and the direction arrival order alone does not cover.
    ///
    /// Ordering eviction by arrival fixed the case where the flood arrives *first*. It cannot fix
    /// the case where the flood arrives *last*, because then the longest-held rows — the ones
    /// arrival order sacrifices — are the session's genuine history. A peer that waits until a
    /// session is established and then floods evicts every relay-delivered row the session had,
    /// `participantJoined` records first. For a session this installation merely joined that is
    /// terminal: the owner's record is relay-delivered, so losing it clears `hasOwner`, after which
    /// `sessionEnded` is refused as `.ownerRequired`, no `endedAt` is ever derived, and `prune` can
    /// never release the graph.
    ///
    /// Fails against the pre-fix comparator, which ranked on `(sequence, id)` only and therefore
    /// evicted the owner's record on the very first flood envelope.
    @Test("a post-flood of inert carriers cannot evict a joined session's membership history")
    func inboundCeilingSacrificesInertCarriersBeforeGenuineHistory() async {
        let policy = SocialRetentionPolicy(maximumStoredEnvelopesPerSession: 4)
        let store = SocialEventLogStore(retentionPolicy: policy)
        let sessionID = UUID()

        // The session is established first: this is the record whose loss un-owns the session.
        let ownerJoin = SocialEventEnvelope(
            sessionID: sessionID,
            authorParticipantID: "eip155:1:0xowner",
            createdAt: Date(timeIntervalSince1970: 1),
            event: .participantJoined(SocialParticipantIdentity(
                participantID: "eip155:1:0xowner",
                caip10Account: "eip155:1:0xowner",
                displayName: "Owner",
                role: .owner,
                verificationState: .pending
            ))
        )
        await store.appendInbound(ownerJoin, topic: "topic")
        let peerShare = SocialEventEnvelope(
            sessionID: sessionID,
            authorParticipantID: "eip155:1:0xowner",
            createdAt: Date(timeIntervalSince1970: 2),
            event: .receiptShared(UUID())
        )
        await store.appendInbound(peerShare, topic: "topic")

        // Then the flood, arriving later and so holding the *highest* sequences.
        for index in 0..<20 {
            await store.appendInbound(
                SocialEventEnvelope(
                    sessionID: sessionID,
                    authorParticipantID: "flooder",
                    createdAt: Date(timeIntervalSince1970: TimeInterval(1_000 + index)),
                    event: .unsupported(kind: "flood.\(index)")
                ),
                topic: "topic"
            )
        }

        let held = await store.currentSnapshot().envelopes.filter { $0.sessionID == sessionID }
        #expect(held.count == policy.maximumStoredEnvelopesPerSession)
        #expect(held.contains { $0.id == ownerJoin.id }, "a post-flood evicted the owner's record")
        #expect(held.contains { $0.id == peerShare.id }, "a post-flood evicted genuine shared history")

        // The ceiling still evicts rather than refusing: the newest carriers are present, so the
        // flood was absorbed by dropping its own older rows, not by walling off the session.
        #expect(held.contains { $0.event == .unsupported(kind: "flood.19") })
        #expect(held.contains { $0.event == .unsupported(kind: "flood.0") } == false)
    }

    /// The bypass the eviction *class* ordering has on its own, and the reason membership inverts
    /// the arrival order rather than merely outranking the carriers.
    ///
    /// Ranking `.unsupported` lowest stops the cheapest flood, but it stops only that one. A
    /// `participantJoined` carrying a fresh participant id is accepted off the relay by design — a
    /// session you joined has to stay legible — and costs an attacker exactly one envelope, the same
    /// as `.unsupported`. So a flood of fresh-id joins lands in the *same* class as the genuine
    /// records, and under oldest-first it evicts the owner's record just as before: the class
    /// ordering would be worth nothing against an attacker who read it.
    ///
    /// Fails against the round-2 `(disposability, arrival, id)` ranking, which evicts `ownerJoin`.
    @Test("a flood of fresh-id participant records cannot evict the owner's record either")
    func membershipFloodEvictsItselfRatherThanGenuineMembership() async {
        let policy = SocialRetentionPolicy(maximumStoredEnvelopesPerSession: 4)
        let store = SocialEventLogStore(retentionPolicy: policy)
        let sessionID = UUID()

        func join(_ id: String, at seconds: TimeInterval) -> SocialEventEnvelope {
            SocialEventEnvelope(
                sessionID: sessionID,
                authorParticipantID: id,
                createdAt: Date(timeIntervalSince1970: seconds),
                event: .participantJoined(SocialParticipantIdentity(
                    participantID: id,
                    caip10Account: id,
                    displayName: "name-\(id)",
                    role: id == "eip155:1:0xowner" ? .owner : .collaborator,
                    verificationState: .pending
                ))
            )
        }

        // The out-of-band anchor, so the owner's relay-delivered record actually bootstraps
        // ownership and the projection assertion below means something.
        await store.saveInvite(
            SocialInvite(
                sessionID: sessionID,
                relayTopic: "topic",
                encryptedSessionKey: "key",
                inviterParticipantID: "eip155:1:0xowner",
                expiresAt: Date(timeIntervalSince1970: 10_000_000),
                nonce: "nonce"
            )
        )

        let ownerJoin = join("eip155:1:0xowner", at: 1)
        let peerJoin = join("eip155:1:0xpeer", at: 2)
        await store.appendInbound(ownerJoin, topic: "topic")
        await store.appendInbound(peerJoin, topic: "topic")

        // Same class as the genuine records, one envelope each, fresh id every time.
        for index in 0..<20 {
            await store.appendInbound(join("eip155:1:0xflood\(index)", at: TimeInterval(1_000 + index)), topic: "topic")
        }

        let held = await store.currentSnapshot().envelopes.filter { $0.sessionID == sessionID }
        #expect(held.count == policy.maximumStoredEnvelopesPerSession)
        #expect(held.contains { $0.id == ownerJoin.id }, "a membership flood evicted the owner's record")
        #expect(held.contains { $0.id == peerJoin.id }, "a membership flood evicted a genuine peer")

        // The flood is absorbed by its own rows, so the session still projects an owner.
        let projection = await store.projection(sessionID: sessionID)
        #expect(projection.participants["eip155:1:0xowner"]?.role == .owner)
    }

    /// The mirror of the test above, and the case a newest-first membership tier inverts rather
    /// than fixes.
    ///
    /// Ranking membership newest-first protects the session's early rows — which is only a
    /// protection if the genuine rows *are* the early ones. An attacker decides that: an invite
    /// holder who floods the moment it joins owns every old slot, and from then on the newest
    /// membership row is always the most recently arrived *genuine* one. The owner's record lands
    /// and is deleted by the very next envelope, so a joined session can never record its owner —
    /// `hasOwner` stays false, the owner's `sessionEnded` is refused as `.ownerRequired`, and
    /// `prune` can never release the graph. That is the same unrecoverable loss newest-first was
    /// introduced to prevent, reached for `maximumStoredEnvelopesPerSession` envelopes once plus
    /// one envelope per genuine record thereafter.
    ///
    /// The anchored inviter is the only participant id in a joined session whose claim did not
    /// travel over the relay, so it is the one row eviction can protect on a security property
    /// rather than on a guess about which rows arrived first.
    ///
    /// Fails against the round-3 `evictsNewestFirst` ranking, which evicts `ownerJoin`.
    @Test("a membership flood that arrives first cannot evict the owner's record either")
    func earlyMembershipFloodCannotEvictTheAnchoredOwnersRecord() async {
        let policy = SocialRetentionPolicy(maximumStoredEnvelopesPerSession: 4)
        let store = SocialEventLogStore(retentionPolicy: policy)
        let sessionID = UUID()
        let ownerID = "eip155:1:0xowner"

        func join(_ id: String, at seconds: TimeInterval) -> SocialEventEnvelope {
            SocialEventEnvelope(
                sessionID: sessionID,
                authorParticipantID: id,
                createdAt: Date(timeIntervalSince1970: seconds),
                event: .participantJoined(SocialParticipantIdentity(
                    participantID: id,
                    caip10Account: id,
                    displayName: "name-\(id)",
                    role: id == ownerID ? .owner : .collaborator,
                    verificationState: .pending
                ))
            )
        }

        await store.saveInvite(
            SocialInvite(
                sessionID: sessionID,
                relayTopic: "topic",
                encryptedSessionKey: "key",
                inviterParticipantID: ownerID,
                expiresAt: Date(timeIntervalSince1970: 10_000_000),
                nonce: "nonce"
            )
        )

        // The flood arrives *before* the session is established, so it owns every old slot.
        for index in 0..<20 {
            await store.appendInbound(join("eip155:1:0xflood\(index)", at: TimeInterval(index)), topic: "topic")
        }

        let ownerJoin = join(ownerID, at: 1_000)
        await store.appendInbound(ownerJoin, topic: "topic")
        // One more envelope — the cheapest one there is — after the genuine record landed.
        await store.appendInbound(
            SocialEventEnvelope(
                sessionID: sessionID,
                authorParticipantID: "eip155:1:0xflood0",
                createdAt: Date(timeIntervalSince1970: 2_000),
                event: .unsupported(kind: "sweep")
            ),
            topic: "topic"
        )

        let held = await store.currentSnapshot().envelopes.filter { $0.sessionID == sessionID }
        #expect(held.count == policy.maximumStoredEnvelopesPerSession)
        #expect(held.contains { $0.id == ownerJoin.id }, "an early membership flood evicted the owner's record")

        // The owner's record survived, so the session still projects an owner — which is the loss
        // that cannot be recovered: without it `sessionEnded` is refused as `.ownerRequired`, no
        // `endedAt` is derivable, and `prune` can never release the graph.
        let projection = await store.projection(sessionID: sessionID)
        #expect(projection.participants[ownerID]?.role == .owner)
    }

    /// The ceiling filled entirely by *genuine* membership, with no attacker and no flood — the
    /// case that decides whether the arrival-order component can be trusted on its own.
    ///
    /// It cannot, and this pins why. Ordinary members are indistinguishable from each other and
    /// from a flood row, so whichever direction arrival order runs, some genuine record is the
    /// designated victim: newest-first churns the top slot, so an unanchored late joiner does not
    /// stick. That residual is accepted and bounded — reaching it needs
    /// `maximumStoredEnvelopesPerSession` participant records in one session.
    ///
    /// What must hold at *any* size is that the anchored owner is never the victim, because losing
    /// that record is the one unrecoverable loss: the session projects no owner, `sessionEnded` is
    /// refused as `.ownerRequired`, and the graph can never be pruned. The anchor is local
    /// provenance from the out-of-band invite, so it survives a ceiling full of wire records.
    ///
    /// Fails against a ranking that orders membership on arrival alone, in either direction.
    @Test("a ceiling filled with genuine members still never evicts the anchored owner")
    func aCeilingFullOfGenuineMembersNeverEvictsTheAnchoredOwner() async {
        let policy = SocialRetentionPolicy(maximumStoredEnvelopesPerSession: 4)
        let store = SocialEventLogStore(retentionPolicy: policy)
        let sessionID = UUID()
        let ownerID = "eip155:1:0xowner"

        func join(_ id: String, role: SharedRole, at seconds: TimeInterval) -> SocialEventEnvelope {
            SocialEventEnvelope(
                sessionID: sessionID,
                authorParticipantID: id,
                createdAt: Date(timeIntervalSince1970: seconds),
                event: .participantJoined(SocialParticipantIdentity(
                    participantID: id,
                    caip10Account: id,
                    displayName: "name-\(id)",
                    role: role,
                    verificationState: .pending
                ))
            )
        }

        await store.saveInvite(
            SocialInvite(
                sessionID: sessionID,
                relayTopic: "topic",
                encryptedSessionKey: "key",
                inviterParticipantID: ownerID,
                expiresAt: Date(timeIntervalSince1970: 10_000_000),
                nonce: "nonce"
            )
        )

        // The owner lands in the middle of the run, so neither "oldest" nor "newest" spares it.
        let ownerJoin = join(ownerID, role: .owner, at: 4)
        for index in 0..<4 {
            await store.appendInbound(
                join("eip155:1:0xpeer\(index)", role: .collaborator, at: TimeInterval(index)),
                topic: "topic"
            )
        }
        await store.appendInbound(ownerJoin, topic: "topic")
        for index in 4..<8 {
            await store.appendInbound(
                join("eip155:1:0xpeer\(index)", role: .collaborator, at: TimeInterval(index + 5)),
                topic: "topic"
            )
        }

        let held = await store.currentSnapshot().envelopes.filter { $0.sessionID == sessionID }
        // The ceiling still evicts — it never refuses — and the owner is not what it spent.
        #expect(held.count == policy.maximumStoredEnvelopesPerSession)
        #expect(held.contains { $0.id == ownerJoin.id }, "a ceiling of genuine members evicted the owner's record")

        let projection = await store.projection(sessionID: sessionID)
        #expect(projection.participants[ownerID]?.role == .owner)
    }

    /// The anchored tier's own bypass, and the mirror of every earlier round: the protection keys on
    /// a `participantID`, not on a row, so whoever can *mint rows naming that participant* owns the
    /// tier.
    ///
    /// `rejectionReason` accepts a `participantUpdated` that restates a held record byte for byte —
    /// deliberately, so a relay re-delivery stays idempotent — and `appendInbound` de-duplicates on
    /// envelope **id**, not on content. Those two are a different gate, and between them an invite
    /// holder republishes the anchored owner's own record under a fresh envelope id as often as it
    /// likes. Every copy passes the projection gate and every copy ranks `isAnchored`.
    ///
    /// Once those copies hold the ceiling, the key `(1, …)` outranks every unanchored row, so the
    /// session's genuine peers are evicted and no unanchored record can ever outrank a replay again:
    /// the ceiling becomes a wall built out of one participant's id, which is the one thing it must
    /// never be. The anchor has to protect the *record*, which is one row, not every row that names
    /// the anchored party.
    @Test("replaying the anchored owner's record cannot take over the protected tier")
    func anchoredProtectionCannotBeClaimedByReplayingTheOwnerRecord() async {
        let policy = SocialRetentionPolicy(maximumStoredEnvelopesPerSession: 4)
        let store = SocialEventLogStore(retentionPolicy: policy)
        let sessionID = UUID()
        let ownerID = "eip155:1:0xowner"
        let peerID = "eip155:1:0xpeer"

        await store.saveInvite(
            SocialInvite(
                sessionID: sessionID,
                relayTopic: "topic",
                encryptedSessionKey: "key",
                inviterParticipantID: ownerID,
                expiresAt: Date(timeIntervalSince1970: 10_000_000),
                nonce: "nonce"
            )
        )

        // Every field fixed, so a replay is byte-identical to what the log stores — which is exactly
        // what makes `foreignRecordUpdate` treat it as a no-op rather than a modification.
        let ownerIdentity = SocialParticipantIdentity(
            participantID: ownerID,
            caip10Account: ownerID,
            displayName: "Owner",
            role: .owner,
            verificationState: .pending,
            joinedAt: Date(timeIntervalSince1970: 1)
        )
        let ownerJoin = SocialEventEnvelope(
            sessionID: sessionID,
            authorParticipantID: ownerID,
            createdAt: Date(timeIntervalSince1970: 1),
            event: .participantJoined(ownerIdentity)
        )
        let peerJoin = SocialEventEnvelope(
            sessionID: sessionID,
            authorParticipantID: peerID,
            createdAt: Date(timeIntervalSince1970: 2),
            event: .participantJoined(SocialParticipantIdentity(
                participantID: peerID,
                caip10Account: peerID,
                displayName: "Peer",
                role: .collaborator,
                verificationState: .pending,
                joinedAt: Date(timeIntervalSince1970: 2)
            ))
        )
        await store.appendInbound(ownerJoin, topic: "topic")
        await store.appendInbound(peerJoin, topic: "topic")

        for index in 0..<8 {
            let replay = SocialEventEnvelope(
                sessionID: sessionID,
                authorParticipantID: ownerID,
                createdAt: Date(timeIntervalSince1970: TimeInterval(1_000 + index)),
                event: .participantUpdated(ownerIdentity)
            )
            // The gate `SocialRelayCoordinator.handleInbound` applies before storage admits
            // anything. If it refused these the flood would be unreachable, so assert it does not —
            // the ceiling cannot delegate this to the projection.
            let projection = await store.projection(sessionID: sessionID)
            #expect(
                projection.rejectionReason(for: replay) == nil,
                "the replay is refused, so this flood would never reach storage"
            )
            await store.appendInbound(replay, topic: "topic")
        }

        let held = await store.currentSnapshot().envelopes.filter { $0.sessionID == sessionID }
        #expect(held.count == policy.maximumStoredEnvelopesPerSession)
        #expect(held.contains { $0.id == ownerJoin.id }, "the owner's own record was evicted")
        #expect(
            held.contains { $0.id == peerJoin.id },
            "a replay of the anchored record evicted a genuine peer out of the unprotected tier"
        )
    }

    /// The anchored slot must go to the row that *establishes* the owner's record, not merely to the
    /// first row that names the owner.
    ///
    /// `participantRemoved` is `.ownerAuthor` and self-removal is refused, so no honest
    /// `.participantRemoved(owner)` exists — but it names the anchored participant just as a join
    /// does. Arriving first, it would hold the protected slot while the owner's genuine record went
    /// back to being ordinary and evictable, which is the unrecoverable loss the anchor exists to
    /// prevent. The relay gate refuses it as `.impersonatedAuthor`, so this exercises
    /// `appendInbound` directly, which is public and is documented as the one place admission
    /// control lives.
    @Test("a tombstone naming the anchored owner cannot take the owner's protected slot")
    func anchoredProtectionGoesToTheRecordNotToATombstone() async {
        let policy = SocialRetentionPolicy(maximumStoredEnvelopesPerSession: 4)
        let store = SocialEventLogStore(retentionPolicy: policy)
        let sessionID = UUID()
        let ownerID = "eip155:1:0xowner"

        await store.saveInvite(
            SocialInvite(
                sessionID: sessionID,
                relayTopic: "topic",
                encryptedSessionKey: "key",
                inviterParticipantID: ownerID,
                expiresAt: Date(timeIntervalSince1970: 10_000_000),
                nonce: "nonce"
            )
        )

        // Arrives first, so it is the earliest row naming the anchored participant.
        await store.appendInbound(
            SocialEventEnvelope(
                sessionID: sessionID,
                authorParticipantID: "eip155:1:0xflood",
                createdAt: Date(timeIntervalSince1970: 1),
                event: .participantRemoved(participantID: ownerID)
            ),
            topic: "topic"
        )

        // Then the early flood, so the owner's record is the *newest* membership row when it lands —
        // the arrangement under which only the anchor, and nothing about arrival order, saves it.
        for index in 0..<20 {
            await store.appendInbound(
                SocialEventEnvelope(
                    sessionID: sessionID,
                    authorParticipantID: "eip155:1:0xflood\(index)",
                    createdAt: Date(timeIntervalSince1970: TimeInterval(index + 2)),
                    event: .participantJoined(SocialParticipantIdentity(
                        participantID: "eip155:1:0xflood\(index)",
                        caip10Account: "eip155:1:0xflood\(index)",
                        displayName: "Flood \(index)",
                        role: .collaborator,
                        verificationState: .pending
                    ))
                ),
                topic: "topic"
            )
        }

        let ownerJoin = SocialEventEnvelope(
            sessionID: sessionID,
            authorParticipantID: ownerID,
            createdAt: Date(timeIntervalSince1970: 1_000),
            event: .participantJoined(SocialParticipantIdentity(
                participantID: ownerID,
                caip10Account: ownerID,
                displayName: "Owner",
                role: .owner,
                verificationState: .pending,
                joinedAt: Date(timeIntervalSince1970: 1_000)
            ))
        )
        await store.appendInbound(ownerJoin, topic: "topic")
        await store.appendInbound(
            SocialEventEnvelope(
                sessionID: sessionID,
                authorParticipantID: "eip155:1:0xflood0",
                createdAt: Date(timeIntervalSince1970: 2_000),
                event: .unsupported(kind: "sweep")
            ),
            topic: "topic"
        )

        let held = await store.currentSnapshot().envelopes.filter { $0.sessionID == sessionID }
        #expect(held.count == policy.maximumStoredEnvelopesPerSession)
        #expect(
            held.contains { $0.id == ownerJoin.id },
            "a tombstone held the anchored slot and the owner's record was evicted"
        )
    }

    /// The protected slot must go to the row that *establishes the owner*, not merely to the
    /// earliest row that names the anchored party — because "earliest" is a race an invite holder
    /// wins for one envelope.
    ///
    /// `rejectionReason` accepts a relay `participantJoined` that introduces the anchored party's
    /// own id with `role: .viewer` — it describes its author, it rebinds nothing, and
    /// `roleEscalation` only fires on `.owner`. That is the same pre-claim
    /// `preClaimPinsTheOwnerDisplayNameAsAKnownResidual` records as reachable. Against an
    /// earliest-arrived protection it is also the *first* row naming the anchored participant, so it
    /// takes the protected slot and the owner's genuine record — which arrives later and is accepted
    /// through `relayMayOverwriteHeldRecord` — is left in the ordinary, evictable tier as the newest
    /// membership row.
    ///
    /// One further envelope then deletes it, and re-reducing the log reads the pre-claim as the
    /// owner's record: `hasOwner` is false, `sessionEnded` is refused as `.ownerRequired`, no
    /// `endedAt` is derivable, and `prune` can never release the graph. That is exactly the
    /// unrecoverable loss the anchor exists to prevent, reached through the protection meant to
    /// prevent it.
    ///
    /// Fails against a protection keyed on "earliest row naming an anchored participant".
    @Test("a pre-claim naming the anchored owner cannot take the owner's protected slot")
    func anchoredProtectionCannotBeClaimedByAPreClaimedNonOwnerRecord() async {
        let policy = SocialRetentionPolicy(maximumStoredEnvelopesPerSession: 4)
        let store = SocialEventLogStore(retentionPolicy: policy)
        let sessionID = UUID()
        let ownerID = "eip155:1:0xowner"

        await store.saveInvite(
            SocialInvite(
                sessionID: sessionID,
                relayTopic: "topic",
                encryptedSessionKey: "key",
                inviterParticipantID: ownerID,
                expiresAt: Date(timeIntervalSince1970: 10_000_000),
                nonce: "nonce"
            )
        )

        // The pre-claim: the anchored party's own id and account, demoted to `.viewer` under a name
        // the attacker chose. Nothing in it is secret — the id is printed in the invite every holder
        // has, and in production the id *is* the account.
        let preClaim = SocialEventEnvelope(
            sessionID: sessionID,
            authorParticipantID: ownerID,
            createdAt: Date(timeIntervalSince1970: 1),
            event: .participantJoined(SocialParticipantIdentity(
                participantID: ownerID,
                caip10Account: ownerID,
                displayName: "Evil",
                role: .viewer,
                verificationState: .pending,
                joinedAt: Date(timeIntervalSince1970: 1)
            ))
        )
        // The gate `SocialRelayCoordinator.handleInbound` applies before storage admits anything. If
        // it refused the pre-claim this would be unreachable, so assert it does not.
        let emptyProjection = await store.projection(sessionID: sessionID)
        #expect(
            emptyProjection.rejectionReason(for: preClaim) == nil,
            "the pre-claim is refused, so this attack would never reach storage"
        )
        await store.appendInbound(preClaim, topic: "topic")

        // The flood arrives next, so the owner's record is the newest membership row when it lands.
        for index in 0..<20 {
            await store.appendInbound(
                SocialEventEnvelope(
                    sessionID: sessionID,
                    authorParticipantID: "eip155:1:0xflood\(index)",
                    createdAt: Date(timeIntervalSince1970: TimeInterval(index + 2)),
                    event: .participantJoined(SocialParticipantIdentity(
                        participantID: "eip155:1:0xflood\(index)",
                        caip10Account: "eip155:1:0xflood\(index)",
                        displayName: "Flood \(index)",
                        role: .collaborator,
                        verificationState: .pending
                    ))
                ),
                topic: "topic"
            )
        }

        let ownerJoin = SocialEventEnvelope(
            sessionID: sessionID,
            authorParticipantID: ownerID,
            createdAt: Date(timeIntervalSince1970: 1_000),
            event: .participantJoined(SocialParticipantIdentity(
                participantID: ownerID,
                caip10Account: ownerID,
                displayName: "Owner",
                role: .owner,
                verificationState: .pending,
                joinedAt: Date(timeIntervalSince1970: 1_000)
            ))
        )
        // The owner's genuine record is accepted over the pre-claim — `relayMayOverwriteHeldRecord`
        // admits the anchored party establishing its own ownership — so the loss below is eviction,
        // not rejection.
        let preClaimedProjection = await store.projection(sessionID: sessionID)
        #expect(preClaimedProjection.rejectionReason(for: ownerJoin) == nil)
        await store.appendInbound(ownerJoin, topic: "topic")
        #expect(await store.projection(sessionID: sessionID).participants[ownerID]?.role == .owner)

        // One more envelope, from anyone.
        await store.appendInbound(
            SocialEventEnvelope(
                sessionID: sessionID,
                authorParticipantID: "eip155:1:0xflood0",
                createdAt: Date(timeIntervalSince1970: 2_000),
                event: .unsupported(kind: "sweep")
            ),
            topic: "topic"
        )

        let held = await store.currentSnapshot().envelopes.filter { $0.sessionID == sessionID }
        #expect(held.count == policy.maximumStoredEnvelopesPerSession)
        #expect(
            held.contains { $0.id == ownerJoin.id },
            "a pre-claim held the anchored slot and the owner's record was evicted"
        )
        // The consequence, stated as the thing that cannot be recovered.
        let projection = await store.projection(sessionID: sessionID)
        #expect(
            projection.participants[ownerID]?.role == .owner,
            "the session is left permanently ownerless and unprunable"
        )
    }

    /// The protected slot must go to a row the *projection* reads as the anchored party's owner
    /// record — not to any row that declares `role: .owner` about them.
    ///
    /// `role == .owner` is one field weaker than the projection's rule, which also requires the
    /// record to carry the anchored party's own account (`describesSelf`). A `participantJoined`
    /// naming the anchored id with `role: .owner` and the **attacker's** wallet therefore held the
    /// protected slot while `rejectionReason` refused that very row as `.roleEscalation` — so the
    /// slot was occupied by something that establishes no owner at all, and the owner's genuine
    /// record, arriving later as it must on a joined session, stayed evictable. One further envelope
    /// deletes it and the session is left permanently ownerless: `sessionEnded` is refused as
    /// `.ownerRequired`, no `endedAt` is derivable, and `prune` can never release the graph.
    ///
    /// This is the same shape as `anchoredProtectionGoesToTheRecordNotToATombstone`: the relay gate
    /// refuses the pre-claim, so the test drives `appendInbound` directly — which is public and is
    /// documented as the one place admission control lives. The assertion below pins that the gate
    /// and the ceiling disagree about this row, which is exactly why the ceiling cannot delegate.
    ///
    /// Fails against a protection keyed on `establishedMembershipRole == .owner` alone.
    @Test("an owner pre-claim carrying a foreign account cannot take the owner's protected slot")
    func anchoredProtectionCannotBeClaimedByAForeignAccountOwnerRecord() async {
        let policy = SocialRetentionPolicy(maximumStoredEnvelopesPerSession: 4)
        let store = SocialEventLogStore(retentionPolicy: policy)
        let sessionID = UUID()
        let ownerID = "eip155:1:0xowner"

        await store.saveInvite(
            SocialInvite(
                sessionID: sessionID,
                relayTopic: "topic",
                encryptedSessionKey: "key",
                inviterParticipantID: ownerID,
                expiresAt: Date(timeIntervalSince1970: 10_000_000),
                nonce: "nonce"
            )
        )

        // The anchored party's id, `role: .owner`, and the attacker's own wallet. Everything the
        // ceiling used to check is satisfied; the one thing the projection checks is not.
        let preClaim = SocialEventEnvelope(
            sessionID: sessionID,
            authorParticipantID: ownerID,
            createdAt: Date(timeIntervalSince1970: 1),
            event: .participantJoined(SocialParticipantIdentity(
                participantID: ownerID,
                caip10Account: "eip155:1:0xattacker",
                displayName: "Evil",
                role: .owner,
                verificationState: .pending,
                joinedAt: Date(timeIntervalSince1970: 1)
            ))
        )
        let emptyProjection = await store.projection(sessionID: sessionID)
        #expect(
            emptyProjection.rejectionReason(for: preClaim) == .roleEscalation,
            "the projection would honor this row, so it is not the divergence under test"
        )
        await store.appendInbound(preClaim, topic: "topic")

        // The flood arrives next, so the owner's record is the newest membership row when it lands.
        for index in 0..<20 {
            await store.appendInbound(
                SocialEventEnvelope(
                    sessionID: sessionID,
                    authorParticipantID: "eip155:1:0xflood\(index)",
                    createdAt: Date(timeIntervalSince1970: TimeInterval(index + 2)),
                    event: .participantJoined(SocialParticipantIdentity(
                        participantID: "eip155:1:0xflood\(index)",
                        caip10Account: "eip155:1:0xflood\(index)",
                        displayName: "Flood \(index)",
                        role: .collaborator,
                        verificationState: .pending
                    ))
                ),
                topic: "topic"
            )
        }

        let ownerJoin = SocialEventEnvelope(
            sessionID: sessionID,
            authorParticipantID: ownerID,
            createdAt: Date(timeIntervalSince1970: 1_000),
            event: .participantJoined(SocialParticipantIdentity(
                participantID: ownerID,
                caip10Account: ownerID,
                displayName: "Owner",
                role: .owner,
                verificationState: .pending,
                joinedAt: Date(timeIntervalSince1970: 1_000)
            ))
        )
        // The pre-claim established nothing, so the genuine record bootstraps ownership normally —
        // the loss below is eviction, not rejection.
        let preClaimedProjection = await store.projection(sessionID: sessionID)
        #expect(preClaimedProjection.rejectionReason(for: ownerJoin) == nil)
        await store.appendInbound(ownerJoin, topic: "topic")
        #expect(await store.projection(sessionID: sessionID).participants[ownerID]?.role == .owner)

        // One more envelope, from anyone.
        await store.appendInbound(
            SocialEventEnvelope(
                sessionID: sessionID,
                authorParticipantID: "eip155:1:0xflood0",
                createdAt: Date(timeIntervalSince1970: 2_000),
                event: .unsupported(kind: "sweep")
            ),
            topic: "topic"
        )

        let held = await store.currentSnapshot().envelopes.filter { $0.sessionID == sessionID }
        #expect(held.count == policy.maximumStoredEnvelopesPerSession)
        #expect(
            held.contains { $0.id == ownerJoin.id },
            "a foreign-account owner pre-claim held the anchored slot and the owner's record was evicted"
        )
        let projection = await store.projection(sessionID: sessionID)
        #expect(
            projection.participants[ownerID]?.role == .owner,
            "the session is left permanently ownerless and unprunable"
        )
    }

    /// The protected slot must go to a row the projection can honor — and `.local` is a row it can
    /// *never* honor off the relay.
    ///
    /// `grantsSelfDescribedOwnership` is a question about the event payload, and
    /// `verificationState` is in that payload but outside the predicate: a `participantJoined`
    /// naming the anchored party's own id and account with `role: .owner` and
    /// `verificationState: .local` satisfies every field the ceiling checked, while
    /// `rejectionReason` refuses that same row unconditionally as `.untrustedLocalIdentity` —
    /// provenance is the one claim the wire cannot make about itself. So the slot was held by a row
    /// that establishes no owner at all, and the owner's genuine record, arriving later as it must
    /// on a joined session, stayed in the evictable tier as the newest membership row. One further
    /// envelope deletes it: `hasOwner` is false, `sessionEnded` is refused as `.ownerRequired`, no
    /// `endedAt` is derivable, and `prune` can never release the graph.
    ///
    /// Same shape and same reachability as `anchoredProtectionCannotBeClaimedByAForeignAccountOwnerRecord`:
    /// the relay gate refuses this row, so the test drives `appendInbound` directly — which is
    /// public and is documented as the one place admission control lives. The assertion below pins
    /// that the gate and the ceiling disagree about it, which is why the ceiling cannot delegate.
    ///
    /// Fails against a protection that reads only the payload's participant id, account and role.
    @Test("a `.local` owner pre-claim cannot take the owner's protected slot")
    func anchoredProtectionCannotBeClaimedByALocalVerificationStateRecord() async {
        let policy = SocialRetentionPolicy(maximumStoredEnvelopesPerSession: 4)
        let store = SocialEventLogStore(retentionPolicy: policy)
        let sessionID = UUID()
        let ownerID = "eip155:1:0xowner"

        await store.saveInvite(
            SocialInvite(
                sessionID: sessionID,
                relayTopic: "topic",
                encryptedSessionKey: "key",
                inviterParticipantID: ownerID,
                expiresAt: Date(timeIntervalSince1970: 10_000_000),
                nonce: "nonce"
            )
        )

        // The anchored party's own id and account, `role: .owner` — and the one trust state a
        // relay-delivered record may never claim.
        let preClaim = SocialEventEnvelope(
            sessionID: sessionID,
            authorParticipantID: ownerID,
            createdAt: Date(timeIntervalSince1970: 1),
            event: .participantJoined(SocialParticipantIdentity(
                participantID: ownerID,
                caip10Account: ownerID,
                displayName: "Evil",
                role: .owner,
                verificationState: .local,
                joinedAt: Date(timeIntervalSince1970: 1)
            ))
        )
        let emptyProjection = await store.projection(sessionID: sessionID)
        #expect(
            emptyProjection.rejectionReason(for: preClaim) == .untrustedLocalIdentity,
            "the projection would honor this row, so it is not the divergence under test"
        )
        await store.appendInbound(preClaim, topic: "topic")

        // The flood arrives next, so the owner's record is the newest membership row when it lands.
        for index in 0..<20 {
            await store.appendInbound(
                SocialEventEnvelope(
                    sessionID: sessionID,
                    authorParticipantID: "eip155:1:0xflood\(index)",
                    createdAt: Date(timeIntervalSince1970: TimeInterval(index + 2)),
                    event: .participantJoined(SocialParticipantIdentity(
                        participantID: "eip155:1:0xflood\(index)",
                        caip10Account: "eip155:1:0xflood\(index)",
                        displayName: "Flood \(index)",
                        role: .collaborator,
                        verificationState: .pending
                    ))
                ),
                topic: "topic"
            )
        }

        let ownerJoin = SocialEventEnvelope(
            sessionID: sessionID,
            authorParticipantID: ownerID,
            createdAt: Date(timeIntervalSince1970: 1_000),
            event: .participantJoined(SocialParticipantIdentity(
                participantID: ownerID,
                caip10Account: ownerID,
                displayName: "Owner",
                role: .owner,
                verificationState: .pending,
                joinedAt: Date(timeIntervalSince1970: 1_000)
            ))
        )
        // The pre-claim established nothing, so the genuine record bootstraps ownership normally —
        // the loss below is eviction, not rejection.
        let preClaimedProjection = await store.projection(sessionID: sessionID)
        #expect(preClaimedProjection.rejectionReason(for: ownerJoin) == nil)
        await store.appendInbound(ownerJoin, topic: "topic")
        #expect(await store.projection(sessionID: sessionID).participants[ownerID]?.role == .owner)

        // One more envelope, from anyone.
        await store.appendInbound(
            SocialEventEnvelope(
                sessionID: sessionID,
                authorParticipantID: "eip155:1:0xflood0",
                createdAt: Date(timeIntervalSince1970: 2_000),
                event: .unsupported(kind: "sweep")
            ),
            topic: "topic"
        )

        let held = await store.currentSnapshot().envelopes.filter { $0.sessionID == sessionID }
        #expect(held.count == policy.maximumStoredEnvelopesPerSession)
        #expect(
            held.contains { $0.id == ownerJoin.id },
            "a `.local` owner pre-claim held the anchored slot and the owner's record was evicted"
        )
        let projection = await store.projection(sessionID: sessionID)
        #expect(
            projection.participants[ownerID]?.role == .owner,
            "the session is left permanently ownerless and unprunable"
        )
    }

    /// The protected slot must prefer a row the projection can honor, and "can honor" is decided by
    /// the **envelope** as well as the payload.
    ///
    /// `authorCAIP10Account` rides on the envelope, not in the record, and it is the first thing
    /// `rejectionReason` reads: a row naming an account other than its own author is refused as
    /// `.mismatchedAccount` the moment any record for that participant is already held. A payload
    /// predicate cannot see it, so an owner pre-claim that is self-describing *in the record* and
    /// contradicts itself *on the envelope* took the protected slot, and a second row backdated
    /// ahead of it supplied the held record that turns the contradiction into a refusal. The
    /// anchored slot then belongs to a row that establishes nothing, and the owner's genuine
    /// record is evicted as the newest membership row — permanently ownerless, exactly as in every
    /// earlier round.
    ///
    /// Note what the attack needs, because it is the reason the ceiling cannot delegate to the
    /// relay gate: both rows are accepted when they *arrive* and only the replay order makes one of
    /// them a refusal. `handleInbound` checks an envelope against the projection as it stands at
    /// arrival; `reduce` replays the stored log in `createdAt` order, which is a wire field. This
    /// drives `appendInbound` directly, like its two siblings above.
    ///
    /// Fails against a protection ranked on arrival order alone.
    @Test("an owner record contradicting its own envelope account loses the protected slot")
    func anchoredProtectionPrefersTheRowTheProjectionCanHonor() async {
        let policy = SocialRetentionPolicy(maximumStoredEnvelopesPerSession: 4)
        let store = SocialEventLogStore(retentionPolicy: policy)
        let sessionID = UUID()
        let ownerID = "eip155:1:0xowner"

        await store.saveInvite(
            SocialInvite(
                sessionID: sessionID,
                relayTopic: "topic",
                encryptedSessionKey: "key",
                inviterParticipantID: ownerID,
                expiresAt: Date(timeIntervalSince1970: 10_000_000),
                nonce: "nonce"
            )
        )

        // Self-describing in the record, and naming the attacker's wallet as the author's account
        // on the envelope. Arrives first, so arrival order alone hands it the slot.
        let preClaim = SocialEventEnvelope(
            sessionID: sessionID,
            authorParticipantID: ownerID,
            authorCAIP10Account: "eip155:1:0xattacker",
            createdAt: Date(timeIntervalSince1970: 2),
            event: .participantJoined(SocialParticipantIdentity(
                participantID: ownerID,
                caip10Account: ownerID,
                displayName: "Evil",
                role: .owner,
                verificationState: .pending,
                joinedAt: Date(timeIntervalSince1970: 2)
            ))
        )
        await store.appendInbound(preClaim, topic: "topic")

        // Backdated behind it, so on replay it supplies the held record the pre-claim's own
        // envelope account then contradicts.
        await store.appendInbound(
            SocialEventEnvelope(
                sessionID: sessionID,
                authorParticipantID: ownerID,
                createdAt: Date(timeIntervalSince1970: 1),
                event: .participantJoined(SocialParticipantIdentity(
                    participantID: ownerID,
                    caip10Account: ownerID,
                    displayName: "Evil",
                    role: .viewer,
                    verificationState: .pending,
                    joinedAt: Date(timeIntervalSince1970: 1)
                ))
            ),
            topic: "topic"
        )
        // The divergence, stated directly: the row holding the protected slot establishes no owner.
        #expect(
            await store.projection(sessionID: sessionID).participants[ownerID]?.role == .viewer,
            "the pre-claim is honored, so it is not the divergence under test"
        )

        for index in 0..<20 {
            await store.appendInbound(
                SocialEventEnvelope(
                    sessionID: sessionID,
                    authorParticipantID: "eip155:1:0xflood\(index)",
                    createdAt: Date(timeIntervalSince1970: TimeInterval(index + 3)),
                    event: .participantJoined(SocialParticipantIdentity(
                        participantID: "eip155:1:0xflood\(index)",
                        caip10Account: "eip155:1:0xflood\(index)",
                        displayName: "Flood \(index)",
                        role: .collaborator,
                        verificationState: .pending
                    ))
                ),
                topic: "topic"
            )
        }

        let ownerJoin = SocialEventEnvelope(
            sessionID: sessionID,
            authorParticipantID: ownerID,
            authorCAIP10Account: ownerID,
            createdAt: Date(timeIntervalSince1970: 1_000),
            event: .participantJoined(SocialParticipantIdentity(
                participantID: ownerID,
                caip10Account: ownerID,
                displayName: "Owner",
                role: .owner,
                verificationState: .pending,
                joinedAt: Date(timeIntervalSince1970: 1_000)
            ))
        )
        await store.appendInbound(ownerJoin, topic: "topic")
        #expect(await store.projection(sessionID: sessionID).participants[ownerID]?.role == .owner)

        // One more envelope, from anyone.
        await store.appendInbound(
            SocialEventEnvelope(
                sessionID: sessionID,
                authorParticipantID: "eip155:1:0xflood0",
                createdAt: Date(timeIntervalSince1970: 2_000),
                event: .unsupported(kind: "sweep")
            ),
            topic: "topic"
        )

        let held = await store.currentSnapshot().envelopes.filter { $0.sessionID == sessionID }
        #expect(held.count == policy.maximumStoredEnvelopesPerSession)
        #expect(
            held.contains { $0.id == ownerJoin.id },
            "a contradicted owner pre-claim held the anchored slot and the owner's record was evicted"
        )
        let projection = await store.projection(sessionID: sessionID)
        #expect(
            projection.participants[ownerID]?.role == .owner,
            "the session is left permanently ownerless and unprunable"
        )
    }

    /// The envelope-level conditions are a **rank, not a filter**, and this is the case that decides
    /// it — the companion to `anchoredProtectionPrefersTheRowTheProjectionCanHonor` above, in the
    /// direction that round's fix could have broken.
    ///
    /// `.mismatchedAccount` refuses a row whose `authorCAIP10Account` names someone other than its
    /// author only *conditionally*: its `let known = participants[author]` binding fails when no
    /// record for that participant is held yet. So the very first such row for an anchored party is
    /// accepted, bootstraps ownership, and — because `.foreignRecordUpdate` then refuses anything
    /// that would change the stored value — becomes the session's **sole honored owner record**.
    ///
    /// Excluding those rows from the protected set, rather than merely ranking them below cleaner
    /// candidates, would therefore leave that record evictable and hand back exactly the
    /// unrecoverable loss the anchor exists to prevent: no `hasOwner`, `sessionEnded` refused as
    /// `.ownerRequired`, no derivable `endedAt`, and `prune` unable to release the graph. The
    /// asymmetry is the point — demoting is always safe, excluding is not — and it is the natural
    /// "tightening" a later round would reach for, so it is pinned rather than argued.
    ///
    /// Fails if `selfDescribedOwnershipProtectionRank` is applied as a `guard … else { continue }`
    /// instead of as a sort key.
    @Test("a contradicted owner record still holds the slot when it is the only candidate")
    func anchoredProtectionRanksRatherThanExcludesTheOnlyHonoredOwnerRecord() async {
        let policy = SocialRetentionPolicy(maximumStoredEnvelopesPerSession: 4)
        let store = SocialEventLogStore(retentionPolicy: policy)
        let sessionID = UUID()
        let ownerID = "eip155:1:0xowner"

        await store.saveInvite(
            SocialInvite(
                sessionID: sessionID,
                relayTopic: "topic",
                encryptedSessionKey: "key",
                inviterParticipantID: ownerID,
                expiresAt: Date(timeIntervalSince1970: 10_000_000),
                nonce: "nonce"
            )
        )

        // The flood lands first, so the owner's record is the newest membership row when it arrives
        // and is the first thing `evictsNewestFirst` reaches for if it is not protected.
        for index in 0..<20 {
            await store.appendInbound(
                SocialEventEnvelope(
                    sessionID: sessionID,
                    authorParticipantID: "eip155:1:0xflood\(index)",
                    createdAt: Date(timeIntervalSince1970: TimeInterval(index + 2)),
                    event: .participantJoined(SocialParticipantIdentity(
                        participantID: "eip155:1:0xflood\(index)",
                        caip10Account: "eip155:1:0xflood\(index)",
                        displayName: "Flood \(index)",
                        role: .collaborator,
                        verificationState: .pending
                    ))
                ),
                topic: "topic"
            )
        }

        // Self-describing in the record and contradicted on the envelope — the shape the round above
        // demotes. Here it is the *only* candidate for the anchor, so demoting it must still leave
        // it protected.
        let ownerJoin = SocialEventEnvelope(
            sessionID: sessionID,
            authorParticipantID: ownerID,
            authorCAIP10Account: "eip155:1:0xattacker",
            createdAt: Date(timeIntervalSince1970: 1_000),
            event: .participantJoined(SocialParticipantIdentity(
                participantID: ownerID,
                caip10Account: ownerID,
                displayName: "Owner",
                role: .owner,
                verificationState: .pending,
                joinedAt: Date(timeIntervalSince1970: 1_000)
            ))
        )
        // No record for this participant is held, so `mismatchedAccount`'s `known` binding fails and
        // the row is honored. That is what makes it worth a protected slot despite its rank.
        #expect(
            await store.projection(sessionID: sessionID).rejectionReason(for: ownerJoin) == nil,
            "the projection refuses this row, so it is not the case under test"
        )
        await store.appendInbound(ownerJoin, topic: "topic")
        #expect(await store.projection(sessionID: sessionID).participants[ownerID]?.role == .owner)

        // One more envelope, from anyone.
        await store.appendInbound(
            SocialEventEnvelope(
                sessionID: sessionID,
                authorParticipantID: "eip155:1:0xflood0",
                createdAt: Date(timeIntervalSince1970: 2_000),
                event: .unsupported(kind: "sweep")
            ),
            topic: "topic"
        )

        let held = await store.currentSnapshot().envelopes.filter { $0.sessionID == sessionID }
        #expect(held.count == policy.maximumStoredEnvelopesPerSession)
        #expect(
            held.contains { $0.id == ownerJoin.id },
            "the only row that establishes the anchored owner was excluded from the protected set"
        )
        let projection = await store.projection(sessionID: sessionID)
        #expect(
            projection.participants[ownerID]?.role == .owner,
            "the session is left permanently ownerless and unprunable"
        )
    }

    /// Eviction must never be able to refuse: the arriving envelope is not a candidate victim, so
    /// an append at the ceiling always lands even when every evictable row is in its own class.
    @Test("an arriving envelope is never its own eviction victim")
    func arrivingEnvelopeIsNeverItsOwnVictim() async {
        let policy = SocialRetentionPolicy(maximumStoredEnvelopesPerSession: 1)
        let store = SocialEventLogStore(retentionPolicy: policy)
        let sessionID = UUID()

        var last: SocialEventEnvelope?
        for index in 0..<5 {
            let envelope = SocialEventEnvelope(
                sessionID: sessionID,
                authorParticipantID: "peer-\(index)",
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                event: .participantJoined(SocialParticipantIdentity(
                    participantID: "peer-\(index)",
                    caip10Account: "eip155:1:0xpeer\(index)",
                    displayName: "Peer \(index)",
                    role: .collaborator,
                    verificationState: .pending
                ))
            )
            await store.appendInbound(envelope, topic: "topic")
            last = envelope
        }

        let held = await store.currentSnapshot().envelopes.filter { $0.sessionID == sessionID }
        #expect(held.count == 1)
        #expect(held.first?.id == last?.id, "the arriving envelope evicted itself — the ceiling refused")
    }

    /// A re-delivery is not new content and must not cost a row.
    ///
    /// Eviction ran before `appendUnique`, which declines an id already held — so at the ceiling a
    /// duplicate evicted a genuine row and then inserted nothing, shrinking the log by one. This
    /// needs no attacker: the relay replays each topic from the cursor on every reconnect.
    ///
    /// Fails against the pre-fix code, which drops to one envelope.
    @Test("a duplicate delivery at the ceiling does not shrink the log")
    func duplicateDeliveryAtTheCeilingCostsNothing() async {
        let policy = SocialRetentionPolicy(maximumStoredEnvelopesPerSession: 2)
        let store = SocialEventLogStore(retentionPolicy: policy)
        let sessionID = UUID()

        let first = SocialEventEnvelope(
            sessionID: sessionID,
            authorParticipantID: "peer",
            createdAt: Date(timeIntervalSince1970: 1),
            event: .receiptShared(UUID())
        )
        let second = SocialEventEnvelope(
            sessionID: sessionID,
            authorParticipantID: "peer",
            createdAt: Date(timeIntervalSince1970: 2),
            event: .receiptShared(UUID())
        )
        await store.appendInbound(first, topic: "topic")
        await store.appendInbound(second, topic: "topic")

        // Replayed from the cursor, exactly as a reconnect does.
        await store.appendInbound(first, topic: "topic")
        await store.appendInbound(second, topic: "topic")

        let held = await store.currentSnapshot().envelopes.filter { $0.sessionID == sessionID }
        #expect(held.count == 2)
        #expect(held.contains { $0.id == first.id })
        #expect(held.contains { $0.id == second.id })
    }

    /// The anchor must not outlive the thing it anchors. Once a session graph is pruned, so is its
    /// anchor — otherwise the map is a durable table that only ever grows.
    ///
    /// Modelled on a session this installation *hosted*: `hostSession` saves an invite naming itself
    /// as inviter, so hosted sessions carry an anchor too, and their owner record is locally minted
    /// and therefore keeps `canAuthorBindingEvents` — which is what lets `sessionEnded` be accepted
    /// and the graph reach a prunable state at all.
    @Test("pruning a terminal session graph also drops its owner anchor")
    func pruningSessionGraphDropsItsOwnerAnchor() async {
        let store = SocialEventLogStore()
        let sessionID = UUID()
        let now = Date(timeIntervalSince1970: 10_000)
        // The shape production mints for a wallet-verified participant: one CAIP-10 value is both
        // the participant id and the account. The anchored-bootstrap rule requires that
        // self-description, because the anchor alone only names *who* may own the session and
        // cannot authenticate an unsigned wire envelope as having come from them.
        let ownerID = "eip155:1:0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed"
        let owner = SocialParticipantIdentity(
            participantID: ownerID,
            caip10Account: ownerID,
            displayName: "Owner",
            role: .owner,
            verificationState: .verified
        )
        await store.saveInvite(SocialInvite(
            sessionID: sessionID,
            relayTopic: "topic-hosted",
            encryptedSessionKey: "key",
            inviterParticipantID: ownerID,
            expiresAt: now.addingTimeInterval(1_000),
            nonce: "nonce"
        ))
        await store.appendLocal([
            SocialEventEnvelope(
                sessionID: sessionID,
                authorParticipantID: ownerID,
                createdAt: now.addingTimeInterval(-200),
                event: .participantJoined(owner)
            ),
            SocialEventEnvelope(
                sessionID: sessionID,
                authorParticipantID: ownerID,
                createdAt: now.addingTimeInterval(-100),
                event: .sessionEnded(endedAt: now.addingTimeInterval(-100))
            )
        ])

        let result = await store.prune(
            now: now,
            policy: SocialRetentionPolicy(terminalSessionRetention: 50, expiredInviteRetention: 0)
        )

        #expect(result.removedSessionCount == 1)
        #expect(await store.currentSnapshot().ownerAnchorsBySessionID.isEmpty)
    }

    /// An anchor for a session that never produced a single envelope and whose invite is gone has
    /// nothing left to anchor, so it must not accumulate.
    @Test("pruning drops an orphaned anchor whose invite expired with no traffic")
    func pruningDropsOrphanedAnchor() async {
        let store = SocialEventLogStore()
        let sessionID = UUID()
        let now = Date(timeIntervalSince1970: 10_000)
        await store.saveInvite(SocialInvite(
            sessionID: sessionID,
            relayTopic: "topic-dead",
            encryptedSessionKey: "key",
            inviterParticipantID: "owner",
            expiresAt: now.addingTimeInterval(-5_000),
            nonce: "nonce"
        ))

        await store.prune(
            now: now,
            policy: SocialRetentionPolicy(terminalSessionRetention: 50, expiredInviteRetention: 0)
        )

        #expect(await store.currentSnapshot().ownerAnchorsBySessionID.isEmpty)
    }

    /// The anchor is durable state, so it has to survive a relaunch — a reloaded log that forgets it
    /// is the same broken joined session, one process later.
    @Test("the owner anchor survives a persistence round-trip")
    func ownerAnchorSurvivesPersistenceRoundTrip() async throws {
        let sessionID = UUID()
        var snapshot = SocialEventLogSnapshot()
        snapshot.ownerAnchorsBySessionID = [sessionID: ["owner"]]

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SocialEventLogSnapshot.self, from: data)

        #expect(decoded.ownerAnchorsBySessionID[sessionID] == ["owner"])
    }

    /// Forward compatibility, matching `locallyMintedEventIDs`: a payload written before anchors
    /// existed decodes as empty rather than failing the whole log.
    @Test("a snapshot written before owner anchors existed still decodes")
    func snapshotWithoutOwnerAnchorsDecodes() throws {
        let legacy = Data(#"{"envelopes":[],"invites":[]}"#.utf8)

        let decoded = try JSONDecoder().decode(SocialEventLogSnapshot.self, from: legacy)

        #expect(decoded.ownerAnchorsBySessionID.isEmpty)
    }

    /// The projection's own approval state carries the same two invariants as
    /// ``CollaborativeApproval``, and had the same synthesized-`Codable` hole.
    /// ``SocialSessionProjection`` is `public` and `Codable` and holds these, so this is their
    /// decode boundary: `requiredApprovals: 0` resolves an approval `.approved` with zero votes,
    /// and a repeated vote from one participant counts twice toward the threshold.
    ///
    /// Fails against the pre-fix code, which decoded `0` and reported `.approved`.
    @Test("a decoded approval state cannot resolve itself")
    func decodedApprovalStateIsBounded() throws {
        let id = UUID()
        let zeroThreshold = """
        {"id":"\(id.uuidString)","prompt":"Ship it?","requiredApprovals":0,"votes":[]}
        """
        let decoded = try JSONDecoder().decode(
            SocialApprovalState.self,
            from: Data(zeroThreshold.utf8)
        )
        #expect(decoded.requiredApprovals == 1)
        #expect(decoded.resolution == .pending, "a decoded approval approved itself with no votes")

        let stuffed = SocialApprovalState(
            id: id,
            prompt: "Ship it?",
            requiredApprovals: 2,
            votes: [
                SocialApprovalVote(participantID: "alice", approved: true, castAt: Date(timeIntervalSince1970: 1)),
                SocialApprovalVote(participantID: "alice", approved: true, castAt: Date(timeIntervalSince1970: 2))
            ]
        )
        let roundTripped = try JSONDecoder().decode(
            SocialApprovalState.self,
            from: try JSONEncoder().encode(stuffed)
        )
        #expect(roundTripped.votes.count == 1, "one participant's vote was counted twice")
        #expect(roundTripped.resolution == .pending)
        #expect(roundTripped.votes.first?.castAt == Date(timeIntervalSince1970: 2))
    }

    /// Arrival order is read back off disk, and the ceiling ranks the membership tier by
    /// `-sequence` (see ``SocialEvent/EvictionClass/evictsNewestFirst``). `-Int.min` is not
    /// representable, so one negative entry in a decoded `inboundSequenceByEventID` **traps** — the
    /// process dies on the next inbound envelope, and dies again on every relaunch, because the
    /// value is reloaded from the same payload. Nothing this package writes is ever negative
    /// (`max + 1`, starting at 1), but the table is decoded straight through and the memberwise
    /// initializer is `public`, so the floor belongs at the boundary.
    ///
    /// Crashes against the pre-fix code rather than failing.
    @Test("a negative stored arrival order cannot trap the storage ceiling")
    func negativeStoredArrivalOrderIsFloored() async {
        let fixture = SyncFixture()
        let heldID = UUID()
        let held = SocialEventEnvelope(
            id: heldID,
            sessionID: fixture.sessionID,
            authorParticipantID: "peer",
            createdAt: fixture.date(1),
            event: .participantJoined(fixture.verifiedParticipant("peer"))
        )
        let store = SocialEventLogStore(
            persistence: SeededSocialEventLogPersistence(
                snapshot: SocialEventLogSnapshot(
                    envelopes: [held],
                    inboundSequenceByEventID: [heldID: Int.min]
                )
            ),
            retentionPolicy: SocialRetentionPolicy(maximumStoredEnvelopesPerSession: 1)
        )

        await store.appendInbound(
            SocialEventEnvelope(
                sessionID: fixture.sessionID,
                authorParticipantID: "flood",
                createdAt: fixture.date(2),
                event: .unsupported(kind: "future")
            ),
            topic: "topic"
        )

        // The ceiling still evicts rather than refusing or trapping, and the floored row is ranked
        // as the oldest content it is.
        let snapshot = await store.currentSnapshot()
        #expect(snapshot.envelopes.count == 1)
        #expect(snapshot.inboundSequenceByEventID.values.allSatisfy { $0 >= 0 })
    }

    /// The other half of the same bound, at the same boundary, for the same reason.
    ///
    /// Flooring at zero closed `-Int.min` in the ranking key and left the allocation untouched:
    /// `appendInbound` takes the next arrival order as `(values.max() ?? 0) + 1`, so a single stored
    /// `Int.max` **traps** on the addition before the ceiling is ever consulted. It is the identical
    /// failure the floor was written against — the process dies on the next inbound envelope and
    /// dies again on every relaunch, because the value is reloaded from the same payload — reached
    /// through the same two doors: a decoded table assigns straight through, and the memberwise
    /// initializer is `public`. A one-sided bound on a value used as both a sort key and a counter
    /// only covers the sort key.
    ///
    /// Crashes against the pre-fix code rather than failing.
    @Test("a saturated stored arrival order cannot trap the next allocation")
    func saturatedStoredArrivalOrderIsCapped() async {
        let fixture = SyncFixture()
        let heldID = UUID()
        let held = SocialEventEnvelope(
            id: heldID,
            sessionID: fixture.sessionID,
            authorParticipantID: "peer",
            createdAt: fixture.date(1),
            event: .participantJoined(fixture.verifiedParticipant("peer"))
        )
        let store = SocialEventLogStore(
            persistence: SeededSocialEventLogPersistence(
                snapshot: SocialEventLogSnapshot(
                    envelopes: [held],
                    inboundSequenceByEventID: [heldID: Int.max]
                )
            ),
            // Deliberately roomy: the trap is in the allocation, not in the eviction, so this must
            // fail with nothing to evict as well.
            retentionPolicy: SocialRetentionPolicy(maximumStoredEnvelopesPerSession: 50)
        )
        let arrivingID = UUID()

        await store.appendInbound(
            SocialEventEnvelope(
                id: arrivingID,
                sessionID: fixture.sessionID,
                authorParticipantID: "flood",
                createdAt: fixture.date(2),
                event: .unsupported(kind: "future")
            ),
            topic: "topic"
        )

        // And again, because the failure mode is a loop: the value is reloaded from the payload, so
        // a bound that only survives one append still dies on every relaunch.
        await store.appendInbound(
            SocialEventEnvelope(
                sessionID: fixture.sessionID,
                authorParticipantID: "flood",
                createdAt: fixture.date(3),
                event: .unsupported(kind: "future")
            ),
            topic: "topic"
        )

        let snapshot = await store.currentSnapshot()
        #expect(snapshot.envelopes.count == 3, "an arriving envelope was never admitted")
        #expect(snapshot.inboundSequenceByEventID[arrivingID] != nil)
        // The saturated row is pulled into the range the allocation can keep working inside, so the
        // next `max + 1` is representable however many times it runs.
        //
        // Asserted against the declared range rather than the looser `>= 0 && < Int.max`, so the
        // test pins the contract the source documents instead of the weakest bound that happens to
        // avoid a trap — a ceiling that drifted upward would otherwise go unnoticed until the
        // allocation sat one increment below the trap again.
        #expect(
            snapshot.inboundSequenceByEventID.values.allSatisfy {
                SocialEventLogSnapshot.inboundSequenceRange.contains($0)
            },
            "a stored arrival order escaped the range the allocation depends on"
        )
    }

    @Test("Projection explains a mutation rejected after session end")
    func explainsPostEndRejection() {
        let sessionID = UUID()
        let owner = SocialParticipantIdentity(
            participantID: "owner",
            caip10Account: "eip155:1:owner",
            displayName: "Owner",
            role: .owner,
            verificationState: .verified
        )
        let joined = SocialEventEnvelope(
            sessionID: sessionID,
            authorParticipantID: "owner",
            createdAt: Date(timeIntervalSince1970: 1),
            event: .participantJoined(owner)
        )
        let ended = SocialEventEnvelope(
            sessionID: sessionID,
            authorParticipantID: "owner",
            createdAt: Date(timeIntervalSince1970: 2),
            event: .sessionEnded(endedAt: Date(timeIntervalSince1970: 2))
        )
        let late = SocialEventEnvelope(
            sessionID: sessionID,
            authorParticipantID: "owner",
            createdAt: Date(timeIntervalSince1970: 3),
            event: .workflowShared("late")
        )

        // This session's own owner record *and* its own end, so both are locally minted. Two
        // separate reasons, and both would make this test pass for the wrong reason if dropped: a
        // relay-delivered `.verified` claim is downgraded to `.pending`, and a relay-delivered
        // `sessionEnded` naming the owner as its author is refused as `.impersonatedAuthor`. Either
        // way the session would never end, and `late` would be refused for its author rather than
        // for the end this test is named for.
        let projection = SocialSessionProjection.reduce(
            [joined, ended],
            sessionID: sessionID,
            locallyMintedEventIDs: [joined.id, ended.id]
        )

        // `late` is deliberately left relay-delivered: the post-end guard is checked first, so it
        // outranks the author binding, and that ordering is what makes the diagnosis specific.
        #expect(projection.rejectionReason(for: late) == .sessionEnded)

        // The two events `isMutatingAfterEnd` answers `false` for, which had no test at all —
        // changing it to an unconditional `true` left the whole suite green.
        //
        // `.sessionEnded` must stay acceptable after an end, or `apply`'s
        // `endedAt = min(endedAt ?? date, date)` is dead code and a correcting *earlier* end can
        // never land. `.unsupported` must stay acceptable because it is the forward-compatibility
        // carrier and is documented as admissible into an ended session — it grants no state, so
        // refusing it would remove the one behaviour the case exists to provide.
        let earlierEnd = SocialEventEnvelope(
            sessionID: sessionID,
            authorParticipantID: "owner",
            createdAt: Date(timeIntervalSince1970: 4),
            event: .sessionEnded(endedAt: Date(timeIntervalSince1970: 1))
        )
        #expect(projection.rejectionReason(for: earlierEnd, isLocallyMinted: true) == nil)

        let carrier = SocialEventEnvelope(
            sessionID: sessionID,
            authorParticipantID: "stranger",
            createdAt: Date(timeIntervalSince1970: 5),
            event: .unsupported(kind: "future.event")
        )
        // Relay-delivered and author-less by design: `.unsupported` needs no author, so this also
        // pins that the post-end guard is what is being tested rather than the author binding.
        #expect(projection.rejectionReason(for: carrier) == nil)
    }
}

private actor SocialEventLogBox {
    var snapshot = SocialEventLogSnapshot()
    func set(_ snapshot: SocialEventLogSnapshot) { self.snapshot = snapshot }
    func get() -> SocialEventLogSnapshot { snapshot }
}

private struct InMemorySocialEventLogPersistence: SocialEventLogPersisting {
    private let box = SocialEventLogBox()
    func load() async -> SocialEventLogSnapshot { await box.get() }
    func save(_ snapshot: SocialEventLogSnapshot) async { await box.set(snapshot) }
}

/// A cold store whose first load returns a payload the caller chose — the only way to exercise what
/// a *decoded* snapshot does to a store, since `SocialEventLogStore`'s own state is private.
private struct SeededSocialEventLogPersistence: SocialEventLogPersisting {
    let snapshot: SocialEventLogSnapshot
    func load() async -> SocialEventLogSnapshot { snapshot }
    func save(_ snapshot: SocialEventLogSnapshot) async { }
}

private struct SyncFixture {
    let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    func verifiedParticipant(_ id: String, role: SharedRole = .collaborator) -> SocialParticipantIdentity {
        participant(id, role: role, verificationState: .verified)
    }

    func participant(
        _ id: String,
        role: SharedRole = .collaborator,
        verificationState: SocialParticipantVerificationState
    ) -> SocialParticipantIdentity {
        SocialParticipantIdentity(
            participantID: id,
            caip10Account: "eip155:1:0x\(id)",
            displayName: id.capitalized,
            role: role,
            verificationState: verificationState,
            joinedAt: date(0),
            proofID: verificationState == .verified ? "proof.\(id)" : nil
        )
    }

    /// Membership events are author-bound by the projection: a participant record may only be
    /// written by that participant (the `SocialJoinVerificationService` self-join flow) or by the
    /// session owner. This helper self-authors the join, which is the only shape production emits —
    /// a synthetic third-party author would now be rejected as `.mismatchedAuthor`.
    func joined(
        _ identity: SocialParticipantIdentity,
        at seconds: TimeInterval,
        id: UUID = UUID()
    ) -> SocialEventEnvelope {
        event(id: id, author: identity.participantID, at: seconds, event: .participantJoined(identity))
    }

    /// `author` has no default, deliberately.
    ///
    /// It used to default to `"system"` — a synthetic third-party author that no production code
    /// emits (`SocialJoinVerificationService` is the only participant-record emitter and it
    /// self-authors) and that the projection now refuses as `.mismatchedAuthor`. The paired
    /// `author == "system"` ternary below suppressed the account claim to match. Every call site
    /// passes `author:` explicitly today, so both were already unreachable; they are removed rather
    /// than left as a trap, because a future test that omitted the argument would silently get a
    /// shape the projection rejects and would be proving nothing.
    func event(
        id: UUID = UUID(),
        author: String,
        at seconds: TimeInterval,
        event: SocialEvent
    ) -> SocialEventEnvelope {
        SocialEventEnvelope(
            id: id,
            sessionID: sessionID,
            authorParticipantID: author,
            authorCAIP10Account: "eip155:1:0x\(author)",
            createdAt: date(seconds),
            event: event
        )
    }

    /// Reduces `events` as a log this installation wrote itself.
    ///
    /// The suites that use this fixture test *projection semantics* — dedupe, vote replacement,
    /// queue convergence, agent-context bounds, post-end rejection — against the shape a live local
    /// log actually holds. Every event in such a log arrived through `appendLocal` or
    /// `enqueueOutbound`, both of which record local provenance, so minting all of them is what
    /// makes the fixture match production rather than what weakens it.
    ///
    /// This used to mark only the `.verified` joins, which left every *binding* event in these
    /// suites relay-delivered. That shape no longer authors anything: the author binding requires
    /// provenance, because a participant is binding-capable only on `.local` or `.verified` and
    /// both of those are reachable only through a locally-minted record — so an envelope off the
    /// wire naming one of them is an impersonation by construction. Keeping the old default would
    /// have meant these tests either failing or, worse, passing because *nothing* projected.
    ///
    /// Tests whose subject is provenance rather than semantics pass `fromThisInstallation: false`,
    /// or build their own `locallyMintedEventIDs` set directly.
    func reduce(
        _ events: [SocialEventEnvelope],
        fromThisInstallation: Bool = true
    ) -> SocialSessionProjection {
        SocialSessionProjection.reduce(
            events,
            sessionID: sessionID,
            locallyMintedEventIDs: fromThisInstallation ? Set(events.map(\.id)) : []
        )
    }
}
