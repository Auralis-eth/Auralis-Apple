import Foundation

struct TokenBalanceRecord: Equatable, Sendable {
    let network: String
    let address: String
    let tokenAddress: String?
    let tokenBalance: String
}
