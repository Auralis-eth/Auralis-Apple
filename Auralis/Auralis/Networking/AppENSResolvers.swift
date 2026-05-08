import ReceiptsCore
import AgentIdentityCore
import AuralisPrimaryModels
import Foundation
import SwiftData

@MainActor
extension ENSResolvers {
    static func live(
        modelContext: ModelContext,
        configurationResolver: any ProviderConfigurationResolving = LiveProviderConfigurationResolver(),
        cacheStore: ENSResolutionCacheStore = sharedCacheStore
    ) -> any ENSResolving {
        live(
            configurationResolver: AppENSProviderConfigurationResolver(configurationResolver: configurationResolver),
            cacheStore: cacheStore,
            eventRecorder: ReceiptBackedENSEventRecorder(
                receiptStore: ReceiptStores.live(modelContext: modelContext)
            )
        )
    }

    static func makeLiveClient(
        configurationResolver: any ProviderConfigurationResolving = LiveProviderConfigurationResolver()
    ) -> any EthereumNameServiceClient {
        makeLiveClient(
            configurationResolver: AppENSProviderConfigurationResolver(configurationResolver: configurationResolver)
        )
    }
}

private struct AppENSProviderConfigurationResolver: ENSProviderConfigurationResolving {
    private let configurationResolver: any ProviderConfigurationResolving

    init(configurationResolver: any ProviderConfigurationResolving) {
        self.configurationResolver = configurationResolver
    }

    func ensProviderConfiguration(for chain: Chain) throws -> ENSProviderEndpointConfiguration {
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
