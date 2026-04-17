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
        let configuration = try? configurationResolver.configuration(for: .ethMainnet)
        guard let rpcURL = configuration?.alchemyRPCURL else {
            return UnavailableEthereumNameServiceClient()
        }

        return Web3EthereumNameServiceClient(rpcURL: rpcURL)
    }

    static func cacheResetService() -> ENSCacheResetService {
        ENSCacheResetService()
    }
}
