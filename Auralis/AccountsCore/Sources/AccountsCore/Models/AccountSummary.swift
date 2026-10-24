import AuralisPrimaryModels
import Foundation

/// Portable account-domain summary used by account presentation without exposing persistence.
public struct AccountSummary: Hashable, Codable, Sendable {
    public let address: AuralisEthereumAddress
    public let name: String?
    public let source: EOAccountSource
    public let preferredChain: Chain
    public let currentChain: Chain

    public init(
        address: AuralisEthereumAddress,
        name: String?,
        source: EOAccountSource,
        preferredChain: Chain,
        currentChain: Chain
    ) {
        self.address = address
        self.name = name
        self.source = source
        self.preferredChain = preferredChain
        self.currentChain = currentChain
    }
}
