import AuralisFoundation
import Foundation
@testable import AuralisRuntime
import Testing

/// A store that hands back rows the registry did not write, including duplicates.
private actor DuplicatingLeaseStore: CapabilityLeaseStoring {
    private var leases: [CapabilityLease]
    private var restrictions: [CapabilityRestriction]

    init(leases: [CapabilityLease], restrictions: [CapabilityRestriction] = []) {
        self.leases = leases
        self.restrictions = restrictions
    }

    func upsert(_ lease: CapabilityLease) { leases.append(lease) }
    func upsert(_ restriction: CapabilityRestriction) { restrictions.append(restriction) }
    func allLeases() -> [CapabilityLease] { leases }
    func allRestrictions() -> [CapabilityRestriction] { restrictions }
    func resetAll() { leases.removeAll(); restrictions.removeAll() }
}

@Suite("Runtime robustness")
struct RuntimeRobustnessTests {
    /// Hydration must not trap on a repeated id.
    ///
    /// `CapabilityLeaseStoring` is public and its conformers own their own uniqueness; the shipping
    /// SwiftData store keys rows on a unique id, but a future store, a partial migration, or a test
    /// double need not. Trapping would crash the app on the path that *reads* authority history,
    /// which is the failure mode the rest of the kernel deliberately avoids for persisted data.
    @Test("duplicate lease ids from a store hydrate instead of trapping")
    func duplicateLeaseIDsDoNotTrap() async {
        let id = UUID()
        let newest = CapabilityLease(
            id: id,
            capability: .audioPlayback,
            reason: "newest",
            grantedTo: .human,
            grantedAt: Date(timeIntervalSince1970: 2_000),
            expiresAt: Date.distantFuture
        )
        let older = CapabilityLease(
            id: id,
            capability: .signMessage,
            reason: "older",
            grantedTo: .human,
            grantedAt: Date(timeIntervalSince1970: 1_000),
            expiresAt: Date.distantFuture
        )
        // Newest-first, matching how both store reads are ordered.
        let registry = CapabilityLeaseRegistry(store: DuplicatingLeaseStore(leases: [newest, older]))

        let active = await registry.activeLeases()
        #expect(active.count == 1)
        // Newest grant wins, the same rule `grantingLease` applies when several leases qualify.
        #expect(active.first?.reason == "newest")
        #expect(await registry.grantingLease(.audioPlayback, to: .human) != nil)
    }

    @Test("duplicate restriction ids from a store hydrate instead of trapping")
    func duplicateRestrictionIDsDoNotTrap() async {
        let id = UUID()
        let restriction = CapabilityRestriction(
            id: id,
            kind: .walletAccess,
            reason: "no wallet",
            createdAt: Date(timeIntervalSince1970: 2_000)
        )
        let duplicate = CapabilityRestriction(
            id: id,
            kind: .walletAccess,
            reason: "stale duplicate",
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        let registry = CapabilityLeaseRegistry(
            store: DuplicatingLeaseStore(leases: [], restrictions: [restriction, duplicate])
        )

        #expect(await registry.activeRestrictions().count == 1)
        // The restriction still bites — degrading a duplicate must not drop enforcement.
        #expect(await registry.isDenied(.signMessage, to: .human))
    }

    /// A lease that expired before this registry ever read the store is not announced as a *new*
    /// expiry.
    ///
    /// `expiredLeaseIDs` only lives in memory and the store hands back every row it holds, so each
    /// relaunch used to re-report the whole history of expired leases. Every one became a
    /// `.capabilityLeaseExpired` event and another `runtime.capability.expired` receipt — per launch,
    /// for the life of the install.
    @Test("a lease that expired before hydration is not reported as newly expired")
    func alreadyExpiredLeaseIsNotReReportedAfterHydration() async {
        let expired = CapabilityLease(
            capability: .audioPlayback,
            reason: "lapsed in an earlier process",
            grantedTo: .human,
            grantedAt: Date(timeIntervalSince1970: 1_000),
            expiresAt: Date(timeIntervalSince1970: 2_000)
        )
        let registry = CapabilityLeaseRegistry(store: DuplicatingLeaseStore(leases: [expired]))

        #expect(await registry.expiredLeases().isEmpty)
        // Still hydrated and still inactive — suppressed from the sweep, not dropped from the registry.
        #expect(await registry.activeLeases().isEmpty)
        #expect(await registry.grantingLease(.audioPlayback, to: .human) == nil)
    }

    @Test("first hydration respects the requested sweep time")
    func firstHydrationRespectsRequestedSweepTime() async {
        let lease = CapabilityLease(
            capability: .audioPlayback,
            reason: "expires after the requested historical sweep",
            grantedTo: .human,
            grantedAt: Date(timeIntervalSince1970: 1_000),
            expiresAt: Date(timeIntervalSince1970: 2_000)
        )
        let registry = CapabilityLeaseRegistry(store: DuplicatingLeaseStore(leases: [lease]))

        #expect(await registry.expiredLeases(at: Date(timeIntervalSince1970: 1_500)).isEmpty)
        #expect(
            await registry.expiredLeases(at: Date(timeIntervalSince1970: 2_001)).map(\.id) == [lease.id]
        )
    }

    /// The suppression above is scoped to leases that lapsed *before* the process started. One that
    /// expires while the app is running is still reported, exactly once.
    @Test("a lease that expires during the session is still reported once")
    func leaseExpiringDuringTheSessionIsReportedExactlyOnce() async {
        let registry = CapabilityLeaseRegistry(store: DuplicatingLeaseStore(leases: []))
        let lease = await registry.grant(
            CapabilityLease(
                capability: .audioPlayback,
                reason: "granted in this process",
                grantedTo: .human,
                grantedAt: Date(),
                expiresAt: Date().addingTimeInterval(60)
            )
        )
        let afterExpiry = lease.expiresAt.addingTimeInterval(1)

        #expect(await registry.expiredLeases(at: lease.grantedAt).isEmpty)
        #expect(await registry.expiredLeases(at: afterExpiry).map(\.id) == [lease.id])
        // The second sweep finds nothing new — the in-process dedupe is unchanged.
        #expect(await registry.expiredLeases(at: afterExpiry).isEmpty)
    }

    /// An ended session must not be reopened by a late approval note.
    ///
    /// `end(status:at:)` returns early once `endedAt` is set, so a status written around it could
    /// never be cleared: the session would read as live via `isActive` forever.
    @Test("noting an approval on an ended session does not reopen it")
    func endedSessionIsNotReopenedByApprovalNote() {
        var session = AgentSession(correlationID: "corr", goal: "goal", actor: .human)
        session.complete()
        let endedAt = session.endedAt

        session.note(approvalID: UUID())

        #expect(session.status == .completed)
        #expect(session.endedAt == endedAt)
        #expect(session.isActive == false)
        // The approval is still recorded; only the lifecycle transition is refused.
        #expect(session.approvalIDs.count == 1)
    }

    @Test("noting an approval on a live session still marks it waiting")
    func liveSessionStillMovesToWaiting() {
        var session = AgentSession(correlationID: "corr", goal: "goal", actor: .human)

        session.note(approvalID: UUID())

        #expect(session.status == .waitingForApproval)
        #expect(session.endedAt == nil)
        #expect(session.isActive)
    }
}

// MARK: - Concurrent hydration

/// A lease store whose reads suspend, widening a reentrancy window that exists regardless.
///
/// The same shape `SocialEventLogStoreConcurrencyTests` uses for F-14, and for the same reason:
/// `CapabilityLeaseStoring` is a separate actor, so every hydration read already suspends. The sleep
/// only makes the interleaving reliable in a test. The shipping `SwiftDataCapabilityLeaseStore`
/// widens it a long way on its own — it fetches and JSON-decodes the whole lease table on first use.
private actor SlowLeaseStore: CapabilityLeaseStoring {
    private var leases: [CapabilityLease]
    private(set) var readCount = 0

    init(leases: [CapabilityLease]) { self.leases = leases }

    func upsert(_ lease: CapabilityLease) { leases.append(lease) }
    func upsert(_ restriction: CapabilityRestriction) { }
    func allRestrictions() async -> [CapabilityRestriction] { [] }
    func resetAll() { leases.removeAll() }

    /// Snapshots *before* suspending, the way a database fetch does: the query has already run, so a
    /// write that lands afterwards is not in this result set.
    func allLeases() async -> [CapabilityLease] {
        readCount += 1
        let snapshot = leases
        try? await Task.sleep(for: .milliseconds(20))
        return snapshot
    }

    func persistedCount() -> Int { leases.count }
}

@Suite("Capability lease hydration")
struct CapabilityLeaseHydrationTests {

    private func standingLease() -> CapabilityLease {
        CapabilityLease(
            capability: .audioPlayback,
            reason: "standing routine authority",
            grantedTo: .human,
            grantedAt: Date(timeIntervalSince1970: 1_000),
            expiresAt: Date.distantFuture
        )
    }

    /// Callers arriving while the first hydration is still reading the store must still see the
    /// durable grants.
    ///
    /// `hydrateIfNeeded()` marked the registry hydrated *before* awaiting the store, so every caller
    /// that arrived during the read took the early return and queried an empty lease table. The
    /// registry fails closed, so `grantingLease` returned nil and `GovernedToolPipeline` refused the
    /// run with "Missing active capability lease" — an authority refusal, receipted as one, for a
    /// grant sitting in the store. Reachable on any cold start where two governed runs under
    /// *different* correlation ids overlap, which `CorrelationGate` does not serialize.
    @Test("concurrent first callers all see the durable grant")
    func concurrentFirstCallersAllSeeTheDurableGrant() async {
        let registry = CapabilityLeaseRegistry(store: SlowLeaseStore(leases: [standingLease()]))

        let granted = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<8 {
                group.addTask { await registry.grantingLease(.audioPlayback, to: .human) != nil }
            }
            return await group.reduce(into: 0) { $0 += $1 ? 1 : 0 }
        }

        #expect(granted == 8, "\(8 - granted) of 8 concurrent callers were refused an authority the store holds")
    }

    /// Hydration must not read the store more than once, however many callers race it.
    @Test("a hydration race reads the store exactly once")
    func hydrationRaceReadsTheStoreOnce() async {
        let store = SlowLeaseStore(leases: [standingLease()])
        let registry = CapabilityLeaseRegistry(store: store)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask { _ = await registry.activeLeases() }
            }
            await group.waitForAll()
        }

        #expect(await store.readCount == 1)
    }

    /// A grant taken while hydration is in flight must survive the hydration that follows it.
    ///
    /// Hydration assigns the lease table wholesale, so a grant written into the gap between "the
    /// registry was marked hydrated" and "the store read came back" was overwritten in memory while
    /// still being persisted — leaving the registry refusing a capability it has a durable grant for
    /// until the next launch.
    @Test("a grant taken during hydration is not erased when hydration lands")
    func grantDuringHydrationSurvivesHydration() async {
        let store = SlowLeaseStore(leases: [standingLease()])
        let registry = CapabilityLeaseRegistry(store: store)
        let fresh = CapabilityLease(
            capability: .signMessage,
            reason: "granted while hydration was in flight",
            grantedTo: .human,
            grantedAt: Date(timeIntervalSince1970: 3_000),
            expiresAt: Date.distantFuture
        )

        await withTaskGroup(of: Void.self) { group in
            group.addTask { _ = await registry.activeLeases() }
            group.addTask { await registry.grant(fresh) }
            await group.waitForAll()
        }

        #expect(
            await registry.grantingLease(.signMessage, to: .human) != nil,
            "a grant taken during hydration was erased by the hydration that followed it"
        )
        #expect(await registry.grantingLease(.audioPlayback, to: .human) != nil)
        // Memory and disk must agree: the grant was persisted either way, so an erased in-memory
        // copy is a divergence, not merely a lost write.
        #expect(await store.persistedCount() == 2)
    }
}
