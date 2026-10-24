import AuralisPrimaryModels
import Foundation

/// Canonicalization for the CAIP-10 account strings carried on participants and envelopes.
///
/// CAIP-10 is `namespace:reference:account`. The namespace and reference are case-insensitive, and
/// for `eip155` the account is an Ethereum address whose capitalization carries an EIP-55 checksum
/// rather than identity — `0xabc…` and `0xAbC…` are the same account. Comparing the raw strings
/// would therefore let a checksummed and an unchecksummed spelling of one address read as two
/// different people, so matching goes through the repo's single EIP-55 implementation
/// (`AuralisEthereumAddress`) instead of a second, local comparison.
enum SocialAccountIdentity {
    /// The comparable form of `account`, or the trimmed, lowercased original when it is not a
    /// recognizable CAIP-10 eip155 account (other namespaces are compared verbatim, case-folded).
    static func canonical(_ account: String) -> String {
        let trimmed = account.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return trimmed.lowercased() }
        let namespace = parts[0].lowercased()
        let reference = parts[1].lowercased()
        // Only eip155 accounts go through address normalization; anything else keeps its account
        // segment verbatim (case-folded) because we cannot assume its equality rules.
        guard namespace == "eip155",
              let normalized = AuralisEthereumAddress.normalized(String(parts[2])) else {
            return "\(namespace):\(reference):\(parts[2].lowercased())"
        }
        return "\(namespace):\(reference):\(normalized)"
    }

    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        canonical(lhs) == canonical(rhs)
    }
}

/// Wallet-proven participant state for Social v1. The app/relay layer owns signature verification;
/// `SocialCore` only records whether an identity is allowed to author binding shared-state events.
public enum SocialParticipantVerificationState: String, Equatable, Sendable, Codable {
    /// Trusted only inside this installation. Local identities must never be transported as wallet proof.
    case local
    case pending
    case verified
    case rejected
}

/// A participant identity that can survive relay sync without depending on wallet or UI frameworks.
public struct SocialParticipantIdentity: Identifiable, Equatable, Sendable, Codable {
    public var id: String { participantID }

    public let participantID: String
    public let caip10Account: String
    public let displayName: String
    public let role: SharedRole
    public let verificationState: SocialParticipantVerificationState
    public let joinedAt: Date
    public let proofID: String?

    public init(
        participantID: String,
        caip10Account: String,
        displayName: String,
        role: SharedRole,
        verificationState: SocialParticipantVerificationState,
        joinedAt: Date = .now,
        proofID: String? = nil
    ) {
        // Bounded like ``SharedAgentContext``'s fields, and for the same reason: these arrive from
        // the relay and are stored forever. The limits are far above any real value — a CAIP-10
        // account tops out near 115 characters — so nothing legitimate is truncated, but a peer
        // cannot spend megabytes of a joiner's disk per participant record either.
        self.participantID = String(participantID.prefix(Self.identifierLimit))
        self.caip10Account = String(caip10Account.prefix(Self.identifierLimit))
        self.displayName = String(displayName.prefix(Self.displayNameLimit))
        self.role = role
        self.verificationState = verificationState
        self.joinedAt = joinedAt
        self.proofID = proofID.map { String($0.prefix(Self.identifierLimit)) }
    }

    static let identifierLimit = 160
    static let displayNameLimit = 120

    public var canAuthorBindingEvents: Bool {
        (verificationState == .local || verificationState == .verified) && role.canVote
    }

    /// The same record, re-run through ``init`` so its clamps apply.
    ///
    /// Needed because this type's `Codable` conformance is **synthesized**: a decoded value assigns
    /// the stored properties directly and never calls `init`, so every bound above is bypassed on
    /// exactly the path that matters — the relay. Applied once at the storage boundary in
    /// ``SocialEventLogStore/appendInbound(_:topic:receivedAt:)``.
    var clampedForStorage: SocialParticipantIdentity {
        SocialParticipantIdentity(
            participantID: participantID,
            caip10Account: caip10Account,
            displayName: displayName,
            role: role,
            verificationState: verificationState,
            joinedAt: joinedAt,
            proofID: proofID
        )
    }

    /// Whether this record is `author` describing itself: the record is *about* that party and
    /// carries that party's own account.
    ///
    /// One definition, consulted from two places that must agree about what the anchored party's
    /// own record looks like — ``SocialSessionProjection``'s owner-bootstrap exemption, which
    /// decides whether such a record may be *accepted* off the relay, and the storage ceiling's
    /// protected-row selection, which decides whether it may be *evicted*. They disagreed once: the
    /// ceiling protected the earliest row naming the anchored party, which is a weaker condition
    /// than the projection's, so a row the projection would never read as the owner's record held
    /// the slot meant for the one it would.
    ///
    /// Not a proof of authorship on its own — every field is public — which is why it is only ever
    /// combined with the anchor; see ``SocialEvent/grantsSelfDescribedOwnership(author:)``.
    func describesSelf(author: String) -> Bool {
        participantID == author && SocialAccountIdentity.matches(caip10Account, author)
    }
}

/// The portable invite payload. The app layer is responsible for encoding this into QR/share formats.
public struct SocialInvite: Identifiable, Equatable, Sendable, Codable {
    public var id: UUID { sessionID }

    public let version: Int
    public let sessionID: UUID
    public let relayTopic: String
    public let encryptedSessionKey: String
    public let inviterParticipantID: String
    public let expiresAt: Date
    public let nonce: String

    public init(
        version: Int = 1,
        sessionID: UUID,
        relayTopic: String,
        encryptedSessionKey: String,
        inviterParticipantID: String,
        expiresAt: Date,
        nonce: String
    ) {
        self.version = version
        self.sessionID = sessionID
        // Bounded like every other type that crosses a trust boundary here. An invite is scanned
        // out-of-band from a QR code, so its fields are supplied by whoever printed the code — this
        // is wire data that simply travels by camera instead of by relay — and `saveInvite` makes it
        // durable, copying `inviterParticipantID` into `ownerAnchorsBySessionID`, which outlives the
        // invite itself.
        //
        // `inviterParticipantID` is the one with a correctness argument rather than only a size one,
        // and it is the argument already written on `SocialEvent.clampedForStorage`: the anchor check
        // `ownerBootstrapAnchors.contains(author)` compares this field against
        // `SocialEventEnvelope.authorParticipantID`, which **is** clamped to `identifierLimit` at the
        // storage boundary. Clamping one side of an equality comparison and not the other is how a
        // value comes to be stored as two different strings; here it would leave an anchor no author
        // id can ever match, so owner bootstrap never opens and the joined session is permanently
        // ownerless. A real CAIP-10 account tops out near 115 characters, so nothing legitimate is
        // truncated — the limit exists to make the two sides agree.
        //
        // `encryptedSessionKey` is deliberately **not** clamped: it is opaque ciphertext whose length
        // belongs to the key-wrapping scheme, not to this package, and truncating it would silently
        // destroy the session key rather than bound anything. It is the one field where a wrong
        // guess is worse than no guess.
        self.relayTopic = String(relayTopic.prefix(SocialParticipantIdentity.identifierLimit))
        self.encryptedSessionKey = encryptedSessionKey
        self.inviterParticipantID = String(
            inviterParticipantID.prefix(SocialParticipantIdentity.identifierLimit)
        )
        self.expiresAt = expiresAt
        self.nonce = String(nonce.prefix(SocialParticipantIdentity.identifierLimit))
    }

    private enum CodingKeys: String, CodingKey {
        case version, sessionID, relayTopic, encryptedSessionKey, inviterParticipantID
        case expiresAt, nonce
    }

    /// Decodes through ``init(version:sessionID:relayTopic:encryptedSessionKey:inviterParticipantID:expiresAt:nonce:)``
    /// so the clamps above run on the decode path too.
    ///
    /// Synthesized `Codable` assigns the stored properties directly, which would bypass them on
    /// exactly the route an invite actually arrives by — decoded from a scanned QR payload. Every
    /// key stays required, as the synthesized conformance had it: an invite missing a field is not a
    /// forward-compatible older invite, it is an unusable one, and failing the decode is how the
    /// scanner reports that.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            version: try container.decode(Int.self, forKey: .version),
            sessionID: try container.decode(UUID.self, forKey: .sessionID),
            relayTopic: try container.decode(String.self, forKey: .relayTopic),
            encryptedSessionKey: try container.decode(String.self, forKey: .encryptedSessionKey),
            inviterParticipantID: try container.decode(String.self, forKey: .inviterParticipantID),
            expiresAt: try container.decode(Date.self, forKey: .expiresAt),
            nonce: try container.decode(String.self, forKey: .nonce)
        )
    }

    public func isExpired(now: Date = .now) -> Bool {
        expiresAt <= now
    }
}

public struct SocialApprovalDraft: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public let prompt: String
    public let requiredApprovals: Int

    public init(id: UUID = UUID(), prompt: String, requiredApprovals: Int) {
        self.id = id
        self.prompt = prompt
        self.requiredApprovals = max(1, requiredApprovals)
    }
}

public struct SocialApprovalVote: Equatable, Sendable, Codable {
    public let participantID: String
    public let approved: Bool
    public let castAt: Date

    public init(participantID: String, approved: Bool, castAt: Date = .now) {
        self.participantID = participantID
        self.approved = approved
        self.castAt = castAt
    }
}

public struct SocialApprovalState: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public let prompt: String
    public let requiredApprovals: Int
    public private(set) var votes: [SocialApprovalVote]
    public private(set) var explicitResolution: ApprovalResolution?

    public init(
        id: UUID,
        prompt: String,
        requiredApprovals: Int,
        votes: [SocialApprovalVote] = [],
        explicitResolution: ApprovalResolution? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.requiredApprovals = max(1, requiredApprovals)
        // One vote per participant, exactly as ``record(_:)`` maintains it, applied here so the
        // invariant also holds for a value built from a decoded or caller-supplied array. Latest
        // wins, matching `record`.
        var seen: Set<String> = []
        self.votes = votes.reversed().filter { seen.insert($0.participantID).inserted }.reversed()
        self.explicitResolution = explicitResolution
    }

    private enum CodingKeys: String, CodingKey {
        case id, prompt, requiredApprovals, votes, explicitResolution
    }

    /// Decodes through ``init(id:prompt:requiredApprovals:votes:explicitResolution:)`` so its bounds
    /// run on the decode path too.
    ///
    /// Synthesized `Codable` assigns the stored properties directly, so both invariants this type
    /// relies on were bypassed by any decoded value — and both decide ``resolution``, which is the
    /// multi-party sign-off primitive itself. `requiredApprovals: 0` makes an approval with **zero
    /// votes** read as `.approved` (`0 >= 0`), and a duplicated vote from one participant counts
    /// twice toward the threshold, so a 2-of-2 resolves on one person's say-so.
    ///
    /// ``SocialSessionProjection`` is `public` and `Codable` and carries these, so this is the
    /// decode boundary for them.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            prompt: try container.decode(String.self, forKey: .prompt),
            requiredApprovals: try container.decode(Int.self, forKey: .requiredApprovals),
            votes: try container.decodeIfPresent([SocialApprovalVote].self, forKey: .votes) ?? [],
            explicitResolution: try container.decodeIfPresent(
                ApprovalResolution.self,
                forKey: .explicitResolution
            )
        )
    }

    public mutating func record(_ vote: SocialApprovalVote) {
        votes.removeAll { $0.participantID == vote.participantID }
        votes.append(vote)
    }

    public mutating func resolve(_ resolution: ApprovalResolution) {
        explicitResolution = resolution
    }

    public var resolution: ApprovalResolution {
        // A cast objection is sticky and outranks even an owner's explicit resolution. `SharedSession`
        // documents the conservative default — "a single objection blocks" — and an owner override
        // that could turn a recorded "no" into `.approved` would quietly erase it. An owner may still
        // resolve an unopposed approval either way, which is the cancellation case the field is for.
        if votes.contains(where: { !$0.approved }) { return .rejected }
        if let explicitResolution { return explicitResolution }
        if votes.filter(\.approved).count >= requiredApprovals { return .approved }
        return .pending
    }
}

public struct SocialQueueProposal: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public let mediaItemID: String
    public let title: String
    public let proposedByParticipantID: String
    public let proposedAt: Date

    public init(
        id: UUID = UUID(),
        mediaItemID: String,
        title: String,
        proposedByParticipantID: String,
        proposedAt: Date = .now
    ) {
        self.id = id
        self.mediaItemID = mediaItemID
        self.title = title
        self.proposedByParticipantID = proposedByParticipantID
        self.proposedAt = proposedAt
    }
}

public struct SocialQueueVote: Equatable, Sendable, Codable {
    public let proposalID: UUID
    public let participantID: String
    public let approved: Bool
    public let castAt: Date

    public init(proposalID: UUID, participantID: String, approved: Bool, castAt: Date = .now) {
        self.proposalID = proposalID
        self.participantID = participantID
        self.approved = approved
        self.castAt = castAt
    }
}

public struct SocialQueueItem: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public let mediaItemID: String
    public let title: String
    public let acceptedProposalID: UUID?
    public let acceptedAt: Date

    public init(
        id: UUID = UUID(),
        mediaItemID: String,
        title: String,
        acceptedProposalID: UUID? = nil,
        acceptedAt: Date = .now
    ) {
        self.id = id
        self.mediaItemID = mediaItemID
        self.title = title
        self.acceptedProposalID = acceptedProposalID
        self.acceptedAt = acceptedAt
    }
}

public enum SocialQueueMutation: Equatable, Sendable, Codable {
    case acceptProposal(proposalID: UUID, item: SocialQueueItem)
    case removeItem(itemID: UUID)
    case reorder(itemID: UUID, destinationIndex: Int)
}

public struct SocialQueueSnapshot: Equatable, Sendable, Codable {
    public let items: [SocialQueueItem]
    public let publishedAt: Date

    public init(items: [SocialQueueItem], publishedAt: Date = .now) {
        self.items = items
        self.publishedAt = publishedAt
    }
}

public enum SocialRitualRunStatus: String, Equatable, Sendable, Codable {
    case started
    case completed
    case partiallyCompleted
    case failed
    case skipped
    case skippedOffline
}

public struct SocialRitualRun: Identifiable, Equatable, Sendable, Codable {
    public var id: String { ritualID }

    public let ritualID: String
    public let status: SocialRitualRunStatus
    public let artifactIDs: [UUID]
    public let receiptIDs: [UUID]

    public init(
        ritualID: String,
        status: SocialRitualRunStatus,
        artifactIDs: [UUID] = [],
        receiptIDs: [UUID] = []
    ) {
        self.ritualID = ritualID
        self.status = status
        self.artifactIDs = artifactIDs
        self.receiptIDs = receiptIDs
    }
}

/// Versioned shared-session event payload. Unknown future payloads can be preserved by callers as
/// `.unsupported` so replay remains tolerant across mixed app versions.
/// A privacy-bounded reference to agent context shared with a session. It deliberately carries a
/// human-readable summary and durable artifact references—not raw prompts, credentials, model-provider
/// internals, copied text, or arbitrary serialized memory.
public struct SharedAgentContext: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public let title: String
    public let summary: String
    public let provenance: String
    public let dataClassNames: [String]
    public let artifactIDs: [UUID]
    public let createdAt: Date
    public let expiresAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        provenance: String,
        dataClassNames: [String] = [],
        artifactIDs: [UUID] = [],
        createdAt: Date = .now,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.title = String(title.prefix(120))
        self.summary = String(summary.prefix(2_000))
        self.provenance = String(provenance.prefix(240))
        self.dataClassNames = Array(dataClassNames.prefix(32)).map { String($0.prefix(80)) }
        self.artifactIDs = Array(artifactIDs.prefix(100))
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }

    public func isExpired(at date: Date) -> Bool {
        expiresAt.map { $0 <= date } ?? false
    }
}

public enum SocialEvent: Equatable, Sendable, Codable {
    case sessionCreated(title: String, correlationID: String)
    case participantJoined(SocialParticipantIdentity)
    case participantUpdated(SocialParticipantIdentity)
    case participantRemoved(participantID: String)
    case sessionEnded(endedAt: Date)
    case receiptShared(UUID)
    case artifactShared(UUID)
    case workflowShared(String)
    case playlistShared(String)
    case agentContextShared(SharedAgentContext)
    case approvalOpened(SocialApprovalDraft)
    case approvalVoteCast(approvalID: UUID, vote: SocialApprovalVote)
    case approvalResolved(approvalID: UUID, resolution: ApprovalResolution)
    case ritualRunChanged(ritualID: String, status: SocialRitualRunStatus, artifactIDs: [UUID], receiptIDs: [UUID])
    case queueProposalCreated(SocialQueueProposal)
    case queueVoteCast(SocialQueueVote)
    case queueMutationAccepted(SocialQueueMutation)
    case queueMutationRejected(proposalID: UUID)
    case queueSnapshotPublished(SocialQueueSnapshot)
    case unsupported(kind: String)
}

public struct SocialEventEnvelope: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public let version: Int
    public let sessionID: UUID
    public let authorParticipantID: String
    public let authorCAIP10Account: String?
    public let createdAt: Date
    public let parentEventIDs: [UUID]
    public let event: SocialEvent

    public init(
        id: UUID = UUID(),
        version: Int = 1,
        sessionID: UUID,
        authorParticipantID: String,
        authorCAIP10Account: String? = nil,
        createdAt: Date = .now,
        parentEventIDs: [UUID] = [],
        event: SocialEvent
    ) {
        self.id = id
        self.version = version
        self.sessionID = sessionID
        self.authorParticipantID = authorParticipantID
        self.authorCAIP10Account = authorCAIP10Account
        self.createdAt = createdAt
        self.parentEventIDs = parentEventIDs
        self.event = event
    }

    /// The same envelope with its author fields and payload bounded — see
    /// ``SocialEvent/clampedForStorage``. Applied once, where wire data becomes durable.
    var clampedForStorage: SocialEventEnvelope {
        SocialEventEnvelope(
            id: id,
            version: version,
            sessionID: sessionID,
            authorParticipantID: String(
                authorParticipantID.prefix(SocialParticipantIdentity.identifierLimit)
            ),
            authorCAIP10Account: authorCAIP10Account.map {
                String($0.prefix(SocialParticipantIdentity.identifierLimit))
            },
            createdAt: createdAt,
            parentEventIDs: Array(parentEventIDs.prefix(64)),
            event: event.clampedForStorage
        )
    }
}

public enum SocialConnectionPhase: String, Equatable, Sendable, Codable {
    case offline
    case connecting
    case connected
    case degraded
    case blocked
}

public struct SocialSyncState: Equatable, Sendable, Codable {
    public let phase: SocialConnectionPhase
    public let pendingOutboundCount: Int
    public let lastReceivedAt: Date?
    public let lastErrorSummary: String?

    public init(
        phase: SocialConnectionPhase = .offline,
        pendingOutboundCount: Int = 0,
        lastReceivedAt: Date? = nil,
        lastErrorSummary: String? = nil
    ) {
        self.phase = phase
        self.pendingOutboundCount = max(0, pendingOutboundCount)
        self.lastReceivedAt = lastReceivedAt
        self.lastErrorSummary = lastErrorSummary
    }
}

/// Deterministic projection used by relay/persistence adapters to reconcile append-only social events.
public struct SocialSessionProjection: Equatable, Sendable, Codable {
    public enum RejectionReason: String, Equatable, Sendable, Codable {
        case sessionEnded
        case unverifiedAuthor
        case ownerRequired
        case removedParticipant
        case mismatchedAuthor
        /// A participant tried to grant itself the owner role while a different owner already held it.
        case roleEscalation
        /// A relay-delivered record claimed the installation-local `.local` trust state, which is
        /// only ever legitimate for an identity this installation minted itself.
        case untrustedLocalIdentity
        /// A relay-delivered record tried to raise an identity this projection already holds to
        /// `.verified` — wallet-proven — without this installation ever having seen the proof.
        ///
        /// A *new* peer's unproven `.verified` claim is downgraded to `.pending` instead of refused,
        /// so a joined session stays legible; see
        /// ``SocialSessionProjection/downgradedVerification(of:isLocallyMinted:)``, which also
        /// records why the proof is not yet transported. This case is the narrower one with no
        /// legitimate reading: the record is already held as unproven, so refusing the escalation
        /// costs nothing, whereas accepting it would hand over `canAuthorBindingEvents` on an
        /// assertion. It is also the case that becomes a *failed proof* rejection once proofs travel
        /// with the identity.
        case unprovenVerifiedIdentity
        /// A participant record tried to change the on-chain account already bound to it.
        ///
        /// Participant records are author-bound, so a member may write its *own* record — which made
        /// the account field rebindable: `apply` replaces the whole identity, so naming a victim's
        /// `caip10Account` in a self-`participantUpdated` re-attributed everything that member went
        /// on to share to the victim's wallet. The ``mismatchedAccount`` check above could not see
        /// it, because it compares the envelope's claimed author account against the record — and
        /// this attack rewrites the record.
        ///
        /// Binding an account is what wallet verification is *for*, so changing it is a
        /// leave-and-rejoin, which re-runs the proof.
        case rebindsAccount
        /// The envelope's `authorCAIP10Account` disagreed with the on-chain account already recorded
        /// for that participant.
        case mismatchedAccount
        /// The owner tried to remove itself, which would leave the session with no owner.
        case selfRemoval
        /// A vote or resolution referenced an approval this projection has never seen opened.
        case unknownApproval
        /// A relay-delivered envelope named, as its author, a participant that can only have become
        /// binding-capable through this installation — so the claim is an impersonation.
        ///
        /// The reachability argument is worth keeping written down, because it is what makes this a
        /// flat refusal rather than a judgement call. A participant passes
        /// ``SocialParticipantIdentity/canAuthorBindingEvents`` only on `.local` or `.verified`;
        /// `.local` is refused off the wire by ``untrustedLocalIdentity``, and `.verified` is either
        /// downgraded to `.pending` for a new peer or refused by ``unprovenVerifiedIdentity`` for a
        /// held one. So *every* binding-capable participant was minted here, and an envelope that
        /// arrives over the relay claiming to be authored by one of them is necessarily forged.
        ///
        /// Lifted by transporting the join proof — see
        /// ``SocialSessionProjection/downgradedVerification(of:isLocallyMinted:)`` — not by a wider
        /// reading of `authorParticipantID`, which is an unsigned wire string.
        case impersonatedAuthor
        /// A relay-delivered record tried to *modify* a participant record this installation already
        /// holds, rather than introduce a new peer.
        ///
        /// The generalisation of ``unprovenVerifiedIdentity``, which refuses one specific wire
        /// modification of a held record. The same reasoning covers role, display name, and trust
        /// state: the record is already here, so refusing the overwrite costs nothing, while
        /// accepting it let any invite holder rewrite the owner's own record.
        case foreignRecordUpdate
    }
    public let sessionID: UUID
    /// Participant ids this installation knows, from outside the relay, could legitimately be the
    /// session's owner — the anchor the owner-bootstrap exemption is bound to.
    ///
    /// Supplied by ``SocialEventLogSnapshot/projection(sessionID:)`` from the two things an
    /// installation knows that an attacker cannot write: an invite it scanned out-of-band (whose
    /// `inviterParticipantID` is the party that vouched for the session) and, via
    /// `locallyMintedEventIDs`, the envelopes it authored itself.
    ///
    /// Empty is the fail-closed reading, so a bare envelope array of unknown origin bootstraps no
    /// owner at all. See ``ownerBootstrapIsOpen(forAuthor:isLocallyMinted:)``.
    public let ownerBootstrapAnchors: Set<String>
    public private(set) var title: String?
    public private(set) var correlationID: String?
    public private(set) var endedAt: Date?
    public private(set) var participants: [String: SocialParticipantIdentity]
    public private(set) var removedParticipantIDs: Set<String>
    public private(set) var sharedReceiptIDs: [UUID]
    public private(set) var sharedArtifactIDs: [UUID]
    public private(set) var sharedWorkflowIDs: [String]
    public private(set) var sharedPlaylistIDs: [String]
    public private(set) var sharedAgentContexts: [SharedAgentContext]
    public private(set) var approvals: [UUID: SocialApprovalState]
    public private(set) var queueProposals: [UUID: SocialQueueProposal]
    public private(set) var queueVotes: [UUID: [String: SocialQueueVote]]
    public private(set) var queueItems: [SocialQueueItem]
    public private(set) var rejectedQueueProposalIDs: Set<UUID>
    public private(set) var ritualRuns: [String: SocialRitualRunStatus]
    public private(set) var ritualRunDetails: [String: SocialRitualRun]

    /// Participants whose current record was written by a locally-minted envelope.
    ///
    /// Distinct from "is `.verified`": this records *how the record got here*, not what it claims.
    /// It is the anchor for the cross-participant account rule, which must not be decided by
    /// `createdAt` ordering — see the account guard in ``rejectionReason(for:isLocallyMinted:)``.
    ///
    /// Not `public`: it is provenance bookkeeping for this type's own rules, and exposing it would
    /// invite a consumer to treat it as a trust signal in its own right.
    private var locallyEstablishedParticipantIDs: Set<String>

    /// The account each participant id was bound to by an envelope **this installation authored**,
    /// precomputed from the whole envelope set before replay rather than accumulated during it.
    ///
    /// `locallyEstablishedParticipantIDs` above is the same fact observed *incrementally*, and that
    /// is precisely what made the cross-participant account rule racey. The rule asks whether some
    /// other locally-established participant already holds the account being claimed — but asked of
    /// the incremental set, "already" means "earlier in `reduce`'s sort on `createdAt`", which is a
    /// wire field. An attacker therefore never had to defeat the anchor: backdating to
    /// `.distantPast` put its record ahead of the locally-minted one that would have armed the
    /// guard, and the guard simply saw an empty projection. The victim's real, checksum-valid
    /// address then rendered in Mission Control under an attacker-chosen display name — the exact
    /// impersonation the rule exists to refuse, on the one device that *knows* the address belongs
    /// to someone else.
    ///
    /// Precomputing makes the answer a property of the log rather than of arrival order, which is
    /// the only form in which "this installation established it" is a fact at all. The incremental
    /// set is kept for the rules that genuinely are about replay position (held-record overwrites,
    /// the author-side account exemption), where seeding it early would instead *strengthen* the
    /// wire's hand — see ``relayMayAssertAnchoredAccount(claimed:author:)``.
    ///
    /// Cleared on removal alongside the incremental set, so leave-and-rejoin stays the documented
    /// way to move an account.
    private var locallyMintedAccountsByParticipantID: [String: String]

    public init(sessionID: UUID, ownerBootstrapAnchors: Set<String> = []) {
        self.locallyEstablishedParticipantIDs = []
        self.locallyMintedAccountsByParticipantID = [:]
        self.sessionID = sessionID
        self.ownerBootstrapAnchors = ownerBootstrapAnchors
        self.title = nil
        self.correlationID = nil
        self.endedAt = nil
        self.participants = [:]
        self.removedParticipantIDs = []
        self.sharedReceiptIDs = []
        self.sharedArtifactIDs = []
        self.sharedWorkflowIDs = []
        self.sharedPlaylistIDs = []
        self.sharedAgentContexts = []
        self.approvals = [:]
        self.queueProposals = [:]
        self.queueVotes = [:]
        self.queueItems = []
        self.rejectedQueueProposalIDs = []
        self.ritualRuns = [:]
        self.ritualRunDetails = [:]
    }

    /// Replays `envelopes` into a deterministic projection.
    ///
    /// `locallyMintedEventIDs` names the envelopes *this installation authored*, as recorded by
    /// ``SocialEventLogStore`` when they were appended — it is never carried on the envelope itself,
    /// because the envelope is the wire format and anything on it is attacker-controlled. Only those
    /// envelopes may introduce an identity in the installation-only `.local` verification state; see
    /// ``RejectionReason/untrustedLocalIdentity``.
    ///
    /// It defaults to empty, which is the fail-closed reading for a bare envelope array of unknown
    /// origin. Callers holding a ``SocialEventLogSnapshot`` should prefer
    /// ``SocialEventLogSnapshot/projection(sessionID:)``, which supplies the provenance automatically.
    ///
    /// `ownerBootstrapAnchors` is the same argument applied to the owner role; see
    /// ``SocialSessionProjection/ownerBootstrapAnchors``. It also defaults to empty — fail closed —
    /// which is why the snapshot form is the one to prefer.
    ///
    /// - Note: `envelopes` are ordered by their *claimed* `createdAt`, which is a wire field and
    ///   therefore attacker-chosen. That is tolerable for content (a backdated share reorders a
    ///   cosmetic list) but it must never decide *authority*, because anyone can claim to be first.
    ///   It used to: the owner-bootstrap exemption below was open until an owner existed, so a
    ///   `participantUpdated` claiming `role: .owner` and `createdAt: .distantPast` sorted ahead of
    ///   the real owner's record, took the exemption, and then had the genuine owner's own claim
    ///   rejected as `.roleEscalation` — a complete session takeover from one backdated envelope.
    ///   The fix is not to find a trustworthy clock but to stop deriving authority from order at
    ///   all: the exemption is bound to `ownerBootstrapAnchors` instead.
    public static func reduce(
        _ envelopes: [SocialEventEnvelope],
        sessionID: UUID,
        locallyMintedEventIDs: Set<UUID> = [],
        ownerBootstrapAnchors: Set<String> = []
    ) -> SocialSessionProjection {
        var projection = SocialSessionProjection(
            sessionID: sessionID,
            ownerBootstrapAnchors: ownerBootstrapAnchors
        )
        var seen: Set<UUID> = []
        let ordered = envelopes
            .filter { $0.sessionID == sessionID }
            .filter { seen.insert($0.id).inserted }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt { return lhs.id.uuidString < rhs.id.uuidString }
                return lhs.createdAt < rhs.createdAt
            }

        // Built before the replay loop, deliberately: the cross-participant account rule must not be
        // able to be raced by an envelope that merely claims an earlier `createdAt`. See
        // ``locallyMintedAccountsByParticipantID``.
        projection.locallyMintedAccountsByParticipantID = Dictionary(
            ordered.compactMap { envelope -> (String, String)? in
                guard locallyMintedEventIDs.contains(envelope.id) else { return nil }
                switch envelope.event {
                case let .participantJoined(identity), let .participantUpdated(identity):
                    return (identity.participantID, identity.caip10Account)
                default:
                    return nil
                }
            },
            uniquingKeysWith: { _, latest in latest }
        )

        for envelope in ordered {
            projection.apply(envelope, isLocallyMinted: locallyMintedEventIDs.contains(envelope.id))
        }
        return projection
    }

    /// Why `envelope` would be refused against this projection, or `nil` if it would be accepted.
    ///
    /// `isLocallyMinted` must be true only when this installation authored the envelope; see
    /// ``reduce(_:sessionID:locallyMintedEventIDs:)``. It defaults to `false`, the fail-closed
    /// reading for an envelope of unknown origin.
    public func rejectionReason(
        for envelope: SocialEventEnvelope,
        isLocallyMinted: Bool = false
    ) -> RejectionReason? {
        if let endedAt, envelope.createdAt > endedAt, envelope.event.isMutatingAfterEnd {
            return .sessionEnded
        }
        // Identity binding: `authorCAIP10Account` rides on the envelope and is self-asserted like
        // everything else, so it must agree with the account already recorded for that participant.
        // Unbound, a member could attribute a shared receipt to someone else's wallet simply by
        // naming their address here. `nil` is the legitimate "not claiming an account" case, and an
        // author with no record yet is handled by the membership rules below.
        //
        // Anchored on the same rule as the write-once binding below: a record that merely arrived
        // over the wire must not be able to refuse a locally-minted author's own account claim.
        // Otherwise a pre-claimed participant id silently invalidates every envelope that device
        // subsequently authors for itself — this guard runs *first*, so it is the one that fires.
        //
        // And anchored on the *other* side too, via ``relayMayAssertAnchoredAccount(claimed:author:)``.
        // Running first is exactly what made this guard the one that mattered: a relay pre-claim
        // naming the anchored party's id with the attacker's wallet poisoned every envelope that
        // party later authored, and it returned here — before the `switch`, before the held-record
        // rules — so the exemption written for precisely this lock-out was never consulted.
        if let claimed = envelope.authorCAIP10Account,
           let known = participants[envelope.authorParticipantID]?.caip10Account,
           !SocialAccountIdentity.matches(claimed, known),
           locallyEstablishedParticipantIDs.contains(envelope.authorParticipantID) || !isLocallyMinted,
           !relayMayAssertAnchoredAccount(claimed: claimed, author: envelope.authorParticipantID) {
            return .mismatchedAccount
        }
        // One authority decision, read once. Previously this was two booleans consulted at two
        // points in the chain, which let a new event type answer `false` to both and skip every
        // author check — see ``EventAuthority``.
        let authority = envelope.event.authority
        if authority.requiresBindingAuthor {
            guard participantCanAuthorBindingEvent(envelope.authorParticipantID) else {
                return .unverifiedAuthor
            }
            // Provenance, not merely the named author — the same reading `.local` and wire-claimed
            // `.verified` already get below, applied to the author binding itself.
            //
            // Asking only "is the named author binding-capable?" asks a question the attacker
            // answers for itself by typing the owner's id, exactly as the foreign-record rule once
            // did. And here the answer is never ambiguous: a participant is binding-capable only on
            // `.local` or `.verified`, `.local` is refused off the wire by `untrustedLocalIdentity`,
            // and `.verified` is either downgraded for a new peer or refused by
            // `unprovenVerifiedIdentity` for a held one. So every binding-capable participant was
            // minted *here*, and a relay-delivered envelope naming one of them is forged by
            // construction. There is no legitimate message this refuses: the only two emitters of
            // social events are `RitualCoordinator.enqueueSocialEvents` and
            // `SocialJoinVerificationService`, both self-authored and both minting locally.
            //
            // Without this, one envelope sealed under the shared session key — which every invite
            // holder has — could author any owner-only or binding event as the host: a
            // `.sessionEnded(endedAt: .distantPast)` made the whole session immediately prunable
            // (erasing every shared receipt and artifact reference), a `.participantRemoved` ejected
            // any member and permanently closed owner bootstrap, an `.approvalResolved` force-approved
            // a 3-of-3 with zero votes, and a `.queueSnapshotPublished` rewrote the user's real
            // playlist. Lifted by the transported join proof, not by trusting the wire.
            guard isLocallyMinted else { return .impersonatedAuthor }

            // Session takeover / hostile-participant control (Social v1 abuse gate): ending the
            // session, removing a participant, or short-circuiting an approval is owner-only. A
            // verified collaborator can vote and share, but cannot silently kill the session or
            // eject peers.
            //
            // Nested inside the binding check rather than standing beside it, because ownership is
            // *additional* to binding authority, never an alternative to it. As two sibling `if`s
            // the stronger requirement could be satisfied while the weaker was skipped, which is
            // the shape every defect in this function has taken.
            if authority == .ownerAuthor, !participantIsOwner(envelope.authorParticipantID) {
                return .ownerRequired
            }
        }
        switch envelope.event {
        case let .participantJoined(identity), let .participantUpdated(identity):
            // Removal is terminal in v1, and deliberately so rather than by omission. The tombstone
            // is write-only, so an owner cannot re-admit a participant it removed — not even one it
            // removed by mistake.
            //
            // The obvious reversible shape is the wrong one: comparing a wire `joinedAt` against a
            // recorded `removedAt` would let an attacker re-admit itself simply by claiming a later
            // timestamp, which is precisely the wire-controlled-ordering race
            // ``ownerBootstrapIsOpen(forAuthor:isLocallyMinted:)`` documents and was hardened
            // against. Re-admission has to be an owner-authorized *event*, not a timestamp
            // comparison — so it is a Phase 2 feature with its own authority rule, not a loosening
            // of this one. Nothing is stranded in the meantime: no code path emits
            // `participantRemoved` today, so there is no removal to undo.
            if removedParticipantIDs.contains(identity.participantID) { return .removedParticipant }
            // Write-once account binding, checked ahead of everything else about this record because
            // it depends on nothing else: not on who is writing, and not on how the envelope
            // arrived. An owner may change a peer's role, and a peer may rename itself, but nobody
            // may move an identity onto a different wallet — the binding is what the wallet proof
            // established, and re-pointing it would re-attribute every record that identity has
            // shared. Changing an account is a leave-and-rejoin, which re-runs the proof.
            //
            // `SocialAccountIdentity.matches` rather than string equality, so an EIP-55 respelling
            // of the same address is not read as a rebind.
            //
            // **Anchored, for the same reason the cross-participant rule below is.** Write-once
            // protects a binding *this installation* established. Unanchored it also let a record
            // introduced over the wire out-rank a later locally-minted one — and because
            // `participantJoined` for an unknown id is deliberately accepted off the relay, any
            // invite holder could pre-claim a participant id with an attacker-chosen account before
            // that device ever recorded its own. `reduce` orders by wire-controlled `createdAt`, so
            // arriving first is free.
            //
            // The consequence was permanent and silent: the local mint paths
            // (`RitualCoordinator.enqueueSocialEvents`, `SocialJoinVerificationService`) never call
            // this function, so the device's own verified join was simply refused at projection time
            // with nothing surfaced. Its record stayed `.pending` under the attacker's account and
            // display name, `canAuthorBindingEvents` stayed false, and every subsequent share, vote,
            // and ritual run it authored was dropped as `.unverifiedAuthor`. Re-running the join
            // mints a later envelope that hits the same guard, so only a full `reset()` recovered.
            // The same shape against the invite's inviter binds the *owner* to an attacker's address
            // on every joiner's device.
            //
            // So: a held record that this installation established is authoritative and still
            // refuses every rebind. A held record that merely arrived over the wire does not get to
            // veto a locally-minted write.
            //
            // Carries the same anchored exemption as the held-record rules below, for the same
            // reason the author-side guard above does: a pre-claim binding the anchored party's id
            // to the attacker's wallet fires *here*, several guards ahead of
            // ``relayMayOverwriteHeldRecord(_:author:)``, so without it the owner's genuine record
            // is still refused and the session is still left permanently ownerless. The exemption
            // only ever admits the anchored party naming its own account as owner, which is the
            // genuine binding by construction.
            if let known = participants[identity.participantID],
               !SocialAccountIdentity.matches(identity.caip10Account, known.caip10Account),
               locallyEstablishedParticipantIDs.contains(identity.participantID) || !isLocallyMinted,
               !relayMayOverwriteHeldRecord(identity, author: envelope.authorParticipantID) {
                return .rebindsAccount
            }
            // The same write-once rule approached from the other side: one wallet is one party, so
            // two participant ids may not claim one account. The check above only fires on a
            // *change* to a record that already exists, which left a brand-new record's first claim
            // unchecked — and `mismatchedAccount` above cannot see it either, because that compares
            // the envelope's author account against a record this projection holds. So an invite
            // holder could join as `attacker` while naming the victim's real, checksum-valid wallet
            // as its own `caip10Account`, under any display name it liked. The record carries no
            // authority, but Mission Control renders the projection, so a genuine address appears as
            // a session participant under an attacker-chosen name — a credible impersonation
            // primitive on a wallet-adjacent surface, and `SocialAccountIdentity.matches` means the
            // spoof renders as the real thing.
            //
            // A removal clears the record (`apply` removes the key), so leave-and-rejoin — the
            // documented way to move an account — still works.
            //
            // **Anchored to local provenance, and that scoping is the whole correctness argument.**
            // The obvious form of this check — refuse any record whose account another participant
            // already holds — is wrong, and wrong in this file's signature way: projection order is
            // decided by `createdAt`, which the wire controls, so "already holds" is a race an
            // attacker wins by backdating. It would have let an attacker *pre-claim* a victim's
            // account and have the victim's own genuine record refused, trading an impersonation
            // for a silent denial of visibility. That is the same reasoning
            // ``ownerBootstrapIsOpen(forAuthor:isLocallyMinted:)`` sets out.
            //
            // So only a *locally-minted* record can block, and only a relay-delivered one can be
            // blocked. A record this installation established cannot be raced, so the ordering
            // hazard disappears — and the case worth defending is exactly the one this covers: an
            // invite holder naming an account this device knows is someone else's (its own, or a
            // peer it verified itself) and having Mission Control render that real, checksummed
            // address under a name the attacker chose. Two *wire* peers colliding on one account is
            // left alone deliberately: neither is trusted, neither record carries authority, and
            // refusing either one would reintroduce the race this guard exists to avoid.
            //
            // Asked of ``locallyMintedAccountsByParticipantID`` rather than of the live projection,
            // because the live projection answers "has it been applied *yet*" and `yet` is decided
            // by `createdAt`. Backdating to `.distantPast` put the attacker's record ahead of the
            // locally-minted one that would have armed this guard, so the anchor was never defeated
            // — it was simply not yet present. See that property.
            //
            // **And asked of the owner-bootstrap anchors as well, which is the half a *joined*
            // session has.** `locallyMintedAccountsByParticipantID` is empty on a session this
            // installation merely joined — nothing here minted a record for anyone — so the rule
            // above protects exactly nobody there, and the one party the device does have
            // out-of-band knowledge about is the inviter. An invite holder could therefore publish
            // `participantJoined` under *its own* fresh participant id while naming the owner's
            // real, checksum-valid account, under any display name it liked: `describesAuthor` is
            // satisfied (it names itself as both author and subject), no record is being modified,
            // no role is escalated, and the account rules above see nothing. Mission Control then
            // renders the owner's genuine address twice — once as the owner, once as
            // "Auralis Support" — which is the same impersonation primitive on the same
            // wallet-adjacent surface that the locally-minted rule exists to refuse, reached on the
            // device that *knows*, from a QR code handed over in person, whose account that is.
            //
            // The ordering hazard that forced the locally-minted rule to be anchored does not
            // reappear, because this asks nothing about what the projection has applied *yet*:
            // ``ownerBootstrapAnchors`` comes from the invite and is fixed before replay begins.
            // And it is one-directional in the same way — the anchored party's own record names the
            // anchor as its `participantID` and is exempt, so a backdated spoof cannot lock the
            // genuine owner out the way an unscoped "someone already holds it" rule would.
            if !isLocallyMinted,
               claimsAnotherLocallyMintedAccount(identity) || claimsAnchoredAccount(identity) {
                return .rebindsAccount
            }
            // `.local` means "trusted only inside this installation" and, like `.verified`, it clears
            // `canAuthorBindingEvents`. It is a *provenance* claim, and provenance is exactly what a
            // relay-delivered envelope cannot prove about itself: an invite holder could simply mint
            // a `.local` record and pick up authoring authority without ever presenting a wallet
            // proof. So the answer comes from how the envelope entered this installation's log, not
            // from anything inside it. A locally-authored ritual is trusted; the wire never is.
            if identity.verificationState == .local, !isLocallyMinted {
                return .untrustedLocalIdentity
            }
            // Participant records are author-bound, exactly like votes and queue proposals below.
            // Writing *another* participant's record is owner authority — otherwise any member could
            // demote the owner to `.viewer` and strip its `canAuthorBindingEvents`.
            //
            // Owner authority alone is not enough, because `authorParticipantID` is a plain wire
            // string with nothing signing it: the relay seals envelopes with one *shared* session
            // key, so AES-GCM proves session-key possession — which every invite holder has by
            // design — not authorship. Asking only `participantIsOwner(authorParticipantID)` asks
            // whether the *named* author is the owner, a question the attacker answers for itself by
            // typing the owner's id. It bought a complete takeover in two envelopes: one naming the
            // owner as author to install `attacker` with `role: .owner`, then a second authored as
            // `attacker` rewriting the genuine owner down to `.viewer`. `.viewer` clears `canVote`
            // and therefore `canAuthorBindingEvents`, so the real owner could no longer end the
            // session, remove the attacker, share, or resolve approvals — and with no owner left no
            // `sessionEnded` is derivable, so `prune` could never release the graph either.
            //
            // So the author's *provenance* has to carry the claim, exactly as it does for `.local`
            // above and for wire-claimed `.verified` below: a foreign-record write counts only if
            // this installation minted it. That is the same accepted trade those two make — a
            // session this installation merely *joined* will not reflect owner-driven role changes,
            // because the owner's writes arrive over the relay like everything else. Membership,
            // names, and existing roles still project, so the session stays legible; what is
            // withheld is one peer rewriting another peer's record on an unprovable assertion. The
            // fix that lifts the restriction is the transported join proof described on
            // ``downgradedVerification(of:isLocallyMinted:)``, not a cleverer reading of the wire.
            let describesAuthor = identity.participantID == envelope.authorParticipantID
            if !describesAuthor,
               !(isLocallyMinted && participantIsOwner(envelope.authorParticipantID)) {
                return .mismatchedAuthor
            }
            // The relay seals envelopes with one *shared* session key, so AES-GCM proves session-key
            // possession, not authorship: `role` arrives self-asserted. Without this check any invite
            // holder could replay `participantUpdated` claiming `.owner` and thereby acquire the
            // owner-only authority that `requiresOwnerAuthor` above exists to protect.
            // The `ownerBootstrapIsOpen` case is the legitimate bootstrap: the session creator records
            // its own owner identity before any owner exists. The exemption is closed permanently by
            // the first removal, because an ownerless session that *used* to have an owner is the
            // aftermath of a removal, not a fresh session — leaving it open let whoever was left
            // self-promote into the owner-only authority the checks above exist to protect.
            //
            // Not gated on `describesAuthor`. It used to be, which meant an envelope writing someone
            // *else's* record as `role: .owner` skipped escalation checking entirely and was policed
            // only by the author-bound rule above — so the two rules had to hold hands for either to
            // work. They are independent readings of the same envelope and each should stand alone:
            // the author-bound rule asks who may write this record, this one asks whether the role
            // being written may be granted at all. Keeping both unconditional means loosening one
            // can never silently open the other.
            if identity.role == .owner,
               !ownerBootstrapIsOpen(
                   forAuthor: envelope.authorParticipantID,
                   identity: identity,
                   isLocallyMinted: isLocallyMinted
               ),
               !participantIsOwner(envelope.authorParticipantID) {
                return .roleEscalation
            }
            // Raising an *existing* record to `.verified` over the wire is refused outright. A new
            // peer's unproven `.verified` claim is merely downgraded (see
            // ``downgradedVerification(of:isLocallyMinted:)``) because a session you joined has to
            // stay legible, but there is no legitimate reading of "this record you already hold as
            // unproven is actually wallet-verified, take my word for it": the record is already
            // there, so nothing is lost by refusing, and accepting it would hand over
            // `canAuthorBindingEvents` on an assertion.
            //
            // Checked *last* of the participant rules, deliberately. Reporting it earlier would
            // mask the specific diagnosis for an envelope that is also a role escalation or a
            // foreign-record write, and making takeover attempts individually diagnosable is the
            // whole purpose of these reasons.
            if identity.verificationState == .verified, !isLocallyMinted,
               let known = participants[identity.participantID],
               known.verificationState != .verified,
               !relayMayOverwriteHeldRecord(identity, author: envelope.authorParticipantID) {
                return .unprovenVerifiedIdentity
            }
            // A relay envelope may *introduce* a participant — a session you joined has to stay
            // legible — but it may never modify a record this installation already holds.
            //
            // `describesAuthor` above is two wire fields compared against each other, so an attacker
            // satisfies it for free by naming its victim as both author and subject. That left the
            // `describesAuthor == true` arm with no provenance requirement at all, and because
            // `requiresVerifiedAuthor` and `requiresOwnerAuthor` are both false for
            // `participantUpdated`, it was the *only* author check such a write faced. One envelope
            // — author and subject both the host, `role: .viewer`, state `.pending`, and a
            // `createdAt` of `.distantFuture` so it sorts last over every record the host will ever
            // mint — permanently cleared the host's `canAuthorBindingEvents` and `hasOwner`. Its
            // ritual history then stopped recording with no visible error, its own `sessionEnded`
            // was refused as `.ownerRequired`, and `prune` could never release the graph. The
            // bootstrap exemption could not recover it either, because a fresh owner record sorts
            // *before* `.distantFuture`.
            //
            // This is the general form of `unprovenVerifiedIdentity` directly above, which already
            // refuses one specific wire modification of a held record; role, display name, and trust
            // state all warrant the same answer for the same reason. Checked after it, so the
            // narrower diagnosis still wins — and after the role and author rules, so a takeover
            // attempt is still reported as the specific thing it is.
            //
            // Introducing a new peer is untouched, and a duplicate relay delivery is not a
            // modification, so re-delivery stays idempotent. Comparing against
            // `downgradedVerification` rather than `identity` is what makes that true: the question
            // is whether the write would change what is *stored*.
            //
            // Anchored, for the reason set out on ``relayMayOverwriteHeldRecord(_:author:)``: a
            // held record that merely *arrived first* must not out-rank the anchored party's own
            // claim about itself, or one backdated envelope permanently denies a joined session its
            // owner. A record this installation established is still absolute.
            if !isLocallyMinted,
               let known = participants[identity.participantID],
               known != downgradedVerification(of: identity, isLocallyMinted: false),
               !relayMayOverwriteHeldRecord(identity, author: envelope.authorParticipantID) {
                return .foreignRecordUpdate
            }
        case let .participantRemoved(participantID):
            // Mirrors the guard `SharedSession.removeParticipant(id:requestedBy:)` has always had.
            // Self-removal by the owner is the one removal that can strand a session with no owner,
            // which is precisely the state the bootstrap exemption above would otherwise reopen.
            if participantID == envelope.authorParticipantID { return .selfRemoval }
        case let .approvalVoteCast(approvalID, vote):
            if vote.participantID != envelope.authorParticipantID { return .mismatchedAuthor }
            // Previously dropped silently by optional chaining in `apply`. The outcome is unchanged —
            // a vote on an approval that was never opened cannot be recorded — but under clock skew
            // it is now diagnosable instead of vanishing.
            if approvals[approvalID] == nil { return .unknownApproval }
        case let .approvalResolved(approvalID, _):
            if approvals[approvalID] == nil { return .unknownApproval }
        case let .queueProposalCreated(proposal):
            if proposal.proposedByParticipantID != envelope.authorParticipantID { return .mismatchedAuthor }
        case let .queueVoteCast(vote):
            if vote.participantID != envelope.authorParticipantID { return .mismatchedAuthor }
        case .sessionCreated:
            // `.eventSpecific` means "policed by the event's own rules", and this is that rule.
            // Without it `sessionCreated` was the one event in the type that no author check
            // reached at all: the authority block above is skipped for `.eventSpecific`, and this
            // `switch` had no arm for it, so a relay envelope fell through to `default: break` and
            // was accepted.
            //
            // The defence written on `authority` — "only ever fills in a title and a correlation id
            // on first write" — is true of `apply` and worthless as a security property, because
            // *first* is decided by `reduce`'s sort on `envelope.createdAt`, a wire field. A
            // backdated relay `sessionCreated` sorts ahead of the host's own, and `??` then makes
            // the host's genuine title and correlation id permanent no-ops. That is the same
            // wire-controlled-ordering error `ownerBootstrapIsOpen` and the account guards were
            // each hardened against; this is the fourth site.
            //
            // `correlationID` is not cosmetic: `SharedSession` documents it as the same key as
            // `AgentSession`, which is what ties shared receipts, worklogs and artifacts together.
            //
            // Nothing legitimate is refused. The only emitter is
            // `RitualCoordinator.enqueueSocialEvents`, which mints the session it is creating
            // locally and in the same batch as its own `participantJoined`.
            if !isLocallyMinted { return .impersonatedAuthor }
        case .unsupported:
            // A forward-compatibility carrier: `apply` does nothing with it, so it grants no state
            // and needs no author. It is still *stored*, which is why its payload is clamped at the
            // boundary (see `SocialEvent.unsupported`'s `kind` clamp) rather than policed here.
            break
        case .sessionEnded, .receiptShared, .artifactShared, .workflowShared, .playlistShared,
             .agentContextShared, .approvalOpened, .ritualRunChanged, .queueMutationAccepted,
             .queueMutationRejected, .queueSnapshotPublished:
            // Fully covered by the authority block above: every one of these is `.bindingAuthor` or
            // `.ownerAuthor`, so it already required a binding-capable author *and* local provenance
            // before reaching here. Listed rather than defaulted — see below.
            break
        }
        return nil
    }

    private mutating func apply(_ envelope: SocialEventEnvelope, isLocallyMinted: Bool) {
        guard rejectionReason(for: envelope, isLocallyMinted: isLocallyMinted) == nil else { return }

        switch envelope.event {
        case let .sessionCreated(title, correlationID):
            self.title = self.title ?? title
            self.correlationID = self.correlationID ?? correlationID
        case let .participantJoined(identity), let .participantUpdated(identity):
            participants[identity.participantID] = downgradedVerification(
                of: identity,
                isLocallyMinted: isLocallyMinted
            )
            // Provenance follows the write that is actually landing. **Insert only — never remove.**
            //
            // There was a symmetric `else { remove(...) }` here, and it was an anchor-stripping
            // primitive with no legitimate use. A *landing* wire write on a record this installation
            // already holds can only be a byte-identical no-op, because `.foreignRecordUpdate`
            // refuses anything that would change the stored value — so the branch fired exclusively
            // for writes that changed nothing, and its only effect was to drop that record's
            // provenance anchor. Every field of a participant record is observable on the relay, so
            // replaying one verbatim was a free way to disarm the anchor and then claim the
            // account it protects. That it was not exploitable today rested on an accident of which
            // verification states the two local mint sites happen to produce.
            //
            // An envelope that does not *establish* a record has no business *un*-establishing one.
            if isLocallyMinted {
                locallyEstablishedParticipantIDs.insert(identity.participantID)
            }
        case let .participantRemoved(participantID):
            removedParticipantIDs.insert(participantID)
            participants.removeValue(forKey: participantID)
            // The record is gone, so its account is no longer held and must stop blocking. Both
            // provenance tables, so leave-and-rejoin remains the documented way to move an account.
            locallyEstablishedParticipantIDs.remove(participantID)
            locallyMintedAccountsByParticipantID.removeValue(forKey: participantID)
        case let .sessionEnded(date):
            endedAt = min(endedAt ?? date, date)
        case let .receiptShared(id):
            appendUnique(id, to: &sharedReceiptIDs)
        case let .artifactShared(id):
            appendUnique(id, to: &sharedArtifactIDs)
        case let .workflowShared(id):
            appendUnique(id, to: &sharedWorkflowIDs)
        case let .playlistShared(id):
            appendUnique(id, to: &sharedPlaylistIDs)
        case let .agentContextShared(context):
            guard context.isExpired(at: envelope.createdAt) == false else { return }
            sharedAgentContexts.removeAll { $0.id == context.id }
            sharedAgentContexts.append(context)
        case let .approvalOpened(draft):
            approvals[draft.id] = approvals[draft.id] ?? SocialApprovalState(
                id: draft.id,
                prompt: draft.prompt,
                requiredApprovals: draft.requiredApprovals
            )
        case let .approvalVoteCast(approvalID, vote):
            approvals[approvalID]?.record(vote)
        case let .approvalResolved(approvalID, resolution):
            approvals[approvalID]?.resolve(resolution)
        case let .ritualRunChanged(ritualID, status, artifactIDs, receiptIDs):
            ritualRuns[ritualID] = status
            ritualRunDetails[ritualID] = SocialRitualRun(
                ritualID: ritualID,
                status: status,
                artifactIDs: artifactIDs,
                receiptIDs: receiptIDs
            )
        case let .queueProposalCreated(proposal):
            queueProposals[proposal.id] = proposal
        case let .queueVoteCast(vote):
            var votes = queueVotes[vote.proposalID] ?? [:]
            votes[vote.participantID] = vote
            queueVotes[vote.proposalID] = votes
        case let .queueMutationAccepted(mutation):
            apply(mutation)
        case let .queueMutationRejected(proposalID):
            rejectedQueueProposalIDs.insert(proposalID)
        case let .queueSnapshotPublished(snapshot):
            // Deliberate last-writer-wins for v1: the snapshot is a whole-queue replacement published
            // by any verified participant, with no reconciliation against `queueItems`. Shared-queue
            // order is cosmetic, self-healing on the next publish, and visible to everyone in the
            // session, so convergence is worth more here than contention control. Unlike approvals it
            // gates nothing — anything binding travels as an approval or a queue mutation, both of
            // which are author-bound above.
            queueItems = snapshot.items
        case .unsupported:
            break
        }
    }

    /// `identity`, with a wire-claimed `.verified` state reduced to `.pending`.
    ///
    /// `.verified` means "a wallet signed this session's join challenge". That is a claim about an
    /// event on someone else's device, and `SocialParticipantIdentity.canAuthorBindingEvents` grants
    /// authority to it — so it is exactly the kind of claim a relay-delivered envelope cannot make
    /// about itself. Only `.local` was provenance-checked, which left the stronger claim unchecked:
    /// an invite holder could mint a `participantJoined` asserting `.verified` and pick up the
    /// authority to vote, resolve approvals, propose queue mutations, and share attributed records,
    /// with no wallet proof of any kind.
    ///
    /// Downgraded rather than refused, because refusing the record would make a session you *joined*
    /// unusable rather than merely restricted: the genuine owner's own record also arrives over the
    /// wire, so dropping it leaves a session with no owner, no members, and a `sessionEnded` that
    /// can never be accepted. `.pending` keeps the membership, names, and roles legible — all of
    /// which are presentation — while withholding the one thing that was unproven. Role is still
    /// policed separately by the escalation and owner-bootstrap rules, so a downgraded record
    /// claiming `.owner` gains nothing: owner-only events also require `canAuthorBindingEvents`.
    ///
    /// The fix that removes the restriction is to transport the proof. ``SocialParticipantProof`` is
    /// already `Codable` and already carries both the ``SocialJoinChallenge`` and the signature, so
    /// it can ride on the identity; verifying it belongs at the inbound boundary, where
    /// `SocialRelayCoordinator.handleInbound` already calls ``rejectionReason(for:isLocallyMinted:)``,
    /// because recovering an EIP-191 signature to a `caip10Account` needs the app's crypto provider
    /// and `SocialCore` deliberately carries no wallet dependency. Until then, a peer must be
    /// verified by *this* installation before it can author anything binding.
    private func downgradedVerification(
        of identity: SocialParticipantIdentity,
        isLocallyMinted: Bool
    ) -> SocialParticipantIdentity {
        guard identity.verificationState == .verified, !isLocallyMinted else { return identity }
        return SocialParticipantIdentity(
            participantID: identity.participantID,
            caip10Account: identity.caip10Account,
            displayName: identity.displayName,
            role: identity.role,
            verificationState: .pending,
            joinedAt: identity.joinedAt,
            proofID: identity.proofID
        )
    }

    /// Whether a relay-delivered record claims an account this installation bound to a *different*
    /// participant id.
    ///
    /// Order-independent by construction: both tables consulted here describe locally-authored
    /// envelopes, and ``locallyMintedAccountsByParticipantID`` is filled before replay begins, so
    /// the answer cannot be changed by an envelope claiming an earlier `createdAt`. The live
    /// projection is still consulted as well, so a projection built incrementally rather than
    /// through ``reduce(_:sessionID:locallyMintedEventIDs:ownerBootstrapAnchors:)`` keeps the rule.
    ///
    /// Two *wire* peers colliding on one account is still left alone deliberately: neither is
    /// trusted, neither record carries authority, and refusing either would reintroduce exactly the
    /// race this function exists to be free of.
    private func claimsAnotherLocallyMintedAccount(_ identity: SocialParticipantIdentity) -> Bool {
        let claimed = identity.caip10Account
        let live = participants.contains { participantID, held in
            participantID != identity.participantID
                && locallyEstablishedParticipantIDs.contains(participantID)
                && SocialAccountIdentity.matches(held.caip10Account, claimed)
        }
        if live { return true }
        return locallyMintedAccountsByParticipantID.contains { participantID, account in
            participantID != identity.participantID
                && SocialAccountIdentity.matches(account, claimed)
        }
    }

    /// Whether a relay-delivered record claims an account belonging to one of this session's
    /// owner-bootstrap anchors, under some *other* participant id.
    ///
    /// The companion to ``claimsAnotherLocallyMintedAccount(_:)`` on the axis a joined session
    /// actually has. That function anchors the one-wallet-one-party rule to local provenance, which
    /// is the right anchor for a session this installation hosted and no anchor at all for one it
    /// joined; here the anchor is the invite, which arrived out-of-band and never crossed the relay.
    ///
    /// Order-independent by construction, like every other rule in this file that is allowed to
    /// refuse: ``ownerBootstrapAnchors`` is supplied by
    /// ``SocialEventLogSnapshot/projection(sessionID:)`` before replay starts, so no `createdAt`
    /// claim can change the answer.
    ///
    /// One-directional, for the reason set out on ``relayMayOverwriteHeldRecord(_:author:)``: the
    /// anchored party's *own* record names the anchor as its `participantID` and is exempted here,
    /// so this can only ever refuse the impostor, never the genuine record. An unscoped "another
    /// participant already holds this account" rule could not say that — it would be decided by
    /// arrival order and a backdated pre-claim would lock the real owner out.
    ///
    /// Matched through ``SocialAccountIdentity/matches(_:_:)`` rather than `==`, so an EIP-55
    /// respelling of the anchor's address is not a way around it — and so a non-CAIP-10 anchor (the
    /// local UUID fallback participant id) never spuriously matches a real account.
    ///
    /// **The two comparisons are deliberately asymmetric, and reading that as a bug is the trap.**
    /// The exemption below is a byte-literal `contains`; the refusal above it is canonical. They are
    /// not two spellings of one question:
    ///
    /// - The refusal asks *address* identity — "is this the anchor's wallet?" — where EIP-55
    ///   capitalization is a checksum and not identity, so it must be canonical or the rule is one
    ///   `lowercased()` away from decorative.
    /// - The exemption asks *slot* identity — "is this the record that will land in the anchored
    ///   party's own entry?" — and that entry is `participants[identity.participantID]`, a
    ///   dictionary keyed on the **literal** string. Only a byte-identical id occupies it.
    ///
    /// Canonicalizing the exemption (including the per-anchor form, which keeps the conjunct
    /// `!matches(anchor, identity.participantID)`) breaks that correspondence and opens a hole it
    /// does not close: a record respelling *both* its `participantID` and its `caip10Account` in
    /// checksummed form would take the exemption while landing in a **different** `participants`
    /// key, so the anchored account ends up held twice — once by the genuine owner and once by an
    /// attacker-chosen display name. That is the F-62 impersonation primitive on a wallet-adjacent
    /// surface, which is exactly what this rule exists to refuse.
    ///
    /// It also buys nothing in the direction it was proposed for. The argument was that a respelled
    /// genuine owner misses the exemption and is refused, leaving a joined session ownerless — but
    /// every other anchor site is byte-literal for the same slot-identity reason
    /// (``isAnchoredSelfDescribing(_:author:)``, ``relayMayAssertAnchoredAccount(claimed:author:)``,
    /// and the storage ceiling's protected-row selection), so a respelled owner record fails
    /// `ownerBootstrapIsOpen` and is refused as `.roleEscalation` regardless. Canonicalizing here
    /// changes which reason is reported and nothing else. The anchor spelling is fixed at the
    /// invite, and production mints the invite's `inviterParticipantID` and the owner's record from
    /// the same account string on the same device, so the respelling does not arise.
    ///
    /// So: byte-literal is fail-closed here, and the one record it refuses that a canonical form
    /// would admit is indistinguishable from an impostor. Pinned by
    /// `wirePeerCannotClaimTheAnchoredOwnersAccount`.
    private func claimsAnchoredAccount(_ identity: SocialParticipantIdentity) -> Bool {
        guard !ownerBootstrapAnchors.contains(identity.participantID) else { return false }
        return ownerBootstrapAnchors.contains {
            SocialAccountIdentity.matches($0, identity.caip10Account)
        }
    }

    private func participantCanAuthorBindingEvent(_ participantID: String) -> Bool {
        participants[participantID]?.canAuthorBindingEvents == true
    }

    private func participantIsOwner(_ participantID: String) -> Bool {
        participants[participantID]?.role == .owner
    }

    private var hasOwner: Bool {
        participants.values.contains { $0.role == .owner }
    }

    /// Whether `author` may record itself as owner without an existing owner's blessing.
    ///
    /// Three conditions, and all three are necessary:
    ///
    /// - The session has never had an owner. An owner already exists, so there is nothing to
    ///   bootstrap.
    /// - Nobody has been removed. The removal clause matters because an owner can delegate
    ///   (`ownerCanDelegateOwnership`), so two owners can coexist and one can remove the other —
    ///   reaching an ownerless session by a route the self-removal guard does not cover. An
    ///   ownerless session that *used* to have an owner is the aftermath of a removal, not a fresh
    ///   session, and leaving the exemption open there let whoever was left self-promote.
    /// - `author` is anchored: either this installation authored the envelope, or it is the
    ///   `inviterParticipantID` of an invite this installation holds.
    ///
    /// The anchor is the condition that was missing, and it is the one that matters, because the
    /// first two conditions are both statements about *what the projection has seen so far* — and
    /// what it has seen so far is decided by `createdAt` ordering, which the wire controls. Without
    /// an anchor, "no owner yet" is not a fact about the session but a race an attacker wins by
    /// claiming an earlier timestamp. With one, an attacker who backdates an owner claim is simply
    /// not a party this installation ever agreed could own the session, whatever order it arrives in.
    ///
    /// Both anchor *sources* are outside the relay's reach: `isLocallyMinted` is recorded by
    /// ``SocialEventLogStore`` from the entry point used and never transmitted, and an invite is
    /// scanned out-of-band from the person who showed it to you.
    ///
    /// The anchor *set* being unreachable is not the same as the comparison being sound, and that
    /// gap was a real hole. `author` is `envelope.authorParticipantID`, an unsigned wire string, and
    /// `inviterParticipantID` is printed in the invite that **every** holder has — so one invite
    /// holder could simply type the inviter's id and take the exemption on every *other* holder's
    /// device. The anchor says who may own the session; on its own it says nothing about who wrote
    /// this envelope. That is the same question F-64 established cannot be asked of the wire.
    ///
    /// So a relay-delivered bootstrap must additionally be **self-describing**: the record has to be
    /// *about* the anchored party, and its account has to be that party's own id. Production
    /// satisfies this by construction — `SocialInviteExchangeModel` passes one CAIP-10 value as both
    /// `inviterParticipantID` and the joiner's `caip10Account`, and `SocialJoinVerificationService`
    /// sets `participantID` and `caip10Account` to the same account it just proved. What it removes
    /// is the substitution: an attacker naming the inviter must now also name the inviter's own
    /// account, which is the genuine record and re-points nothing at the attacker's wallet.
    private func ownerBootstrapIsOpen(
        forAuthor author: String,
        identity: SocialParticipantIdentity,
        isLocallyMinted: Bool
    ) -> Bool {
        guard !hasOwner, removedParticipantIDs.isEmpty else { return false }
        if isLocallyMinted { return true }
        return isAnchoredSelfDescribing(identity, author: author)
    }

    /// Whether a relay-delivered record is the anchored party describing itself.
    ///
    /// The one piece of out-of-band evidence this installation has about a session it joined: the
    /// invite was handed over in person, so its `inviterParticipantID` names a party we agreed
    /// could own the session. That alone proves nothing about *this* envelope — the id is printed
    /// in the invite every holder has — which is why the record must also be about that party and
    /// carry that party's own account. Together those make the claim unforgeable by a peer, because
    /// the only record satisfying them is the anchored party's genuine one.
    ///
    /// The two halves are split so the storage ceiling can ask the same question: the anchor set is
    /// this type's, but "does this record describe its own author" is a property of the envelope.
    /// See ``SocialEvent/grantsSelfDescribedOwnership(author:)``.
    private func isAnchoredSelfDescribing(
        _ identity: SocialParticipantIdentity,
        author: String
    ) -> Bool {
        ownerBootstrapAnchors.contains(author) && identity.describesSelf(author: author)
    }

    /// Whether a held record may be overwritten by `identity`, arriving over the relay.
    ///
    /// The held-record guards (`unprovenVerifiedIdentity`, `foreignRecordUpdate`) protect a record
    /// this projection already holds — but "already holds" is decided by `reduce`'s sort on
    /// `createdAt`, a wire field. That is the race this file has had to close three times already,
    /// and it was still open here: an invite holder could publish a backdated
    /// `participantJoined` for the *owner's* id — role `.viewer`, state `.pending`, an
    /// attacker-chosen display name — and the owner's genuine record would then arrive and be
    /// refused as a foreign-record update. The session is left with no owner on that device,
    /// permanently: `sessionEnded` is refused as `.ownerRequired`, no `endedAt` is derivable, and
    /// `prune` can never release the graph. Round 14 fixed exactly this shape for the *account*
    /// rules by anchoring them to local provenance; these two were handed off unanchored.
    ///
    /// A record **this installation established** is still absolute — nothing off the wire may
    /// touch it. What changes is that a record which merely *arrived first* no longer outranks the
    /// anchored party's own claim about itself.
    ///
    /// **The exemption is one-directional, and that is the whole safety argument.** It does not
    /// hold that an ordinary peer cannot satisfy the anchor conditions — it can. All three are
    /// public: `inviterParticipantID` is printed in the invite every holder has, and in production
    /// the participant id *is* the CAIP-10 account (`SocialJoinVerificationService` sets both to the
    /// account it proved), so a peer forges `isAnchoredSelfDescribing` by typing the anchored
    /// party's id into three fields. What it cannot do is make the forgery useful, because the
    /// exemption only ever permits *establishing* ownership.
    ///
    /// Permitting it in the other direction handed back the identical permanent lock-out from the
    /// opposite side, which is what this function exists to close. A `participantUpdated` naming the
    /// owner as both author and subject, with the owner's real account and `role: .viewer`, passes
    /// every other guard — `roleEscalation` only fires on `.owner`, and the account rules see a
    /// match — so the exemption was the last thing standing between an invite holder and clearing
    /// `hasOwner` on every other device. After that `sessionEnded` is refused as `.ownerRequired`,
    /// no `endedAt` is derivable, `prune` can never release the graph, and the attacker can re-apply
    /// after any corrective write because a later `createdAt` is free.
    private func relayMayOverwriteHeldRecord(
        _ identity: SocialParticipantIdentity,
        author: String
    ) -> Bool {
        guard !locallyEstablishedParticipantIDs.contains(identity.participantID) else { return false }
        guard isAnchoredSelfDescribing(identity, author: author) else { return false }
        // Direction first: only a write that *establishes* ownership is ever a candidate.
        guard identity.role == .owner else { return false }
        guard let known = participants[identity.participantID] else { return true }
        // Once ownership is held, the exemption has done its job and must stop granting anything —
        // otherwise it is a standing licence to rewrite the owner's record forever, since the anchor
        // conditions are public and a later `createdAt` is free. The remaining mutable field is the
        // display name, and renaming the owner under their real, checksum-valid account on a
        // wallet-adjacent surface is the impersonation primitive F-62 was about.
        //
        // **This closes the rename in one direction only, and the other direction is a known,
        // accepted residual — not an oversight.** If the *attacker's* record is the one held first,
        // the genuine owner's record differs from it only in `displayName` (and `joinedAt` /
        // `proofID`), so it fails both disjuncts below and is refused as `.foreignRecordUpdate`
        // forever. The attacker-chosen name is then pinned to the owner's genuine account. See
        // `anchoredExemptionCannotRenameAHeldOwnerRecord`, which pins the direction that *is*
        // closed, and `preClaimPinsTheOwnerDisplayNameAsAKnownResidual`, which pins this one.
        //
        // It is residual rather than fixable here because `isAnchoredSelfDescribing` is forgeable by
        // design: all three of its conditions are public, as its own doc comment says. The two
        // records are therefore indistinguishable to this function, so *every* tie-break rule is
        // symmetric between them, and the choice is only which forgery wins:
        //
        // - First-established wins (what this does) costs the attacker a one-time race.
        // - Last-writer wins — the shape an arrival-order or sequence-based rule produces, since a
        //   later arrival is as free as a later `createdAt` — hands the attacker a permanent,
        //   continuously re-winnable rename. That is **strictly worse**, which is why no ordering
        //   axis is threaded into this projection. Arrival order is not adversary-free either: the
        //   relay is untrusted for confidentiality (see `SocialInviteMint`) and therefore for
        //   ordering, so a hostile relay reorders replay at will.
        //
        // The fix is to stop the forgery, not to re-order it: the transported join proof described
        // on ``downgradedVerification(of:isLocallyMinted:)`` makes the genuine record the only one
        // that can satisfy the anchor, at which point first-established-wins is simply correct.
        //
        // The second disjunct is what keeps this idempotent, and it cannot be replaced by the
        // simpler "held record is not yet owner". `rejectionReason(for:)` is public and
        // `SocialRelayCoordinator` calls it against the *already-reduced* projection, so by then the
        // owner's own record is applied and downgraded to `.pending` — at which point the simpler
        // form reads the owner's genuine envelope as "raising a held record to `.verified`" and
        // refuses the very envelope it just accepted.
        return known.role != .owner
            || known == downgradedVerification(of: identity, isLocallyMinted: false)
    }

    /// Whether a relay-delivered envelope may assert `claimed` as its author's own account, despite
    /// a held record binding that participant to a different one.
    ///
    /// The companion to ``relayMayOverwriteHeldRecord(_:author:)`` on the *author* axis, and without
    /// it that function is unreachable in the case it was written for. Both account rules decide
    /// "already bound" from a record that may itself have arrived over the wire, and
    /// `mismatchedAccount` returns **before the `switch` is entered** — so a pre-claim that names
    /// the anchored party's id with an attacker-chosen account shadows the held-record exemption
    /// entirely and the lock-out stays wide open. The fix that closed the bland pre-claim left the
    /// non-bland one, which is the easier attack: name the victim's id, name your own wallet.
    ///
    /// Narrowed the same way and for the same reason: the anchored party must be naming its *own*
    /// account, and the record being contradicted must not be one this installation established.
    /// Granting it costs nothing an attacker did not already have — bypassing this guard confers no
    /// authority by itself, because every binding event still requires `isLocallyMinted`.
    private func relayMayAssertAnchoredAccount(claimed: String, author: String) -> Bool {
        ownerBootstrapAnchors.contains(author)
            && !locallyEstablishedParticipantIDs.contains(author)
            && SocialAccountIdentity.matches(claimed, author)
    }

    private mutating func apply(_ mutation: SocialQueueMutation) {
        switch mutation {
        case let .acceptProposal(proposalID, item):
            guard !queueItems.contains(where: { $0.acceptedProposalID == proposalID || $0.id == item.id }) else { return }
            queueItems.append(item)
        case let .removeItem(itemID):
            queueItems.removeAll { $0.id == itemID }
        case let .reorder(itemID, destinationIndex):
            guard let current = queueItems.firstIndex(where: { $0.id == itemID }) else { return }
            let item = queueItems.remove(at: current)
            let destination = min(max(0, destinationIndex), queueItems.count)
            queueItems.insert(item, at: destination)
        }
    }

    private func appendUnique<T: Equatable>(_ value: T, to values: inout [T]) {
        if !values.contains(value) { values.append(value) }
    }
}

// Payload bounds for the types `SocialEvent.clampedForStorage` carries.
//
// Participant ids inside a payload use the *same* limit as `SocialEventEnvelope`'s
// `authorParticipantID`, deliberately. Several guards compare the two for equality
// (`vote.participantID != envelope.authorParticipantID` → `.mismatchedAuthor`), so clamping one
// side and not the other would make an over-long author id store as two different strings and the
// event would be permanently inert while diagnostics had already reported it accepted.
extension SocialApprovalVote {
    var clampedForStorage: SocialApprovalVote {
        SocialApprovalVote(
            participantID: String(participantID.prefix(SocialParticipantIdentity.identifierLimit)),
            approved: approved,
            castAt: castAt
        )
    }
}

extension SocialQueueVote {
    var clampedForStorage: SocialQueueVote {
        SocialQueueVote(
            proposalID: proposalID,
            participantID: String(participantID.prefix(SocialParticipantIdentity.identifierLimit)),
            approved: approved,
            castAt: castAt
        )
    }
}

extension SocialQueueProposal {
    var clampedForStorage: SocialQueueProposal {
        SocialQueueProposal(
            id: id,
            mediaItemID: String(mediaItemID.prefix(SocialParticipantIdentity.identifierLimit)),
            title: String(title.prefix(SocialParticipantIdentity.displayNameLimit)),
            proposedByParticipantID: String(
                proposedByParticipantID.prefix(SocialParticipantIdentity.identifierLimit)
            ),
            proposedAt: proposedAt
        )
    }
}

extension SocialQueueItem {
    var clampedForStorage: SocialQueueItem {
        SocialQueueItem(
            id: id,
            mediaItemID: String(mediaItemID.prefix(SocialParticipantIdentity.identifierLimit)),
            title: String(title.prefix(SocialParticipantIdentity.displayNameLimit)),
            acceptedProposalID: acceptedProposalID,
            acceptedAt: acceptedAt
        )
    }
}

// `internal`, not `fileprivate`: the authority mapping is the security contract of this file, so it
// is directly testable rather than only observable through `rejectionReason`'s combined verdict.
extension SocialEvent {
    /// The same event with every relay-controlled free-text field bounded.
    ///
    /// Every `Codable` conformance in this file is synthesized, so a decoded value assigns its
    /// stored properties directly and the clamps written into the initializers never run on wire
    /// data. That made the one place the package *did* bound a payload — `SharedAgentContext` —
    /// ineffective on the only path that can be hostile.
    ///
    /// It matters because the durable log has no size cap and, for a session this installation
    /// merely joined, no release path either: `prune` can only drop a session that reached a
    /// terminal state, and a joined session never derives an `endedAt`. So anything accepted here
    /// is kept for good. `.unsupported` is the sharpest case — it is accepted with no author check
    /// by design, and `isMutatingAfterEnd` is false for it, so it is accepted into an *ended*
    /// session too.
    ///
    /// Applied at the storage boundary rather than in `rejectionReason`, because this is a question
    /// about what we are willing to *keep*, not about whether the author had the right to say it.
    var clampedForStorage: SocialEvent {
        switch self {
        case let .sessionCreated(title, correlationID):
            return .sessionCreated(
                title: String(title.prefix(SocialParticipantIdentity.displayNameLimit)),
                correlationID: String(correlationID.prefix(SocialParticipantIdentity.identifierLimit))
            )
        case let .participantJoined(identity):
            return .participantJoined(identity.clampedForStorage)
        case let .participantUpdated(identity):
            return .participantUpdated(identity.clampedForStorage)
        case let .participantRemoved(participantID):
            return .participantRemoved(
                participantID: String(participantID.prefix(SocialParticipantIdentity.identifierLimit))
            )
        case let .workflowShared(id):
            return .workflowShared(String(id.prefix(SocialParticipantIdentity.identifierLimit)))
        case let .playlistShared(id):
            return .playlistShared(String(id.prefix(SocialParticipantIdentity.identifierLimit)))
        case let .agentContextShared(context):
            // Re-runs `SharedAgentContext.init`, which is where its own clamps live.
            return .agentContextShared(
                SharedAgentContext(
                    id: context.id,
                    title: context.title,
                    summary: context.summary,
                    provenance: context.provenance,
                    dataClassNames: context.dataClassNames,
                    artifactIDs: context.artifactIDs,
                    createdAt: context.createdAt,
                    expiresAt: context.expiresAt
                )
            )
        case let .unsupported(kind):
            return .unsupported(kind: String(kind.prefix(SocialParticipantIdentity.identifierLimit)))
        case let .approvalOpened(draft):
            return .approvalOpened(
                SocialApprovalDraft(
                    id: draft.id,
                    prompt: String(draft.prompt.prefix(SocialEvent.promptLimit)),
                    requiredApprovals: draft.requiredApprovals
                )
            )
        case let .approvalVoteCast(approvalID, vote):
            return .approvalVoteCast(approvalID: approvalID, vote: vote.clampedForStorage)
        case let .queueVoteCast(vote):
            return .queueVoteCast(vote.clampedForStorage)
        case let .queueProposalCreated(proposal):
            return .queueProposalCreated(proposal.clampedForStorage)
        case let .queueMutationAccepted(mutation):
            switch mutation {
            case let .acceptProposal(proposalID, item):
                return .queueMutationAccepted(
                    .acceptProposal(proposalID: proposalID, item: item.clampedForStorage)
                )
            case .removeItem, .reorder:
                return self
            }
        case let .queueSnapshotPublished(snapshot):
            // The sharpest one. `SocialQueueApplier.apply` reconciles this straight into the user's
            // real AuraPlay playlist, and `SocialQueueSnapshot` has no item cap of its own — so a
            // single 16 KiB envelope carrying hundreds of fabricated entries was written verbatim.
            return .queueSnapshotPublished(
                SocialQueueSnapshot(
                    items: snapshot.items.prefix(SocialEvent.queueItemLimit).map(\.clampedForStorage),
                    publishedAt: snapshot.publishedAt
                )
            )
        case let .ritualRunChanged(ritualID, status, artifactIDs, receiptIDs):
            return .ritualRunChanged(
                ritualID: String(ritualID.prefix(SocialParticipantIdentity.identifierLimit)),
                status: status,
                artifactIDs: Array(artifactIDs.prefix(SocialEvent.referenceLimit)),
                receiptIDs: Array(receiptIDs.prefix(SocialEvent.referenceLimit))
            )
        case .sessionEnded, .receiptShared, .artifactShared, .approvalResolved,
             .queueMutationRejected:
            // Genuinely nothing to bound: a `Date`, a `UUID`, or an enum. Listed rather than
            // defaulted, so a new case with a `String` or collection payload has to decide.
            //
            // The earlier version of this arm also listed `approvalOpened`, `approvalVoteCast`,
            // `ritualRunChanged`, `queueProposalCreated`, `queueVoteCast`, `queueMutationAccepted`
            // and `queueSnapshotPublished` under a comment claiming they carried "UUIDs, enums,
            // counts and already-bounded value types". That was simply false — between them they
            // carry seven unbounded `String`s and three uncapped arrays.
            return self
        }
    }

    /// Free-text prompt shown to a human in an approval, so it is bounded like a display string
    /// rather than like an identifier.
    static let promptLimit = 2_000
    /// Items one published queue snapshot may carry. Well above a real shared playlist.
    static let queueItemLimit = 500
    /// Artifact/receipt references one ritual-run event may carry.
    static let referenceLimit = 200

    var isMutatingAfterEnd: Bool {
        switch self {
        case .sessionEnded, .unsupported:
            return false
        default:
            return true
        }
    }

    /// Where this event sits in the per-session storage ceiling's eviction order.
    ///
    /// The ceiling in ``SocialEventLogStore/appendInbound(_:topic:receivedAt:)`` originally evicted
    /// in arrival order, which is right as a tie-break and wrong as the *only* axis: the rows that
    /// have been in the log longest are the session's genuine early history, so a flood arriving
    /// *after* a session is established evicted exactly the records whose loss cannot be recovered.
    /// Without the peers' `participantJoined` records the session has no owner, `sessionEnded` is
    /// refused as `.ownerRequired`, no `endedAt` is derivable, and `prune` can never release it.
    ///
    /// **The classification is exhaustive rather than heuristic, and that rests on one fact worth
    /// stating plainly: a relay peer can only ever get two kinds of event into the log.** Every
    /// `.bindingAuthor` and `.ownerAuthor` event requires `isLocallyMinted`, and `.sessionCreated`
    /// is refused off the wire outright, so a relay-delivered envelope that survives
    /// `rejectionReason` is either `.unsupported` or a participant record. Nothing else is
    /// reachable. So ranking those two against each other is not a judgement about which genuine
    /// history matters least — it is the whole attack surface.
    ///
    /// - ``inertCarrier`` is `.unsupported`, the one case that provably grants nothing:
    ///   `rejectionReason` has no rule for it, `apply` does nothing with it, `isMutatingAfterEnd` is
    ///   false for it, and no consumer outside this package switches on it. It is also the cheapest
    ///   flood available — no author check at all — so it is both the most disposable content the
    ///   log can hold and the content a hostile peer reaches for first. Losing it costs
    ///   forward-compatibility replay for payloads this build cannot interpret anyway.
    /// - ``membership`` is the participant records, which establish who the session's people are.
    ///   Evicted **last**, and — uniquely — newest-first; see ``evictsNewestFirst``.
    /// - ``content`` is everything else. Relay-unreachable in practice (all of it requires local
    ///   provenance), so in a real log this class holds only locally-minted rows, which the ceiling
    ///   never evicts anyway. It exists so the ordering is total for a caller using the public
    ///   ``SocialEventLogStore/appendInbound(_:topic:receivedAt:)`` directly, and for logs written
    ///   before the guards above existed.
    var evictionClass: EvictionClass {
        switch self {
        case .unsupported:
            return .inertCarrier
        case .participantJoined, .participantUpdated, .participantRemoved:
            return .membership
        case .sessionCreated, .sessionEnded, .receiptShared, .artifactShared, .workflowShared,
             .playlistShared, .agentContextShared, .approvalOpened, .approvalVoteCast,
             .approvalResolved, .ritualRunChanged, .queueProposalCreated, .queueVoteCast,
             .queueMutationAccepted, .queueMutationRejected, .queueSnapshotPublished:
            return .content
        }
    }

    /// Whether this event *establishes* the membership record it names, rather than retiring it.
    ///
    /// The ceiling protects the anchored owner's record by protecting one row, so it has to pick the
    /// right row, and "which participant is this row about" is deliberately a different question —
    /// one for which `.participantRemoved` is as much about the anchored party as a join
    /// is. Letting a tombstone take the slot would hand it to the one membership event that can
    /// never legitimately name the anchored owner: `participantRemoved` is `.ownerAuthor`, and the
    /// owner removing itself is refused as `.selfRemoval`, so no honest `.participantRemoved(owner)`
    /// exists. A forged one landing first would then hold the protected slot while the owner's
    /// genuine record went back to being evictable — the exact unrecoverable loss the anchor exists
    /// to prevent.
    ///
    /// `rejectionReason` already refuses such an envelope off the relay as `.impersonatedAuthor`, so
    /// this is not reachable through `SocialRelayCoordinator` today. It is checked here anyway
    /// because ``SocialEventLogStore/appendInbound(_:topic:receivedAt:)`` is public and is documented
    /// as the one place admission control lives — a ceiling that silently depends on a gate in
    /// another type is a gate that will eventually be moved.
    var establishesMembershipRecord: Bool {
        switch self {
        case .participantJoined, .participantUpdated:
            return true
        default:
            return false
        }
    }

    /// The role a membership event declares for the participant it establishes, or `nil` for every
    /// other case.
    ///
    /// The ceiling needs this because naming the anchored participant is **not** the same claim as
    /// being that participant's owner record, and only the second is worth a protected slot. The
    /// anchor identifies *who* the inviter is; it says nothing about which of the rows naming them
    /// actually establishes ownership. A hostile peer that pre-claims the anchored id with any
    /// non-owner role takes the slot on arrival order alone, and the genuine owner record — landing
    /// afterwards, as it must on a joined session — stays evictable and is deleted by the next
    /// envelope. That leaves the session permanently ownerless: `sessionEnded` is refused as
    /// `.ownerRequired`, no `endedAt` is derivable, and `prune` can never release the graph.
    ///
    /// Requiring `.owner` here closes that without pretending to solve the harder problem. A
    /// pre-claim that *does* declare `.owner` still takes the slot, but then the session has an
    /// owner and the loss is the bounded display-name residual documented on
    /// ``SocialSessionProjection`` — the record is `.pending`, it cannot author binding events, and
    /// the account binding is still the genuine one. The unrecoverable outcome is what the anchor
    /// is for, and it is the one this rules out.
    var establishedMembershipRole: SharedRole? {
        guard establishesMembershipRecord else { return nil }
        switch self {
        case let .participantJoined(identity), let .participantUpdated(identity):
            return identity.role
        default:
            return nil
        }
    }

    /// The verification state a membership event declares, or `nil` for every other case.
    ///
    /// Companion to ``establishedMembershipRole``, and read for the same kind of reason: the storage
    /// ceiling has to rank rows by whether the projection could honor them, and
    /// ``SocialSessionProjection/RejectionReason/untrustedLocalIdentity`` is decided by this field
    /// alone. A relay-delivered `.local` record is refused unconditionally — provenance is the one
    /// claim the wire cannot make about itself — so a row carrying it establishes no owner no matter
    /// what else it says.
    var establishedMembershipVerificationState: SocialParticipantVerificationState? {
        guard establishesMembershipRecord else { return nil }
        switch self {
        case let .participantJoined(identity), let .participantUpdated(identity):
            return identity.verificationState
        default:
            return nil
        }
    }

    /// Whether this event is `author` establishing itself as the session's owner.
    ///
    /// **The storage ceiling's half of the predicate the projection decides ownership with, so that
    /// the two cannot disagree about which row is the owner's record.** Combined with the anchor set
    /// by the caller, this is exactly ``SocialSessionProjection``'s `isAnchoredSelfDescribing` plus
    /// the `role == .owner` direction check that both of that function's callers already apply —
    /// ``SocialSessionProjection/rejectionReason(for:isLocallyMinted:)``'s `roleEscalation` guard via
    /// `ownerBootstrapIsOpen`, and `relayMayOverwriteHeldRecord`'s `guard identity.role == .owner`.
    ///
    /// Asking anything *weaker* than the projection's rule is what every round of this defect has
    /// been. The protected slot exists so that a session always retains a row the projection will
    /// read as its owner; a row that satisfies a weaker condition is a row the projection may refuse,
    /// and then the slot is held by something that keeps nothing alive. Three fields have each been
    /// the weak point in turn: naming the anchored party (a replay flood filled the tier), being any
    /// membership row about them (a tombstone took the slot), and declaring any role (a `.viewer`
    /// pre-claim took it). `role == .owner` alone is still weaker — it omits the *account*, so a
    /// `participantJoined` naming the anchored party's id with the attacker's wallet and `.owner`
    /// holds the slot while `roleEscalation` refuses the very same row at projection time, because
    /// ``SocialParticipantIdentity/describesSelf(author:)`` is false for it. The owner's genuine
    /// record is then left evictable and the next envelope deletes it: `hasOwner` is false,
    /// `sessionEnded` is refused as `.ownerRequired`, no `endedAt` is derivable, and `prune` can
    /// never release the graph.
    ///
    /// Stating it as one shared predicate rather than a fourth field comparison is the point. The
    /// ceiling no longer has to pick the *right* row on an ordering axis the sender controls.
    ///
    /// **It is the payload half of the question, and on its own it is still not "the projection
    /// honors this row".** Two of the fields `rejectionReason` reads about an ownership claim are
    /// not in the payload at all — the record's `verificationState`, which refuses `.local` off the
    /// wire outright, and the envelope's `authorCAIP10Account`, which its very first guard compares
    /// against the held record. A row can satisfy everything below and still establish no owner, so
    /// protecting it would hold the slot for nothing while the genuine record stayed evictable —
    /// the same failure as every round before, one layer out. The ceiling therefore asks this
    /// through ``SocialEventEnvelope/grantsSelfDescribedOwnership`` and ranks the candidates with
    /// ``SocialEventEnvelope/selfDescribedOwnershipProtectionRank``, which covers the other two.
    ///
    /// `rejectionReason` refuses the non-self-describing form off the relay as `.roleEscalation`, so
    /// it is not reachable through `SocialRelayCoordinator` today. It is checked here for the same
    /// reason ``establishesMembershipRecord`` is: ``SocialEventLogStore/appendInbound(_:topic:receivedAt:)``
    /// is public and is documented as the one place admission control lives.
    func grantsSelfDescribedOwnership(author: String) -> Bool {
        guard establishesMembershipRecord, establishedMembershipRole == .owner else { return false }
        switch self {
        case let .participantJoined(identity), let .participantUpdated(identity):
            return identity.describesSelf(author: author)
        default:
            return false
        }
    }

    /// The eviction tiers, ordered: the lowest `rawValue` is sacrificed first.
    ///
    /// Listed rather than defaulted in ``evictionClass``, so a new `SocialEvent` case has to state
    /// where it sits rather than silently inheriting the most-protected tier.
    enum EvictionClass: Int, Equatable, Sendable {
        case inertCarrier = 0
        case content = 1
        case membership = 2

        /// Whether this tier evicts its **newest** member rather than its oldest.
        ///
        /// True only for ``membership``, and it is what closes the tiering's own bypass. Ranking
        /// `.unsupported` lowest stops the cheapest flood, but a `participantJoined` carrying a
        /// fresh participant id is accepted off the relay by design — a session you joined has to
        /// stay legible — and costs an attacker exactly one envelope, the same as `.unsupported`.
        /// So a flood of fresh-id joins lands in this tier alongside the genuine records and,
        /// under oldest-first, evicts the owner's record just as before. The tier would have been
        /// worth nothing against an attacker who read it.
        ///
        /// Newest-first inverts that. For membership specifically, first-established-wins is
        /// already the semantics the projection enforces — `.foreignRecordUpdate` holds that a
        /// record this installation already has is absolute — so sacrificing the newest is the
        /// eviction order that *agrees* with the authority model instead of fighting it. A flood
        /// arriving after the session is established now evicts its own most recent row on each
        /// append: it churns one slot and the genuine early records are untouchable.
        ///
        /// Victim selection runs before the insert, so an arriving envelope is never its own
        /// victim; the ceiling still evicts and never refuses.
        ///
        /// **This ordering alone does not protect the owner, and must not be read as if it does.**
        /// It protects whichever genuine records happen to be *early*, and an attacker picks that:
        /// an invite holder who floods the moment it joins owns every old slot, after which the
        /// newest membership row is always the most recently arrived *genuine* one — so the owner's
        /// relay-delivered record lands and is deleted by the very next envelope, and a joined
        /// session can never record its owner at all. Inverting the arrival order swaps which flood
        /// timing wins; it does not decide between a flood row and a genuine one, because on the
        /// wire those two are indistinguishable. The decision that actually holds is made one
        /// component earlier in the ranking key, on the owner anchor, which is local provenance the
        /// sender cannot forge. See ``SocialEvent/grantsSelfDescribedOwnership(author:)``.
        ///
        /// Residual, accepted: once this tier is at the ceiling, an *unanchored* late joiner does
        /// not stick, and successive joiners churn the same slot.
        ///
        /// An earlier draft of this note claimed reaching that state needs
        /// ``SocialRetentionPolicy/maximumStoredEnvelopesPerSession`` *genuine* participant records
        /// in one session, and that is simply false — it is reachable by an attacker, for one
        /// envelope per slot, with the same fresh-id joins this very paragraph says are accepted off
        /// the relay by design. The residual is therefore adversarial, not merely a large-session
        /// edge case, and the honest statement of it is: while a flood is in progress, a *new*
        /// member's record may not persist on this device.
        ///
        /// It is residual rather than fixable here because the two rows are indistinguishable on
        /// the wire, so every ordering over them is symmetric — the alternative, oldest-first, simply
        /// trades it for a late flood permanently deleting genuine records the log already holds,
        /// which is worse because that loss does not end when the flood does. What must hold at any
        /// size, and does, is that the one unrecoverable loss is out of reach: the anchored owner's
        /// record is protected by local provenance, so `hasOwner`, `sessionEnded` and `prune` keep
        /// working at any flood volume and any flood timing. Closing the rest needs the transported
        /// join proof described on ``SocialSessionProjection/downgradedVerification(of:isLocallyMinted:)``,
        /// which makes a flood row distinguishable in the first place.
        var evictsNewestFirst: Bool { self == .membership }
    }

    /// What an envelope's author must prove before this event may be applied.
    ///
    /// **One exhaustive mapping, deliberately replacing two independent booleans.** The old shape
    /// was `requiresVerifiedAuthor` plus `requiresOwnerAuthor`, and the second carried
    /// `default: return false` — so a newly added `SocialEvent` case was silently *not* owner-gated,
    /// and because the two were read at separate points in an ordered guard chain, a case answering
    /// `false` to both bypassed every author check in the function. That is not hypothetical: it is
    /// exactly how a relay envelope came to rewrite the host's own owner record, since
    /// `.participantUpdated` answers `false` to both and the only remaining check compared two
    /// attacker-controlled wire fields against each other.
    ///
    /// `rejectionReason` has produced a Blocker in three separate audit rounds, every one of them
    /// an *interaction* between guards rather than a fault inside one. A single exhaustive `switch`
    /// with **no `default`** is the structural fix: adding a `SocialEvent` case now fails to
    /// compile until its authority is stated, which is the property the booleans could not provide.
    var authority: EventAuthority {
        switch self {
        // No author requirement *at this layer* — each of these carries its own rule in
        // `rejectionReason`'s `switch`, and `.eventSpecific` is only honest while that stays true.
        //
        // Participant records are policed by provenance, foreign-record writes, role escalation and
        // account binding. `sessionCreated` is refused off the wire outright. `unsupported` applies
        // nothing, so it grants no state.
        //
        // The earlier version of this comment asserted that `sessionCreated` "only ever fills in a
        // title and a correlation id on first write" and left it at that — but it had no arm in the
        // `switch` at all, so it fell through to a `default: break` and was accepted unauthenticated
        // from the relay. A bucket meaning "policed elsewhere" is only as good as the audit that
        // checks *elsewhere* exists; the `switch` is now exhaustive so the compiler performs that
        // audit.
        case .sessionCreated, .participantJoined, .participantUpdated, .unsupported:
            return .eventSpecific

        // Owner-only. `approvalResolved` belongs here because it writes `explicitResolution`, which
        // outranks the vote tally — gated on binding authority alone, any single verified
        // collaborator could declare a 3-of-3 approval `.approved` with zero votes cast, defeating
        // the multi-party sign-off primitive this type exists to provide.
        case .participantRemoved, .sessionEnded, .approvalResolved:
            return .ownerAuthor

        // Binding: changes shared state that other members are entitled to rely on.
        case .receiptShared, .artifactShared, .workflowShared, .playlistShared, .agentContextShared,
             .approvalOpened, .approvalVoteCast, .ritualRunChanged, .queueProposalCreated,
             .queueVoteCast, .queueMutationAccepted, .queueMutationRejected, .queueSnapshotPublished:
            return .bindingAuthor
        }
    }
}

// `internal` for the same reason the authority mapping is: the storage ceiling's half of the
// ownership predicate is a security contract, so it is directly testable rather than only
// observable through eviction outcomes.
extension SocialEventEnvelope {
    /// ``SocialEvent/grantsSelfDescribedOwnership(author:)`` asked of this row's own author.
    ///
    /// The envelope form exists because the payload is only *part* of what the projection reads
    /// about an ownership claim — see ``selfDescribedOwnershipProtectionRank``, which covers the
    /// rest. Routing the ceiling through one envelope-level entry point is what stops the two from
    /// being consulted separately and drifting apart again.
    var grantsSelfDescribedOwnership: Bool {
        event.grantsSelfDescribedOwnership(author: authorParticipantID)
    }

    /// Where this row ranks among the candidates for one anchored participant's protected slot,
    /// lowest first.
    ///
    /// The protected slot is one row per anchor — it has to be, or the tier is attacker-fillable —
    /// so something must choose between candidates, and the only choice that is *safe* is the one
    /// that prefers a row the projection can actually honor. Arrival order cannot do that: it is a
    /// property of the sender's timing, not of the row.
    ///
    /// Two fields decide it, and both sit outside ``SocialEvent/grantsSelfDescribedOwnership(author:)``
    /// because neither is reachable from the payload alone:
    ///
    /// - A relay-delivered record claiming `.local` is refused unconditionally as
    ///   ``SocialSessionProjection/RejectionReason/untrustedLocalIdentity``. Every candidate here is
    ///   relay-delivered by construction (the ceiling's candidate set excludes locally-minted and
    ///   pending-outbound ids), so such a row establishes no owner, ever.
    /// - `authorCAIP10Account` is on the *envelope*, not in the record, and
    ///   ``SocialSessionProjection/rejectionReason(for:isLocallyMinted:)`` reads it in its very first
    ///   guard. A row whose author account names someone other than its author contradicts the
    ///   self-description its payload asserts, and is refused as
    ///   ``SocialSessionProjection/RejectionReason/mismatchedAccount`` the moment any record for that
    ///   participant is already held.
    ///
    /// **A rank rather than a filter, and that is the whole safety argument.** Excluding these rows
    /// outright would be a regression, not a tightening: the second case is refused only
    /// *conditionally*, so a log can hold one as its sole honored owner record — once such a row is
    /// applied, the genuine record that follows differs from it and is refused as
    /// ``SocialSessionProjection/RejectionReason/foreignRecordUpdate``, which is reachable through
    /// the relay gate. Dropping it from the protected set would leave that session's only owner row
    /// evictable and hand back exactly the unrecoverable loss the anchor exists to prevent. Ranking
    /// keeps the tier bounded at one row per anchor *and* never empties it on a judgement the row's
    /// own fields cannot settle: a better candidate displaces it if one ever arrives, and the
    /// selection is recomputed from the stored set on every append, so nothing is locked in.
    var selfDescribedOwnershipProtectionRank: Int {
        if event.establishedMembershipVerificationState == .local { return 1 }
        if let claimed = authorCAIP10Account,
           !SocialAccountIdentity.matches(claimed, authorParticipantID) {
            return 1
        }
        return 0
    }
}

/// The author requirement for a ``SocialEvent``, as one ordered scale.
///
/// Ordered on purpose: `ownerAuthor` is `bindingAuthor` *plus* ownership, so the checks compose
/// rather than being independently remembered at two points in the chain. That composition is what
/// stops the two requirements from drifting apart.
enum EventAuthority: Equatable, Sendable {
    /// Policed by the event's own rules rather than by the author binding.
    case eventSpecific
    /// The author must be binding-capable **and** the envelope locally minted.
    case bindingAuthor
    /// Everything `bindingAuthor` requires, and the author must be the session owner.
    case ownerAuthor

    /// Whether the author binding applies. True for both authority levels, which is the invariant
    /// the old pair of booleans had to restate — and `participantRemoved`/`sessionEnded`/
    /// `approvalResolved` had to appear in *both* lists to get it.
    var requiresBindingAuthor: Bool { self != .eventSpecific }
}
