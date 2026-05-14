import Foundation

public struct TokenBalanceRecord: Equatable, Sendable {
    public let network: String
    public let address: String
    public let tokenAddress: String?
    public let tokenBalance: String

    public init(
        network: String,
        address: String,
        tokenAddress: String?,
        tokenBalance: String
    ) {
        self.network = network
        self.address = address
        self.tokenAddress = tokenAddress
        self.tokenBalance = tokenBalance
    }
}
