import Foundation

struct LiveProviderConfigurationResolver: ProviderConfigurationResolving {
    private let keyProvider: (Secrets.APIKeyProvider) -> String?

    init(
        keyProvider: @escaping (Secrets.APIKeyProvider) -> String? = { Secrets.apiKeyOrNil($0) }
    ) {
        self.keyProvider = keyProvider
    }

    func configuration(for chain: Chain) throws -> ProviderEndpointConfiguration {
        let alchemyKey = keyProvider(.alchemy)

        let alchemyNFTBaseURL = try alchemyKey.flatMap {
            try Self.url("https://\(chain.rawValue).g.alchemy.com/nft/v3/\($0)")
        }
        let alchemyDataAPIBaseURL = try alchemyKey.flatMap {
            try Self.url("https://api.g.alchemy.com/data/v1/\($0)")
        }
        let alchemyRPCURL = try alchemyKey.flatMap {
            try Self.url("https://\(chain.rawValue).g.alchemy.com/v2/\($0)")
        }

        let configuration = ProviderEndpointConfiguration(
            chain: chain,
            alchemyNFTBaseURL: alchemyNFTBaseURL,
            alchemyDataAPIBaseURL: alchemyDataAPIBaseURL,
            alchemyRPCURL: chain.supportsEVMRPC ? alchemyRPCURL : nil
        )
        return configuration
    }

    private static func url(_ string: String) throws -> URL {
        guard let url = URL(string: string) else {
            throw ProviderAbstractionError.invalidURL
        }

        return url
    }
}
