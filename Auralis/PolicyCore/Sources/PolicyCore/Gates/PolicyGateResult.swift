/// The caller-facing result of a policy decision.
public struct PolicyGateResult: Equatable, Sendable {
    public let isAllowed: Bool
    public let userMessage: String
    /// Effect output for actions that actually executed (e.g. `signature`, `transactionHash`). Empty for
    /// permission-only gates and for denied/escalated outcomes.
    public let outputs: [String: String]

    public init(isAllowed: Bool, userMessage: String, outputs: [String: String] = [:]) {
        self.isAllowed = isAllowed
        self.userMessage = userMessage
        self.outputs = outputs
    }
}
