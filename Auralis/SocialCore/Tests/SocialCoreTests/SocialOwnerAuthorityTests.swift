import Foundation
@testable import SocialCore
import Testing

/// Social v1 abuse gate (session-takeover + hostile-participant): only the session owner may end the
/// session or remove a participant, even though any verified collaborator may vote and share.
struct SocialOwnerAuthorityTests {
    private let sessionID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!

    private func identity(
        _ id: String,
        role: SharedRole,
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

    /// The shape production actually mints for a wallet-verified participant: one CAIP-10 value is
    /// the participant id **and** the account.
    ///
    /// `SocialInviteExchangeModel` passes a single `participantID` as both the invite's
    /// `inviterParticipantID` and the joiner's `caip10Account`, and
    /// `SocialJoinVerificationService` then sets `participantID` and `caip10Account` to the account
    /// it just proved. The anchored-bootstrap tests below have to use this shape, because that
    /// self-description is what the anchor check relies on — see `ownerBootstrapIsOpen`.
    private static let anchoredOwner = "eip155:1:0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed"

    /// The same address with its EIP-55 checksum capitalization. Byte-different, canonically equal —
    /// which is what makes it the probe for the two comparison modes in `claimsAnchoredAccount`.
    private static let checksummedAnchoredOwner = "eip155:1:0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"

    private func selfDescribingOwner(
        state: SocialParticipantVerificationState = .verified
    ) -> SocialParticipantIdentity {
        identity(Self.anchoredOwner, role: .owner, state: state, account: Self.anchoredOwner)
    }

    private func envelope(
        _ author: String,
        _ event: SocialEvent,
        at seconds: TimeInterval
    ) -> SocialEventEnvelope {
        SocialEventEnvelope(
            id: UUID(),
            sessionID: sessionID,
            authorParticipantID: author,
            createdAt: Date(timeIntervalSince1970: seconds),
            event: event
        )
    }

    /// Owner + verified collaborator both present.
    private var membership: [SocialEventEnvelope] {
        [
            envelope("owner", .sessionCreated(title: "Trip", correlationID: "corr"), at: 0),
            envelope("owner", .participantJoined(identity("owner", role: .owner)), at: 1),
            envelope("owner", .participantJoined(identity("collab", role: .collaborator)), at: 2)
        ]
    }

    /// Reduces `membership` plus `extra`, with the membership records marked as ones this
    /// installation established.
    ///
    /// The projection's defaults trust nothing — a relay-delivered `.verified` identity grants no
    /// binding authority and no participant can bootstrap the owner role — so a fixture built from
    /// a bare envelope array projects no members at all. This suite models the installation that
    /// *created* the session, and for that installation the real ``SocialEventLogStore`` records
    /// exactly these envelopes as locally minted.
    ///
    /// `fromThisInstallation` has **no default, deliberately.** It used to be implicitly `false`,
    /// which meant every "the owner can …" test below was feeding a *relay-delivered* envelope
    /// authored as the owner and asserting it was accepted — pinning an impersonation as required
    /// behaviour. Two tests in this one file then contradicted each other:
    /// `ownerCanEndSession` asserted that envelope was accepted while
    /// `anchoredRelayOwnerCannotEndSession` asserted the byte-identical envelope was refused, and
    /// the only difference was whether the *victim* happened to host the session.
    ///
    /// So each test now has to say which question it is asking. `true` asks an authority question
    /// (who may do this?); `false` asks a provenance question (may the wire claim to be them?).
    /// Both rules exist and each is pinned separately, because an attack that defeats either one is
    /// a takeover.
    private func reduce(
        adding extra: [SocialEventEnvelope],
        fromThisInstallation: Bool
    ) -> SocialSessionProjection {
        // Captured once: `membership` mints fresh envelope ids on every access.
        let base = membership
        let minted = fromThisInstallation ? base + extra : base
        return SocialSessionProjection.reduce(
            base + extra,
            sessionID: sessionID,
            locallyMintedEventIDs: Set(minted.map(\.id))
        )
    }

    @Test("a verified collaborator cannot end the session")
    func collaboratorCannotEndSession() {
        let ended = envelope("collab", .sessionEnded(endedAt: Date(timeIntervalSince1970: 10)), at: 10)
        let projection = reduce(adding: [ended], fromThisInstallation: true)
        #expect(projection.endedAt == nil)
        // Named, so the refusal is on owner authority rather than incidentally on provenance.
        #expect(projection.rejectionReason(for: ended, isLocallyMinted: true) == .ownerRequired)
    }

    @Test("the owner can end the session")
    func ownerCanEndSession() {
        let projection = reduce(
            adding: [envelope("owner", .sessionEnded(endedAt: Date(timeIntervalSince1970: 10)), at: 10)],
            fromThisInstallation: true
        )
        #expect(projection.endedAt != nil)
    }

    /// The provenance half of `ownerCanEndSession`, and the reason that test has to be explicit.
    ///
    /// The envelope is byte-identical to the one the owner legitimately authors; only its origin
    /// differs. `authorParticipantID` is an unsigned wire string and the relay seals every envelope
    /// with one *shared* session key, so an invite holder can type the host's id. Accepting it ended
    /// the host's session on the host's own device — and with `endedAt: .distantPast` the whole
    /// graph became immediately prunable, erasing every shared receipt and artifact reference.
    @Test("a relay envelope cannot end the session by naming the owner as its author")
    func relayEnvelopeCannotImpersonateTheOwnerToEndTheSession() {
        let spoofed = envelope("owner", .sessionEnded(endedAt: .distantPast), at: 10)
        let projection = reduce(adding: [spoofed], fromThisInstallation: false)
        #expect(projection.endedAt == nil)
        #expect(projection.rejectionReason(for: spoofed) == .impersonatedAuthor)
    }

    @Test("a verified collaborator cannot remove another participant")
    func collaboratorCannotRemoveParticipant() {
        let removal = envelope("collab", .participantRemoved(participantID: "owner"), at: 10)
        let projection = reduce(adding: [removal], fromThisInstallation: true)
        #expect(projection.participants["owner"] != nil)
        #expect(projection.removedParticipantIDs.isEmpty)
        #expect(projection.rejectionReason(for: removal, isLocallyMinted: true) == .ownerRequired)
    }

    @Test("the owner can remove a participant")
    func ownerCanRemoveParticipant() {
        let projection = reduce(
            adding: [envelope("owner", .participantRemoved(participantID: "collab"), at: 10)],
            fromThisInstallation: true
        )
        #expect(projection.participants["collab"] == nil)
        #expect(projection.removedParticipantIDs.contains("collab"))
    }

    /// The same impersonation against removal. Worse than ending the session, because a removal also
    /// closes the owner-bootstrap exemption permanently, so the ejection cannot be undone.
    @Test("a relay envelope cannot remove a participant by naming the owner as its author")
    func relayEnvelopeCannotImpersonateTheOwnerToRemoveAParticipant() {
        let spoofed = envelope("owner", .participantRemoved(participantID: "collab"), at: 10)
        let projection = reduce(adding: [spoofed], fromThisInstallation: false)
        #expect(projection.participants["collab"] != nil)
        #expect(projection.removedParticipantIDs.isEmpty)
        #expect(projection.rejectionReason(for: spoofed) == .impersonatedAuthor)
    }

    /// The owner-bootstrap race. `reduce` orders envelopes by their *claimed* `createdAt`, which is
    /// a wire field, and the exemption that lets a session creator record its own owner identity was
    /// open until an owner existed. So an attacker backdating `role: .owner` sorted ahead of the
    /// genuine owner's record, took the exemption, and then had the real owner's own claim refused
    /// as `.roleEscalation` — a complete takeover from one envelope with a chosen timestamp.
    ///
    /// The exemption is now anchored to provenance (or to an invite's inviter) instead of to arrival
    /// order, so claiming an earlier moment buys nothing.
    @Test("a backdated owner claim cannot win the bootstrap race")
    func backdatedOwnerClaimCannotTakeOverTheSession() {
        let base = membership
        let backdated = SocialEventEnvelope(
            id: UUID(),
            sessionID: sessionID,
            authorParticipantID: "attacker",
            createdAt: .distantPast,
            event: .participantJoined(identity("attacker", role: .owner, state: .pending))
        )

        let projection = SocialSessionProjection.reduce(
            [backdated] + base,
            sessionID: sessionID,
            locallyMintedEventIDs: Set(base.map(\.id))
        )

        #expect(projection.participants["attacker"] == nil)
        #expect(projection.participants["owner"]?.role == .owner)
        #expect(projection.rejectionReason(for: backdated) == .roleEscalation)
    }

    /// The flip side: a session this installation *joined* has no locally-minted owner record, so
    /// the anchor comes from the invite it scanned out-of-band. Without it a joined session could
    /// never project an owner, and its `sessionEnded` would be refused forever.
    @Test("an invite's inviter can still bootstrap the owner of a joined session")
    func invitedOwnerStillBootstraps() {
        var snapshot = SocialEventLogSnapshot(envelopes: [
            envelope(Self.anchoredOwner, .participantJoined(selfDescribingOwner()), at: 1)
        ])
        snapshot.invites = [
            SocialInvite(
                sessionID: sessionID,
                relayTopic: "topic",
                encryptedSessionKey: "key",
                inviterParticipantID: Self.anchoredOwner,
                expiresAt: Date(timeIntervalSince1970: 10_000),
                nonce: "nonce"
            )
        ]

        let projection = snapshot.projection(sessionID: sessionID)

        #expect(projection.participants[Self.anchoredOwner]?.role == .owner)
    }

    /// The anchor names *who* may own the session; on its own it says nothing about who wrote the
    /// envelope claiming it. `inviterParticipantID` is printed in the invite that **every** holder
    /// has, and `authorParticipantID` is an unsigned wire string — so one invite holder could type
    /// the inviter's id and take the exemption on every *other* holder's device.
    ///
    /// Fails against the pre-fix code, which asked only `ownerBootstrapAnchors.contains(author)`.
    ///
    /// The surviving requirement is that an anchored wire bootstrap be **self-describing**: the
    /// record is about the anchored party and carries that party's own account. The attacker can
    /// still name the inviter — it just can no longer point the inviter's record at its own wallet,
    /// which is the whole value of the attack.
    @Test("an invite holder cannot bootstrap the owner onto an account of its choosing")
    func anchoredBootstrapMustDescribeTheAnchoredParty() {
        var snapshot = SocialEventLogSnapshot(envelopes: [])
        snapshot.invites = [
            SocialInvite(
                sessionID: sessionID,
                relayTopic: "topic",
                encryptedSessionKey: "key",
                inviterParticipantID: Self.anchoredOwner,
                expiresAt: Date(timeIntervalSince1970: 10_000),
                nonce: "nonce"
            )
        ]
        // Authored as the inviter — free, it is in the invite — but binding the inviter's id to the
        // attacker's wallet, under a display name the attacker chose.
        let spoofed = envelope(
            Self.anchoredOwner,
            .participantJoined(
                identity(
                    Self.anchoredOwner,
                    role: .owner,
                    state: .pending,
                    account: "eip155:1:0xmallory"
                )
            ),
            at: 1
        )
        snapshot.envelopes = [spoofed]

        let projection = snapshot.projection(sessionID: sessionID)

        #expect(projection.rejectionReason(for: spoofed) == .roleEscalation)
        #expect(projection.participants[Self.anchoredOwner] == nil)
    }

    /// The other half of the anchor, and the one that turns a takeover into a permanent wedge.
    ///
    /// The held-record guards protect a record the projection "already holds" — but *already* is
    /// decided by `reduce`'s sort on wire-controlled `createdAt`. So an invite holder could
    /// pre-claim the owner's participant id with a backdated, harmless-looking `.viewer`/`.pending`
    /// record, and the owner's genuine record would then be refused as `.foreignRecordUpdate`. The
    /// device ends up with no owner at all: `sessionEnded` is refused as `.ownerRequired`, no
    /// `endedAt` is ever derivable, and `prune` can never release the graph.
    ///
    /// Fails against the pre-fix code, where the genuine record was refused.
    @Test("a pre-claimed record cannot lock out the anchored owner's genuine one")
    func preClaimCannotLockOutTheAnchoredOwner() {
        var snapshot = SocialEventLogSnapshot(envelopes: [])
        snapshot.invites = [
            SocialInvite(
                sessionID: sessionID,
                relayTopic: "topic",
                encryptedSessionKey: "key",
                inviterParticipantID: Self.anchoredOwner,
                expiresAt: Date(timeIntervalSince1970: 10_000),
                nonce: "nonce"
            )
        ]
        // Backdated so it sorts first, and deliberately bland so no other guard fires.
        let preClaim = envelope(
            Self.anchoredOwner,
            .participantJoined(
                identity(
                    Self.anchoredOwner,
                    role: .viewer,
                    state: .pending,
                    account: Self.anchoredOwner
                )
            ),
            at: -10_000
        )
        let genuine = envelope(
            Self.anchoredOwner,
            .participantJoined(selfDescribingOwner()),
            at: 1
        )
        snapshot.envelopes = [preClaim, genuine]

        let projection = snapshot.projection(sessionID: sessionID)

        #expect(projection.rejectionReason(for: genuine) == nil)
        #expect(projection.participants[Self.anchoredOwner]?.role == .owner)
    }

    /// The exemption must not run in the other direction.
    ///
    /// All three anchor conditions are public — the inviter's id is printed in the invite every
    /// holder has, and production makes the participant id *be* the CAIP-10 account — so a peer can
    /// satisfy `isAnchoredSelfDescribing` by typing the owner's id into three fields. The only
    /// thing stopping that from being useful is that the exemption establishes ownership and never
    /// surrenders it: a `.viewer` overwrite of a held `.owner` record clears `hasOwner`, after which
    /// `sessionEnded` is refused as `.ownerRequired`, no `endedAt` is derivable, and `prune` never
    /// releases the graph — the identical permanent wedge the exemption exists to prevent, reached
    /// from the opposite side.
    ///
    /// Fails against the pre-fix exemption, which accepted the demotion.
    @Test("the anchored exemption cannot be used to demote a held owner record")
    func anchoredExemptionCannotDemoteAHeldOwnerRecord() {
        var snapshot = SocialEventLogSnapshot(envelopes: [])
        snapshot.invites = [
            SocialInvite(
                sessionID: sessionID,
                relayTopic: "topic",
                encryptedSessionKey: "key",
                inviterParticipantID: Self.anchoredOwner,
                expiresAt: Date(timeIntervalSince1970: 10_000),
                nonce: "nonce"
            )
        ]
        let genuine = envelope(
            Self.anchoredOwner,
            .participantJoined(selfDescribingOwner()),
            at: 1
        )
        // Author and subject both the owner, the owner's real account, a later `createdAt` — every
        // field an invite holder can supply for itself.
        let demotion = envelope(
            Self.anchoredOwner,
            .participantUpdated(
                identity(
                    Self.anchoredOwner,
                    role: .viewer,
                    state: .pending,
                    account: Self.anchoredOwner
                )
            ),
            at: 2
        )
        snapshot.envelopes = [genuine]

        let projection = snapshot.projection(sessionID: sessionID)

        #expect(projection.participants[Self.anchoredOwner]?.role == .owner)
        #expect(projection.rejectionReason(for: demotion) == .foreignRecordUpdate)
    }

    /// Once ownership is held the exemption must stop granting anything.
    ///
    /// Restricting it to `role == .owner` closes the demotion, but on its own it leaves a standing
    /// licence to rewrite the owner's record: the anchor conditions are public and a later
    /// `createdAt` is free, so an invite holder could rename the owner under their real,
    /// checksum-valid account for as long as the session lives. That is the impersonation primitive
    /// on a wallet-adjacent surface, not a cosmetic one.
    ///
    /// Fails against the `role == .owner`-only form of the exemption.
    @Test("the anchored exemption cannot rename a held owner record")
    func anchoredExemptionCannotRenameAHeldOwnerRecord() {
        var snapshot = SocialEventLogSnapshot(envelopes: [])
        snapshot.invites = [
            SocialInvite(
                sessionID: sessionID,
                relayTopic: "topic",
                encryptedSessionKey: "key",
                inviterParticipantID: Self.anchoredOwner,
                expiresAt: Date(timeIntervalSince1970: 10_000),
                nonce: "nonce"
            )
        ]
        let genuine = envelope(
            Self.anchoredOwner,
            .participantJoined(selfDescribingOwner()),
            at: 1
        )
        // Ownership and account left intact so every other guard stays silent — only the name moves.
        let rename = envelope(
            Self.anchoredOwner,
            .participantUpdated(
                SocialParticipantIdentity(
                    participantID: Self.anchoredOwner,
                    caip10Account: Self.anchoredOwner,
                    displayName: "Auralis Support",
                    role: .owner,
                    verificationState: .pending
                )
            ),
            at: 2
        )
        snapshot.envelopes = [genuine]

        let projection = snapshot.projection(sessionID: sessionID)

        #expect(projection.rejectionReason(for: rename) == .foreignRecordUpdate)
        // And the owner's own record is still idempotent on re-delivery.
        #expect(projection.rejectionReason(for: genuine) == nil)
    }

    /// The *other* direction of the rule above, pinned as a known residual rather than left for a
    /// later round to rediscover as new.
    ///
    /// `anchoredExemptionCannotRenameAHeldOwnerRecord` shows that once the genuine owner record is
    /// held, a rename is refused. This shows the mirror: if the **attacker's** record lands first,
    /// the genuine one differs from it only in `displayName`, fails the same guard, and is refused
    /// as `.foreignRecordUpdate` permanently — so an attacker-chosen name stays pinned to the
    /// owner's real, checksum-valid account.
    ///
    /// It is residual rather than fixable in the projection because `isAnchoredSelfDescribing` is
    /// forgeable by design — all three of its conditions are public — so the two records are
    /// indistinguishable here and every tie-break is symmetric between them. First-established-wins
    /// costs the attacker a one-time race; the arrival-ordered alternative is last-writer-wins,
    /// which hands it a permanent, re-winnable rename and is strictly worse. The fix is the
    /// transported join proof, which makes the genuine record the only one that can satisfy the
    /// anchor at all.
    ///
    /// This test will need inverting when that lands — which is the point of writing it down.
    @Test("a pre-claim pins the owner's display name, and the genuine record is refused (known residual)")
    func preClaimPinsTheOwnerDisplayNameAsAKnownResidual() {
        var snapshot = SocialEventLogSnapshot(envelopes: [])
        snapshot.invites = [
            SocialInvite(
                sessionID: sessionID,
                relayTopic: "topic",
                encryptedSessionKey: "key",
                inviterParticipantID: Self.anchoredOwner,
                expiresAt: Date(timeIntervalSince1970: 10_000),
                nonce: "nonce"
            )
        ]
        // The attacker names the owner's id and the owner's own account — everything an invite
        // holder can read off the invite — and picks the display name.
        let preClaim = envelope(
            Self.anchoredOwner,
            .participantJoined(
                SocialParticipantIdentity(
                    participantID: Self.anchoredOwner,
                    caip10Account: Self.anchoredOwner,
                    displayName: "Auralis Support",
                    role: .owner,
                    verificationState: .pending
                )
            ),
            at: 1
        )
        snapshot.envelopes = [preClaim]

        let projection = snapshot.projection(sessionID: sessionID)
        #expect(projection.participants[Self.anchoredOwner]?.displayName == "Auralis Support")

        // The genuine record is refused, and *which* guard refuses it depends only on the trust
        // state it carries — both are the same residual.
        //
        // A wallet-verified record trips the narrower `unprovenVerifiedIdentity`, which is checked
        // first on purpose so a takeover attempt keeps its specific diagnosis.
        let verified = envelope(Self.anchoredOwner, .participantJoined(selfDescribingOwner()), at: 2)
        #expect(projection.rejectionReason(for: verified) == .unprovenVerifiedIdentity)

        // Stripped to the minimum — differing from the pre-claim in the display name alone — it is
        // the general held-record guard that refuses it.
        let renameOnly = envelope(
            Self.anchoredOwner,
            .participantJoined(selfDescribingOwner(state: .pending)),
            at: 3
        )
        #expect(projection.rejectionReason(for: renameOnly) == .foreignRecordUpdate)

        // What the residual is *not*: the record carries no authority. It is `.pending`, so it
        // cannot author anything binding, and the account binding is the owner's genuine one.
        let held = projection.participants[Self.anchoredOwner]
        #expect(held?.verificationState == .pending)
        #expect(held?.canAuthorBindingEvents == false)
        #expect(held?.caip10Account == Self.anchoredOwner)
        // And it is diagnosable rather than silent — `.foreignRecordUpdate` is reported to
        // `recordRejectedEvent`, so the conflict is visible in relay diagnostics.
    }

    /// The pre-claim that actually locks the owner out is the one that is *not* bland.
    ///
    /// `preClaimCannotLockOutTheAnchoredOwner` builds its pre-claim with the owner's own account so
    /// that "no other guard fires" — but an attacker has no reason to be that polite. Naming the
    /// owner's participant id while claiming the attacker's own wallet poisons the account binding,
    /// and `rebindsAccount` fires several guards *ahead* of the held-record exemption, so the
    /// genuine owner record was still refused and the session still ended up permanently ownerless.
    ///
    /// Fails against the pre-fix code with `.rebindsAccount`.
    @Test("a pre-claim naming a foreign account cannot lock out the anchored owner")
    func nonBlandPreClaimCannotLockOutTheAnchoredOwner() {
        var snapshot = SocialEventLogSnapshot(envelopes: [])
        snapshot.invites = [
            SocialInvite(
                sessionID: sessionID,
                relayTopic: "topic",
                encryptedSessionKey: "key",
                inviterParticipantID: Self.anchoredOwner,
                expiresAt: Date(timeIntervalSince1970: 10_000),
                nonce: "nonce"
            )
        ]
        let preClaim = envelope(
            Self.anchoredOwner,
            .participantJoined(
                identity(
                    Self.anchoredOwner,
                    role: .collaborator,
                    state: .pending,
                    account: "eip155:1:0xmallory"
                )
            ),
            at: -10_000
        )
        let genuine = envelope(
            Self.anchoredOwner,
            .participantJoined(selfDescribingOwner()),
            at: 1
        )
        snapshot.envelopes = [preClaim, genuine]

        let projection = snapshot.projection(sessionID: sessionID)

        #expect(projection.rejectionReason(for: genuine) == nil)
        #expect(projection.participants[Self.anchoredOwner]?.role == .owner)
        // The binding is repaired too — the attacker's wallet no longer holds the owner's id.
        #expect(projection.participants[Self.anchoredOwner]?.caip10Account == Self.anchoredOwner)
    }

    /// The same lock-out reached through the *author* guard, which returns before the `switch` runs.
    ///
    /// `mismatchedAccount` compares the envelope's `authorCAIP10Account` against the account already
    /// recorded for that participant. A pre-claim that poisons the record therefore refuses every
    /// envelope the anchored party subsequently authors *for any event type*, and it does so ahead
    /// of every held-record rule — so it shadowed the exemption entirely.
    ///
    /// Fails against the pre-fix code with `.mismatchedAccount`.
    @Test("a poisoned account binding cannot refuse the anchored party's own authored envelopes")
    func poisonedBindingCannotRefuseTheAnchoredAuthor() {
        var snapshot = SocialEventLogSnapshot(envelopes: [])
        snapshot.invites = [
            SocialInvite(
                sessionID: sessionID,
                relayTopic: "topic",
                encryptedSessionKey: "key",
                inviterParticipantID: Self.anchoredOwner,
                expiresAt: Date(timeIntervalSince1970: 10_000),
                nonce: "nonce"
            )
        ]
        let preClaim = envelope(
            Self.anchoredOwner,
            .participantJoined(
                identity(
                    Self.anchoredOwner,
                    role: .collaborator,
                    state: .pending,
                    account: "eip155:1:0xmallory"
                )
            ),
            at: -10_000
        )
        // The anchored party naming its own account, which is what production mints.
        let genuine = SocialEventEnvelope(
            id: UUID(),
            sessionID: sessionID,
            authorParticipantID: Self.anchoredOwner,
            authorCAIP10Account: Self.anchoredOwner,
            createdAt: Date(timeIntervalSince1970: 1),
            event: .participantJoined(selfDescribingOwner())
        )
        snapshot.envelopes = [preClaim, genuine]

        let projection = snapshot.projection(sessionID: sessionID)

        #expect(projection.rejectionReason(for: genuine) == nil)
        #expect(projection.participants[Self.anchoredOwner]?.role == .owner)
    }

    /// The boundary the whole anchored exemption rests on, and it had **no test** — removing the
    /// guard left all 178 tests green.
    ///
    /// `relayMayOverwriteHeldRecord` opens with
    /// `guard !locallyEstablishedParticipantIDs.contains(identity.participantID)`, and that line is
    /// the entire content of its safety claim: *"a record this installation established is still
    /// absolute — nothing off the wire may touch it."* Everything else in the exemption is
    /// deliberately forgeable — the function's own documentation says all three anchor conditions
    /// are public, so a peer satisfies `isAnchoredSelfDescribing` by typing the anchored party's id
    /// into three fields.
    ///
    /// The host device is exactly where the two preconditions meet: it saved the invite it issued,
    /// so its own id is an anchor, *and* it minted its own participant record, so its own id is
    /// locally established. Without the guard, a relay envelope that names the anchored party as
    /// author and subject reaches `known.role != .owner`, is granted the exemption, and overwrites
    /// the host's own record — replacing a trusted `.local` state with a wire-asserted `.pending`
    /// one. That clears `canAuthorBindingEvents` on the host's own session: its `sessionEnded` is
    /// then refused as `.unverifiedAuthor`, no `endedAt` is derivable, and `prune` can never release
    /// the graph. The permanent wedge, reached on the one device that should be immune to it.
    @Test("the anchored exemption cannot overwrite a record this installation established")
    func anchoredExemptionCannotOverwriteALocallyEstablishedRecord() {
        var snapshot = SocialEventLogSnapshot(envelopes: [])
        snapshot.invites = [
            SocialInvite(
                sessionID: sessionID,
                relayTopic: "topic",
                encryptedSessionKey: "key",
                inviterParticipantID: Self.anchoredOwner,
                expiresAt: Date(timeIntervalSince1970: 10_000),
                nonce: "nonce"
            )
        ]
        // This installation minted the anchored party's record itself, so it is locally established.
        // Held as a non-owner, which is what makes `known.role != .owner` the open door.
        let established = envelope(
            Self.anchoredOwner,
            .participantJoined(
                identity(
                    Self.anchoredOwner,
                    role: .collaborator,
                    state: .local,
                    account: Self.anchoredOwner
                )
            ),
            at: 1
        )
        snapshot.envelopes = [established]
        snapshot.locallyMintedEventIDs = [established.id]

        // Author and subject both the anchored party, its real account, a later `createdAt` — every
        // field an invite holder can read off the invite.
        let overwrite = envelope(
            Self.anchoredOwner,
            .participantUpdated(
                SocialParticipantIdentity(
                    participantID: Self.anchoredOwner,
                    caip10Account: Self.anchoredOwner,
                    displayName: "Auralis Support",
                    role: .owner,
                    verificationState: .pending
                )
            ),
            at: 2
        )
        snapshot.envelopes.append(overwrite)

        let projection = snapshot.projection(sessionID: sessionID)

        #expect(projection.rejectionReason(for: overwrite) == .foreignRecordUpdate)
        // The record this installation established is untouched in every field the overwrite moved.
        let held = projection.participants[Self.anchoredOwner]
        #expect(held?.verificationState == .local)
        #expect(held?.displayName == Self.anchoredOwner)
        #expect(held?.role == .collaborator)
        // And the authority that would have been stripped survives, which is the consequence.
        #expect(held?.canAuthorBindingEvents == true)
    }

    /// The same boundary on the *author* axis, and the same gap: removing the
    /// `!locallyEstablishedParticipantIDs.contains(author)` clause from
    /// `relayMayAssertAnchoredAccount` left all 178 tests green.
    ///
    /// That clause is what stops the anchored exemption from letting the wire re-assert an account
    /// binding this installation established. It is narrower in effect than the record-side guard
    /// above — `relayMayOverwriteHeldRecord` catches the participant-record writes that get past it,
    /// so the outcome stays a refusal either way — but *which* refusal is itself a contract here:
    /// these reasons exist so a takeover attempt is individually diagnosable, and a guard whose
    /// removal silently re-routes the diagnosis is a guard that will be removed.
    @Test("the anchored exemption cannot re-assert a locally established account binding")
    func anchoredExemptionCannotReassertALocallyEstablishedAccount() {
        var snapshot = SocialEventLogSnapshot(envelopes: [])
        snapshot.invites = [
            SocialInvite(
                sessionID: sessionID,
                relayTopic: "topic",
                encryptedSessionKey: "key",
                inviterParticipantID: Self.anchoredOwner,
                expiresAt: Date(timeIntervalSince1970: 10_000),
                nonce: "nonce"
            )
        ]
        // This installation bound the anchored id to a *different* account and established it.
        let established = envelope(
            Self.anchoredOwner,
            .participantJoined(
                identity(
                    Self.anchoredOwner,
                    role: .collaborator,
                    state: .local,
                    account: "eip155:1:0xfb6916095ca1df60bb79ce92ce3ea74c37c5d359"
                )
            ),
            at: 1
        )
        snapshot.envelopes = [established]
        snapshot.locallyMintedEventIDs = [established.id]

        // A relay envelope authored as the anchored party, naming the anchor as its own account —
        // the exact shape the exemption admits when the binding is *not* locally established.
        let reassert = SocialEventEnvelope(
            id: UUID(),
            sessionID: sessionID,
            authorParticipantID: Self.anchoredOwner,
            authorCAIP10Account: Self.anchoredOwner,
            createdAt: Date(timeIntervalSince1970: 2),
            event: .participantUpdated(
                identity(
                    Self.anchoredOwner,
                    role: .collaborator,
                    state: .pending,
                    account: Self.anchoredOwner
                )
            )
        )

        let projection = snapshot.projection(sessionID: sessionID)

        #expect(projection.rejectionReason(for: reassert) == .mismatchedAccount)
        #expect(
            projection.participants[Self.anchoredOwner]?.caip10Account
                == "eip155:1:0xfb6916095ca1df60bb79ce92ce3ea74c37c5d359"
        )
    }

    /// The exemption is narrow: it is the *anchored* party's own claim that outranks a pre-claim,
    /// not any wire peer's. An ordinary invite holder satisfies none of the three conditions, so
    /// wire-peer-versus-wire-peer rewriting stays closed.
    @Test("an ordinary peer still cannot rewrite a record the projection holds")
    func anUnanchoredPeerStillCannotRewriteAHeldRecord() {
        var snapshot = SocialEventLogSnapshot(envelopes: [])
        snapshot.invites = [
            SocialInvite(
                sessionID: sessionID,
                relayTopic: "topic",
                encryptedSessionKey: "key",
                inviterParticipantID: Self.anchoredOwner,
                expiresAt: Date(timeIntervalSince1970: 10_000),
                nonce: "nonce"
            )
        ]
        let peer = "eip155:1:0xpeer"
        // One value, reused — `identity(_:role:state:account:)` defaults `joinedAt` to `.now`, so
        // two calls do not produce the same record and a re-delivery test built from two calls
        // would be testing modification, not idempotence.
        let peerRecord = identity(peer, role: .collaborator, state: .pending, account: peer)
        let introduced = envelope(peer, .participantJoined(peerRecord), at: 1)
        let rewrite = envelope(peer, .participantJoined(peerRecord), at: 2)
        snapshot.envelopes = [introduced]
        let projection = snapshot.projection(sessionID: sessionID)

        // Same stored value is idempotent; a record that would *change* what is stored is not.
        #expect(projection.rejectionReason(for: rewrite) == nil)
        let renamed = envelope(
            peer,
            .participantJoined(
                SocialParticipantIdentity(
                    participantID: peer,
                    caip10Account: peer,
                    displayName: "Renamed by an attacker",
                    role: .collaborator,
                    verificationState: .pending
                )
            ),
            at: 3
        )
        #expect(projection.rejectionReason(for: renamed) == .foreignRecordUpdate)
    }

    /// What the anchor does *not* buy, pinned so it cannot be relaxed by accident.
    ///
    /// The invite anchor lets a joined session's owner hold the `.owner` role, but the record still
    /// arrives over the relay, so its `.verified` claim is downgraded to `.pending` and
    /// `canAuthorBindingEvents` stays false. `sessionEnded` is refused as `.unverifiedAuthor` — not
    /// `.ownerRequired` — and that is the correct outcome: accepting it would mean accepting every
    /// other binding event from an unproven peer as well.
    ///
    /// The consequence is a known limitation rather than a second bug to fix here: a session someone
    /// else hosted never derives an `endedAt` on this device, so `SocialEventLogStore.prune` can
    /// never release its envelopes. Closing that needs the transported join proof described on
    /// ``SocialSessionProjection/downgradedVerification(of:isLocallyMinted:)``, or a retention axis
    /// that does not require a terminal state.
    @Test("an anchored but relay-delivered owner still cannot end the session")
    func anchoredRelayOwnerCannotEndSession() {
        var snapshot = SocialEventLogSnapshot(envelopes: [
            envelope(Self.anchoredOwner, .participantJoined(selfDescribingOwner()), at: 1)
        ])
        snapshot.invites = [
            SocialInvite(
                sessionID: sessionID,
                relayTopic: "topic",
                encryptedSessionKey: "key",
                inviterParticipantID: Self.anchoredOwner,
                expiresAt: Date(timeIntervalSince1970: 10_000),
                nonce: "nonce"
            )
        ]
        let ended = envelope(
            Self.anchoredOwner,
            .sessionEnded(endedAt: Date(timeIntervalSince1970: 10)),
            at: 10
        )
        snapshot.envelopes.append(ended)

        let projection = snapshot.projection(sessionID: sessionID)

        #expect(projection.participants[Self.anchoredOwner]?.role == .owner)
        #expect(projection.participants[Self.anchoredOwner]?.verificationState == .pending)
        #expect(projection.rejectionReason(for: ended) == .unverifiedAuthor)
        #expect(projection.endedAt == nil)
    }

    /// The one-wallet-one-party rule, asked on the axis a *joined* session actually has.
    ///
    /// `claimsAnotherLocallyMintedAccount` anchors that rule to local provenance, which is the right
    /// anchor for a session this installation hosted and **no anchor at all** for one it joined —
    /// nothing here minted a record for anyone, so the table it consults is empty. That left the one
    /// party the device *does* have out-of-band knowledge about completely unprotected: any invite
    /// holder could publish a `participantJoined` under its own fresh participant id while naming
    /// the owner's real, checksum-valid account and a display name of its choosing. Every other
    /// guard stays silent — it names itself as both author and subject, modifies no held record,
    /// escalates no role — so the record was accepted, and Mission Control rendered the owner's
    /// genuine address twice, once as the owner and once as "Auralis Support". That is the exact
    /// impersonation primitive the locally-minted rule exists to refuse, on a wallet-adjacent
    /// surface, reached on the device that knows from a QR code handed over in person whose account
    /// that is.
    ///
    /// Fails against the pre-fix code, where `rejectionReason` returned `nil`.
    @Test("a wire peer cannot claim the anchored owner's account under its own id")
    func wirePeerCannotClaimTheAnchoredOwnersAccount() {
        var snapshot = SocialEventLogSnapshot(envelopes: [])
        snapshot.invites = [
            SocialInvite(
                sessionID: sessionID,
                relayTopic: "topic",
                encryptedSessionKey: "key",
                inviterParticipantID: Self.anchoredOwner,
                expiresAt: Date(timeIntervalSince1970: 10_000),
                nonce: "nonce"
            )
        ]
        let genuine = envelope(
            Self.anchoredOwner,
            .participantJoined(selfDescribingOwner()),
            at: 1
        )
        // A fresh participant id the attacker owns, carrying the *owner's* account.
        let impostor = envelope(
            "mallory",
            .participantJoined(
                SocialParticipantIdentity(
                    participantID: "mallory",
                    caip10Account: Self.anchoredOwner,
                    displayName: "Auralis Support",
                    role: .collaborator,
                    verificationState: .pending
                )
            ),
            at: 2
        )
        snapshot.envelopes = [genuine, impostor]

        let projection = snapshot.projection(sessionID: sessionID)

        #expect(projection.rejectionReason(for: impostor) == .rebindsAccount)
        #expect(projection.participants["mallory"] == nil)

        // (1) The *account* side must be canonical. An EIP-55 respelling is the same address, so
        // the same refusal — otherwise the rule is one `lowercased()` away from decorative. This is
        // the assertion that fails if `SocialAccountIdentity.matches` is replaced by `==`.
        let respelledAccount = envelope(
            "mallory-two",
            .participantJoined(
                SocialParticipantIdentity(
                    participantID: "mallory-two",
                    caip10Account: Self.checksummedAnchoredOwner,
                    displayName: "Auralis Support",
                    role: .collaborator,
                    verificationState: .pending
                )
            ),
            at: 3
        )
        #expect(projection.rejectionReason(for: respelledAccount) == .rebindsAccount)

        // (2) The *exemption* side must stay byte-literal, and this is the assertion that pins it.
        //
        // Here the impostor respells the participant id as well, so under a canonical exemption —
        // including the per-anchor form `matches(anchor, account) && !matches(anchor, id)` — this
        // record reads as "the anchored party describing itself" and is let through. It must not
        // be, because `participants` is keyed on the **literal** id: the respelling lands in a
        // *different* dictionary entry, so admitting it leaves the anchored account held twice —
        // once by the genuine owner and once under a display name the attacker chose. That is the
        // impersonation primitive this rule exists to refuse, not a recovery path for the owner.
        //
        // Nothing is stranded by refusing it. Every other anchor site is byte-literal for the same
        // slot-identity reason, so a genuinely respelled owner record fails `ownerBootstrapIsOpen`
        // and is refused as `.roleEscalation` anyway — canonicalizing here changes the reported
        // reason and nothing else. See `claimsAnchoredAccount`.
        let respelledIdentity = envelope(
            Self.checksummedAnchoredOwner,
            .participantJoined(
                SocialParticipantIdentity(
                    participantID: Self.checksummedAnchoredOwner,
                    caip10Account: Self.checksummedAnchoredOwner,
                    displayName: "Auralis Support",
                    role: .collaborator,
                    verificationState: .pending
                )
            ),
            at: 4
        )
        #expect(
            projection.rejectionReason(for: respelledIdentity) == .rebindsAccount,
            "a checksummed respelling took the anchored party's exemption under a different key"
        )

        // The genuine owner is untouched and still the only holder of that account — which is the
        // property all three refusals above exist to preserve.
        #expect(projection.participants[Self.anchoredOwner]?.displayName == Self.anchoredOwner)
        #expect(projection.participants.count == 1)
    }

    /// And the respelled form really is the *same address*, so (2) above is refusing a record that
    /// canonical matching would otherwise admit — not one that fails for an unrelated reason.
    @Test("the respelled anchor fixture is the same account as the anchor")
    func checksummedAnchorIsTheSameAccount() {
        #expect(SocialAccountIdentity.matches(Self.anchoredOwner, Self.checksummedAnchoredOwner))
        #expect(Self.anchoredOwner != Self.checksummedAnchoredOwner)
    }

    /// The direction that must stay open, pinned alongside the rule above.
    ///
    /// Every account rule in this file has had to be one-directional, because an unscoped "someone
    /// already holds this account" test is decided by `reduce`'s sort on wire-controlled
    /// `createdAt` — so a backdated pre-claim would trade the impersonation for a permanent denial
    /// of the owner's own record, which is strictly worse. The anchor set is fixed before replay and
    /// the anchored party's own record names the anchor as its `participantID`, so the impostor is
    /// refused whatever order it arrives in and the genuine record is never the one refused.
    @Test("a backdated account impostor cannot lock out the anchored owner")
    func backdatedAccountImpostorCannotLockOutTheAnchoredOwner() {
        var snapshot = SocialEventLogSnapshot(envelopes: [])
        snapshot.invites = [
            SocialInvite(
                sessionID: sessionID,
                relayTopic: "topic",
                encryptedSessionKey: "key",
                inviterParticipantID: Self.anchoredOwner,
                expiresAt: Date(timeIntervalSince1970: 10_000),
                nonce: "nonce"
            )
        ]
        let impostor = SocialEventEnvelope(
            id: UUID(),
            sessionID: sessionID,
            authorParticipantID: "mallory",
            createdAt: .distantPast,
            event: .participantJoined(
                SocialParticipantIdentity(
                    participantID: "mallory",
                    caip10Account: Self.anchoredOwner,
                    displayName: "Auralis Support",
                    role: .collaborator,
                    verificationState: .pending
                )
            )
        )
        let genuine = envelope(
            Self.anchoredOwner,
            .participantJoined(selfDescribingOwner()),
            at: 1
        )
        snapshot.envelopes = [impostor, genuine]

        let projection = snapshot.projection(sessionID: sessionID)

        #expect(projection.rejectionReason(for: genuine) == nil)
        #expect(projection.participants[Self.anchoredOwner]?.role == .owner)
        #expect(projection.participants["mallory"] == nil)
    }

    /// And the rule must not refuse an ordinary peer joining with its *own* account, which is the
    /// whole point of a session staying legible after you join it.
    @Test("the anchored-account rule leaves an ordinary peer's own account alone")
    func anchoredAccountRuleLeavesOrdinaryPeersAlone() {
        var snapshot = SocialEventLogSnapshot(envelopes: [])
        snapshot.invites = [
            SocialInvite(
                sessionID: sessionID,
                relayTopic: "topic",
                encryptedSessionKey: "key",
                inviterParticipantID: Self.anchoredOwner,
                expiresAt: Date(timeIntervalSince1970: 10_000),
                nonce: "nonce"
            )
        ]
        let peer = "eip155:1:0xfb6916095ca1df60bb79ce92ce3ea74c37c5d359"
        let joined = envelope(
            peer,
            .participantJoined(
                SocialParticipantIdentity(
                    participantID: peer,
                    caip10Account: peer,
                    displayName: "Peer",
                    role: .collaborator,
                    verificationState: .pending
                )
            ),
            at: 1
        )
        snapshot.envelopes = [joined]

        let projection = snapshot.projection(sessionID: sessionID)

        #expect(projection.rejectionReason(for: joined) == nil)
        #expect(projection.participants[peer]?.caip10Account == peer)
    }

    /// And the anchor is scoped to the session it was issued for: an invite to one session must not
    /// let its inviter bootstrap ownership of another.
    @Test("an invite to one session does not anchor ownership of a different one")
    func inviteAnchorIsScopedToItsSession() {
        var snapshot = SocialEventLogSnapshot(envelopes: membership)
        snapshot.invites = [
            SocialInvite(
                sessionID: UUID(),
                relayTopic: "topic",
                encryptedSessionKey: "key",
                inviterParticipantID: "owner",
                expiresAt: Date(timeIntervalSince1970: 10_000),
                nonce: "nonce"
            )
        ]

        let projection = snapshot.projection(sessionID: sessionID)

        #expect(projection.participants["owner"] == nil)
    }
}
