import AuralisPrimaryModels
import Foundation

public struct ActiveShellSelection: Equatable, Sendable {
    public let address: String
    public let chain: Chain

    public init(address: String, chain: Chain) {
        self.address = address
        self.chain = chain
    }
}
