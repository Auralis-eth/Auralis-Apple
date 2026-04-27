import Foundation

protocol EthereumNameServiceClient: Sendable {
    var allowsOffchainLookup: Bool { get }
    func resolveAddress(forENS name: String) async throws -> String
    func resolveName(forAddress address: String) async throws -> String
}

extension EthereumNameServiceClient {
    var allowsOffchainLookup: Bool { false }
}
