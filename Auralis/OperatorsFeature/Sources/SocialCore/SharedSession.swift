import Foundation
import AuralisRuntime

public extension ActorRef {
    /// A non-optional, stable key for matching participants/votes.
    ///
    /// Delegates to `ActorRef.identityKey` (kind + identifier) rather than defining a second notion
    /// of identity. The earlier local key fell back to `displayName` and dropped `kind` whenever an
    /// identifier existed, which meant a cosmetic field could decide who is allowed to vote and two
    /// different kinds sharing an identifier collapsed into one voter.
    var participantKey: String { identityKey }
}

/// P1-SOCIAL-101 — Shared Session / Shared Context primitive.
///
/// The bounded first step toward human coordination: not a social network, just a way for more than
/// one actor to share a unit of operator work — shared workflows, shared receipts/artifacts, and
/// collaborative approvals — while everything stays governed and attributed. A `SharedSession` reuses
/// the same `correlationID` seam as `AgentSession`, so shared receipts and worklogs correlate exactly
/// the way single-actor ones do.

/// A participant's authority within a shared session.
public enum SharedRole: String, Equatable, Sendable, Codable, CaseIterable {
    /// Created the session; can end it and manage participants.
    case owner
    /// Can contribute work and cast approval votes.
    case collaborator
    /// Read-only visibility into the shared context.
    case viewer

    /// Whether this role may cast a collaborative-approval vote.
    public var canVote: Bool { self != .viewer }
}

/// One actor's membership in a shared session.
public struct SharedParticipant: Identifiable, Equatable, Sendable, Codable {
    public var id: String { actor.participantKey }
    public let actor: ActorRef
    public let role: SharedRole
    public let joinedAt: Date

    public init(actor: ActorRef, role: SharedRole, joinedAt: Date = .now) {
        self.actor = actor
        self.role = role
        self.joinedAt = joinedAt
    }
}

/// The resolution state of a collaborative approval.
public enum ApprovalResolution: String, Equatable, Sendable, Codable {
    case pending
    case approved
    case rejected
}

/// A single actor's vote on a collaborative approval.
public struct ApprovalVote: Equatable, Sendable, Codable {
    public let actor: ActorRef
    public let approved: Bool
    public let castAt: Date

    public init(actor: ActorRef, approved: Bool, castAt: Date = .now) {
        self.actor = actor
        self.approved = approved
        self.castAt = castAt
    }
}

/// A proposal that needs sign-off from more than one participant before it may proceed.
///
/// Bounded on purpose: `approved` once approvals reach `requiredApprovals`, `rejected` the moment any
/// participant votes against it (a single objection blocks — the conservative default for a governed
/// system), otherwise `pending`. One vote per actor; the latest vote from an actor wins.
public struct CollaborativeApproval: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    /// The runtime `ApprovalRequest` this collaborative vote stands in for (referenced by id for older payloads).
    public let approvalRequestID: UUID
    /// Full request snapshot, so collaborative resolution can resume/deny the exact runtime approval even
    /// after the view model's ephemeral pending-approval list refreshes.
    public let approvalRequest: ApprovalRequest?
    public let prompt: String
    public let requiredApprovals: Int
    public private(set) var votes: [ApprovalVote]

    public init(
        id: UUID = UUID(),
        approvalRequestID: UUID,
        approvalRequest: ApprovalRequest? = nil,
        prompt: String,
        requiredApprovals: Int,
        votes: [ApprovalVote] = []
    ) {
        self.id = id
        self.approvalRequestID = approvalRequestID
        self.approvalRequest = approvalRequest
        self.prompt = prompt
        self.requiredApprovals = max(1, requiredApprovals)
        // One vote per actor, exactly as ``record(_:)`` maintains it, applied here so the invariant
        // also holds for a value built from a decoded or caller-supplied array. Latest wins,
        // matching `record`.
        var seen: Set<String> = []
        self.votes = votes.reversed().filter { seen.insert($0.actor.participantKey).inserted }.reversed()
    }

    private enum CodingKeys: String, CodingKey {
        case id, approvalRequestID, approvalRequest, prompt, requiredApprovals, votes
    }

    /// Decodes through ``init(id:approvalRequestID:approvalRequest:prompt:requiredApprovals:votes:)``
    /// so its bounds run on the decode path too.
    ///
    /// The conformance was synthesized, which assigns the stored properties directly and bypasses
    /// both invariants ``resolution`` depends on — and `resolution` *is* the multi-party sign-off
    /// this type exists to provide. A persisted payload carrying `requiredApprovals: 0` decodes
    /// intact and then reads as `.approved` with **zero votes cast** (`approvalCount >= 0`), and a
    /// duplicated vote from one actor counts twice toward the threshold, resolving a 2-of-2 on one
    /// person's say-so. `SharedSession` round-trips its whole approval graph through
    /// ``SharedSessionPersisting`` on every launch, so the decode path is the one that matters.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            approvalRequestID: try container.decode(UUID.self, forKey: .approvalRequestID),
            approvalRequest: try container.decodeIfPresent(ApprovalRequest.self, forKey: .approvalRequest),
            prompt: try container.decode(String.self, forKey: .prompt),
            requiredApprovals: try container.decode(Int.self, forKey: .requiredApprovals),
            votes: try container.decodeIfPresent([ApprovalVote].self, forKey: .votes) ?? []
        )
    }

    /// Records a vote, replacing any prior vote from the same actor.
    public mutating func record(_ vote: ApprovalVote) {
        votes.removeAll { $0.actor.participantKey == vote.actor.participantKey }
        votes.append(vote)
    }

    public var approvalCount: Int { votes.filter(\.approved).count }
    public var rejectionCount: Int { votes.filter { !$0.approved }.count }

    public var resolution: ApprovalResolution {
        if rejectionCount > 0 { return .rejected }
        if approvalCount >= requiredApprovals { return .approved }
        return .pending
    }
}

/// A shared unit of operator work visible to more than one actor.
public struct SharedSession: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    /// Ties shared receipts, worklogs, and artifacts together — same key as `AgentSession`.
    public let correlationID: String
    public let title: String
    public let createdBy: ActorRef
    public let createdAt: Date
    public private(set) var endedAt: Date?
    public private(set) var participants: [SharedParticipant]
    public private(set) var sharedReceiptIDs: [UUID]
    public private(set) var sharedArtifactIDs: [UUID]
    public private(set) var sharedPlaybookIDs: [String]
    public private(set) var sharedAgentContexts: [SharedAgentContext]
    public private(set) var approvals: [CollaborativeApproval]

    public init(
        id: UUID = UUID(),
        correlationID: String,
        title: String,
        createdBy: ActorRef,
        createdAt: Date = .now
    ) {
        self.id = id
        self.correlationID = correlationID
        self.title = title
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.endedAt = nil
        self.participants = [SharedParticipant(actor: createdBy, role: .owner, joinedAt: createdAt)]
        self.sharedReceiptIDs = []
        self.sharedArtifactIDs = []
        self.sharedPlaybookIDs = []
        self.sharedAgentContexts = []
        self.approvals = []
    }

    private enum CodingKeys: String, CodingKey {
        case id, correlationID, title, createdBy, createdAt, endedAt, participants
        case sharedReceiptIDs, sharedArtifactIDs, sharedPlaybookIDs, sharedAgentContexts, approvals
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        correlationID = try container.decode(String.self, forKey: .correlationID)
        title = try container.decode(String.self, forKey: .title)
        createdBy = try container.decode(ActorRef.self, forKey: .createdBy)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        // De-duplicated on the way in, because `addParticipant(_:role:at:)` refuses a key the
        // session already holds and every reader assumes that: `vote` and `removeParticipant`
        // resolve a participant with `first(where:)`, so a duplicate key means the *role* that
        // decides whether someone may vote or eject a peer is whichever copy happens to be first in
        // the array. A payload holding one actor as both `.viewer` and `.owner` is then resolved by
        // array order rather than by the model. First wins, matching `addParticipant`.
        var seenParticipantKeys: Set<String> = []
        participants = (try container.decodeIfPresent([SharedParticipant].self, forKey: .participants) ?? [])
            .filter { seenParticipantKeys.insert($0.actor.participantKey).inserted }
        sharedReceiptIDs = try container.decodeIfPresent([UUID].self, forKey: .sharedReceiptIDs) ?? []
        sharedArtifactIDs = try container.decodeIfPresent([UUID].self, forKey: .sharedArtifactIDs) ?? []
        sharedPlaybookIDs = try container.decodeIfPresent([String].self, forKey: .sharedPlaybookIDs) ?? []
        sharedAgentContexts = try container.decodeIfPresent([SharedAgentContext].self, forKey: .sharedAgentContexts) ?? []
        // The same de-duplication as `participants` above, on the collection that had the same
        // add-guard and was left without it. ``openApproval(_:)`` refuses an id the session already
        // holds, and every reader assumes that: `vote(_:onApproval:)` resolves the target with
        // `firstIndex(where:)`, Mission Control counts `approvals.filter { $0.resolution == .pending }`,
        // and it renders them through a `ForEach` keyed on ``CollaborativeApproval/id`` — which is
        // undefined for a repeated id. So a payload holding one approval twice counts one pending
        // sign-off as two and records every vote into whichever copy happens to be first, while the
        // other copy — possibly carrying a different `requiredApprovals` — is what some other reader
        // sees. First wins, matching `openApproval`.
        var seenApprovalIDs: Set<UUID> = []
        approvals = (try container.decodeIfPresent([CollaborativeApproval].self, forKey: .approvals) ?? [])
            .filter { seenApprovalIDs.insert($0.id).inserted }
    }

    public var isActive: Bool { endedAt == nil }

    public mutating func addParticipant(_ actor: ActorRef, role: SharedRole, at now: Date = .now) {
        guard isActive,
              !participants.contains(where: { $0.actor.participantKey == actor.participantKey }) else { return }
        participants.append(SharedParticipant(actor: actor, role: role, joinedAt: now))
    }

    public mutating func removeParticipant(id participantID: String, requestedBy requesterID: String) {
        guard isActive,
              participants.first(where: { $0.id == requesterID })?.role == .owner,
              participantID != requesterID else { return }
        participants.removeAll { $0.id == participantID }
    }

    public mutating func share(receiptID: UUID) {
        if isActive, !sharedReceiptIDs.contains(receiptID) { sharedReceiptIDs.append(receiptID) }
    }

    public mutating func share(artifactID: UUID) {
        if isActive, !sharedArtifactIDs.contains(artifactID) { sharedArtifactIDs.append(artifactID) }
    }

    public mutating func share(playbookID: String) {
        if isActive, !sharedPlaybookIDs.contains(playbookID) { sharedPlaybookIDs.append(playbookID) }
    }

    public mutating func share(agentContext: SharedAgentContext) {
        guard isActive, agentContext.isExpired(at: .now) == false else { return }
        sharedAgentContexts.removeAll { $0.id == agentContext.id }
        sharedAgentContexts.append(agentContext)
    }

    public mutating func openApproval(_ approval: CollaborativeApproval) {
        guard isActive, approvals.contains(where: { $0.id == approval.id }) == false else { return }
        approvals.append(approval)
    }

    /// Casts a vote on an open collaborative approval. Ignored for viewers or unknown approvals.
    public mutating func vote(_ vote: ApprovalVote, onApproval approvalID: UUID) {
        guard isActive,
              participants.first(where: { $0.actor.participantKey == vote.actor.participantKey })?.role.canVote == true,
              let index = approvals.firstIndex(where: { $0.id == approvalID }) else { return }
        approvals[index].record(vote)
    }

    public mutating func end(at now: Date = .now) {
        guard endedAt == nil else { return }
        endedAt = now
    }
}

/// Tracks shared sessions. Mission Control observes this to show collaborative work. Backed by an
/// injected ``SharedSessionPersisting`` so sessions survive relaunch (the default is ephemeral).
public actor SharedSessionStore {
    private var sessions: [UUID: SharedSession] = [:]
    private let persistence: any SharedSessionPersisting
    private var hydrated = false
    private var hydration: Task<Void, Never>?
    private var lastWrite: Task<Void, Never>?

    public init(persistence: any SharedSessionPersisting = EphemeralSharedSessionPersistence()) {
        self.persistence = persistence
    }

    /// Loads persisted sessions on first access.
    ///
    /// Single-flighted through ``hydration`` for the same reason as `RitualStore.ensureHydrated()`:
    /// this actor is reentrant across the `await` on `persistence.load()`, so a flag set before that
    /// suspension let every caller arriving during the load run against an empty store. `create` /
    /// `mutate` then persisted `Array(sessions.values)` from that empty state, dropping every
    /// already-persisted session from disk until some later write happened to restore it.
    private func ensureHydrated() async {
        if hydrated { return }
        if let hydration { return await hydration.value }

        let task = Task { await self.hydrate() }
        hydration = task
        await task.value
        hydration = nil
    }

    /// Loads and merges persisted sessions. Runs on this actor inside the single-flight task, so
    /// `hydrated` is only true once the merged sessions are visible.
    private func hydrate() async {
        for session in await persistence.load() where sessions[session.id] == nil {
            sessions[session.id] = session
        }
        hydrated = true
    }

    /// Writes the whole session collection through to `persistence`, chained behind any write already
    /// in flight — the same ordering guarantee as `SocialEventLogStore.commit(_:)`, for the same
    /// reason.
    ///
    /// Hydration makes the read-modify-write atomic on this actor, but every save is still a *whole
    /// collection* replacement, so correctness also depends on the saves landing in the order they
    /// were committed in memory. Two concurrent `create`s snapshot `{A}` and `{A, B}`; if the earlier,
    /// slower save completes last the durable state is `{A}` and session B is gone on relaunch, with
    /// memory showing both the whole time. Nothing surfaces until the next launch, which is precisely
    /// why the ordering has to be structural rather than left to save latency.
    private func persist() async {
        let value = Array(sessions.values)
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

    @discardableResult
    public func create(_ session: SharedSession) async -> SharedSession {
        await ensureHydrated()
        sessions[session.id] = session
        await persist()
        return session
    }

    public func session(id: UUID) async -> SharedSession? {
        await ensureHydrated()
        return sessions[id]
    }

    public func activeSessions() async -> [SharedSession] {
        await ensureHydrated()
        return sessions.values.filter(\.isActive).sorted { $0.createdAt > $1.createdAt }
    }

    public func allSessions() async -> [SharedSession] {
        await ensureHydrated()
        return sessions.values.sorted { $0.createdAt > $1.createdAt }
    }

    /// Applies a mutation to a stored session and persists the result.
    @discardableResult
    public func mutate(id: UUID, _ transform: @Sendable (inout SharedSession) -> Void) async -> SharedSession? {
        await ensureHydrated()
        guard var session = sessions[id] else { return nil }
        transform(&session)
        sessions[id] = session
        await persist()
        return session
    }

    /// Erases every stored session and its durable backing, for the privacy reset (MC-Device-012).
    ///
    /// A shared session is a record of activity, not configuration, so — unlike the ritual *catalog* —
    /// all of it goes: titles, participants, shared artifact/receipt references, collaborative
    /// approvals, and the CAIP-10 accounts of the people who took part.
    ///
    /// Hydration is completed first, then everything is cleared, so an in-flight load cannot merge
    /// sessions back in *after* the erase — which is what a bare `hydrated = true` allowed. It also
    /// leaves the store hydrated, so a later access cannot resurrect what this just erased by
    /// re-reading persistence.
    public func reset() async {
        await ensureHydrated()
        sessions.removeAll()
        // Through `persist()` rather than a bare `persistence.save([])`, so the erase joins the write
        // chain. An unchained erase can complete *before* a `create` save that was already in flight,
        // and the session the reset was asked to delete comes back on disk.
        await persist()
    }
}
