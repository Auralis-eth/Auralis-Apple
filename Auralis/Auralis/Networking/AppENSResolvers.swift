import ReceiptsCore
import ReceiptStorage
import AgentIdentityCore
import AuralisPrimaryModels
import Foundation
import SwiftData
import NFTKit

@MainActor
extension ENSResolvers {
    static func live(
        modelContext: ModelContext,
        cacheStore: ENSResolutionCacheStore = sharedCacheStore
    ) -> any ENSResolving {
        live(
            configurationResolver: AppENSProviderConfigurationResolver(
                configurationResolver: LiveProviderConfigurationResolver()
            ),
            cacheStore: cacheStore,
            eventRecorder: ReceiptBackedENSEventRecorder(
                receiptStore: ReceiptStores.live(modelContext: modelContext)
            )
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
