/// Side-effect-free standing policy used by governed tool runtimes.
/// Receipt emission belongs to the runtime's terminal evidence phase, not policy evaluation.
public enum StandingToolPolicyVerdict: Equatable, Sendable {
    case allow
    case block(reason: String)
    case requireApproval(prompt: String)
}

public enum StandingToolPolicy {
    public static func evaluate(
        action: PolicyControlledAction,
        mode: CryptoMode,
        isCryptoCapability: Bool,
        requiresConfirmation: Bool,
        intent: String
    ) -> StandingToolPolicyVerdict {
        if isCryptoCapability {
            switch mode {
            case .observe where action.isBlockedInObserveMode:
                // Names the action with the human-readable `intent`, as the `.requireApproval`
                // branches below already do. This reason is not internal diagnostics: it reaches a
                // person verbatim through `PipelineBackedPolicyGate` → `PolicyGateResult.userMessage`
                // → the "Policy decision" alert, and `action.rawValue` is a schema identifier — the
                // alert used to read "AuralisPolicy denied sign_message in Observe mode."
                return .block(reason: "“\(intent)” is not available in Observe mode.")
            case .assist:
                return .requireApproval(prompt: "Policy approval required for “\(intent)”.")
            case .observe, .operate:
                break
            }
        }

        if requiresConfirmation {
            return .requireApproval(prompt: "Policy approval required for “\(intent)”.")
        }
        return .allow
    }
}
