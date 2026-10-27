public struct ContextBalancesSummary: Equatable, Sendable {
    public let nativeBalanceDisplay: ContextField<String>
    public let nativeBalanceStatusMessage: ContextField<String>

    public init(
        nativeBalanceDisplay: ContextField<String>,
        nativeBalanceStatusMessage: ContextField<String>
    ) {
        self.nativeBalanceDisplay = nativeBalanceDisplay
        self.nativeBalanceStatusMessage = nativeBalanceStatusMessage
    }
}
