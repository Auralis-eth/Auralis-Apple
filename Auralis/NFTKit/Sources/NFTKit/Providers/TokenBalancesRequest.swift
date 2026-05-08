import Foundation

public struct TokenBalancesRequest: Equatable, Sendable {
    public let addresses: [TokenBalancesAddress]
    public let includeNativeTokens: Bool
    public let includeErc20Tokens: Bool
    public let pageKey: String?

    public init(
        addresses: [TokenBalancesAddress],
        includeNativeTokens: Bool,
        includeErc20Tokens: Bool,
        pageKey: String?
    ) {
        self.addresses = addresses
        self.includeNativeTokens = includeNativeTokens
        self.includeErc20Tokens = includeErc20Tokens
        self.pageKey = pageKey
    }
}
