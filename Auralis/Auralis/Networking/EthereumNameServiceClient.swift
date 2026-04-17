import Foundation

protocol EthereumNameServiceClient {
    func resolveAddress(forENS name: String) async throws -> String
    func resolveName(forAddress address: String) async throws -> String
}
