import AuralisPrimaryModels
import ReceiptsCore

/// Applies the current action policy and records denied execution-style behavior.
@MainActor
public enum ActionPolicyGate {
    public static func attempt(
        _ action: PolicyControlledAction,
        mode: AppMode,
        executionEvidence: PolicyExecutionEvidence = .none,
        signingChainAllowlist: SigningChainAllowlist = .denyAll,
        receiptStore: (any ReceiptStore)? = nil,
        payloadSanitizer: any ReceiptPayloadSanitizing = DefaultReceiptPayloadSanitizer(),
        log: @escaping (String) -> Void = { _ in }
    ) async -> PolicyGateResult {
        guard mode == .observe, action.isBlockedInObserveMode else {
            let executionReadiness = PolicyExecutionReadiness.evaluate(
                action: action,
                evidence: executionEvidence,
                signingChainAllowlist: signingChainAllowlist
            )
            guard executionReadiness.isAllowed else {
                log("Policy denied: \(action.rawValue) \(executionReadiness.userMessage)")
                return executionReadiness
            }

            if action.requiresHighRiskReceipt, let receiptStore {
                await appendPolicyReceipt(
                    action: action,
                    mode: mode,
                    receiptStore: receiptStore,
                    payloadSanitizer: payloadSanitizer,
                    decision: .approved,
                    userMessage: "Policy allowed this high-risk action.",
                    log: log
                )
            }
            return PolicyGateResult(isAllowed: true, userMessage: "")
        }

        let userMessage = "Not available in Observe mode"
        log("Policy denied: \(action.rawValue)")

        if let receiptStore {
            await appendPolicyReceipt(
                action: action,
                mode: mode,
                receiptStore: receiptStore,
                payloadSanitizer: payloadSanitizer,
                decision: .denied,
                userMessage: userMessage,
                log: log
            )
        }

        return PolicyGateResult(isAllowed: false, userMessage: userMessage)
    }
}

private extension ActionPolicyGate {
    enum PolicyReceiptDecision: String {
        case approved
        case denied

        var trigger: String {
            "policy.\(rawValue)"
        }
    }

    static func appendPolicyReceipt(
        action: PolicyControlledAction,
        mode: AppMode,
        receiptStore: any ReceiptStore,
        payloadSanitizer: any ReceiptPayloadSanitizing,
        decision: PolicyReceiptDecision,
        userMessage: String,
        log: @escaping (String) -> Void
    ) async {
        let payload = payloadSanitizer.sanitize(
            PolicyDecisionReceiptPayload(
                action: action.rawValue,
                capabilityID: action.capabilityID.rawValue,
                decision: decision.rawValue,
                userMessage: userMessage
            ).rawPayload
        )

        do {
            _ = try await receiptStore.append(
                ReceiptDraft(
                    actor: .user,
                    mode: mode.receiptMode,
                    trigger: decision.trigger,
                    scope: "policy",
                    summary: action.summary,
                    provenance: "policy",
                    isSuccess: decision == .approved,
                    details: payload
                )
            )
        } catch {
            log("Policy \(decision.rawValue) receipt append failed: \(error.localizedDescription)")
        }
    }
}

private extension AppMode {
    var receiptMode: ReceiptMode {
        ReceiptMode(rawValue: rawValue) ?? .observe
    }
}

private struct PolicyDecisionReceiptPayload: TypedReceiptPayload {
    let action: String
    let capabilityID: String
    let decision: String
    let userMessage: String

    var fields: [ReceiptPayloadField] {
        [
            .public("action", string: action, kind: .label),
            .public("capabilityID", string: capabilityID, kind: .label),
            .public("decision", string: decision, kind: .label),
            .bool("policy_denied", decision == "denied"),
            .bool("policy_approved", decision == "approved"),
            .redacted("message", string: userMessage, kind: .freeformText)
        ]
    }
}
