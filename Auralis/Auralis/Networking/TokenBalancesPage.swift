import Foundation

struct TokenBalancesPage: Equatable, Sendable {
    let tokens: [TokenBalanceRecord]
    let pageKey: String?
}
