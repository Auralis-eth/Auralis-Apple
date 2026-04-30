import Foundation

/// Identifies the active wallet-and-chain scope for AuraPlay library queries.
struct AuraPlayLibraryScope: Equatable, Sendable {
    let accountAddress: String?
    let chain: Chain
}
