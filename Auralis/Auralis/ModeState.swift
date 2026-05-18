import Observation
import PolicyCore
import SwiftUI

// MARK: - P0-601 Mode System (Observe v0)

/// Observable owner for the current app mode.
/// Phase 0 persists via AppStorage and is locked to `.observe`.
@MainActor
@Observable
public final class ModeState {
    public nonisolated static let storageDecisionIdentifier = "app.mode"

    @ObservationIgnored
    @AppStorage private var storedModeRaw: String

    /// The currently active application mode.
    public private(set) var mode: AppMode = .observe

    /// Creates a mode state store and normalizes persisted values to the Phase 0 observe-only mode.
    public init(
        userDefaults: UserDefaults? = nil,
        storageKey: String = "app.mode"
    ) {
        _storedModeRaw = AppStorage(
            wrappedValue: AppMode.observe.rawValue,
            storageKey,
            store: userDefaults
        )

        // Phase 0 is hard-locked to Observe even if storage somehow contains another value.
        storedModeRaw = AppMode.observe.rawValue
        mode = .observe
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
