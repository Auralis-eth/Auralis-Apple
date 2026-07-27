import Foundation

public struct WalletConnectorRegistry: Sendable {
    private let providersByID: [WalletProviderID: ThirdPartyWalletProvider]

    public init(providers: [ThirdPartyWalletProvider] = WalletConnectorCatalog.defaultProviders) {
        self.providersByID = Dictionary(
            uniqueKeysWithValues: providers.map { ($0.id, $0) }
        )
    }

    public var providers: [ThirdPartyWalletProvider] {
        providersByID.values.sorted { $0.displayName < $1.displayName }
    }

    public func provider(id: WalletProviderID) -> ThirdPartyWalletProvider? {
        providersByID[id]
    }

    public func providers(supporting chain: WalletChain) -> [ThirdPartyWalletProvider] {
        providers.filter { $0.supportedChains.contains(chain) }
    }
}
