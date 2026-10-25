import AuralisPrimaryModels
import Foundation
import ProviderKit

public struct ProviderBackedENSConfigurationResolver: ENSProviderConfigurationResolving {
    private let configurationResolver: any ProviderConfigurationResolving

    public init(configurationResolver: any ProviderConfigurationResolving) {
        self.configurationResolver = configurationResolver
    }

    public func ensProviderConfiguration(for chain: Chain) throws -> ENSProviderEndpointConfiguration {
        do {
            let configuration = try configurationResolver.configuration(for: chain)
            return ENSProviderEndpointConfiguration(
                chain: configuration.chain,
                rpcURL: configuration.alchemyRPCURL
            )
        } catch ProviderAbstractionError.invalidURL {
            throw ENSProviderConfigurationError.invalidProviderConfiguration
        } catch ProviderAbstractionError.missingAPIKey(_) {
            throw ENSProviderConfigurationError.missingProviderConfiguration
        } catch {
            throw ENSProviderConfigurationError.unavailableProvider
        }
    }
}
