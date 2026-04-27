import Foundation

struct UnavailableEthereumNameServiceClient: EthereumNameServiceClient, Sendable {
    private let error: ENSResolutionError

    init(error: ENSResolutionError = .unavailableProvider) {
        self.error = error
    }

    func resolveAddress(forENS name: String) async throws -> String {
        throw error
    }

    func resolveName(forAddress address: String) async throws -> String {
        throw error
    }
}
