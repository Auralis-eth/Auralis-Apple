import Foundation
import Testing
@testable import WalletConnectorKit

@Suite("Wallet connector registry")
struct WalletConnectorRegistryTests {
    @Test("Default catalog includes launch wallet providers")
    func defaultCatalogIncludesLaunchProviders() {
        let providerIDs = Set(WalletConnectorCatalog.defaultProviders.map(\.id.rawValue))

        #expect(providerIDs == [
            "metamask",
            "rainbow",
            "coinbase-wallet",
            "phantom",
        ])
    }

    @Test("Registry connects through the matching provider")
    func registryConnectsThroughMatchingProvider() async throws {
        let registry = WalletConnectorRegistry(connectors: [
            StubWalletConnector(provider: WalletConnectorCatalog.metamask),
        ])

        let session = try await registry.connect(
            providerID: "metamask",
            request: WalletConnectionRequest(
                preferredChain: .base,
                appName: "Unit Test"
            )
        )

        #expect(session.providerID == "metamask")
        #expect(session.chain == .base)
    }

    @Test("Registry rejects unsupported providers")
    func registryRejectsUnsupportedProviders() async {
        let registry = WalletConnectorRegistry(connectors: [])

        await #expect(throws: WalletConnectionError.unsupportedProvider("unknown")) {
            try await registry.connect(
                providerID: "unknown",
                request: WalletConnectionRequest(appName: "Unit Test")
            )
        }
    }

    @Test("Registry rejects unsupported preferred chains before connector handoff")
    func registryRejectsUnsupportedPreferredChains() async {
        let registry = WalletConnectorRegistry(connectors: [
            StubWalletConnector(provider: WalletConnectorCatalog.metamask),
        ])

        await #expect(throws: WalletConnectionError.unsupportedChain(.solana)) {
            try await registry.connect(
                providerID: "metamask",
                request: WalletConnectionRequest(
                    preferredChain: .solana,
                    appName: "Unit Test"
                )
            )
        }
    }
}

private struct StubWalletConnector: WalletConnector {
    let provider: ThirdPartyWalletProvider

    func connect(request: WalletConnectionRequest) async throws -> WalletConnectionSession {
        WalletConnectionSession(
            providerID: provider.id,
            accountAddress: "0x0000000000000000000000000000000000000001",
            chain: request.preferredChain ?? provider.supportedChains[0]
        )
    }

    func disconnect(session: WalletConnectionSession) async {
    }
}
