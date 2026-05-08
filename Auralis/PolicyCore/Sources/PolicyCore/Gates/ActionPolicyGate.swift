import ReceiptsCore

/// Applies the current action policy and records denied execution-style behavior.
@MainActor
public enum ActionPolicyGate {
    public static func attempt(
        _ action: PolicyControlledAction,
        mode: AppMode,
        receiptStore: (any ReceiptStore)? = nil,
        payloadSanitizer: any ReceiptPayloadSanitizing = DefaultReceiptPayloadSanitizer(),
        log: @escaping (String) -> Void = { _ in }
    ) async -> PolicyGateResult {
        guard mode == .observe, action.isBlockedInObserveMode else {
            return PolicyGateResult(isAllowed: true, userMessage: "")
        }

        let userMessage = "Not available in Observe mode"
        log("Policy denied: \(action.rawValue)")

        if let receiptStore {
            let payload = payloadSanitizer.sanitize(
                PolicyDeniedReceiptPayload(
                    action: action.rawValue,
                    capabilityID: action.capabilityID.rawValue,
                    userMessage: userMessage
                ).rawPayload
            )

            do {
                _ = try await receiptStore.append(
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
        }

        return PolicyGateResult(isAllowed: false, userMessage: userMessage)
    }
}

private struct PolicyDeniedReceiptPayload: TypedReceiptPayload {
    let action: String
    let capabilityID: String
    let userMessage: String

    var fields: [ReceiptPayloadField] {
        [
            .public("action", string: action, kind: .label),
            .public("capabilityID", string: capabilityID, kind: .label),
            .bool("policy_denied", true),
            .redacted("message", string: userMessage, kind: .freeformText)
        ]
    }
}
