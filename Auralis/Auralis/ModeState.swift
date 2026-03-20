import SwiftUI
import Combine

// MARK: - P0-601 Mode System (Observe v0)

/// The global application mode. Phase 0 is locked to `.observe`.
public enum AppMode: String, Codable, CaseIterable, Equatable {
    case observe = "Observe"
}

/// Observable owner for the current app mode.
/// Phase 0 persists via AppStorage and is locked to `.observe`.
public final class ModeState: ObservableObject {
    @AppStorage("app.mode") private var storedModeRaw: String = AppMode.observe.rawValue

    @Published public private(set) var mode: AppMode = .observe

    public init() {
        // Ensure stored value is valid; otherwise reset to .observe
        if let parsed = AppMode(rawValue: storedModeRaw) {
            mode = parsed
        } else {
            storedModeRaw = AppMode.observe.rawValue
            mode = .observe
        }
    }

    /// Internal setter to keep storage in sync. Exposed for future phases.
    public func setMode(_ newMode: AppMode) {
        // In Phase 0, we still allow setting for future-proofing, but callers shouldn't expose UI.
        mode = newMode
        storedModeRaw = newMode.rawValue
    }
}

// MARK: - Environment integration

private struct ModeStateKey: EnvironmentKey {
    static let defaultValue: ModeState = ModeState()
}

public extension EnvironmentValues {
    var modeState: ModeState {
        get { self[ModeStateKey.self] }
        set { self[ModeStateKey.self] = newValue }
    }
}

public extension View {
    /// Injects a shared ModeState into the environment.
    func modeState(_ state: ModeState) -> some View {
        environment(\.modeState, state)
    }
}

// MARK: - Receipt augmentation helper (Phase 0)

/// Lightweight helper for attaching the current mode to receipt-like payloads.
public struct ModeReceiptAugmentor {
    public static func attachMode(to dict: [String: Any], modeState: ModeState) -> [String: Any] {
        var out = dict
        out["mode"] = modeState.mode.rawValue
        return out
    }
}

// MARK: - Execute policy gate (Phase 0)

/// Denies any execute/action behavior while in Observe mode. Logs a message for diagnostics.
public enum ExecutePolicyGate {
    public static func canExecute(modeState: ModeState, log: (String) -> Void = { print($0) }) -> Bool {
        if modeState.mode == .observe {
            log("Execute denied: app is in Observe mode (P0)")
            return false
        }
        return true
    }
}
