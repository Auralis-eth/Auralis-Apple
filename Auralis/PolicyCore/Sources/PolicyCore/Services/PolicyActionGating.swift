/// Service contract for callers that need policy-checked actions.
@MainActor
public protocol PolicyActionGating {
    func attempt(_ action: PolicyControlledAction) async -> PolicyGateResult
}
