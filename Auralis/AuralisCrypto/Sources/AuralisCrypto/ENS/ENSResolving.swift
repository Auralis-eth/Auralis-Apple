import Foundation

/// Resolves ENS names and addresses for wallet-facing surfaces.
///
/// Methods may be called from any actor. Conformers are responsible for synchronizing access to
/// their internal caches and transport clients.
public protocol ENSResolving: Sendable {
    /// Returns the cached forward lookup result if one is already available.
    func cachedForwardResolution(forENS name: String) async -> ENSForwardResolution?
    /// Returns the cached reverse lookup result if one is already available.
    func cachedReverseResolution(forAddress address: String) async -> ENSReverseResolution?
    /// Performs a network-backed ENS lookup for a name.
    func resolveAddress(forENS name: String, correlationID: String?) async throws -> ENSForwardResolution
    /// Performs a network-backed reverse ENS lookup for an address.
    func reverseLookup(address: String, correlationID: String?) async -> ENSReverseResolution?
}
