import Foundation

struct ContextBalancesSummary: Equatable, Sendable {
    let nativeBalanceDisplay: ContextField<String>
    let nativeBalanceStatusMessage: ContextField<String>
}
