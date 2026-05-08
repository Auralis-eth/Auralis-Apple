import Foundation

public struct ProviderTokenHolding: Equatable, Sendable {
    public let contractAddress: String
    public let symbol: String?
    public let displayName: String
    public let amountDisplay: String
    public let updatedAt: Date
    public let isPlaceholder: Bool
    public let isAmountHidden: Bool

    public init(
        contractAddress: String,
        symbol: String?,
        displayName: String,
        amountDisplay: String,
        updatedAt: Date,
        isPlaceholder: Bool,
        isAmountHidden: Bool
    ) {
        self.contractAddress = contractAddress
        self.symbol = symbol
        self.displayName = displayName
        self.amountDisplay = amountDisplay
        self.updatedAt = updatedAt
        self.isPlaceholder = isPlaceholder
        self.isAmountHidden = isAmountHidden
    }
}
