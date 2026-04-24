import Foundation
import SwiftData

@MainActor
enum ENSResolvers {
    static func live(
        modelContext: ModelContext,
        configurationResolver: any ProviderConfigurationResolving = LiveProviderConfigurationResolver()
    ) -> any ENSResolving {
        let client = makeLiveClient(configurationResolver: configurationResolver)
        return Web3EthereumNameServiceResolver(
            client: client,
            eventRecorder: ReceiptBackedENSEventRecorder(
                receiptStore: ReceiptStores.live(modelContext: modelContext)
            )
        )
    }

    static func makeLiveClient(
        configurationResolver: any ProviderConfigurationResolving = LiveProviderConfigurationResolver()
    ) -> any EthereumNameServiceClient {
        let configuration: ProviderEndpointConfiguration
        do {
            configuration = try configurationResolver.configuration(for: .ethMainnet)
        } catch ProviderAbstractionError.invalidURL {
            return UnavailableEthereumNameServiceClient(error: .invalidProviderConfiguration)
        } catch {
            return UnavailableEthereumNameServiceClient()
        }

        guard let rpcURL = configuration.alchemyRPCURL else {
            return UnavailableEthereumNameServiceClient(error: .missingProviderConfiguration)
        }

        return Web3EthereumNameServiceClient(rpcURL: rpcURL)
    }

    static func cacheResetService() -> ENSCacheResetService {
        ENSCacheResetService()
    }
}
