import Foundation
import AuralisOperators

/// Process-wide owners of the three `UserDefaults`-backed coordination stores.
///
/// **Why this exists (P0.5 / audit F-23).** `SharedSessionStore`, `RitualStore`, and
/// `SocialEventLogStore` each hold an in-memory snapshot and persist by rewriting that *whole*
/// snapshot. That design is only safe while exactly one store instance owns a given `UserDefaults`
/// key. Two instances over one key do not merge — each writes back the state it happens to be
/// holding, so whichever writes last erases everything the other recorded.
///
/// More than one host really does get built in this process. `RuntimeAssembly.sharedHost` memoizes by
/// `ObjectIdentifier(modelContext.container)`, and `RuntimeBackgroundScheduler.runInBackground()`
/// opens a *fresh* `ModelContainer` — a different object, so a cache miss, so a second
/// `RuntimeHost`. With per-host stores that meant the background refresh's ritual runs and social
/// events were silently erased by the next foreground write (and vice versa), including
/// `RitualStore`'s `lastRuns` / `completedOccurrenceIDs`, whose loss makes an already-completed
/// ritual run again.
///
/// So the durable stores are shared per process while the registries that sit above them stay
/// per-host — the arrangement the two-hosts-per-process design always assumed.
///
/// Keyed by the identity of the persistence rather than unconditionally global, so a caller that
/// supplies its own backing gets its own store (and two hosts sharing one custom backing still share
/// one store). Tests that inject a store directly bypass this entirely and are unaffected.
///
/// What that guarantees, precisely, is one store per *backing instance* — not one store per
/// `UserDefaults` key, which the memo cannot see because the persistence protocols do not expose
/// one. Two separately constructed backings aimed at the same suite and key would still resolve to
/// two stores and would still clobber. Nothing ships in that shape: every production caller arrives
/// through `RuntimeHost.persistent(...)`'s defaults below, and each test uses its own suite. Keep it
/// that way — a new caller that builds its own `UserDefaults`-backed persistence over a key another
/// one already owns reintroduces F-23, silently.
///
/// Only the type and the three default backings are `public`, and only because a `public` function's
/// default argument value cannot reference an internal declaration. The resolvers below are called
/// from this module alone.
@MainActor
public enum SharedCoordinationStores {
    // The default backings are singletons because that is what makes the default path collapse onto
    // one store per key: a fresh persistence per call would key a fresh store per call, which is the
    // bug this type exists to prevent.
    public static let defaultSharedSessionPersistence = UserDefaultsSharedSessionPersistence()
    public static let defaultRitualStatePersistence = UserDefaultsRitualStatePersistence()
    public static let defaultSocialEventLogPersistence = UserDefaultsSocialEventLogPersistence()

    private static var sharedSessionStores: [ObjectIdentifier: SharedSessionStore] = [:]
    private static var ritualStores: [ObjectIdentifier: RitualStore] = [:]
    private static var socialEventLogStores: [ObjectIdentifier: SocialEventLogStore] = [:]

    static func sharedSessionStore(
        for persistence: any SharedSessionPersisting & SocialPersistenceQuarantining
    ) -> SharedSessionStore {
        let key = ObjectIdentifier(persistence)
        if let existing = sharedSessionStores[key] { return existing }
        let store = SharedSessionStore(persistence: persistence)
        sharedSessionStores[key] = store
        return store
    }

    static func ritualStore(
        for persistence: any RitualStatePersisting & SocialPersistenceQuarantining
    ) -> RitualStore {
        let key = ObjectIdentifier(persistence)
        if let existing = ritualStores[key] { return existing }
        let store = RitualStore(persistence: persistence)
        ritualStores[key] = store
        return store
    }

    static func socialEventLogStore(
        for persistence: any SocialEventLogPersisting & SocialPersistenceQuarantining
    ) -> SocialEventLogStore {
        let key = ObjectIdentifier(persistence)
        if let existing = socialEventLogStores[key] { return existing }
        let store = SocialEventLogStore(persistence: persistence)
        socialEventLogStores[key] = store
        return store
    }

    /// Drops the memo tables. Tests only — a test that builds hosts over the default backings would
    /// otherwise inherit stores warmed by an earlier test in the same process.
    ///
    /// Deliberately not `public`: a production caller would leave already-built hosts holding the
    /// old store while the next host opens a fresh one over the same key, which is exactly the
    /// clobber this type prevents. `@testable import` reaches it at this access level.
    static func resetForTesting() {
        sharedSessionStores.removeAll()
        ritualStores.removeAll()
        socialEventLogStores.removeAll()
    }
}
