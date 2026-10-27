import AuralisFoundation
import Foundation

/// The authority surface a capability lease grants into.
public enum CapabilityLeaseScope: String, CaseIterable, Equatable, Sendable, Codable {
    case account
    case data
    case execution
    case artifact

    public var displayTitle: String {
        switch self {
        case .account: return "Account scope"
        case .data: return "Data scope"
        case .execution: return "Execution scope"
        case .artifact: return "Artifact scope"
        }
    }

    public static func defaultScope(for capability: CapabilityID) -> CapabilityLeaseScope {
        switch capability {
        case .signMessage, .approveSpending, .draftTransaction:
            return .account
        case .playlistManagement, .autoOrganization, .musicLibraryClassification, .metadataOverride:
            return .data
        case .runPlugin, .backgroundMusicTask, .playbackQueue, .audioPlayback:
            return .execution
        case .musicExport:
            return .artifact
        }
    }
}

/// A temporary, inspectable, revocable grant of a capability to an actor.
///
/// The differentiator behind "Planner can access the music library for 20 minutes" / "No wallet
/// access". A lease is a *time-boxed* authority, distinct from the static `CapabilityDescriptor`
/// metadata in `AuralisFoundation`.
public struct CapabilityLease: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public let capability: CapabilityID
    public let reason: String
    public let scope: CapabilityLeaseScope
    public let grantedTo: ActorRef
    public let sessionCorrelationID: String?
    public let grantedAt: Date
    public let expiresAt: Date
    public private(set) var revokedAt: Date?

    public init(
        id: UUID = UUID(),
        capability: CapabilityID,
        reason: String? = nil,
        scope: CapabilityLeaseScope? = nil,
        grantedTo: ActorRef,
        sessionCorrelationID: String? = nil,
        grantedAt: Date = .now,
        expiresAt: Date,
        revokedAt: Date? = nil
    ) {
        self.id = id
        self.capability = capability
        self.reason = reason ?? CapabilityRegistry.descriptor(for: capability).summary
        self.scope = scope ?? CapabilityLeaseScope.defaultScope(for: capability)
        self.grantedTo = grantedTo
        self.sessionCorrelationID = sessionCorrelationID
        self.grantedAt = grantedAt
        self.expiresAt = expiresAt
        self.revokedAt = revokedAt
    }

    /// Tolerant decoding for `grantedTo`, matching `WorkflowStepLog.init(from:)`.
    ///
    /// A lease is read back through a `compactMap`, so a required attribution column turns "this
    /// grant predates `ActorRef`" into "this grant no longer exists" — the failure mode is a lease
    /// that silently stops authorizing rather than one that reads as unattributed. `.system` is the
    /// conservative fallback: it still expires, and `matchesIdentity(of:)` keeps it from widening
    /// authority to a named agent it was never granted to.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        capability = try container.decode(CapabilityID.self, forKey: .capability)
        reason = try container.decode(String.self, forKey: .reason)
        scope = try container.decode(CapabilityLeaseScope.self, forKey: .scope)
        grantedTo = try container.decodeIfPresent(ActorRef.self, forKey: .grantedTo) ?? .system
        sessionCorrelationID = try container.decodeIfPresent(String.self, forKey: .sessionCorrelationID)
        grantedAt = try container.decode(Date.self, forKey: .grantedAt)
        expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        revokedAt = try container.decodeIfPresent(Date.self, forKey: .revokedAt)
    }

    public func isActive(at now: Date = .now) -> Bool {
        if let revokedAt, now >= revokedAt { return false }
        return now >= grantedAt && now < expiresAt
    }

    public func grants(
        capability: CapabilityID,
        to actor: ActorRef,
        correlationID: String?,
        scope requestedScope: CapabilityLeaseScope? = nil,
        at now: Date = .now
    ) -> Bool {
        // Identity match, not structural equality: a lease must not stop applying because the
        // requesting actor happens to carry a `displayName` or inference metadata the grant didn't.
        guard self.capability == capability,
              grantedTo.matchesIdentity(of: actor),
              isActive(at: now) else {
            return false
        }
        if let requestedScope, scope != requestedScope { return false }
        if let sessionCorrelationID {
            return sessionCorrelationID == correlationID
        }
        return true
    }

    public mutating func revoke(at now: Date = .now) {
        guard revokedAt == nil else { return }
        revokedAt = now
    }
}

public enum CapabilityRestrictionKind: Equatable, Sendable, Codable, Hashable {
    case walletAccess
    case externalNetwork
    case capability(CapabilityID)

    public var displayTitle: String {
        switch self {
        case .walletAccess:
            return "No wallet access"
        case .externalNetwork:
            return "No external network"
        case let .capability(capability):
            return "No \(CapabilityRegistry.descriptor(for: capability).title)"
        }
    }

    public func denies(_ capability: CapabilityID) -> Bool {
        switch self {
        case .walletAccess:
            return [.signMessage, .approveSpending, .draftTransaction].contains(capability)
        case .externalNetwork:
            return capability == .runPlugin
        case let .capability(deniedCapability):
            return capability == deniedCapability
        }
    }
}

/// A temporary, inspectable, revocable denial. This is the negative counterpart to a lease, used for
/// policies like "No wallet access" or "No external network" that must be visible instead of implied.
public struct CapabilityRestriction: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public let kind: CapabilityRestrictionKind
    public let reason: String
    public let appliesTo: ActorRef?
    public let sessionCorrelationID: String?
    public let createdAt: Date
    public let expiresAt: Date?
    public private(set) var revokedAt: Date?

    public init(
        id: UUID = UUID(),
        kind: CapabilityRestrictionKind,
        reason: String,
        appliesTo: ActorRef? = nil,
        sessionCorrelationID: String? = nil,
        createdAt: Date = .now,
        expiresAt: Date? = nil,
        revokedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.reason = reason
        self.appliesTo = appliesTo
        self.sessionCorrelationID = sessionCorrelationID
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.revokedAt = revokedAt
    }

    public func isActive(at now: Date = .now) -> Bool {
        if let revokedAt, now >= revokedAt { return false }
        if let expiresAt, now >= expiresAt { return false }
        return now >= createdAt
    }

    public func denies(capability: CapabilityID, actor: ActorRef, correlationID: String?, at now: Date = .now) -> Bool {
        guard isActive(at: now), kind.denies(capability) else { return false }
        // Identity match, not structural equality — otherwise a denial silently stops applying when
        // the actor being checked carries display/inference metadata the restriction was built without.
        if let appliesTo, !appliesTo.matchesIdentity(of: actor) { return false }
        if let sessionCorrelationID, sessionCorrelationID != correlationID { return false }
        return true
    }

    public mutating func revoke(at now: Date = .now) {
        guard revokedAt == nil else { return }
        revokedAt = now
    }
}

/// Durable storage for authority state. Runtime enforcement remains in ``CapabilityLeaseRegistry``,
/// but a store lets Mission Control rehydrate active grants/restrictions after relaunch.
public protocol CapabilityLeaseStoring: Sendable {
    func upsert(_ lease: CapabilityLease) async
    func upsert(_ restriction: CapabilityRestriction) async
    func allLeases() async -> [CapabilityLease]
    func allRestrictions() async -> [CapabilityRestriction]
    func resetAll() async
}

public actor InMemoryCapabilityLeaseStore: CapabilityLeaseStoring {
    private var leases: [UUID: CapabilityLease] = [:]
    private var restrictions: [UUID: CapabilityRestriction] = [:]

    public init() { }

    public func upsert(_ lease: CapabilityLease) {
        leases[lease.id] = lease
    }

    public func upsert(_ restriction: CapabilityRestriction) {
        restrictions[restriction.id] = restriction
    }

    public func allLeases() -> [CapabilityLease] {
        leases.values.sorted { $0.grantedAt > $1.grantedAt }
    }

    public func allRestrictions() -> [CapabilityRestriction] {
        restrictions.values.sorted { $0.createdAt > $1.createdAt }
    }

    public func resetAll() {
        leases.removeAll()
        restrictions.removeAll()
    }
}

/// Tracks live capability leases and answers "is this actor allowed to use this capability right now?".
public actor CapabilityLeaseRegistry {
    private var leases: [UUID: CapabilityLease] = [:]
    private var restrictions: [UUID: CapabilityRestriction] = [:]
    private var expiredLeaseIDs: Set<UUID> = []
    private let store: (any CapabilityLeaseStoring)?
    private var didHydrate = false
    /// The one in-flight hydration. Concurrent callers await *this* rather than a flag, for the same
    /// reason ``RuntimeHost/bootstrap()`` does; see ``hydrateIfNeeded(at:)``.
    private var hydrationTask: Task<Void, Never>?

    public init(store: (any CapabilityLeaseStoring)? = nil) {
        self.store = store
    }

    @discardableResult
    public func grant(_ lease: CapabilityLease) async -> CapabilityLease {
        await hydrateIfNeeded()
        leases[lease.id] = lease
        expiredLeaseIDs.remove(lease.id)
        await store?.upsert(lease)
        return lease
    }

    public func revoke(id: UUID, at now: Date = .now) async {
        await hydrateIfNeeded()
        guard var lease = leases[id] else { return }
        lease.revoke(at: now)
        leases[id] = lease
        await store?.upsert(lease)
    }

    @discardableResult
    public func deny(_ restriction: CapabilityRestriction) async -> CapabilityRestriction {
        await hydrateIfNeeded()
        restrictions[restriction.id] = restriction
        await store?.upsert(restriction)
        return restriction
    }

    public func revokeRestriction(id: UUID, at now: Date = .now) async {
        await hydrateIfNeeded()
        guard var restriction = restrictions[id] else { return }
        restriction.revoke(at: now)
        restrictions[id] = restriction
        await store?.upsert(restriction)
    }

    public func activeLeases(at now: Date = .now) async -> [CapabilityLease] {
        await hydrateIfNeeded()
        return leases.values.filter { $0.isActive(at: now) }
    }

    public func activeRestrictions(at now: Date = .now) async -> [CapabilityRestriction] {
        await hydrateIfNeeded()
        return restrictions.values.filter { $0.isActive(at: now) }
    }

    /// Whether this actor has an active lease for `capability` at `now`.
    public func isGranted(
        _ capability: CapabilityID,
        to actor: ActorRef,
        correlationID: String? = nil,
        scope: CapabilityLeaseScope? = nil,
        at now: Date = .now
    ) async -> Bool {
        await grantingLease(capability, to: actor, correlationID: correlationID, scope: scope, at: now) != nil
    }

    /// The lease that authorizes this actor to use `capability` at `now`, or `nil` if none does.
    ///
    /// The authority side of attribution (P0.5-601/602): callers need to *record* which grant let an
    /// action through, not just whether one existed, so a receipt or worklog entry can answer "under
    /// what authority did this happen?" after the fact. When several leases qualify, the newest grant
    /// wins so the recorded authority matches what an operator most recently decided.
    public func grantingLease(
        _ capability: CapabilityID,
        to actor: ActorRef,
        correlationID: String? = nil,
        scope: CapabilityLeaseScope? = nil,
        at now: Date = .now
    ) async -> CapabilityLease? {
        await hydrateIfNeeded()
        guard await !isDenied(capability, to: actor, correlationID: correlationID, at: now) else { return nil }
        return leases.values
            .sorted { $0.grantedAt > $1.grantedAt }
            .first {
                $0.grants(
                    capability: capability,
                    to: actor,
                    correlationID: correlationID,
                    scope: scope,
                    at: now
                )
            }
    }

    public func isDenied(
        _ capability: CapabilityID,
        to actor: ActorRef,
        correlationID: String? = nil,
        at now: Date = .now
    ) async -> Bool {
        await firstDenial(for: capability, to: actor, correlationID: correlationID, at: now) != nil
    }

    public func firstDenial(
        for capability: CapabilityID,
        to actor: ActorRef,
        correlationID: String? = nil,
        at now: Date = .now
    ) async -> CapabilityRestriction? {
        await hydrateIfNeeded()
        return restrictions.values
            .sorted { $0.createdAt > $1.createdAt }
            .first { $0.denies(capability: capability, actor: actor, correlationID: correlationID, at: now) }
    }

    /// Backward-compatible diagnostic helper. Enforcement should use the actor-scoped overload.
    public func isGranted(_ capability: CapabilityID, at now: Date = .now) async -> Bool {
        await hydrateIfNeeded()
        return leases.values.contains { $0.capability == capability && $0.isActive(at: now) }
    }

    /// Returns leases that expired since the last sweep so callers can publish expiration events.
    ///
    /// "Since the last sweep" spans process boundaries, not just this one. A lease that was already
    /// past `expiresAt` when this registry first read the store is marked swept during hydration, so
    /// it is never reported here; see ``hydrateIfNeeded()``.
    public func expiredLeases(at now: Date = .now) async -> [CapabilityLease] {
        await hydrateIfNeeded(at: now)
        let newlyExpired = leases.values.filter { lease in
            !expiredLeaseIDs.contains(lease.id)
                && lease.revokedAt == nil
                && now >= lease.expiresAt
        }
        for lease in newlyExpired {
            expiredLeaseIDs.insert(lease.id)
        }
        return newlyExpired
    }

    /// Drops every grant and restriction, in memory and in the backing store.
    ///
    /// Used by the privacy reset: a lease records which actor was permitted to do what, and for how
    /// long, so it is part of the history a person is entitled to erase. Dropping grants fails closed
    /// — the pipeline refuses capabilities it cannot find a lease for — and standing routine authority
    /// is re-seeded on the next host bootstrap. `didHydrate` stays set so a cleared registry does not
    /// repopulate itself from rows the store has already deleted.
    public func resetAll() async {
        didHydrate = true
        leases.removeAll()
        restrictions.removeAll()
        expiredLeaseIDs.removeAll()
        await store?.resetAll()
    }

    /// Ensures the durable grants and restrictions have been read, exactly once, before the caller
    /// inspects them.
    ///
    /// Whether hydration was *started* is not the question a caller is asking.
    ///
    /// This used to set `didHydrate = true` before awaiting the store, which stopped a second caller
    /// re-reading it but let that caller straight through into an **empty** registry. Because the
    /// registry fails closed, a `grantingLease` arriving during the read returned nil and
    /// `GovernedToolPipeline` refused the run with "Missing active capability lease" — an authority
    /// refusal, receipted as one, for a grant sitting in the store. A `grant` arriving in the same
    /// window was worse: it wrote into the table hydration was about to replace wholesale, so the
    /// lease persisted to disk and vanished from memory.
    ///
    /// Callers now await the *hydration itself*. The task is installed before any suspension point,
    /// and the task **body** is what publishes the hydrated state — the distinction that matters,
    /// because a single-flight whose caller installs the result has the same hole in a different
    /// place (awaiters resume in an unspecified order). Same idiom as
    /// `ReceiptSignerFactory.resolveSigner()` and `SocialEventLogStore`'s cold load.
    private func hydrateIfNeeded(at hydratedAt: Date = .now) async {
        if let hydrationTask {
            await hydrationTask.value
            return
        }
        guard !didHydrate, let store else { return }
        let task = Task { await self.performHydration(from: store, at: hydratedAt) }
        hydrationTask = task
        await task.value
    }

    /// Reads the durable grants and restrictions once, and marks every lease that is *already* past
    /// its expiry as swept.
    ///
    /// That last part is what keeps ``expiredLeases(at:)`` idempotent across launches. `expiredLeaseIDs`
    /// is in-memory, and the store returns every row it holds with no expiry filter, so without this a
    /// relaunch re-reported every lease that had ever expired as *newly* expired. Each one became a
    /// `.capabilityLeaseExpired` event and — via `RuntimeReceiptObserver` — another
    /// `runtime.capability.expired` receipt, on every launch, forever. Standing routine authority
    /// alone mints roughly ten 24-hour leases a day, so the ledger accumulated hundreds of duplicate
    /// expiry entries for expiries that happened once, and the duplication grew with the square of
    /// the install's age.
    ///
    /// Nothing is lost by staying quiet about them. An expiry that happened while the process was not
    /// running cannot be timestamped honestly here — the event would carry *launch* time, not the
    /// moment the lease lapsed — and the grant receipt already records `expiresAt`, so when a lease
    /// ended remains answerable from the ledger, and answerable more accurately than these events ever
    /// were. What this suppresses is only the re-announcement; a lease that expires while the app is
    /// running is unaffected and still reported exactly once.
    ///
    /// Runs as the body of ``hydrateIfNeeded(at:)``'s single-flight task, and publishes every piece of
    /// state it loads before that task completes — so "the task finished" and "the registry is usable"
    /// are one event rather than two.
    private func performHydration(from store: any CapabilityLeaseStoring, at hydratedAt: Date) async {
        let storedLeases = await store.allLeases()
        let storedRestrictions = await store.allRestrictions()
        // Cleared once the state below is published, so the steady-state authority check is a flag
        // test rather than a task await. Everything from here is one synchronous region on this
        // actor, so there is no window where `hydrationTask` is nil and `didHydrate` is still false.
        defer { hydrationTask = nil }
        // `resetAll()` wins. It sets `didHydrate` precisely so a cleared registry cannot repopulate
        // itself, and it may have run while these two reads were in flight — replaying rows the
        // store has already deleted would undo a privacy reset.
        guard !didHydrate else { return }
        didHydrate = true
        // Uniqued, not `uniqueKeysWithValues:`, which *traps* on a repeated id. `CapabilityLeaseStoring`
        // is a public protocol whose conformers own their own uniqueness; the shipping SwiftData store
        // keys rows on a `@Attribute(.unique)` id, but a future store, a partial migration, or a test
        // double need not, and none of that justifies crashing on the path that *reads* authority
        // history. This matches how the rest of the kernel treats persisted data: degrade a bad row,
        // never trap on it (see ``ActorRef/reconstructed(rawKind:identifier:displayName:inference:)``).
        //
        // First writer wins, and both store reads are ordered newest-first, so a duplicated id
        // resolves to the most recent grant — the same "newest wins" rule ``grantingLease`` applies.
        leases = Dictionary(
            storedLeases.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        restrictions = Dictionary(
            storedRestrictions.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for lease in leases.values where lease.revokedAt == nil && hydratedAt >= lease.expiresAt {
            expiredLeaseIDs.insert(lease.id)
        }
    }
}
