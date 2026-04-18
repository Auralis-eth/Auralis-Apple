import Foundation

protocol ProviderConfigurationResolving: Sendable {
    func configuration(for chain: Chain) throws -> ProviderEndpointConfiguration
}
