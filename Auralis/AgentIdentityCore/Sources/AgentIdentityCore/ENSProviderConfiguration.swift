import AuralisPrimaryModels
import Foundation

public protocol ENSProviderConfigurationResolving: Sendable {
    func ensProviderConfiguration(for chain: Chain) throws -> ENSProviderEndpointConfiguration
}

public struct ENSProviderEndpointConfiguration: Equatable, Sendable {
    public let chain: Chain
    public let rpcURL: URL?

    public init(chain: Chain, rpcURL: URL?) {
        self.chain = chain
        self.rpcURL = rpcURL
    }
}

public enum ENSProviderConfigurationError: Error, Equatable, Sendable {
    case missingProviderConfiguration
    case invalidProviderConfiguration
    case unavailableProvider
}
