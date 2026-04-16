import Foundation

protocol TokenHoldingsProviding {
    func tokenHoldings(for address: String, chain: Chain) async throws -> [ProviderTokenHolding]
}
