import AuralisPrimaryModels
import Foundation

public protocol ProviderConfigurationResolving: Sendable {
    func configuration(for chain: Chain) throws -> ProviderEndpointConfiguration
}
