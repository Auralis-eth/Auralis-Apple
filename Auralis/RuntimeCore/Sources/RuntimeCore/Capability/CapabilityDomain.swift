import CapabilitiesCore

/// Classifies a capability by product domain, so governance can apply the crypto-scoped Observe
/// boundary (ADR-010): only `.wallet` capabilities are gated; everything else operates fully.
public enum CapabilityDomain {
    /// Whether a capability is crypto/wallet and therefore subject to the Observe boundary.
    public static func isCrypto(_ capability: CapabilityID) -> Bool {
        CapabilityRegistry.descriptor(for: capability).category == .wallet
    }
}
