import Foundation
@testable import AuralisOperators
import Testing

/// Social v1 abuse gate, participant-record leg (companion to ``SocialOwnerAuthorityTests``).
///
/// The relay seals every envelope with one *shared* per-session key, so AES-GCM proves that the
/// sender holds the invite — not which participant authored the event. `authorParticipantID`,
/// `role`, and `verificationState` therefore all arrive self-asserted, and the projection is the
/// only thing standing between an invite holder and the owner-only authority
/// (`sessionEnded` / `participantRemoved`) that ``SocialOwnerAuthorityTests`` pins down.
///
/// Each test below is a takeover attempt that the projection accepted before this suite existed.
struct SocialParticipantAuthorityTests {
    private let sessionID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!

    private func identity(
        _ id: String,
        role: SharedRole,
        state: SocialParticipantVerificationState = .verified
    ) -> SocialParticipantIdentity {
        SocialParticipantIdentity(
            participantID: id,
            caip10Account: "eip155:1:0x\(id)",
            displayName: id,
            role: role,
            verificationState: state
        )
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

    /// Reduces `membership` plus the supplied envelopes, with the membership records marked as ones
    /// *this* installation established.
    ///
    /// Required because the projection's defaults trust nothing: a `.verified` identity delivered
    /// over the relay grants no binding authority, and no participant can bootstrap the owner role.
    /// These suites model the installation that created the session, and for that installation the
    /// real ``SocialEventLogStore`` records exactly these envelopes as locally minted — so supplying
    /// the provenance is what makes the fixture match a live log rather than weakening it.
    ///
    /// - Parameters:
    ///   - extra: Relay-delivered envelopes. This is what keeps every attack below an attack.
    ///   - local: Envelopes this installation authored — the legitimate flows, which really do
    ///     originate here (the owner re-roling a peer, a participant renaming itself).
    private func reduce(
        adding extra: [SocialEventEnvelope] = [],
        fromThisInstallation local: [SocialEventEnvelope] = []
    ) -> SocialSessionProjection {
        // Captured once: `membership` mints fresh envelope ids on every access.
        let base = membership
        return SocialSessionProjection.reduce(
            base + extra + local,
            sessionID: sessionID,
            locallyMintedEventIDs: Set((base + local).map(\.id))
        )
    }

    // MARK: - A relay envelope may introduce a peer, never modify a record we hold

    /// The shape this suite was missing, and it is the one that mattered.
    ///
    /// Every existing foreign-record test uses a *foreign* envelope — author and subject differ —
    /// because that is the shape the previous takeover used. But `describesAuthor` compares two
    /// wire fields against each other, so an attacker satisfies it for free by naming its victim as
    /// **both** author and subject. And because `participantUpdated` requires neither a verified nor
    /// an owner author, that comparison was the only author check such a write ever faced.
    ///
    /// `.distantFuture` is what makes it permanent rather than merely disruptive: `reduce` orders by
    /// the claimed `createdAt`, so the attacker's record is applied after every record the host
    /// holds *and* after every record the host will ever mint. Even the owner-bootstrap exemption
    /// cannot recover the session, because a freshly minted owner record sorts earlier.
    @Test("a relay envelope cannot rewrite the owner's own record by naming the owner as its author")
    func relayEnvelopeCannotRewriteTheOwnersRecordByNamingTheOwnerAsAuthor() {
        let attack = SocialEventEnvelope(
            id: UUID(),
            sessionID: sessionID,
            authorParticipantID: "owner",
            createdAt: .distantFuture,
            event: .participantUpdated(
                SocialParticipantIdentity(
                    participantID: "owner",
                    caip10Account: "eip155:1:0xowner",
                    displayName: "owner",
                    role: .viewer,
                    verificationState: .pending
                )
            )
        )

        let projection = reduce(adding: [attack])

        #expect(projection.rejectionReason(for: attack) == .foreignRecordUpdate)
        // The consequences this prevents, named rather than implied: the owner keeps its role, so
        // `canAuthorBindingEvents` survives and the session still has an owner — without which no
        // `sessionEnded` is derivable and `prune` can never release the graph.
        #expect(projection.participants["owner"]?.role == .owner)
        #expect(projection.participants["owner"]?.canAuthorBindingEvents == true)
    }

    /// The same mechanism against a peer rather than the owner: display names are presentation, but
    /// the rule is the same one, and leaving renames writable leaves the role path writable too.
    @Test("a relay envelope cannot rename a participant record this installation already holds")
    func relayEnvelopeCannotRenameAHeldRecord() {
        let renamed = SocialParticipantIdentity(
            participantID: "collab",
            caip10Account: "eip155:1:0xcollab",
            displayName: "Totally The Owner",
            role: .collaborator,
            verificationState: .pending
        )
        let attack = envelope("collab", .participantUpdated(renamed), at: 10)

        let projection = reduce(adding: [attack])

        #expect(projection.rejectionReason(for: attack) == .foreignRecordUpdate)
        #expect(projection.participants["collab"]?.displayName == "collab")
    }

    /// The rule refuses *modification*, not delivery, so a session you joined still becomes legible
    /// and a duplicate relay delivery stays idempotent. Both halves matter: refusing new peers would
    /// reproduce the failure the `.verified` downgrade exists to avoid.
    @Test("a relay envelope may still introduce a peer this installation has never seen")
    func relayEnvelopeMayStillIntroduceANewPeer() {
        let newcomer = envelope(
            "newcomer",
            .participantJoined(identity("newcomer", role: .collaborator, state: .pending)),
            at: 10
        )

        let projection = reduce(adding: [newcomer])

        #expect(projection.rejectionReason(for: newcomer) == nil)
        #expect(projection.participants["newcomer"]?.role == .collaborator)
    }

    @Test("re-delivering an unchanged record is not treated as a modification")
    func redeliveringAnUnchangedRecordIsAccepted() {
        let identity = identity("newcomer", role: .collaborator, state: .pending)
        let first = envelope("newcomer", .participantJoined(identity), at: 10)
        let duplicate = envelope("newcomer", .participantUpdated(identity), at: 11)

        let projection = reduce(adding: [first, duplicate])

        #expect(projection.rejectionReason(for: duplicate) == nil)
        #expect(projection.participants["newcomer"]?.displayName == "newcomer")
    }

    /// A wire `.verified` is downgraded to `.pending` on arrival, so a *re-delivery* of that same
    /// claim is a record this installation holds being asked to rise to `.verified` — which is
    /// exactly what ``SocialSessionProjection/RejectionReason/unprovenVerifiedIdentity`` refuses.
    ///
    /// Pinned because it is the one place the two rules overlap, and the narrower diagnosis has to
    /// win. The general foreign-record rule is checked *after* it precisely so a takeover attempt is
    /// still reported as the specific thing it is; collapsing them would make every rejection here
    /// read as a generic "modification" and lose that.
    ///
    /// Nothing is lost by the refusal: the peer is already present and legible as `.pending`, and
    /// only its unproven authority claim is withheld.
    @Test("a re-delivered verified claim is still refused as an unproven verification")
    func redeliveredVerifiedPeerIsRefusedAsUnprovenRatherThanAsAModification() {
        let claimed = identity("newcomer", role: .collaborator, state: .verified)
        let first = envelope("newcomer", .participantJoined(claimed), at: 10)
        let duplicate = envelope("newcomer", .participantUpdated(claimed), at: 11)

        let projection = reduce(adding: [first, duplicate])

        #expect(projection.participants["newcomer"]?.verificationState == .pending)
        #expect(projection.rejectionReason(for: duplicate) == .unprovenVerifiedIdentity)
    }

    // MARK: - Removal is terminal

    /// The removal tombstone, which had **no test at all** — disabling the guard left all 178 tests
    /// green.
    ///
    /// It matters because `apply` for `.participantRemoved` does not merely mark the id: it deletes
    /// the record from `participants` *and* clears both provenance tables
    /// (`locallyEstablishedParticipantIDs`, `locallyMintedAccountsByParticipantID`). So every other
    /// guard that could refuse a re-join is disarmed by the removal itself — `foreignRecordUpdate`
    /// sees no held record, `rebindsAccount` sees no binding, and the cross-participant account rule
    /// sees no locally-minted claim on the account. The tombstone is the *only* thing standing
    /// between an owner ejecting a hostile participant and that participant simply publishing a
    /// fresh `participantJoined` and walking back in, under its own account, over the relay.
    @Test("a removed participant cannot rejoin over the relay")
    func removedParticipantCannotRejoinFromTheWire() {
        let removal = envelope("owner", .participantRemoved(participantID: "collab"), at: 10)
        let rejoin = envelope(
            "collab",
            .participantJoined(identity("collab", role: .collaborator, state: .pending)),
            at: 11
        )

        let projection = reduce(adding: [rejoin], fromThisInstallation: [removal])

        #expect(projection.removedParticipantIDs.contains("collab"))
        #expect(projection.rejectionReason(for: rejoin) == .removedParticipant)
        #expect(projection.participants["collab"] == nil, "an ejected participant walked back in")
    }

    /// Removal is terminal in v1 *by design*, not by omission: the tombstone is write-only, so not
    /// even the owner may re-admit someone it removed — re-admission has to be its own
    /// owner-authorized event with its own authority rule, because the obvious reversible shape
    /// (comparing a wire `joinedAt` against the removal) would be decided by an attacker-chosen
    /// timestamp. Pinned so the restriction cannot be relaxed silently in one direction only.
    @Test("not even the owner can re-admit a removed participant")
    func ownerCannotReadmitARemovedParticipant() {
        let removal = envelope("owner", .participantRemoved(participantID: "collab"), at: 10)
        let readmit = envelope(
            "owner",
            .participantJoined(identity("collab", role: .collaborator)),
            at: 11
        )

        let projection = reduce(fromThisInstallation: [removal, readmit])

        #expect(
            projection.rejectionReason(for: readmit, isLocallyMinted: true) == .removedParticipant
        )
        #expect(projection.participants["collab"] == nil)
    }

    // MARK: - One wallet is one party

    /// The write-once account binding approached from the other side. `rebindsAccount` above only
    /// fires on a *change* to a record that already exists, which left a brand-new record's first
    /// claim unchecked — so an invite holder could join under its own participant id while naming
    /// the victim's real wallet as its account. No authority comes with it, but Mission Control
    /// renders the projection, so a genuine checksummed address appears as a session participant
    /// under a name the attacker chose.
    @Test("a new record cannot claim an account another participant already holds")
    func aNewRecordCannotClaimAnotherParticipantsAccount() {
        let impostor = SocialParticipantIdentity(
            participantID: "attacker",
            caip10Account: "eip155:1:0xowner",
            displayName: "Owner",
            role: .collaborator,
            verificationState: .pending
        )
        let attack = envelope("attacker", .participantJoined(impostor), at: 10)

        let projection = reduce(adding: [attack])

        #expect(projection.rejectionReason(for: attack) == .rebindsAccount)
        #expect(projection.participants["attacker"] == nil)
    }

    /// The rule above is anchored to local provenance, and this is why.
    ///
    /// Written unanchored it refuses any record whose account another participant already holds —
    /// and "already holds" is decided by `createdAt`, a wire field. An attacker who backdates can
    /// therefore *pre-claim* a victim's account and have the victim's own genuine record refused:
    /// an impersonation fix traded for a silent denial of visibility, via the exact ordering race
    /// `ownerBootstrapIsOpen` exists to close.
    ///
    /// Both records here arrive over the relay and the attacker's sorts first. The victim must
    /// still project.
    @Test("a backdated account pre-claim cannot block a later genuine record")
    func backdatedAccountPreClaimCannotBlockAGenuineRecord() {
        let contestedAccount = "eip155:1:0xnewcomer"
        let preClaim = SocialEventEnvelope(
            id: UUID(),
            sessionID: sessionID,
            authorParticipantID: "attacker",
            createdAt: .distantPast,
            event: .participantJoined(SocialParticipantIdentity(
                participantID: "attacker", caip10Account: contestedAccount,
                displayName: "Newcomer", role: .collaborator, verificationState: .pending
            ))
        )
        let genuine = envelope(
            "newcomer",
            .participantJoined(SocialParticipantIdentity(
                participantID: "newcomer", caip10Account: contestedAccount,
                displayName: "newcomer", role: .collaborator, verificationState: .pending
            )),
            at: 10
        )

        let projection = reduce(adding: [preClaim, genuine])

        #expect(projection.rejectionReason(for: genuine) == nil)
        #expect(projection.participants["newcomer"]?.caip10Account == contestedAccount)
    }

    /// The fifth hole in this function, and the mirror image of the cross-participant rule above.
    ///
    /// Introducing a participant the projection has never seen is *deliberately* accepted off the
    /// relay — a joined session has to become legible. But the write-once account binding was not
    /// anchored, so a wire-introduced record out-ranked a later locally-minted one. Any invite
    /// holder could pre-claim a participant id with an attacker-chosen account, and because
    /// ordering is by wire-controlled `createdAt`, arriving first is free.
    ///
    /// The damage was permanent and silent. The local mint paths never call `rejectionReason`, so
    /// the device's own verified join was refused at projection time with nothing surfaced: the
    /// record stayed `.pending` under the attacker's account and display name,
    /// `canAuthorBindingEvents` stayed false, and every share, vote, and ritual run that device
    /// authored afterwards was dropped as `.unverifiedAuthor`. Re-joining mints a later envelope
    /// that hits the same guard, so only a full `reset()` recovered.
    @Test("a wire pre-claim cannot refuse this installation's own later record")
    func wirePreClaimCannotRefuseALocallyMintedRecord() {
        let victimID = "eip155:1:0xbob"
        // Arrives first by claiming an earlier moment — free, because `createdAt` is a wire field.
        let preClaim = SocialEventEnvelope(
            id: UUID(),
            sessionID: sessionID,
            authorParticipantID: victimID,
            createdAt: .distantPast,
            event: .participantJoined(SocialParticipantIdentity(
                participantID: victimID,
                caip10Account: "eip155:1:0xdead",
                displayName: "Bob",
                role: .collaborator,
                verificationState: .pending
            ))
        )
        // What `SocialJoinVerificationService` mints after the wallet actually signs.
        let genuine = envelope(
            victimID,
            .participantJoined(SocialParticipantIdentity(
                participantID: victimID,
                caip10Account: victimID,
                displayName: "Bob",
                role: .collaborator,
                verificationState: .verified
            )),
            at: 20
        )

        let projection = reduce(adding: [preClaim], fromThisInstallation: [genuine])

        #expect(projection.rejectionReason(for: genuine, isLocallyMinted: true) == nil)
        #expect(projection.participants[victimID]?.caip10Account == victimID)
        #expect(projection.participants[victimID]?.verificationState == .verified)
        // The whole point: this device can still author binding events as itself.
        #expect(projection.participants[victimID]?.canAuthorBindingEvents == true)
    }

    /// And the anchored rule still does its job where it matters: an account this installation
    /// established itself cannot be claimed by a relay record. That is the case with real
    /// consequence, because the address is one this device knows belongs to someone else, and
    /// Mission Control renders the projection.
    @Test("a locally established account cannot be claimed by a relay record")
    func locallyEstablishedAccountCannotBeClaimedFromTheWire() {
        let attack = envelope(
            "attacker",
            .participantJoined(SocialParticipantIdentity(
                participantID: "attacker", caip10Account: "eip155:1:0xcollab",
                displayName: "collab", role: .collaborator, verificationState: .pending
            )),
            at: 10
        )

        let projection = reduce(adding: [attack])

        #expect(projection.rejectionReason(for: attack) == .rebindsAccount)
        #expect(projection.participants["attacker"] == nil)
    }

    /// The anchoring above is only sound if it is **order-independent**, and that is the half that
    /// was missing.
    ///
    /// The guard asks whether some *other* participant whose record this installation established
    /// already holds the account — but it asks that question of `participants` and
    /// `locallyEstablishedParticipantIDs` *as they stand when the wire record is applied*, and
    /// `reduce` applies envelopes in `createdAt` order, which the wire controls. So the attacker
    /// does not have to defeat the anchor; it only has to sort ahead of the locally-minted record
    /// that would have armed it. `.distantPast` is free.
    ///
    /// The consequence is the exact one this guard exists to prevent: Mission Control renders the
    /// projection, so the victim's real, EIP-55-checksummed address appears as a session
    /// participant under a display name the attacker chose — on the device that *knows* the address
    /// belongs to someone else.
    ///
    /// Identical in every field to `locallyEstablishedAccountCannotBeClaimedFromTheWire` except for
    /// `createdAt`, which is the whole point.
    @Test("a backdated relay record still cannot claim a locally established account")
    func backdatedRelayRecordCannotClaimALocallyEstablishedAccount() {
        let attack = SocialEventEnvelope(
            id: UUID(),
            sessionID: sessionID,
            authorParticipantID: "attacker",
            createdAt: .distantPast,
            event: .participantJoined(SocialParticipantIdentity(
                participantID: "attacker", caip10Account: "eip155:1:0xcollab",
                displayName: "collab", role: .collaborator, verificationState: .pending
            ))
        )

        let projection = reduce(adding: [attack])

        #expect(projection.participants["attacker"] == nil, "a backdated pre-claim took the victim's account")
        #expect(projection.participants["collab"]?.caip10Account == "eip155:1:0xcollab")
    }

    // MARK: - Escalation is refused

    @Test("a collaborator cannot promote itself to owner")
    func collaboratorCannotSelfPromote() {
        let projection = reduce(
            adding: [envelope("collab", .participantUpdated(identity("collab", role: .owner)), at: 10)]
        )
        #expect(projection.participants["collab"]?.role == .collaborator)
    }

    /// The reason self-promotion matters: owner role is what unlocks `sessionEnded`.
    @Test("a self-promoting collaborator still cannot end the session")
    func selfPromotionDoesNotUnlockSessionEnd() {
        let projection = reduce(
            adding: [
                envelope("collab", .participantUpdated(identity("collab", role: .owner)), at: 10),
                envelope("collab", .sessionEnded(endedAt: Date(timeIntervalSince1970: 11)), at: 11)
            ]
        )
        #expect(projection.endedAt == nil)
    }

    @Test("a self-promoting participant still cannot remove the owner")
    func selfPromotionDoesNotUnlockRemoval() {
        let projection = reduce(
            adding: [
                envelope("attacker", .participantUpdated(identity("attacker", role: .owner)), at: 10),
                envelope("attacker", .participantRemoved(participantID: "owner"), at: 11)
            ]
        )
        #expect(projection.participants["attacker"] == nil)
        #expect(projection.participants["owner"]?.role == .owner)
        #expect(projection.removedParticipantIDs.isEmpty)
    }

    @Test("self-promotion to owner is rejected as roleEscalation")
    func selfPromotionReasonIsRoleEscalation() {
        let projection = reduce()
        let attack = envelope("collab", .participantUpdated(identity("collab", role: .owner)), at: 10)
        #expect(projection.rejectionReason(for: attack) == .roleEscalation)
    }

    // MARK: - Participant records are author-bound

    @Test("a collaborator cannot rewrite another participant's record")
    func collaboratorCannotRewriteAnotherParticipant() {
        let projection = reduce(
            adding: [envelope("collab", .participantUpdated(identity("owner", role: .viewer)), at: 10)]
        )
        #expect(projection.participants["owner"]?.role == .owner)
        #expect(projection.participants["owner"]?.canAuthorBindingEvents == true)
    }

    @Test("rewriting another participant's record is rejected as mismatchedAuthor")
    func foreignParticipantWriteReasonIsMismatchedAuthor() {
        let projection = reduce()
        let attack = envelope("collab", .participantUpdated(identity("owner", role: .viewer)), at: 10)
        #expect(projection.rejectionReason(for: attack) == .mismatchedAuthor)
    }

    /// The author-bound rule above was checked against `participantIsOwner(authorParticipantID)`, and
    /// `authorParticipantID` is a plain wire string with nothing signing it — every invite holder can
    /// write the owner's id into it, because AES-GCM under the shared session key proves session-key
    /// possession, not authorship. So the guard asked "is the *named* author the owner", which an
    /// attacker answers for free, instead of "did this installation mint the write".
    ///
    /// Demotion, not just impersonation, is the damage: `.viewer` clears `canVote` and therefore
    /// `canAuthorBindingEvents`, so the genuine owner can no longer end the session, remove the
    /// attacker, share, or resolve approvals — and with no owner left, no `sessionEnded` is ever
    /// derivable and the session graph can never be pruned.
    @Test("a relay envelope spoofing the owner's author id cannot write a foreign record")
    func spoofedOwnerAuthorCannotWriteForeignRecord() {
        let projection = reduce()
        let seizure = envelope(
            "owner",                                            // spoofed: anyone can type this
            .participantJoined(identity("attacker", role: .owner, state: .pending)),
            at: 10
        )

        #expect(projection.rejectionReason(for: seizure) == .mismatchedAuthor)
    }

    /// The seizure end to end. Envelope 1 installs the attacker as a second owner under the spoofed
    /// author id; envelope 2 then uses that freshly-minted ownership to rewrite the real owner's own
    /// record down to `.viewer`. Both must be refused, and the owner must come out unchanged.
    @Test("a spoofed owner author cannot seize ownership and demote the real owner")
    func spoofedOwnerAuthorCannotDemoteTheRealOwner() {
        let demoted = SocialParticipantIdentity(
            participantID: "owner",
            caip10Account: "eip155:1:0xowner",                  // matches, so `rebindsAccount` is silent
            displayName: "owner",
            role: .viewer,
            verificationState: .pending
        )
        let projection = reduce(
            adding: [
                envelope("owner", .participantJoined(identity("attacker", role: .owner, state: .pending)), at: 10),
                envelope("attacker", .participantUpdated(demoted), at: 11)
            ]
        )

        #expect(projection.participants["attacker"] == nil, "the spoofed author id installed an owner")
        #expect(projection.participants["owner"]?.role == .owner)
        #expect(projection.participants["owner"]?.canAuthorBindingEvents == true)
    }

    /// The authority the demotion would have stripped, end to end: once the real owner is a `.viewer`
    /// it cannot end its own session, and an unendable session is also an unprunable one.
    @Test("a spoofed owner author cannot stop the real owner ending the session")
    func spoofedOwnerAuthorCannotLockOutTheRealOwner() {
        let demoted = SocialParticipantIdentity(
            participantID: "owner",
            caip10Account: "eip155:1:0xowner",
            displayName: "owner",
            role: .viewer,
            verificationState: .pending
        )
        let projection = reduce(
            adding: [
                envelope("owner", .participantJoined(identity("attacker", role: .owner, state: .pending)), at: 10),
                envelope("attacker", .participantUpdated(demoted), at: 11)
            ],
            fromThisInstallation: [
                envelope("owner", .sessionEnded(endedAt: Date(timeIntervalSince1970: 12)), at: 12)
            ]
        )

        #expect(projection.endedAt == Date(timeIntervalSince1970: 12))
    }

    /// A *foreign* record naming `role: .owner` is now policed by the escalation rule too, not only
    /// by the author-bound rule. The two are independent readings of the same envelope and the
    /// escalation one used to be gated on `describesAuthor`, so it never saw a foreign write at all.
    /// Owner delegation — the one legitimate foreign owner-record write — must keep working, and
    /// `ownerCanDelegateOwnership` below is the other half of this pair.
    @Test("a foreign record claiming owner is refused unless the author really is the owner")
    func foreignOwnerRecordIsPoliced() {
        let projection = reduce()
        let fromCollaborator = envelope("collab", .participantUpdated(identity("attacker", role: .owner)), at: 10)
        let fromSpoofedOwner = envelope("owner", .participantUpdated(identity("attacker", role: .owner)), at: 11)

        #expect(projection.rejectionReason(for: fromCollaborator) == .mismatchedAuthor)
        #expect(projection.rejectionReason(for: fromSpoofedOwner) == .mismatchedAuthor)
        // Locally minted *and* authored by a real owner: delegation, and the only accepted shape.
        #expect(projection.rejectionReason(for: fromSpoofedOwner, isLocallyMinted: true) == nil)
    }

    @Test("a collaborator cannot mark another participant rejected to silence it")
    func collaboratorCannotRevokeAnotherParticipantsVerification() {
        let projection = reduce(
            adding: [
                envelope("collab", .participantUpdated(identity("owner", role: .owner, state: .rejected)), at: 10)
            ]
        )
        #expect(projection.participants["owner"]?.verificationState == .verified)
    }

    // MARK: - Wire-claimed verification

    /// `.verified` means "a wallet signed this session's join challenge" — an event that happened on
    /// someone else's device. It is minted locally by the app's join verifier and then *broadcast*,
    /// so it arrives on the wire like everything else, and `canAuthorBindingEvents` granted
    /// authority to it. Only `.local` was provenance-checked, leaving the stronger claim unchecked:
    /// any invite holder could assert `.verified` and pick up the authority to vote, propose queue
    /// mutations, and share attributed records, with no wallet proof at all.
    @Test("a relay-delivered verified identity is downgraded and cannot author binding events")
    func unprovenVerifiedWireIdentityIsDowngraded() {
        let projection = reduce(
            adding: [envelope("stranger", .participantJoined(identity("stranger", role: .collaborator)), at: 10)]
        )

        // Recorded, so a joined session stays legible — but unproven, so it carries no authority.
        #expect(projection.participants["stranger"]?.verificationState == .pending)
        #expect(projection.participants["stranger"]?.canAuthorBindingEvents == false)
    }

    /// The authority the downgrade withholds, end to end: a share is a binding event, so an
    /// unproven peer's attempt to attribute a receipt to the session is refused.
    @Test("a downgraded peer cannot author a binding event")
    func downgradedPeerCannotShare() {
        let receiptID = UUID()
        let projection = reduce(
            adding: [
                envelope("stranger", .participantJoined(identity("stranger", role: .collaborator)), at: 10),
                envelope("stranger", .receiptShared(receiptID), at: 11)
            ]
        )

        #expect(projection.sharedReceiptIDs.isEmpty)
    }

    /// Claiming `.owner` buys nothing either: owner-only events require `canAuthorBindingEvents` as
    /// well as the role, so a downgraded record cannot exercise the authority it claims.
    @Test("a downgraded peer claiming owner still cannot end the session")
    func downgradedOwnerClaimCannotEndSession() {
        let projection = reduce(
            adding: [
                envelope("stranger", .participantJoined(identity("stranger", role: .owner)), at: 10),
                envelope("stranger", .sessionEnded(endedAt: Date(timeIntervalSince1970: 11)), at: 11)
            ]
        )

        #expect(projection.endedAt == nil)
    }

    /// Raising a record this projection *already holds* as unproven has no legitimate reading —
    /// nothing is lost by refusing it, and accepting it would hand over binding authority on an
    /// assertion. This is also the case that becomes a failed-proof rejection once proofs travel.
    @Test("re-asserting verification over the wire is rejected as unprovenVerifiedIdentity")
    func wireVerificationEscalationIsRejected() {
        let projection = reduce(
            adding: [
                envelope("stranger", .participantJoined(identity("stranger", role: .collaborator)), at: 10)
            ]
        )
        let escalation = envelope(
            "stranger",
            .participantUpdated(identity("stranger", role: .collaborator)),
            at: 11
        )

        #expect(projection.rejectionReason(for: escalation) == .unprovenVerifiedIdentity)
    }

    // MARK: - Account binding is write-once

    /// Participant records are author-bound, which made the *account* field rebindable: `apply`
    /// replaces the whole identity, so naming a victim's `caip10Account` in a self-update
    /// re-attributed everything the attacker went on to share to the victim's wallet. The
    /// `mismatchedAccount` guard could not see it — that compares the envelope's claimed author
    /// account against the record, and this rewrites the record.
    @Test("a participant cannot rebind its own record to another account")
    func selfUpdateCannotRebindAccount() {
        let rebound = SocialParticipantIdentity(
            participantID: "collab",
            caip10Account: "eip155:1:0xVICTIM",
            displayName: "collab",
            role: .collaborator,
            verificationState: .verified
        )

        let projection = reduce(adding: [envelope("collab", .participantUpdated(rebound), at: 10)])

        #expect(projection.participants["collab"]?.caip10Account == "eip155:1:0xcollab")
    }

    @Test("rebinding an account is rejected as rebindsAccount")
    func rebindReasonIsNamed() {
        let projection = reduce()
        let rebound = SocialParticipantIdentity(
            participantID: "collab",
            caip10Account: "eip155:1:0xVICTIM",
            displayName: "collab",
            role: .collaborator,
            verificationState: .verified
        )

        #expect(projection.rejectionReason(for: envelope("collab", .participantUpdated(rebound), at: 10)) == .rebindsAccount)
    }

    /// Not even the owner, because the binding is what the wallet proof established and the owner
    /// never held that proof. Changing an account is a leave-and-rejoin.
    @Test("the owner cannot move a participant onto a different account either")
    func ownerCannotRebindAParticipantsAccount() {
        let rebound = SocialParticipantIdentity(
            participantID: "collab",
            caip10Account: "eip155:1:0xVICTIM",
            displayName: "collab",
            role: .collaborator,
            verificationState: .verified
        )

        let projection = reduce(adding: [envelope("owner", .participantUpdated(rebound), at: 10)])

        #expect(projection.participants["collab"]?.caip10Account == "eip155:1:0xcollab")
    }

    /// EIP-55 capitalization is a checksum, not an identity, so a respelling of the *same* address
    /// must not read as a rebind — otherwise a legitimate rename from a differently-cased client
    /// would be refused.
    @Test("an EIP-55 respelling of the same account is not a rebind")
    func checksumRespellingIsNotARebind() {
        let address = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
        let original = SocialParticipantIdentity(
            participantID: "wallet",
            caip10Account: "eip155:1:\(address.lowercased())",
            displayName: "wallet",
            role: .collaborator,
            verificationState: .verified
        )
        let respelled = SocialParticipantIdentity(
            participantID: "wallet",
            caip10Account: "eip155:1:\(address)",
            displayName: "Renamed",
            role: .collaborator,
            verificationState: .verified
        )
        let projection = reduce(
            fromThisInstallation: [
                envelope("wallet", .participantJoined(original), at: 10),
                envelope("wallet", .participantUpdated(respelled), at: 11)
            ]
        )

        #expect(projection.participants["wallet"]?.displayName == "Renamed")
    }

    // MARK: - Legitimate flows still work

    /// Session bootstrap: the creator records its own owner identity before any owner exists.
    @Test("the session creator can record its own owner identity")
    func ownerBootstrapIsAllowed() {
        let projection = reduce()
        #expect(projection.participants["owner"]?.role == .owner)
    }

    /// Owner authority: admitting and managing *other* participants stays an owner capability.
    @Test("the owner can admit and re-role another participant")
    func ownerCanManageOthers() {
        let projection = reduce(
            fromThisInstallation: [envelope("owner", .participantUpdated(identity("collab", role: .viewer)), at: 10)]
        )
        #expect(projection.participants["collab"]?.role == .viewer)
    }

    /// The owner may hand the owner role to someone else; that is delegation, not escalation.
    @Test("the owner can promote another participant to owner")
    func ownerCanDelegateOwnership() {
        let projection = reduce(
            fromThisInstallation: [envelope("owner", .participantUpdated(identity("collab", role: .owner)), at: 10)]
        )
        #expect(projection.participants["collab"]?.role == .owner)
    }

    /// The `SocialJoinVerificationService` flow: a joiner self-reports its own collaborator identity
    /// after a local wallet-ownership check. This must keep working.
    @Test("a joiner can record its own non-owner identity")
    func joinerSelfRecordIsAllowed() {
        // Locally established, because that is where this flow actually happens: the joiner's *own*
        // installation runs the wallet-ownership check and mints the record. The relay copy that
        // reaches everyone else is what `unprovenVerifiedWireIdentityCannotAuthorBindingEvents`
        // covers — until the proof travels with it, a peer cannot be taken at its word.
        let projection = reduce(
            fromThisInstallation: [
                envelope("joiner", .participantJoined(identity("joiner", role: .collaborator)), at: 10)
            ]
        )

        #expect(projection.participants["joiner"]?.role == .collaborator)
        #expect(projection.participants["joiner"]?.canAuthorBindingEvents == true)
    }

    @Test("a participant may still update its own display name")
    func selfUpdateIsAllowed() {
        var renamed = identity("collab", role: .collaborator)
        renamed = SocialParticipantIdentity(
            participantID: renamed.participantID,
            caip10Account: renamed.caip10Account,
            displayName: "Renamed",
            role: renamed.role,
            verificationState: renamed.verificationState
        )
        let projection = reduce(
            fromThisInstallation: [envelope("collab", .participantUpdated(renamed), at: 10)]
        )
        #expect(projection.participants["collab"]?.displayName == "Renamed")
    }
}
