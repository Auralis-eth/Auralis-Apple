import Foundation
import web3

struct Web3EthereumNameServiceClient: EthereumNameServiceClient, @unchecked Sendable {
    private let ethereumNameService: EthereumNameService

    init(rpcURL: URL) {
        let client = EthereumHttpClient(url: rpcURL, network: .mainnet)
        self.ethereumNameService = EthereumNameService(client: client)
    }

    func resolveAddress(forENS name: String) async throws -> String {
        let address = try await ethereumNameService.resolve(
            ens: name,
            mode: .allowOffchainLookup
        )
        return address.asString()
    }

    func resolveName(forAddress address: String) async throws -> String {
        let name = try await ethereumNameService.resolve(
            address: EthereumAddress(address),
            mode: .allowOffchainLookup
        )
        return name
    }
}
