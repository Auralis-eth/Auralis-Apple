import Foundation

// Persistence seams for the human-coordination stores (P1-SOCIAL-101/102).
//
// These keep `SocialCore` a pure domain leaf: the protocols describe *what* survives a relaunch, and
// the app supplies a concrete backing (UserDefaults/JSON) without `SocialCore` taking a storage
// dependency. The default implementations are ephemeral, so `SharedSessionStore()` / `RitualStore()`
// behave exactly as before in tests and previews.

// MARK: - Shared sessions (P1-SOCIAL-101)

/// Durable backing for the set of shared sessions. `SharedSession` is `Codable`, so the whole graph —
/// participants, shared receipt/artifact/playbook IDs, and collaborative approvals with their votes —
/// round-trips as one unit.
public protocol SharedSessionPersisting: Sendable {
    func load() async -> [SharedSession]
    func save(_ sessions: [SharedSession]) async
}

/// The default no-op backing: sessions live only for the process lifetime.
public struct EphemeralSharedSessionPersistence: SharedSessionPersisting {
    public init() { }
    public func load() async -> [SharedSession] { [] }
    public func save(_ sessions: [SharedSession]) async { }
}

// MARK: - Rituals (P1-SOCIAL-102)

/// The user intent worth persisting for rituals: which built-ins are enabled, any user-defined
/// (custom) rituals, and each ritual's last-run timestamp (so scheduled rituals stay due-correct
/// across launches). The built-in catalog structure itself is *not* persisted — it stays authoritative
/// in code so app updates can change a ritual's playbooks without a stale copy overriding them.
public struct RitualPersistedState: Codable, Sendable, Equatable {
    public var enabledIDs: Set<String>
    public var customRituals: [RitualDefinition]
    public var lastRuns: [String: Date]
    public var completedOccurrenceIDs: Set<RitualOccurrenceID>

    public init(
        enabledIDs: Set<String> = [],
        customRituals: [RitualDefinition] = [],
        lastRuns: [String: Date] = [:],
        completedOccurrenceIDs: Set<RitualOccurrenceID> = []
    ) {
        self.enabledIDs = enabledIDs
        self.customRituals = customRituals
        self.lastRuns = lastRuns
        self.completedOccurrenceIDs = completedOccurrenceIDs
    }

    private enum CodingKeys: String, CodingKey {
        case enabledIDs, customRituals, lastRuns, completedOccurrenceIDs
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabledIDs = try container.decodeIfPresent(Set<String>.self, forKey: .enabledIDs) ?? []
        customRituals = try container.decodeIfPresent([RitualDefinition].self, forKey: .customRituals) ?? []
        lastRuns = try container.decodeIfPresent([String: Date].self, forKey: .lastRuns) ?? [:]
        completedOccurrenceIDs = try container.decodeIfPresent(
            Set<RitualOccurrenceID>.self,
            forKey: .completedOccurrenceIDs
        ) ?? []
    }
}

/// Durable backing for ritual enabled-state, custom rituals, and last-run timestamps.
public protocol RitualStatePersisting: Sendable {
    func load() async -> RitualPersistedState
    func save(_ state: RitualPersistedState) async
}

/// The default no-op backing: enabled toggles and last-run state reset to the catalog each launch.
public struct EphemeralRitualStatePersistence: RitualStatePersisting {
    public init() { }
    public func load() async -> RitualPersistedState { RitualPersistedState() }
    public func save(_ state: RitualPersistedState) async { }
}

// MARK: - Sync event log (Social v1)

public struct SocialRelayCursor: Equatable, Sendable, Codable {
    public var topic: String
    public var lastReceivedAt: Date?
    public var lastEventID: UUID?

    public init(topic: String, lastReceivedAt: Date? = nil, lastEventID: UUID? = nil) {
        self.topic = topic
        self.lastReceivedAt = lastReceivedAt
        self.lastEventID = lastEventID
    }
}

public struct SocialEventLogSnapshot: Equatable, Sendable, Codable {
    public var envelopes: [SocialEventEnvelope]
    public var pendingOutboundEventIDs: [UUID]
    public var invites: [SocialInvite]
    public var replayCursors: [String: SocialRelayCursor]
    public var syncStates: [UUID: SocialSyncState]
    /// The envelopes this installation authored, as opposed to received from a relay.
    ///
    /// Deliberately stored *beside* the envelopes rather than on them: `SocialEventEnvelope` is the
    /// wire format, so a provenance flag carried inside it would cross the relay and be forgeable by
    /// anyone holding the invite — which is precisely the claim it is meant to settle. Recorded by
    /// ``SocialEventLogStore`` from the entry point used (``SocialEventLogStore/appendLocal(_:)-(Array)``
    /// and ``SocialEventLogStore/enqueueOutbound(_:)-(Array)`` mint; ``SocialEventLogStore/appendInbound(_:topic:receivedAt:)``
    /// does not), and never transmitted.
    public var locallyMintedEventIDs: Set<UUID>
    /// The owner-bootstrap anchors this installation has established for a session, kept for as long
    /// as the session graph itself, keyed by session id.
    ///
    /// Recorded by ``SocialEventLogStore/saveInvite(_:)`` from the invite's `inviterParticipantID`,
    /// because an invite arrives out-of-band and is the one thing in a *joined* session that did not
    /// travel over the relay. It is held here rather than read back off the invite because an invite
    /// is a short-lived credential and the anchor is a durable fact: `SocialInviteMint.defaultTTL` is
    /// 7 days and ``SocialRetentionPolicy/expiredInviteRetention`` is another 7, so every joined
    /// session reaches a day when ``SocialEventLogStore/prune(now:policy:)`` deletes the invite — and
    /// the normal joiner flow may forget it even sooner via
    /// ``SocialEventLogStore/removeInvite(sessionID:)``.
    ///
    /// Tying the anchor to the invite's lifetime meant that day silently un-owned the session: the
    /// owner's relay-delivered `participantJoined` was refused as
    /// ``SocialSessionProjection/RejectionReason/roleEscalation``, every record the owner had shared
    /// became ``SocialSessionProjection/RejectionReason/unverifiedAuthor``, and with no `endedAt`
    /// derivable the graph could never be ended or pruned again.
    ///
    /// Dropping the invite's secrets is not a statement that the inviter never vouched for the
    /// session, so forgetting an invite leaves the anchor; it is cleared only when the session graph
    /// it anchors is pruned, which also keeps this table from growing without bound.
    public var ownerAnchorsBySessionID: [UUID: Set<String>]
    /// The order relay-delivered envelopes actually *arrived*, which is the only ordering axis in
    /// this type the wire does not control.
    ///
    /// Stored beside the envelopes for the same reason `locallyMintedEventIDs` is: it is a local
    /// observation, not a wire fact, so carrying it inside `SocialEventEnvelope` would hand it to
    /// the sender. It exists because `envelopes` is **not** in insertion order — every mutation ends
    /// in `normalized()`, which sorts by `createdAt`, an attacker-chosen payload field. Eviction
    /// read "the first evictable index" as "the longest-held envelope" and it is not: a flood
    /// claiming `createdAt = .distantFuture` sorts *last*, so every eviction fell on the session's
    /// genuine early history — the peers' `participantJoined` records first, which is the one loss
    /// that cannot be recovered, because without them the session has no owner and `prune` can never
    /// release it. The attacker chose which rows died, in order, and kept its own.
    ///
    /// Rows written before this table existed decode with no entry and sort as 0, i.e. they are
    /// evicted before anything recorded since. That is the correct reading — they are the oldest
    /// content in the log — and it is self-healing, because every envelope admitted after the
    /// upgrade is sequenced.
    public var inboundSequenceByEventID: [UUID: Int]

    /// The range ``inboundSequenceByEventID`` is held to, and it is a bound at **both** ends because
    /// the value is used in two different ways.
    ///
    /// As a *sort key* it is negated — ``SocialEvent/EvictionClass/evictsNewestFirst`` ranks the
    /// membership tier by `-sequence` — and `-Int.min` is not representable. As a *counter* it is
    /// incremented: `appendInbound` allocates the next arrival order as `max + 1`, and `Int.max + 1`
    /// is not representable either. Flooring alone covered the first and left the second, which is
    /// the same crash by the same route: one out-of-range entry kills the process on the next
    /// inbound envelope, and kills it again on every relaunch, because the table is reloaded from
    /// the payload that carried it.
    ///
    /// Every value this package writes is `max + 1` starting at 1 and is bounded in practice by the
    /// number of envelopes ever admitted, so nothing legitimate is touched. The bound exists because
    /// this table is decoded from persistence — where `Codable` assigns straight through — and
    /// because the memberwise initializer above is `public`. The ceiling is well below `Int.max` so
    /// that the allocation below it cannot overflow either; collapsing two saturated entries into a
    /// tie is harmless, because every ranking that reads this breaks ties on the envelope id.
    static let inboundSequenceRange = 0...(Int.max / 2)

    public init(
        envelopes: [SocialEventEnvelope] = [],
        pendingOutboundEventIDs: [UUID] = [],
        invites: [SocialInvite] = [],
        replayCursors: [String: SocialRelayCursor] = [:],
        syncStates: [UUID: SocialSyncState] = [:],
        locallyMintedEventIDs: Set<UUID> = [],
        ownerAnchorsBySessionID: [UUID: Set<String>] = [:],
        inboundSequenceByEventID: [UUID: Int] = [:]
    ) {
        self.envelopes = envelopes
        self.pendingOutboundEventIDs = pendingOutboundEventIDs
        self.invites = invites
        self.replayCursors = replayCursors
        self.syncStates = syncStates
        self.locallyMintedEventIDs = locallyMintedEventIDs
        self.ownerAnchorsBySessionID = ownerAnchorsBySessionID
        self.inboundSequenceByEventID = inboundSequenceByEventID
    }

    private enum CodingKeys: String, CodingKey {
        case envelopes, pendingOutboundEventIDs, invites, replayCursors, syncStates
        case locallyMintedEventIDs, ownerAnchorsBySessionID, inboundSequenceByEventID
    }

    /// Forward-compatible decode, like ``SharedSession`` and ``RitualPersistedState``.
    ///
    /// A payload written before provenance existed has no `locallyMintedEventIDs`, and there is no
    /// way to reconstruct it after the fact — `pendingOutboundEventIDs` only covers events not yet
    /// published. It therefore decodes as empty, the fail-closed reading: a pre-upgrade `.local`
    /// participant record stops projecting, which loses some historical ritual-run *display* but
    /// grants no authority. Treating the absent key as "all mine" would have been fail-open for any
    /// log written while the relay flag was enabled.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        envelopes = try container.decodeIfPresent([SocialEventEnvelope].self, forKey: .envelopes) ?? []
        pendingOutboundEventIDs = try container.decodeIfPresent([UUID].self, forKey: .pendingOutboundEventIDs) ?? []
        invites = try container.decodeIfPresent([SocialInvite].self, forKey: .invites) ?? []
        replayCursors = try container.decodeIfPresent([String: SocialRelayCursor].self, forKey: .replayCursors) ?? [:]
        syncStates = try container.decodeIfPresent([UUID: SocialSyncState].self, forKey: .syncStates) ?? [:]
        locallyMintedEventIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .locallyMintedEventIDs) ?? []
        // Same fail-closed reading as the provenance above: a payload written before anchors existed
        // decodes as empty. A joined session in such a log keeps its anchor only while its invite is
        // still present, which is the pre-upgrade behavior, and the next `saveInvite` re-establishes
        // it durably.
        ownerAnchorsBySessionID = try container.decodeIfPresent(
            [UUID: Set<String>].self,
            forKey: .ownerAnchorsBySessionID
        ) ?? [:]
        // Absent for any log written before arrival order was recorded. Decoding as empty makes
        // every pre-upgrade row sort as 0 — evicted first, which is what "oldest" means for content
        // whose arrival we never observed — and the table refills from the next inbound append.
        inboundSequenceByEventID = try container.decodeIfPresent(
            [UUID: Int].self,
            forKey: .inboundSequenceByEventID
        ) ?? [:]
    }

    /// The reduced state for one session, with this log's own provenance supplied automatically.
    ///
    /// Prefer this to calling ``SocialSessionProjection/reduce(_:sessionID:locallyMintedEventIDs:ownerBootstrapAnchors:)``
    /// with a bare envelope array: the array form defaults to trusting nothing, so a caller that
    /// forgets the provenance silently drops every locally-authored `.local` participant and can
    /// bootstrap no owner at all.
    public func projection(sessionID: UUID) -> SocialSessionProjection {
        SocialSessionProjection.reduce(
            envelopes,
            sessionID: sessionID,
            locallyMintedEventIDs: locallyMintedEventIDs,
            ownerBootstrapAnchors: ownerBootstrapAnchors(sessionID: sessionID)
        )
    }

    /// The participants this installation knows, from outside the relay, could own `sessionID`.
    ///
    /// An invite is the root of trust for a session you *joined*: it arrives out-of-band — scanned
    /// from the person who showed it to you — so its `inviterParticipantID` is the one party in the
    /// session whose claim to it did not travel over the relay. For a session you *created*, the
    /// anchor is provenance instead, and `reduce` reads that from `locallyMintedEventIDs`.
    ///
    /// Scoped to the one session, not the whole invite list: an invite to session A says nothing
    /// about who may own session B, and a single shared anchor set would let an inviter you trusted
    /// once bootstrap ownership of every other session in the log.
    ///
    /// Read from ``ownerAnchorsBySessionID`` as well as the live invite list, because the invite that
    /// established the anchor is retention-bounded while the session it anchors is not. The invite
    /// list is still consulted so a log written before anchors were recorded keeps working.
    func ownerBootstrapAnchors(sessionID: UUID) -> Set<String> {
        let fromInvites = invites
            .filter { $0.sessionID == sessionID }
            .map(\.inviterParticipantID)
        return Set((fromInvites + Array(ownerAnchorsBySessionID[sessionID] ?? [])).filter { !$0.isEmpty })
    }
}

public protocol SocialEventLogPersisting: Sendable {
    func load() async -> SocialEventLogSnapshot
    func save(_ snapshot: SocialEventLogSnapshot) async
}

public struct EphemeralSocialEventLogPersistence: SocialEventLogPersisting {
    public init() { }
    public func load() async -> SocialEventLogSnapshot { SocialEventLogSnapshot() }
    public func save(_ snapshot: SocialEventLogSnapshot) async { }
}

public struct SocialRetentionPolicy: Equatable, Sendable {
    public let terminalSessionRetention: TimeInterval
    public let expiredInviteRetention: TimeInterval

    /// The most relay-delivered envelopes one session may hold.
    ///
    /// A *size* axis, deliberately separate from the two *age* axes above, because age cannot bound
    /// a joined session: `prune` releases a session only once it has a terminal state, and a
    /// session this installation joined never derives one (the owner's `sessionEnded` arrives over
    /// the relay and is refused as unproven). That left relay-accepted content with no bound at all
    /// in either dimension.
    ///
    /// Well above any plausible real session — a collaborative ritual emits a handful of events per
    /// run — and low enough that the worst case is bounded disk rather than unbounded.
    public let maximumStoredEnvelopesPerSession: Int

    public init(
        terminalSessionRetention: TimeInterval = 90 * 24 * 60 * 60,
        expiredInviteRetention: TimeInterval = 7 * 24 * 60 * 60,
        maximumStoredEnvelopesPerSession: Int = 5_000
    ) {
        self.terminalSessionRetention = max(0, terminalSessionRetention)
        self.expiredInviteRetention = max(0, expiredInviteRetention)
        self.maximumStoredEnvelopesPerSession = max(1, maximumStoredEnvelopesPerSession)
    }
}

public struct SocialPruneResult: Equatable, Sendable {
    public let removedSessionCount: Int
    public let removedEnvelopeCount: Int
    public let removedInviteCount: Int
}

public actor SocialEventLogStore {
    private let persistence: any SocialEventLogPersisting
    private var snapshot: SocialEventLogSnapshot?
    private var load: Task<SocialEventLogSnapshot, Never>?
    private var lastWrite: Task<Void, Never>?

    /// The admission bound applied to relay-delivered envelopes.
    ///
    /// Stored rather than passed, because admission happens on every inbound append while `prune`
    /// runs occasionally — and the two must agree about what the log is allowed to hold. `prune`
    /// keeps its own parameter so a caller can sweep with a different *age* policy without
    /// redefining the size ceiling under it.
    private let retentionPolicy: SocialRetentionPolicy

    public init(
        persistence: any SocialEventLogPersisting = EphemeralSocialEventLogPersistence(),
        retentionPolicy: SocialRetentionPolicy = SocialRetentionPolicy()
    ) {
        self.persistence = persistence
        self.retentionPolicy = retentionPolicy
    }

    /// Appends a relay-delivered envelope and advances the topic's replay watermark.
    ///
    /// `receivedAt` is the *local* clock reading for when this envelope arrived. The watermark is
    /// clamped to it and is only ever moved forward, because `envelope.createdAt` is an attacker- and
    /// relay-controlled payload field with no inherent bound:
    ///
    /// - Without the clamp, a single envelope claiming `createdAt = .distantFuture` pushed the cursor
    ///   to year 4001. Every later resume then asked the relay for events "since 4001" and silently
    ///   skipped all genuine traffic — a permanent, one-message denial of sync.
    /// - Without the monotonic `max`, a backdated envelope rewound a healthy cursor and forced a full
    ///   re-download of the topic's history on every reconnect.
    ///
    /// `lastEventID` only moves when the watermark actually advances, so the cursor's id and timestamp
    /// always describe the same envelope.
    public func appendInbound(
        _ envelope: SocialEventEnvelope,
        topic: String? = nil,
        receivedAt: Date = .now
    ) async {
        await mutate { snapshot in
            // Admission control, and this is the only place it can live. `rejectionReason` answers
            // "was the author entitled to say this?"; neither it nor the rate limiter answers "are
            // we willing to keep it?" — the limiter bounds throughput, and the retention policy
            // bounds *age*, which never applies to a session this installation merely joined
            // because such a session never derives an `endedAt` for `prune` to act on. So without a
            // ceiling here, relay-accepted content is kept forever and nothing bounds the total.
            //
            // **The ceiling evicts; it must never refuse.** A wall here is strictly worse than the
            // unbounded growth it replaces: any invite holder can reach the cap with events that
            // are accepted by design (`.unsupported` needs no author), and from that moment every
            // *genuine* inbound envelope for the session is discarded — permanently, because there
            // is no release path for a joined session's log. One peer would be able to silence a
            // session for everyone else, unrecoverably short of a full reset. Dropping the oldest
            // evictable envelope instead costs history, which is recoverable, rather than the
            // session, which is not.
            //
            // Only relay-delivered content is evictable. Locally-minted envelopes are this
            // installation's own record and are the root of the authority model; pending-outbound
            // ones have not been published yet, so evicting either would be data loss we authored.
            // That means a session can still exceed the ceiling through its *own* events — which is
            // correct, because nothing hostile can drive that.
            let stored = envelope.clampedForStorage
            // A re-delivery is not new content, and must not cost a row. Checked *before* the
            // ceiling: evicting to make room and then declining to insert — which is what
            // `appendUnique` does for an id already held — shrinks the log by one every time. The
            // relay replays each topic from the cursor on reconnect, so this needs no attacker at
            // all; a few hundred replayed envelopes silently delete a few hundred genuine ones.
            if !snapshot.envelopes.contains(where: { $0.id == stored.id }) {
                // Only relay-delivered rows count toward the ceiling, which is what
                // ``SocialRetentionPolicy/maximumStoredEnvelopesPerSession`` already says it bounds.
                // Counting *all* of a session's rows meant a host that authored its way to the cap —
                // `RitualCoordinator` mints an envelope per artifact and per receipt on every run —
                // reached a state with nothing evictable, and the branch that handled it refused
                // inbound envelopes permanently. That is the exact wall this ceiling exists not to
                // be. Scoped this way there is always a victim when the test passes, so the ceiling
                // evicts and never refuses.
                //
                // Ranked as (eviction class, arrival order, id). Arrival order is the right
                // tie-break and the wrong *primary* axis: the longest-held rows are the session's
                // genuine early history, so a flood arriving after a session is established evicted
                // precisely the `participantJoined` records whose loss leaves the session
                // permanently ownerless and unprunable. The id breaks remaining ties so eviction is
                // deterministic across runs and reproducible in tests.
                //
                // The class ordering is exhaustive rather than heuristic because a relay peer can
                // only land two kinds of event here at all — `.unsupported` and participant records;
                // everything else needs local provenance. See ``SocialEvent/EvictionClass``, and
                // ``SocialEvent/EvictionClass/evictsNewestFirst`` for why membership inverts the
                // arrival order rather than merely outranking the carriers: a `participantJoined`
                // with a fresh id is accepted off the relay by design and costs an attacker exactly
                // as much as `.unsupported`, so class ordering alone would have been bypassable by
                // anyone who read it.
                //
                // The anchor outranks the class, because it is the only component of this key the
                // sender cannot choose. Class and arrival order both rank rows that are
                // *indistinguishable on the wire*: a `participantJoined` with a fresh id is
                // accepted off the relay by design — a session you joined has to stay legible — so
                // a flood row and a genuine member's row differ in nothing the log can check, and
                // every ordering over them is symmetric. Whichever direction arrival order runs, an
                // attacker picks its flood timing to be on the winning side: oldest-first loses the
                // session's early history to a late flood, newest-first loses the owner's record to
                // an early one. The owner-bootstrap anchor breaks that symmetry because it comes
                // from the invite, which arrived out-of-band and never crossed the relay. So an
                // anchored membership record is evicted only once nothing else is left, at any
                // flood timing, and the arrival-order component below decides merely which ordinary
                // rows are kept.
                //
                // It outranks the class **and is bounded by the anchor set**, which is the half that
                // was missing: see the protected-row selection below for why "the sender cannot
                // choose the anchor" is not the same claim as "the sender cannot choose how many
                // rows sit in the anchored tier".
                let anchors = snapshot.ownerBootstrapAnchors(sessionID: stored.sessionID)
                let candidates = snapshot.envelopes.indices.filter { index in
                    let held = snapshot.envelopes[index]
                    return held.sessionID == stored.sessionID
                        && !snapshot.locallyMintedEventIDs.contains(held.id)
                        && !snapshot.pendingOutboundEventIDs.contains(held.id)
                }
                // **The anchor protects a record, which is one row — not every row that names the
                // anchored party.** Keying the protection on `participantID` alone made the
                // protected tier attacker-fillable, which is worse than the bug it closed.
                //
                // `rejectionReason` accepts a `participantUpdated` that restates a held record byte
                // for byte, deliberately, so that a relay re-delivery stays idempotent; and this
                // ceiling de-duplicates on envelope **id**, which is a different question. Between
                // the two, any invite holder republishes the anchored owner's own record under a
                // fresh envelope id as often as it likes — every copy passes the projection gate,
                // and every copy was `isAnchored`. Once those copies held the ceiling, the anchored
                // key outranked every unanchored row, so the session's genuine peers were evicted
                // and no unanchored record could ever outrank a replay again. That is the ceiling
                // turning into a wall built out of one participant id, which is precisely what it
                // must never become.
                //
                // Only the **earliest-arrived** row for each anchored participant carries the
                // protection, so the protected tier is bounded by the anchor set — which comes from
                // out-of-band invites, not from the relay — rather than by how many envelopes a peer
                // is willing to send. Earliest rather than newest for the same reason the projection
                // holds first-established-wins: a later row for a record this log already holds can
                // only be a no-op, because `.foreignRecordUpdate` refuses anything that would change
                // the stored value, so it has nothing to protect. Ties break on id, as below, so the
                // choice is deterministic when two rows share a sequence.
                //
                // And the row must *be* the anchored party's owner record, not merely name them.
                // Bounding the protection to one row per anchor fixed the replay flood but left the
                // slot assigned on arrival order, which a hostile peer controls: a `participantJoined`
                // pre-claiming the anchored id with any non-owner role is admitted (the projection
                // accepts the genuine owner record over it afterwards, so this is eviction, not
                // rejection), takes the slot by landing first, and the owner's genuine record — which
                // on a *joined* session can only arrive later, over the relay — is then evicted by
                // the next envelope.
                //
                // "Is the anchored party's owner record" is **the projection's question, and it is
                // asked with the projection's own predicate** —
                // ``SocialEvent/grantsSelfDescribedOwnership(author:)`` combined with the anchor set
                // is exactly `isAnchoredSelfDescribing` plus the `role == .owner` direction check
                // that `ownerBootstrapIsOpen` and `relayMayOverwriteHeldRecord` both apply. Each
                // round of this defect has been the ceiling asking something *weaker* than the
                // projection and the gap being the attack: naming the anchored party, then being any
                // membership row about them, then declaring any role. `role == .owner` on its own was
                // still weaker by one field — it omits the account, so a row naming the anchored id
                // with the attacker's wallet held the slot while `roleEscalation` refused that same
                // row at projection time, leaving the owner's genuine record evictable again.
                //
                // Sharing the predicate is what ends that: every protected row is one the projection
                // reads as the anchored party's own owner record, so the ceiling no longer has to
                // pick the *right* row — whichever member of the protected set survives keeps
                // `hasOwner` true, and the unrecoverable loss is out of reach by construction rather
                // than by the ordering being correct.
                //
                // And the predicate is asked of the **envelope**, not of the payload, which is the
                // half that was still missing. `rejectionReason` reads two fields about an
                // ownership claim that no payload-shaped question can see: the record's
                // `verificationState` — a relay `.local` record is refused outright as
                // `.untrustedLocalIdentity` — and the envelope's own `authorCAIP10Account`, which
                // its *first* guard compares against the held record. A row can be the anchored
                // party's self-describing owner record on every field below and still be refused
                // for one of those two, at which point it holds the slot while establishing no
                // owner, and the genuine record is evictable again. That is the same defect as the
                // four before it, one layer out from the payload.
                //
                // Those two are a **rank**, not a filter, and the distinction is load-bearing: the
                // account one refuses only *conditionally*, so such a row can be a session's sole
                // honored owner record, and excluding it would evict the very thing being
                // protected. See ``SocialEventEnvelope/selfDescribedOwnershipProtectionRank``.
                var earliestAnchored: [String: (rank: Int, sequence: Int, id: UUID)] = [:]
                for index in candidates {
                    let held = snapshot.envelopes[index]
                    // Keyed on the author, which `grantsSelfDescribedOwnership` has just established
                    // is also the record's `participantID` — the same identity the projection anchors
                    // on, so the tier stays bounded by the out-of-band anchor set.
                    let participantID = held.authorParticipantID
                    guard held.grantsSelfDescribedOwnership,
                          anchors.contains(participantID) else { continue }
                    let candidate = (
                        rank: held.selfDescribedOwnershipProtectionRank,
                        sequence: snapshot.inboundSequenceByEventID[held.id] ?? 0,
                        id: held.id
                    )
                    guard let incumbent = earliestAnchored[participantID] else {
                        earliestAnchored[participantID] = candidate
                        continue
                    }
                    if (candidate.rank, candidate.sequence, candidate.id.uuidString)
                        < (incumbent.rank, incumbent.sequence, incumbent.id.uuidString) {
                        earliestAnchored[participantID] = candidate
                    }
                }
                let protectedIDs = Set(earliestAnchored.values.map(\.id))
                let evictable: [(index: Int, key: (Int, Int, Int, String))] = candidates
                    .map { index in
                        let held = snapshot.envelopes[index]
                        let evictionClass = held.event.evictionClass
                        let sequence = snapshot.inboundSequenceByEventID[held.id] ?? 0
                        return (
                            index,
                            (
                                protectedIDs.contains(held.id) ? 1 : 0,
                                evictionClass.rawValue,
                                evictionClass.evictsNewestFirst ? -sequence : sequence,
                                held.id.uuidString
                            )
                        )
                    }
                if evictable.count >= retentionPolicy.maximumStoredEnvelopesPerSession,
                   let victim = evictable.min(by: { $0.key < $1.key })?.index {
                    let removed = snapshot.envelopes.remove(at: victim)
                    snapshot.inboundSequenceByEventID[removed.id] = nil
                }
                let nextSequence = (snapshot.inboundSequenceByEventID.values.max() ?? 0) + 1
                if appendUnique(stored, to: &snapshot.envelopes) {
                    snapshot.inboundSequenceByEventID[stored.id] = nextSequence
                }
            }
            guard let topic else { return }
            let previous = snapshot.replayCursors[topic]
            let observedAt = min(envelope.createdAt, receivedAt)
            guard observedAt > (previous?.lastReceivedAt ?? .distantPast) else {
                // Stale or duplicate delivery: keep the watermark we already trust.
                snapshot.replayCursors[topic] = previous ?? SocialRelayCursor(
                    topic: topic,
                    lastReceivedAt: observedAt,
                    lastEventID: envelope.id
                )
                return
            }
            snapshot.replayCursors[topic] = SocialRelayCursor(
                topic: topic,
                lastReceivedAt: observedAt,
                lastEventID: envelope.id
            )
        }
    }

    /// Records an installation-local event without placing it in the relay outbox.
    public func appendLocal(_ envelope: SocialEventEnvelope) async {
        await appendLocal([envelope])
    }

    /// Batch form of ``appendLocal(_:)``.
    ///
    /// Every mutation re-encodes and rewrites the *whole* snapshot through ``persistence``, so a
    /// caller appending N events one at a time paid N full writes over a log that only grows. A
    /// collaborative ritual run emits one event per produced artifact and one per receipt, which
    /// made a routine, scheduled operation quadratic in the size of the log it was appending to.
    public func appendLocal(_ envelopes: [SocialEventEnvelope]) async {
        guard !envelopes.isEmpty else { return }
        await mutate { snapshot in
            for envelope in envelopes {
                // Provenance follows the *stored* envelope, not the one we were handed. `appendUnique`
                // keeps the first envelope for an id, so marking an id we failed to insert would hand
                // local trust to whatever payload already occupies it — and inbound envelopes share
                // this id space. `isLocallyMinted` is the single primitive the whole authority model
                // rests on (it gates `.local` records, foreign-record writes, owner bootstrap, the
                // wire-`.verified` downgrade, and the author binding itself), so it must never be set
                // for content this installation did not author. Infeasible against v4 UUIDs today;
                // recorded structurally rather than left to rest on that.
                guard appendUnique(envelope, to: &snapshot.envelopes) else { continue }
                snapshot.locallyMintedEventIDs.insert(envelope.id)
            }
        }
    }

    @discardableResult
    public func enqueueOutbound(_ envelope: SocialEventEnvelope) async -> SocialEventEnvelope {
        await enqueueOutbound([envelope])
        return envelope
    }

    /// Batch form of ``enqueueOutbound(_:)``. Same one-write-per-batch rationale as
    /// ``appendLocal(_:)-(Array)``; relay ordering is preserved because the outbox keeps insertion order.
    @discardableResult
    public func enqueueOutbound(_ envelopes: [SocialEventEnvelope]) async -> [SocialEventEnvelope] {
        guard !envelopes.isEmpty else { return [] }
        await mutate { snapshot in
            for envelope in envelopes {
                // Same provenance-follows-storage rule as `appendLocal(_:)`: an id we did not insert
                // belongs to an envelope we did not author, and must not be marked as ours or queued
                // for publication under our authorship.
                guard appendUnique(envelope, to: &snapshot.envelopes) else { continue }
                // Outbound means *we* authored it and are publishing it, so it is locally minted
                // even though it will also travel over the relay.
                snapshot.locallyMintedEventIDs.insert(envelope.id)
                if !snapshot.pendingOutboundEventIDs.contains(envelope.id) {
                    snapshot.pendingOutboundEventIDs.append(envelope.id)
                }
            }
        }
        return envelopes
    }

    public func markPublished(eventID: UUID) async {
        await mutate { snapshot in
            snapshot.pendingOutboundEventIDs.removeAll { $0 == eventID }
        }
    }

    /// Stores an invite and durably records its inviter as an owner-bootstrap anchor for that session.
    ///
    /// The anchor is written here, not derived from the invite on demand, because the invite expires
    /// and is pruned while the session graph it vouches for does not; see
    /// ``SocialEventLogSnapshot/ownerAnchorsBySessionID``.
    public func saveInvite(_ invite: SocialInvite) async {
        await mutate { snapshot in
            snapshot.invites.removeAll { $0.sessionID == invite.sessionID }
            snapshot.invites.append(invite)
            let inviter = invite.inviterParticipantID
            guard !inviter.isEmpty else { return }
            snapshot.ownerAnchorsBySessionID[invite.sessionID, default: []].insert(inviter)
        }
    }

    /// Forgets an invite's relay secrets. The session's owner-bootstrap anchor is deliberately *not*
    /// cleared: consuming or rolling back an invite says nothing about whether its inviter vouched
    /// for the session, and dropping the anchor here would un-own every session joined through the
    /// normal flow. Anchors are released with the session graph in ``prune(now:policy:)``.
    public func removeInvite(sessionID: UUID) async {
        await mutate { snapshot in
            snapshot.invites.removeAll { $0.sessionID == sessionID }
        }
    }

    public func setSyncState(_ state: SocialSyncState, for sessionID: UUID) async {
        await mutate { snapshot in
            snapshot.syncStates[sessionID] = state
        }
    }

    public func setReplayCursor(_ cursor: SocialRelayCursor) async {
        await mutate { snapshot in
            snapshot.replayCursors[cursor.topic] = cursor
        }
    }

    public func pendingOutbound() async -> [SocialEventEnvelope] {
        let snapshot = await currentSnapshot()
        // `uniquingKeysWith:` rather than `uniqueKeysWithValues:`: the latter traps on a duplicate id,
        // and it was safe only by the invariant that every write path runs `normalized()` first. A
        // future setter that forgets to would have turned a duplicate relay delivery into a crash.
        let byID = Dictionary(snapshot.envelopes.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        return snapshot.pendingOutboundEventIDs.compactMap { byID[$0] }
    }

    /// The reduced state for one session. Provenance comes from this log, so a locally-authored
    /// `.local` participant projects normally while a relay-delivered one is refused.
    public func projection(sessionID: UUID) async -> SocialSessionProjection {
        await currentSnapshot().projection(sessionID: sessionID)
    }

    public func allEnvelopes() async -> [SocialEventEnvelope] {
        await currentSnapshot().envelopes
    }

    public func allInvites() async -> [SocialInvite] {
        await currentSnapshot().invites
    }

    public func currentSnapshot() async -> SocialEventLogSnapshot {
        if let snapshot { return snapshot }
        // Single-flight the cold load, matching `ReceiptSignerFactory.resolveSigner()`. This actor is
        // reentrant across the `await` on `persistence.load()`, so without joining an in-flight load
        // two racing mutations would each read the pre-load snapshot and write back over one another,
        // silently dropping an event or an invite.
        //
        // The task *installs* the cache itself rather than returning the loaded value for the calling
        // side to install. Awaiters of a task resume in unspecified order, so when installation lived
        // on the creating call, a joining `mutate` could resume first, read `snapshot` as still nil,
        // and write back a snapshot built from empty — erasing the entire persisted log, pending
        // outbound relay queue included, on its durable write. Installing inside the task makes "the
        // task has a value" and "the cache is warm" the same event for every caller.
        if let load {
            return await load.value
        }

        let task = Task { await self.hydrate() }
        load = task

        let loaded = await task.value
        load = nil
        return loaded
    }

    /// Loads persistence and installs the result as the in-memory cache. Runs on this actor inside
    /// the single-flight task, so no caller can observe a nil cache after the task completes.
    private func hydrate() async -> SocialEventLogSnapshot {
        let loaded = await persistence.load().normalized()
        // A concurrent `reset()` may have installed an authoritative empty snapshot while the load
        // was in flight; it must win over the state that predates it.
        if let snapshot { return snapshot }
        snapshot = loaded
        return loaded
    }

    public func reset() async {
        snapshot = SocialEventLogSnapshot()
        load = nil
        // Chained like any other write: a privacy reset must not be overtaken by an in-flight save
        // that would restore the log it just cleared.
        await commit(SocialEventLogSnapshot())
    }

    /// Removes complete, old terminal session graphs and stale invites. Active-session history and
    /// pending outbound events are never truncated because doing so could corrupt deterministic replay.
    @discardableResult
    public func prune(
        now: Date = .now,
        policy: SocialRetentionPolicy = SocialRetentionPolicy()
    ) async -> SocialPruneResult {
        var result = SocialPruneResult(removedSessionCount: 0, removedEnvelopeCount: 0, removedInviteCount: 0)
        await mutate { snapshot in
            let pendingIDs = Set(snapshot.pendingOutboundEventIDs)
            let sessionIDs = Set(snapshot.envelopes.map(\.sessionID))
            let removableSessionIDs = Set(sessionIDs.filter { sessionID in
                let sessionEnvelopes = snapshot.envelopes.filter { $0.sessionID == sessionID }
                guard sessionEnvelopes.allSatisfy({ !pendingIDs.contains($0.id) }) else { return false }
                // Provenance must be threaded here too. Without it a session whose owner is a
                // locally-minted `.local` identity would have its `sessionEnded` rejected, never
                // derive an `endedAt`, and so never become prunable — a slow leak of exactly the
                // local-only ritual sessions this store creates most often.
                let projection = SocialSessionProjection.reduce(
                    sessionEnvelopes,
                    sessionID: sessionID,
                    locallyMintedEventIDs: snapshot.locallyMintedEventIDs,
                    // Threaded for the same reason as the provenance above: without the anchor a
                    // joined session's owner does not project at all, so its `sessionEnded` is
                    // refused as `.ownerRequired` rather than reaching the narrower trust check.
                    //
                    // The anchor alone is not sufficient to make a *joined* session prunable, and
                    // deliberately so. A relay-delivered owner record is downgraded to `.pending`
                    // (``SocialSessionProjection/downgradedVerification(of:isLocallyMinted:)``), which
                    // clears `canAuthorBindingEvents`, so the owner's `sessionEnded` is refused as
                    // `.unverifiedAuthor` and no `endedAt` is ever derived. A session someone else
                    // hosted therefore retains its envelopes on this device indefinitely. Relaxing
                    // the trust check is the wrong fix — it would hand unproven peers every other
                    // binding authority too — so closing this needs either the transported join proof
                    // described on `downgradedVerification`, or a retention axis that does not depend
                    // on a session reaching a terminal state. Tracked as follow-on work rather than
                    // widened here.
                    ownerBootstrapAnchors: snapshot.ownerBootstrapAnchors(sessionID: sessionID)
                )
                guard let endedAt = projection.endedAt else { return false }
                return endedAt <= now.addingTimeInterval(-policy.terminalSessionRetention)
            })

            let envelopeCount = snapshot.envelopes.count
            let inviteCount = snapshot.invites.count
            // The topics belonging to the session graphs being erased. Computed *before* the invites
            // are removed, because the invite is the only record mapping a topic back to a session.
            let prunedTopics = Set(
                snapshot.invites
                    .filter { removableSessionIDs.contains($0.sessionID) }
                    .map(\.relayTopic)
            )
            snapshot.envelopes.removeAll { removableSessionIDs.contains($0.sessionID) }
            snapshot.invites.removeAll {
                removableSessionIDs.contains($0.sessionID)
                    || $0.expiresAt <= now.addingTimeInterval(-policy.expiredInviteRetention)
            }
            for sessionID in removableSessionIDs { snapshot.syncStates.removeValue(forKey: sessionID) }
            // Drop only the cursors for pruned sessions. Retaining by "topic still has an invite"
            // deleted the replay progress of every *live* session whose invite had already been
            // consumed and removed by `removeInvite(sessionID:)` — the normal joiner flow — forcing a
            // full history re-download on the next reconnect.
            snapshot.replayCursors = snapshot.replayCursors.filter { !prunedTopics.contains($0.key) }
            // Anchors are released with the graph they anchor, which is the only place they are
            // released — an expired invite must not take the session's owner with it. The second
            // clause bounds the table for the case the first cannot see: an invite that expired and
            // was pruned without a single envelope ever arriving leaves an anchor with nothing left
            // to anchor.
            let liveSessionIDs = Set(snapshot.envelopes.map(\.sessionID))
            let invitedSessionIDs = Set(snapshot.invites.map(\.sessionID))
            snapshot.ownerAnchorsBySessionID = snapshot.ownerAnchorsBySessionID.filter { sessionID, _ in
                liveSessionIDs.contains(sessionID) || invitedSessionIDs.contains(sessionID)
            }
            result = SocialPruneResult(
                removedSessionCount: removableSessionIDs.count,
                removedEnvelopeCount: envelopeCount - snapshot.envelopes.count,
                removedInviteCount: inviteCount - snapshot.invites.count
            )
        }
        return result
    }

    private func mutate(_ body: (inout SocialEventLogSnapshot) -> Void) async {
        // Warm the cache *before* the critical section. Everything from the read of `snapshot` to the
        // write-back below is then free of suspension points, which is what makes the
        // read-modify-write atomic on this actor: two concurrent mutations can no longer both read
        // the same snapshot and have the second silently discard the first one's event.
        _ = await currentSnapshot()
        var value = snapshot ?? SocialEventLogSnapshot()
        body(&value)
        value = value.normalized()
        snapshot = value
        await commit(value)
    }

    /// Writes `value` through to `persistence`, chained behind any write already in flight.
    ///
    /// Every save rewrites the *whole* snapshot, so durable writes must land in the order they were
    /// committed in memory: if an earlier, slower `save` completed after a later one, it would
    /// resurrect a snapshot that predates events already accepted, and those events would be gone on
    /// relaunch. The in-memory state is already correct at this point — this orders the disk to match.
    private func commit(_ value: SocialEventLogSnapshot) async {
        let previous = lastWrite
        let write = Task { [persistence] in
            await previous?.value
            await persistence.save(value)
        }
        lastWrite = write
        await write.value
        // Only the newest write clears the chain, so a burst collapses to one link rather than
        // retaining every task that ever ran.
        if lastWrite == write { lastWrite = nil }
    }

    /// Appends `envelope` unless an envelope with the same id is already stored, reporting whether
    /// it landed.
    ///
    /// The return value is load-bearing for provenance. The first envelope for an id wins, so when
    /// this returns `false` the *stored* payload is some earlier envelope — possibly one that
    /// arrived over the relay. A caller that recorded local provenance regardless would hand
    /// `isLocallyMinted` to content it did not author. See ``appendLocal(_:)-(Array)``.
    @discardableResult
    private func appendUnique(_ envelope: SocialEventEnvelope, to values: inout [SocialEventEnvelope]) -> Bool {
        guard !values.contains(where: { $0.id == envelope.id }) else { return false }
        values.append(envelope)
        return true
    }
}

private extension SocialEventLogSnapshot {
    func normalized() -> SocialEventLogSnapshot {
        var seenEnvelopeIDs: Set<UUID> = []
        let uniqueEnvelopes = envelopes
            .filter { seenEnvelopeIDs.insert($0.id).inserted }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt { return lhs.id.uuidString < rhs.id.uuidString }
                return lhs.createdAt < rhs.createdAt
            }
        let envelopeIDs = Set(uniqueEnvelopes.map(\.id))
        var seenPendingIDs: Set<UUID> = []
        let pending = pendingOutboundEventIDs.filter { envelopeIDs.contains($0) && seenPendingIDs.insert($0).inserted }
        var inviteBySessionID: [UUID: SocialInvite] = [:]
        for invite in invites {
            inviteBySessionID[invite.sessionID] = invite
        }

        return SocialEventLogSnapshot(
            envelopes: uniqueEnvelopes,
            pendingOutboundEventIDs: pending,
            invites: inviteBySessionID.values.sorted { $0.expiresAt < $1.expiresAt },
            replayCursors: replayCursors,
            syncStates: syncStates,
            // Kept in step with the envelopes so pruning a session graph cannot leave provenance
            // entries behind for ids that no longer exist.
            locallyMintedEventIDs: locallyMintedEventIDs.intersection(envelopeIDs),
            // Deliberately *not* filtered against the envelopes: an invite is saved before any of
            // the session's traffic arrives, so an anchor legitimately exists for a session with no
            // envelopes yet. Releasing it is `prune`'s job, which can tell "not started" from
            // "finished". Empty sets are dropped so a cleared anchor does not linger as a key.
            ownerAnchorsBySessionID: ownerAnchorsBySessionID.filter { !$0.value.isEmpty },
            // Same reasoning as the provenance sweep above, and the same sweep: arrival order for an
            // envelope that no longer exists is dead weight `prune` would otherwise leave behind.
            //
            // Clamped as well, which is a bound rather than bookkeeping: the value is both negated
            // as a sort key and incremented as a counter, and each end of the range traps on one of
            // those. See ``SocialEventLogSnapshot/inboundSequenceRange``.
            inboundSequenceByEventID: inboundSequenceByEventID
                .filter { envelopeIDs.contains($0.key) }
                .mapValues {
                    min(
                        max(SocialEventLogSnapshot.inboundSequenceRange.lowerBound, $0),
                        SocialEventLogSnapshot.inboundSequenceRange.upperBound
                    )
                }
        )
    }
}
