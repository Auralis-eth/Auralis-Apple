import Foundation

protocol ProviderConfigurationResolving {
    func configuration(for chain: Chain) throws -> ProviderEndpointConfiguration
}
