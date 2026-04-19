import Foundation
import web3

final class Web3EthereumNameServiceClient: EthereumNameServiceClient, Sendable {
    private let rpcURL: URL

    init(rpcURL: URL) {
        self.rpcURL = rpcURL
    }

    func resolveAddress(forENS name: String) async throws -> String {
        let address = try await makeEthereumNameService().resolve(
            ens: name,
            mode: .allowOffchainLookup
        )
        return address.asString()
    }

    func resolveName(forAddress address: String) async throws -> String {
        try await makeEthereumNameService().resolve(
            address: EthereumAddress(address),
            mode: .allowOffchainLookup
        )
    }

    private func makeEthereumNameService() -> EthereumNameService {
        let client = EthereumHttpClient(url: rpcURL, network: .mainnet)
        return EthereumNameService(client: client)
    }
}
