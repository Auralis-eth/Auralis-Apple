import Foundation
@testable import RuntimeKit
import SocialCore
import Testing

/// More than one `RuntimeHost` exists in this process: `RuntimeAssembly.sharedHost` memoizes by
/// `ObjectIdentifier(modelContext.container)`, and `RuntimeBackgroundScheduler.runInBackground()`
/// opens a *fresh* `ModelContainer`, so the background refresh misses that memo and builds a second
/// host.
///
/// `SharedSessionStore`, `RitualStore`, and `SocialEventLogStore` all persist by rewriting the
/// *entire* snapshot they hold in memory. Two instances over one `UserDefaults` key therefore do not
/// merge — the later writer erases whatever the other one recorded, which for `RitualStore`'s
/// `lastRuns` means an already-completed ritual runs again. These tests pin that the default
/// (shipping) path resolves **one** store per backing.
///
/// Audit finding F-23.
@MainActor
@Suite("Shared coordination stores")
struct SharedCoordinationStoresTests {
    /// `nonisolated` so the `UserDefaults` is created and consumed inside one isolation region —
    /// `UserDefaults` is not `Sendable`, so handing one to an actor's initializer from the main actor
    /// is a region-isolation error.
    private nonisolated static func makeEventLogPersistence(
        suite: String,
        key: String
    ) -> UserDefaultsSocialEventLogPersistence {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removeObject(forKey: key)
        return UserDefaultsSocialEventLogPersistence(defaults: defaults, key: key)
    }

    /// Deletes the suite's backing store so a run leaves nothing behind in the host's preferences.
    /// Each test owns its own suite name, so this can never tear down a sibling running in parallel.
    private nonisolated static func removeSuite(_ suite: String) {
        UserDefaults.standard.removePersistentDomain(forName: suite)
    }

    private func makeEnvelope(_ author: String) -> SocialEventEnvelope {
        SocialEventEnvelope(
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!,
            authorParticipantID: author,
            event: .workflowShared("workflow.\(author)")
        )
    }

    /// Not the tautology it resembles. Each `#expect` evaluates the declaration *twice*, so what is
    /// under test is the declaration kind, not the identity operator: a `static let` hands back the
    /// same instance both times, while the plausible refactor to a computed `static var` would hand
    /// back a fresh backing per access — keying a fresh store per call and silently restoring the
    /// two-stores-over-one-key clobber. This fails the moment someone makes that edit.
    @Test("the default backings are process-wide singletons, not fresh per call")
    func defaultBackingsAreSingletons() {
        #expect(
            SharedCoordinationStores.defaultSocialEventLogPersistence
                === SharedCoordinationStores.defaultSocialEventLogPersistence
        )
        #expect(
            SharedCoordinationStores.defaultSharedSessionPersistence
                === SharedCoordinationStores.defaultSharedSessionPersistence
        )
        #expect(
            SharedCoordinationStores.defaultRitualStatePersistence
                === SharedCoordinationStores.defaultRitualStatePersistence
        )
    }

    @Test("one backing resolves to one store, however many times it is asked for")
    func oneBackingResolvesToOneStore() {
        defer { Self.removeSuite("F23.oneStore") }
        SharedCoordinationStores.resetForTesting()
        let persistence = Self.makeEventLogPersistence(suite: "F23.oneStore", key: "log")

        let first = SharedCoordinationStores.socialEventLogStore(for: persistence)
        let second = SharedCoordinationStores.socialEventLogStore(for: persistence)

        #expect(first === second)
    }

    @Test("a distinct backing resolves to a distinct store")
    func distinctBackingsResolveToDistinctStores() {
        defer { Self.removeSuite("F23.distinct") }
        SharedCoordinationStores.resetForTesting()
        let first = SharedCoordinationStores.socialEventLogStore(
            for: Self.makeEventLogPersistence(suite: "F23.distinct", key: "a")
        )
        let second = SharedCoordinationStores.socialEventLogStore(
            for: Self.makeEventLogPersistence(suite: "F23.distinct", key: "b")
        )

        #expect(first !== second)
    }

    /// The failure this guards, stated as an executable fact: two stores over one key lose an event.
    ///
    /// Both caches are warmed *before* either writes, which is the real sequence — the foreground
    /// host warms at launch and the background-refresh host warms when its task fires, and only then
    /// do they both write. (Warming them lazily inside the appends instead would serialize the two
    /// writes and hide the bug, because the second store would load the first one's snapshot.)
    @Test("two independent stores over one key lose events")
    func twoIndependentStoresLoseEvents() async {
        defer { Self.removeSuite("F23.clobber") }
        let persistence = Self.makeEventLogPersistence(suite: "F23.clobber", key: "log")

        // Deliberately *not* via SharedCoordinationStores — this is the pre-fix per-host shape.
        let foregroundHostStore = SocialEventLogStore(persistence: persistence)
        let backgroundHostStore = SocialEventLogStore(persistence: persistence)
        _ = await foregroundHostStore.currentSnapshot()
        _ = await backgroundHostStore.currentSnapshot()

        await foregroundHostStore.appendLocal(makeEnvelope("foreground"))
        await backgroundHostStore.appendLocal(makeEnvelope("background"))

        let reloaded = SocialEventLogStore(persistence: persistence)
        #expect(
            await reloaded.allEnvelopes().count == 1,
            "two independent stores do not merge — one event must be lost"
        )
    }

    /// And the fix: both hosts' events survive when the backing resolves to one shared store.
    @Test("one shared store keeps both hosts' events")
    func sharedStoreKeepsBothHostsEvents() async {
        defer { Self.removeSuite("F23.shared") }
        SharedCoordinationStores.resetForTesting()
        let persistence = Self.makeEventLogPersistence(suite: "F23.shared", key: "log")

        let foregroundHostStore = SharedCoordinationStores.socialEventLogStore(for: persistence)
        let backgroundHostStore = SharedCoordinationStores.socialEventLogStore(for: persistence)
        await foregroundHostStore.appendLocal(makeEnvelope("foreground"))
        await backgroundHostStore.appendLocal(makeEnvelope("background"))

        let reloaded = SocialEventLogStore(persistence: persistence)
        #expect(await reloaded.allEnvelopes().count == 2, "shared store must keep both hosts' events")
    }
}
