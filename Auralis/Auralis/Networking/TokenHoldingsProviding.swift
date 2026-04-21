import Foundation

struct TokenHoldingsProviderWarning: Equatable, Sendable {
    let message: String
}

struct TokenHoldingsFetchResult: Equatable, Sendable {
    let holdings: [ProviderTokenHolding]
    let warning: TokenHoldingsProviderWarning?
}

protocol TokenHoldingsProviding {
    func tokenHoldings(for address: String, chain: Chain) async throws -> TokenHoldingsFetchResult
}
