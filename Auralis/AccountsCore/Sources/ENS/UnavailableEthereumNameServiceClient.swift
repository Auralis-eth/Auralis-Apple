import Foundation

public struct UnavailableEthereumNameServiceClient: EthereumNameServiceClient, Sendable {
    private let error: ENSResolutionError

    public init(error: ENSResolutionError = .unavailableProvider) {
        self.error = error
    }

    public func resolveAddress(forENS name: String) async throws -> String {
        throw error
    }

    public func resolveName(forAddress address: String) async throws -> String {
        throw error
    }
}
