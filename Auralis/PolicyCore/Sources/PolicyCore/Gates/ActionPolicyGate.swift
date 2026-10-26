import ReceiptsCore
import RuntimeCore

/// Applies the current action policy and records denied execution-style behavior.
///
/// **Not the gate the app runs.** `ArchitectureBoundaryTests` bans `ActionPolicyGate.attempt(` from
/// app source and `PolicyAssembly` builds `PipelineBackedPolicyGate` instead, which routes through
/// `GovernedToolPipeline`. This type stays `public` because this package's own tests exercise it and
/// because it is the mode-policy rule in its simplest form. It is left un-deprecated only to keep a
/// clean build clean — not because anything calls it. Anyone wiring a new caller should wire the
/// governed pipeline.
@MainActor
public enum ActionPolicyGate {
    /// - Parameter actor: Structured attribution for the party attempting the action
    ///   (P0.5-602). Required, with no default: this gate writes the receipt for denied and high-risk
    ///   actions, so a defaulted human would make every agent-initiated attempt claim a person did it.
    public static func attempt(
        _ action: PolicyControlledAction,
        mode: CryptoMode,
        actor: ActorRef,
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
                // A readiness denial is a refusal and leaves a receipt, exactly as the Observe
                // denial below does. It used to return bare, so the one branch that refuses an
                // action in Assist or Operate — the modes where acting is possible — was the one
                // branch with no audit trail. Not gated on `requiresHighRiskReceipt`, for the same
                // reason the Observe denial is not: a refusal is worth recording whatever the
                // action's risk class.
                if let receiptStore {
                    await appendPolicyReceipt(
                        action: action,
                        mode: mode,
                        receiptStore: receiptStore,
                        payloadSanitizer: payloadSanitizer,
                        actorDetail: actor.receiptActorDetail,
                        decision: .denied,
                        userMessage: executionReadiness.userMessage,
                        log: log
                    )
                }
                return executionReadiness
            }

            if action.requiresHighRiskReceipt, let receiptStore {
                await appendPolicyReceipt(
                    action: action,
                    mode: mode,
                    receiptStore: receiptStore,
                    payloadSanitizer: payloadSanitizer,
                    actorDetail: actor.receiptActorDetail,
                    decision: .approved,
                    userMessage: "Policy allowed this high-risk action.",
                    log: log
                )
            }
            return PolicyGateResult(isAllowed: true, userMessage: "")
        }

        let userMessage = "Not available in \(mode.rawValue) mode"
        log("Policy denied: \(action.rawValue)")

        if let receiptStore {
            await appendPolicyReceipt(
                action: action,
                mode: mode,
                receiptStore: receiptStore,
                payloadSanitizer: payloadSanitizer,
                actorDetail: actor.receiptActorDetail,
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

    /// What permitted (or refused) the action, from the gate's own point of view (P0.5-601/602).
    ///
    /// This gate consults no capability lease — it applies the app's standing mode policy — so
    /// `policyDefault` is the honest source in both directions. Recording it means the large majority
    /// of policy history stops persisting a null authority and can answer "what let this happen?"
    /// `ReceiptAuthorityDetail` rather than `RuntimeCore.AuthorityRef` for the same reason the actor
    /// is a `ReceiptActorDetail`: PolicyCore is a leaf.
    static func policyAuthority(
        action: PolicyControlledAction,
        decision: PolicyReceiptDecision,
        userMessage: String
    ) -> ReceiptAuthorityDetail {
        ReceiptAuthorityDetail(
            source: "policyDefault",
            capability: action.capabilityID.rawValue,
            reason: userMessage.isEmpty
                ? "Standing policy \(decision.rawValue) this action."
                : userMessage
        )
    }

    /// The receipt's own sentence, derived from the decision and the mode it was taken in.
    ///
    /// It used to be `action.summary` unconditionally. That property is the *Observe-mode
    /// unavailability* explanation — "Signing messages is not available in Observe mode." — which is
    /// right for the Observe denial and false everywhere else. Both other branches became reachable
    /// when `ReceiptMode` stopped having `.observe` as its only case, and neither was written for:
    /// a successful Operate signature wrote `isSuccess: true`, `mode: .operate`, and a summary
    /// asserting the action could not happen, on one row.
    ///
    /// The specific reason for a denial is not lost by this — it travels in the authority's `reason`
    /// and in the payload's `message` field, both built from `userMessage`.
    static func policyReceiptSummary(
        action: PolicyControlledAction,
        mode: CryptoMode,
        decision: PolicyReceiptDecision
    ) -> String {
        switch decision {
        case .approved:
            return "\(action.title) was allowed by standing policy in \(mode.label) mode."
        case .denied where mode == .observe && action.isBlockedInObserveMode:
            // The case `action.summary` is actually written for, in prose that names the capability.
            return action.summary
        case .denied:
            return "\(action.title) was denied by standing policy in \(mode.label) mode."
        }
    }

    static func appendPolicyReceipt(
        action: PolicyControlledAction,
        mode: CryptoMode,
        receiptStore: any ReceiptStore,
        payloadSanitizer: any ReceiptPayloadSanitizing,
        actorDetail: ReceiptActorDetail,
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
                    actorDetail: actorDetail,
                    authorityDetail: policyAuthority(
                        action: action,
                        decision: decision,
                        userMessage: userMessage
                    ),
                    mode: mode.receiptMode,
                    trigger: decision.trigger,
                    scope: "policy",
                    summary: policyReceiptSummary(action: action, mode: mode, decision: decision),
                    provenance: "policy",
                    isSuccess: decision == .approved,
                    // Deliberately un-correlated (P0.5-602): this gate applies standing mode policy to
                    // a single attempt, outside any session or workflow run. The governed path
                    // (`PipelineBackedPolicyGate` → `GovernedToolPipeline`) is the one that carries a
                    // correlation id, and files its receipts under the proposal's.
                    correlationID: nil,
                    details: payload
                )
            )
        } catch {
            log("Policy \(decision.rawValue) receipt append failed: \(error.localizedDescription)")
        }
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
            // Surfaced under the readable receipt's Approvals section (P1-301); the raw `decision`
            // field above is retained for existing readers and the policy summary.
            .public("approvalDecision", string: decision, kind: .label),
            .bool("policy_denied", decision == "denied"),
            .bool("policy_approved", decision == "approved"),
            .redacted("message", string: userMessage, kind: .freeformText)
        ]
    }
}
