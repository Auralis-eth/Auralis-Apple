import Foundation

public struct WalletConnectorRegistry: Sendable {
    private let connectorsByProviderID: [WalletProviderID: any WalletConnector]

    public init(connectors: [any WalletConnector]) {
        self.connectorsByProviderID = Dictionary(
            uniqueKeysWithValues: connectors.map { ($0.provider.id, $0) }
        )
    }

    public var providers: [ThirdPartyWalletProvider] {
        connectorsByProviderID.values
            .map(\.provider)
            .sorted { $0.displayName < $1.displayName }
    }

    public func provider(id: WalletProviderID) -> ThirdPartyWalletProvider? {
        connectorsByProviderID[id]?.provider
    }

    public func connect(
        providerID: WalletProviderID,
        request: WalletConnectionRequest
    ) async throws -> WalletConnectionSession {
        guard let connector = connectorsByProviderID[providerID] else {
            throw WalletConnectionError.unsupportedProvider(providerID)
        }

        if let preferredChain = request.preferredChain,
           !connector.provider.supportedChains.contains(preferredChain) {
            throw WalletConnectionError.unsupportedChain(preferredChain)
        }

        return try await connector.connect(request: request)
    }

    public func disconnect(session: WalletConnectionSession) async {
        await connectorsByProviderID[session.providerID]?.disconnect(session: session)
    }
}
