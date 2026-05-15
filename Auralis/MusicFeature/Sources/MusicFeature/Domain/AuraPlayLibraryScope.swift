import AuralisPrimaryModels
import Foundation

/// Identifies the active account-and-chain scope for AuraPlay library queries.
public struct AuraPlayLibraryScope: Equatable, Sendable {
    public let accountAddress: String?
    public let chain: Chain

    public init(accountAddress: String?, chain: Chain) {
        self.accountAddress = accountAddress
        self.chain = chain
    }
}
