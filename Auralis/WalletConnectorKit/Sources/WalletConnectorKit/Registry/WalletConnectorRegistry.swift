import Foundation

public struct WalletConnectorRegistry: Sendable {
    private let providersByID: [WalletProviderID: ThirdPartyWalletProvider]

    public init(providers: [ThirdPartyWalletProvider] = WalletConnectorCatalog.defaultProviders) {
        // `providers` is caller-supplied and has no uniqueness guarantee, so a
        // duplicate `id` must not trap the process (as `uniqueKeysWithValues`
        // would). Keep the first occurrence — mirrors the same safety the
        // lifecycle service applies at the connector boundary.
        self.providersByID = Dictionary(
            providers.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
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

    public func providers(supporting chain: WalletChain, method: WalletRequestMethod) -> [ThirdPartyWalletProvider] {
        providers.filter { provider in
            provider.supports(chain: chain, method: method)
        }
    }
}

public extension ThirdPartyWalletProvider {
    func supports(chain: WalletChain, method: WalletRequestMethod) -> Bool {
        guard supportedChains.contains(chain) else { return false }
        let capabilities = capabilities
        switch method {
        case .ethPersonalSign, .ethSignTypedData, .ethSignTypedDataV4:
            return chain.namespace == "eip155"
                && capabilities.contains([.evm, .messageSigning])
        case .ethSendTransaction:
            return chain.namespace == "eip155"
                && capabilities.contains([.evm, .transactionSigning])
        case .walletSwitchEthereumChain:
            return chain.namespace == "eip155"
                && capabilities.contains([.evm, .chainSwitching])
        case .walletAddEthereumChain:
            return chain.namespace == "eip155"
                && capabilities.contains([.evm, .chainAddition])
        case .walletWatchAsset:
            return chain.namespace == "eip155"
                && capabilities.contains([.evm, .assetWatching])
        case .solanaSignMessage:
            return chain == .solana
                && capabilities.contains([.solana, .messageSigning])
        case .solanaSignTransaction:
            return chain == .solana
                && capabilities.contains([.solana, .transactionSigning])
        case .solanaSignAllTransactions:
            return chain == .solana
                && capabilities.contains([.solana, .batchTransactionSigning])
        case .solanaSignAndSendTransaction:
            return chain == .solana
                && capabilities.contains([.solana, .signAndSend])
        }
    }
}
