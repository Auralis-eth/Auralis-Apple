import Foundation

protocol TokenBalancesProviding {
    func tokenBalances(for request: TokenBalancesRequest) async throws -> TokenBalancesPage
}
