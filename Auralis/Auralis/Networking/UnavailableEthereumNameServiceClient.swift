import Foundation

struct UnavailableEthereumNameServiceClient: EthereumNameServiceClient {
    func resolveAddress(forENS name: String) async throws -> String {
        throw ENSResolutionError.unavailableProvider
    }

    func resolveName(forAddress address: String) async throws -> String {
        throw ENSResolutionError.unavailableProvider
    }
}
