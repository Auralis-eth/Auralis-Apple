import AuralisPrimaryModels
import Foundation

public struct TokenHoldingsProviderWarning: Equatable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

public struct TokenHoldingsFetchResult: Equatable, Sendable {
    public let holdings: [ProviderTokenHolding]
    public let warning: TokenHoldingsProviderWarning?

    public init(holdings: [ProviderTokenHolding], warning: TokenHoldingsProviderWarning?) {
        self.holdings = holdings
        self.warning = warning
    }
}

public protocol TokenHoldingsProviding {
    func tokenHoldings(for address: String, chain: Chain) async throws -> TokenHoldingsFetchResult
}
