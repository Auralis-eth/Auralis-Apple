/// The caller-facing result of a policy decision.
public struct PolicyGateResult: Equatable, Sendable {
    public let isAllowed: Bool
    public let userMessage: String

    public init(isAllowed: Bool, userMessage: String) {
        self.isAllowed = isAllowed
        self.userMessage = userMessage
    }
}
