import Foundation

protocol ENSResolving {
    func cachedForwardResolution(forENS name: String) async -> ENSForwardResolution?
    func cachedReverseResolution(forAddress address: String) async -> ENSReverseResolution?
    func resolveAddress(forENS name: String, correlationID: String?) async throws -> ENSForwardResolution
    func reverseLookup(address: String, correlationID: String?) async -> ENSReverseResolution?
}
