import AuralisPrimaryModels

/// Chains that future signing and transaction-drafting paths may target.
///
/// The default policy is intentionally empty. Shipping code must opt in to each
/// chain before a signing-capable flow can become executable.
public struct SigningChainAllowlist: Equatable, Sendable {
    private let allowedChains: [Chain]

    public init(allowedChains: some Sequence<Chain>) {
        self.allowedChains = Array(allowedChains)
    }

    public func contains(_ chain: Chain) -> Bool {
        allowedChains.contains(chain)
    }

    public static let denyAll = SigningChainAllowlist(allowedChains: [])
}
