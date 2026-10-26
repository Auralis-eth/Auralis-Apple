/// Chains that future signing and transaction-drafting paths may target.
///
/// The default policy is intentionally empty. Shipping code must opt in to each
/// chain before a signing-capable flow can become executable.
public struct SigningChainAllowlist: Equatable, Sendable {
    private let allowedChains: Set<PolicyChainReference>

    public init(allowedChains: some Sequence<PolicyChainReference>) {
        self.allowedChains = Set(allowedChains)
    }

    public func contains(_ chain: PolicyChainReference) -> Bool {
        allowedChains.contains(chain)
    }

    public static let denyAll = SigningChainAllowlist(allowedChains: [])
}
