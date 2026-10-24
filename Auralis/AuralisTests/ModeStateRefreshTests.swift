@testable import Auralis
import Foundation
import PolicyCore
import Testing

/// `ModeState.refreshFromStorage()` must actually re-read persisted storage.
///
/// `ModeState.mode` is a *stored* property, assigned once in `init` and thereafter only by `setMode`.
/// Anywhere two instances exist over one `UserDefaults` — the background refresh holds a memoized one
/// for the life of the process, and `PersistedCryptoMode` holds another — a long-lived instance that
/// did not perform the write keeps reporting the mode as of its own construction. That would mean
/// background work evaluating policy, and stamping the hashed receipt `mode` column, against a mode
/// the user has already left.
///
/// The fix relies on `@AppStorage`'s getter being a *live* read of the underlying store even though the
/// property wrapper lives on a non-`View` `@Observable` class. That is the load-bearing assumption, and
/// it is an assumption about framework behavior rather than about this codebase — so it is pinned here
/// rather than reasoned about. If SwiftUI ever changes it, this suite fails instead of the ledger
/// quietly recording the wrong mode.
@MainActor
@Suite("ModeState storage refresh")
struct ModeStateRefreshTests {
    /// An isolated suite so these never touch `UserDefaults.standard` or the real `app.mode` key.
    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "ModeStateRefreshTests." + UUID().uuidString
        return try #require(UserDefaults(suiteName: suiteName))
    }

    @Test("a second instance observes a mode written by the first")
    func refreshObservesAnotherInstancesWrite() throws {
        let defaults = try makeDefaults()
        let key = "app.mode.test"

        let writer = ModeState(userDefaults: defaults, storageKey: key)
        let reader = ModeState(userDefaults: defaults, storageKey: key)
        #expect(reader.mode == .observe)

        writer.setMode(.operate)

        // Without the refresh, `reader` still reports its construction-time value.
        reader.refreshFromStorage()
        #expect(reader.mode == .operate)
    }

    /// The precise background-refresh scenario: a long-lived instance must see a mode the user changed
    /// through a *different* instance after it was constructed.
    @Test("a long-lived instance tracks later changes across refreshes")
    func longLivedInstanceTracksLaterChanges() throws {
        let defaults = try makeDefaults()
        let key = "app.mode.test"

        let foreground = ModeState(userDefaults: defaults, storageKey: key)
        let background = ModeState(userDefaults: defaults, storageKey: key)

        foreground.setMode(.operate)
        background.refreshFromStorage()
        #expect(background.mode == .operate)

        // The user drops back to Observe; the background instance must follow, not stay on Operate.
        foreground.setMode(.observe)
        background.refreshFromStorage()
        #expect(background.mode == .observe)
    }

    /// Convergence without anyone calling `refreshFromStorage()`.
    ///
    /// This is the half that was missing. `refreshFromStorage()` was correct and tested, but nothing
    /// invoked it on the instance the SwiftUI environment holds — `PersistedCryptoMode` (the default
    /// `cryptoModeSetter` for every host built without explicit plumbing) writes through its own
    /// private instance, and `RuntimeBackgroundScheduler` holds a third. A governed `setMode(.observe)`
    /// through either persisted the change while the UI instance kept reporting Operate, which is what
    /// fed the stale value to the policy gate and into the hashed receipt `mode` column.
    @Test("an instance converges on another's write without an explicit refresh")
    func instanceConvergesWithoutExplicitRefresh() async throws {
        let defaults = try makeDefaults()
        let key = "app.mode.test"

        let writer = ModeState(userDefaults: defaults, storageKey: key)
        let liveUIInstance = ModeState(userDefaults: defaults, storageKey: key)
        #expect(liveUIInstance.mode == .observe)

        writer.setMode(.operate)

        // Notification delivery hops to the main actor, so yield rather than asserting synchronously.
        for _ in 0..<100 where liveUIInstance.mode != .operate {
            await Task.yield()
        }
        #expect(liveUIInstance.mode == .operate, "a write through another instance never propagated")
    }

    /// And in the safety-critical direction: a demotion to Observe must propagate too, since that is
    /// the one the policy gate must not miss.
    @Test("a demotion to observe propagates without an explicit refresh")
    func demotionPropagatesWithoutExplicitRefresh() async throws {
        let defaults = try makeDefaults()
        let key = "app.mode.test"

        let writer = ModeState(userDefaults: defaults, storageKey: key)
        let liveUIInstance = ModeState(userDefaults: defaults, storageKey: key)

        writer.setMode(.operate)
        for _ in 0..<100 where liveUIInstance.mode != .operate {
            await Task.yield()
        }

        writer.setMode(.observe)
        for _ in 0..<100 where liveUIInstance.mode != .observe {
            await Task.yield()
        }
        #expect(liveUIInstance.mode == .observe)
    }

    /// A write through `PersistedCryptoMode` — the defaulted setter — reaches an independent instance.
    @Test("a PersistedCryptoMode write reaches an instance over the same store")
    func persistedCryptoModeWritePropagates() async throws {
        let defaults = try makeDefaults()
        let key = "app.mode.test"
        let observer = ModeState(userDefaults: defaults, storageKey: key)

        // Mirrors what `PersistedCryptoMode.set` does: refresh, then write, through a separate
        // instance over the same store.
        let setter = ModeState(userDefaults: defaults, storageKey: key)
        setter.refreshFromStorage()
        setter.setMode(.assist)

        for _ in 0..<100 where observer.mode != .assist {
            await Task.yield()
        }
        #expect(observer.mode == .assist)
    }

    @Test("refreshing with no external change is a no-op")
    func refreshWithoutChangeKeepsMode() throws {
        let defaults = try makeDefaults()
        let key = "app.mode.test"

        let state = ModeState(userDefaults: defaults, storageKey: key)
        state.setMode(.operate)

        state.refreshFromStorage()
        #expect(state.mode == .operate)
    }

    /// An unparsable persisted value degrades to the safe mode rather than trapping or holding stale.
    @Test("an unknown persisted value refreshes to observe")
    func unknownPersistedValueRefreshesToObserve() throws {
        let defaults = try makeDefaults()
        let key = "app.mode.test"

        let state = ModeState(userDefaults: defaults, storageKey: key)
        state.setMode(.operate)

        defaults.set("not-a-mode", forKey: key)
        state.refreshFromStorage()

        #expect(state.mode == .observe)
    }
}
