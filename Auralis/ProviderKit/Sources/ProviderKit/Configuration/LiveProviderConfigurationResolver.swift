import AuralisPrimaryModels
import Foundation

public struct LiveProviderConfigurationResolver: ProviderConfigurationResolving {
    private let keyProvider: @Sendable (Secrets.APIKeyProvider) -> String?

    public init(
        keyProvider: @escaping @Sendable (Secrets.APIKeyProvider) -> String? = { Secrets.apiKeyOrNil($0) }
    ) {
        self.keyProvider = keyProvider
    }

    public func configuration(for chain: Chain) throws -> ProviderEndpointConfiguration {
        let alchemyKey = keyProvider(.alchemy)
        let heliusKey = keyProvider(.helius)

        let alchemyNFTBaseURL = try alchemyKey.flatMap {
            try Self.url("https://\(chain.rawValue).g.alchemy.com/nft/v3/\($0)")
        }
        let alchemyDataAPIBaseURL = try alchemyKey.flatMap {
            try Self.url("https://api.g.alchemy.com/data/v1/\($0)")
        }
        let alchemyRPCURL = try alchemyKey.flatMap {
            try Self.url("https://\(chain.rawValue).g.alchemy.com/v2/\($0)")
        }

        let heliusDASBaseURL = try heliusKey.flatMap { _ in
            try Self.url("https://mainnet.helius-rpc.com/")
        }

        let configuration = ProviderEndpointConfiguration(
            chain: chain,
            alchemyNFTBaseURL: alchemyNFTBaseURL,
            alchemyDataAPIBaseURL: alchemyDataAPIBaseURL,
            alchemyRPCURL: chain.supportsProviderRPC ? alchemyRPCURL : nil,
            heliusDASBaseURL: chain == .solanaMainnet ? heliusDASBaseURL : nil
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

private extension Chain {
    var supportsProviderRPC: Bool {
        switch self {
        case .solanaMainnet, .solanaDevnetTestnet:
            return false
        default:
            return true
        }
    }
}
