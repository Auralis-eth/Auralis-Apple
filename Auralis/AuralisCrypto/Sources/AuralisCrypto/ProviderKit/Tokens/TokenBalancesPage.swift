import Foundation

public struct TokenBalancesPage: Equatable, Sendable {
    public let tokens: [TokenBalanceRecord]
    public let pageKey: String?

    public init(tokens: [TokenBalanceRecord], pageKey: String?) {
        self.tokens = tokens
        self.pageKey = pageKey
    }
}
