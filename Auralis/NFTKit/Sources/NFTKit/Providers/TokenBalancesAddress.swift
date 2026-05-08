import Foundation

public struct TokenBalancesAddress: Equatable, Sendable {
    public let address: String
    public let networks: [String]

    public init(address: String, networks: [String]) {
        self.address = address
        self.networks = networks
    }
}
