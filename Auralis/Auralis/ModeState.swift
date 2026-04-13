import SwiftUI

// MARK: - P0-601 Mode System (Observe v0)

/// The global application mode. Phase 0 is locked to `.observe`.
public enum AppMode: String, Codable, CaseIterable, Equatable {
    case observe = "Observe"
}

/// Observable owner for the current app mode.
/// Phase 0 persists via AppStorage and is locked to `.observe`.
public final class ModeState: ObservableObject {
    @AppStorage("app.mode") private var storedModeRaw: String = AppMode.observe.rawValue
    private let storageWriter: (String) -> Void

    @Published public private(set) var mode: AppMode = .observe

    public init(
        userDefaults: UserDefaults? = nil,
        storageKey: String = "app.mode"
    ) {
        if let userDefaults {
            storageWriter = { value in
                userDefaults.set(value, forKey: storageKey)
            }
        } else {
            storageWriter = { _ in }
        }

        // Phase 0 is hard-locked to Observe even if storage somehow contains another value.
        storedModeRaw = AppMode.observe.rawValue
        storageWriter(AppMode.observe.rawValue)
        mode = .observe
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

// MARK: - Policy gate (Phase 0)

enum PolicyControlledAction: String, CaseIterable, Sendable {
    case signMessage = "sign_message"
    case approveSpending = "approve_spending"
    case draftTransaction = "draft_transaction"
    case runPlugin = "run_plugin"

    var title: String {
        switch self {
        case .signMessage:
            return "Sign Message"
        case .approveSpending:
            return "Approve Spending"
        case .draftTransaction:
            return "Draft Transaction"
        case .runPlugin:
            return "Run Plugin"
        }
    }

    var summary: String {
        switch self {
        case .signMessage:
            return "Signing messages is not available in Observe mode."
        case .approveSpending:
            return "Token approvals are not available in Observe mode."
        case .draftTransaction:
            return "Transaction drafting is not available in Observe mode."
        case .runPlugin:
            return "Tool and plugin execution remains available in Observe mode."
        }
    }

    var isBlockedInObserveMode: Bool {
        switch self {
        case .signMessage, .approveSpending, .draftTransaction:
            return true
        case .runPlugin:
            return false
        }
    }
}

struct PolicyGateResult: Equatable, Sendable {
    let isAllowed: Bool
    let userMessage: String
}

/// Applies the current action policy and records denied execution-style behavior.
@MainActor
enum ActionPolicyGate {
    static func attempt(
        _ action: PolicyControlledAction,
        modeState: ModeState,
        receiptStore: any ReceiptStore,
        payloadSanitizer: any ReceiptPayloadSanitizing = DefaultReceiptPayloadSanitizer(),
        log: (String) -> Void = { print($0) }
    ) -> PolicyGateResult {
        guard modeState.mode == .observe, action.isBlockedInObserveMode else {
            return PolicyGateResult(isAllowed: true, userMessage: "")
        }

        let userMessage = "Not available in Observe mode"
        log("Policy denied: \(action.rawValue)")

        let payload = payloadSanitizer.sanitize(
            PolicyDeniedReceiptPayload(
                action: action.rawValue,
                userMessage: userMessage
            ).rawPayload
        )

        do {
            _ = try receiptStore.append(
                ReceiptDraft(
                    actor: .user,
                    mode: .observe,
                    trigger: "policy.denied",
                    scope: "policy",
                    summary: action.summary,
                    provenance: "policy",
                    isSuccess: false,
                    details: payload
                )
            )
        } catch {
            log("Policy denial receipt append failed: \(error.localizedDescription)")
        }

        return PolicyGateResult(isAllowed: false, userMessage: userMessage)
    }
}

private struct PolicyDeniedReceiptPayload: TypedReceiptPayload {
    let action: String
    let userMessage: String

    var fields: [ReceiptPayloadField] {
        [
            .public("action", string: action, kind: .label),
            .bool("policy_denied", true),
            .redacted("message", string: userMessage, kind: .freeformText)
        ]
    }
}
