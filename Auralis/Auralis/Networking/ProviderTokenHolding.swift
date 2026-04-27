import Foundation

struct ProviderTokenHolding: Equatable, Sendable {
    let contractAddress: String
    let symbol: String?
    let displayName: String
    let amountDisplay: String
    let updatedAt: Date
    let isPlaceholder: Bool
    let isAmountHidden: Bool
}
