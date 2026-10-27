import AuralisRuntime

/// Service contract for callers that need policy-checked actions.
@MainActor
public protocol PolicyActionGating {
    /// Evaluates the *class* of action with no concrete payload — used by gates that only decide
    /// permission and never perform the effect.
    ///
    /// - Parameter actor: Who is attempting the action (P0.5-602). Required, with no default:
    ///   the gate writes a receipt for high-risk and denied actions, and a gate that guesses would
    ///   record a human as having attempted work an agent actually attempted. Policy accepts the
    ///   canonical runtime actor rather than a receipt-storage representation; receipt mapping is an
    ///   outer-boundary concern.
    func attempt(_ action: PolicyControlledAction, actor: ActorRef) async -> PolicyGateResult

    /// Evaluates an action carrying its concrete `payload` (message bytes, transaction, …). Gates that
    /// actually execute cleared actions use the payload to perform the real effect; gates that only
    /// decide permission ignore it (the default forwards to ``attempt(_:actor:)``).
    func attempt(
        _ action: PolicyControlledAction,
        payload: PolicyActionPayload?,
        actor: ActorRef
    ) async -> PolicyGateResult
}

public extension PolicyActionGating {
    func attempt(
        _ action: PolicyControlledAction,
        payload: PolicyActionPayload?,
        actor: ActorRef
    ) async -> PolicyGateResult {
        await attempt(action, actor: actor)
    }
}
