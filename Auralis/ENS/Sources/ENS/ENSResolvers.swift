import Foundation

@MainActor
public enum ENSResolvers {
    public static let sharedCacheStore = ENSResolutionCacheStore()

    public static func live(
        configurationResolver: any ENSProviderConfigurationResolving,
        cacheStore: ENSResolutionCacheStore = sharedCacheStore,
        eventRecorder: any ENSEventRecording = NoOpENSEventRecorder()
    ) -> any ENSResolving {
        let client = makeLiveClient(configurationResolver: configurationResolver)
        return Web3EthereumNameServiceResolver(
            client: client,
            cacheStore: cacheStore,
            eventRecorder: eventRecorder
        )
    }

    public static func makeLiveClient(
        configurationResolver: any ENSProviderConfigurationResolving
    ) -> any EthereumNameServiceClient {
        let configuration: ENSProviderEndpointConfiguration
        do {
            configuration = try configurationResolver.ensProviderConfiguration(for: .ethMainnet)
        } catch ENSProviderConfigurationError.invalidProviderConfiguration {
            return UnavailableEthereumNameServiceClient(error: .invalidProviderConfiguration)
        } catch ENSProviderConfigurationError.missingProviderConfiguration {
            return UnavailableEthereumNameServiceClient(error: .missingProviderConfiguration)
        } catch {
            return UnavailableEthereumNameServiceClient()
        }

        guard let rpcURL = configuration.rpcURL else {
            return UnavailableEthereumNameServiceClient(error: .missingProviderConfiguration)
        }

        return Web3EthereumNameServiceClient(rpcURL: rpcURL)
    }

    public static func cacheResetService(
        cacheStore: ENSResolutionCacheStore = sharedCacheStore
    ) -> ENSCacheResetService {
        ENSCacheResetService(cacheStore: cacheStore)
    }
}
