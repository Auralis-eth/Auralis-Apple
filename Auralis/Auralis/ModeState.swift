import Observation
import PolicyCore
import SwiftUI

// MARK: - Mode System

/// Observable owner for the current app mode.
@MainActor
@Observable
public final class ModeState {
    public nonisolated static let storageDecisionIdentifier = "app.mode"

    @ObservationIgnored
    @AppStorage private var storedModeRaw: String

    /// The same store and key `storedModeRaw` writes through, held directly so ``refreshFromStorage()``
    /// can perform a genuine read.
    ///
    /// `@AppStorage`'s getter is **not** a live `UserDefaults` read when the wrapper lives outside a
    /// `View` — it resolves against a value captured at construction. A `refreshFromStorage()` written
    /// in terms of `storedModeRaw` therefore compiled, read plausibly, and did nothing at all; it is
    /// pinned by `ModeStateRefreshTests`, which failed against exactly that implementation.
    @ObservationIgnored
    private let store: UserDefaults
    @ObservationIgnored
    private let storageKey: String

    /// Keeps this instance in step with writes made through *any other* instance over the same store.
    ///
    /// Without it the mode plumbing was split in half. ``PersistedCryptoMode`` — the default
    /// `cryptoModeProvider`/`cryptoModeSetter` for every host built without explicit plumbing — owns
    /// its own private `ModeState`, and `RuntimeBackgroundScheduler` holds another for the life of the
    /// process. `mode` is a *stored* property, so a governed `setMode(.observe)` through either of
    /// those persisted the change while the instance injected into the SwiftUI environment went on
    /// reporting the old value. Settings showed Operate, `PolicyAssembly`'s gate evaluated as Operate,
    /// and every foreground receipt stamped `.operate` into the hashed `mode` column against a user
    /// who was persisted as Observe — the exact ledger corruption `PersistedCryptoMode` was written to
    /// prevent, reintroduced on the write side.
    ///
    /// `UserDefaults.didChangeNotification` is posted for in-process writes, so one subscription makes
    /// every instance converge. `mode` stays stored rather than becoming a computed read of `store`
    /// precisely so this path still drives `@Observable` invalidation and the UI actually re-renders.
    /// `nonisolated(unsafe)` so `deinit` — which is nonisolated — can unregister. Safe by
    /// construction: it is assigned exactly once during `init` and read exactly once in `deinit`,
    /// never concurrently, and `NotificationCenter.removeObserver` is itself thread-safe.
    @ObservationIgnored
    private nonisolated(unsafe) var storeObserver: (any NSObjectProtocol)?

    /// The currently active application mode.
    public private(set) var mode: CryptoMode = .observe

    /// Creates a mode state store and normalizes unknown persisted values to Observe.
    public init(
        userDefaults: UserDefaults? = nil,
        storageKey: String = "app.mode"
    ) {
        _storedModeRaw = AppStorage(
            wrappedValue: CryptoMode.observe.rawValue,
            storageKey,
            store: userDefaults
        )
        self.store = userDefaults ?? .standard
        self.storageKey = storageKey

        mode = CryptoMode(rawValue: storedModeRaw) ?? .observe
        storedModeRaw = mode.rawValue

        // Registered after the initial normalization so the first notification cannot race it.
        storeObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: self.store,
            queue: nil
        ) { [weak self] _ in
            // Hops to the main actor rather than assuming the notification arrives there: with
            // `queue: nil` it is delivered on the posting thread, and a background host's `setMode`
            // does not post from the main thread. `refreshFromStorage()` is an idempotent, guarded
            // read, so the hop cannot reorder into anything harmful.
            Task { @MainActor [weak self] in
                self?.refreshFromStorage()
            }
        }
    }

    deinit {
        if let storeObserver {
            NotificationCenter.default.removeObserver(storeObserver)
        }
    }

    public func setMode(_ mode: CryptoMode) {
        guard self.mode != mode else { return }
        self.mode = mode
        storedModeRaw = mode.rawValue
    }

    /// Re-reads the persisted mode into ``mode``.
    ///
    /// `mode` is a *stored* property, assigned once in `init` and thereafter only by ``setMode(_:)`` —
    /// it is not a computed view onto `@AppStorage`. So a long-lived instance that did not perform the
    /// write itself keeps reporting the mode as of its own construction. That matters wherever two
    /// instances exist over one `UserDefaults`: the background refresh holds a memoized `ModeState`
    /// for the life of the process, and without this it would evaluate policy and stamp the hashed
    /// receipt `mode` column as Operate against a user who had since dropped to Observe.
    ///
    /// Reads `store` directly rather than `storedModeRaw`, because `@AppStorage`'s getter is not a live
    /// read outside a `View` — see the `store`/`storageKey` properties. An absent or unparsable value
    /// degrades to `.observe`, the safe mode.
    ///
    /// Strictly a read: it must not write back. A normalizing `storedModeRaw = persisted.rawValue` here
    /// hung the app — this runs from `cryptoModeProvider`, which is consulted during view updates, and
    /// an `@AppStorage` write invalidates observers, so each read scheduled another update and the main
    /// thread spun (the Mission Control UI tests failed with "Unable to monitor event loop"). `init`
    /// already normalizes an unparsable stored value; nothing else needs to.
    public func refreshFromStorage() {
        let persisted = store.string(forKey: storageKey).flatMap(CryptoMode.init(rawValue:)) ?? .observe
        guard mode != persisted else { return }
        mode = persisted
    }
}

// MARK: - Environment integration

@MainActor
private struct ModeStateKey: EnvironmentKey {
    @MainActor
    private static let mainActorDefaultValue = ModeState()

    nonisolated static var defaultValue: ModeState {
        MainActor.assumeIsolated {
            mainActorDefaultValue
        }
    }
}

/// Environment accessors for reading and overriding the shared mode state.
public extension EnvironmentValues {
    /// The shared mode state injected into the SwiftUI environment.
    var modeState: ModeState {
        get { self[ModeStateKey.self] }
        set { self[ModeStateKey.self] = newValue }
    }
}

/// Convenience helpers for installing mode state into SwiftUI view hierarchies.
public extension View {
    /// Injects a shared ModeState into the environment.
    func modeState(_ state: ModeState) -> some View {
        environment(\.modeState, state)
    }
}

// MARK: - Receipt augmentation helper (Phase 0)

/// Lightweight helper for attaching the current mode to receipt-like payloads.
public struct ModeReceiptAugmentor {
    /// Returns a copy of the payload dictionary with the current app mode attached.
    @MainActor
    public static func attachMode(to dict: [String: Any], modeState: ModeState) -> [String: Any] {
        var out = dict
        out["mode"] = modeState.mode.rawValue
        return out
    }
}
