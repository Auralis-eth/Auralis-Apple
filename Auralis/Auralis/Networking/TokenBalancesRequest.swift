import Foundation

struct TokenBalancesRequest: Equatable, Sendable {
    let addresses: [TokenBalancesAddress]
    let includeNativeTokens: Bool
    let includeErc20Tokens: Bool
    let pageKey: String?
}
