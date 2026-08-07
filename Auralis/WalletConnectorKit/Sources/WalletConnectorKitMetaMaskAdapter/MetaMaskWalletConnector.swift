import Foundation
import WalletConnectorKit

public protocol MetaMaskSDKClient: Sendable {
    func connect(wallet: ThirdPartyWalletProvider?) async throws -> WalletConnectionStart
    func request(_ request: WalletRequest, in sessionId: WalletSessionID) async throws -> WalletResponse
    func disconnect(sessionId: WalletSessionID) async throws
}

public actor MetaMaskWalletConnector: WalletConnector {
    private let client: any MetaMaskSDKClient
    private let eventsStream: AsyncStream<WalletConnectorEvent>

    public init(client: any MetaMaskSDKClient) {
        self.client = client
        self.eventsStream = AsyncStream { $0.finish() }
    }

    public nonisolated var events: AsyncStream<WalletConnectorEvent> { eventsStream }

    public func connect(proposal: WalletNamespaceProposalSet = .defaultV1, wallet: ThirdPartyWalletProvider?) async throws -> WalletConnectionStart {
        try await client.connect(wallet: wallet ?? WalletConnectorCatalog.metamask)
    }

    public func handleCallback(url: URL) async throws {}
    public func sessions() async throws -> [WalletConnectorSession] { [] }

    public func disconnect(sessionId: WalletSessionID) async throws {
        try await client.disconnect(sessionId: sessionId)
    }

    public func request(_ request: WalletRequest, in sessionId: WalletSessionID) async throws -> WalletResponse {
        try await client.request(request, in: sessionId)
    }
}

public struct UnconfiguredMetaMaskSDKClient: MetaMaskSDKClient {
    public init() {}

    public func connect(wallet: ThirdPartyWalletProvider?) async throws -> WalletConnectionStart {
        throw WalletConnectionError.unavailable("MetaMask SDK client is not configured.")
    }

    public func request(_ request: WalletRequest, in sessionId: WalletSessionID) async throws -> WalletResponse {
        throw WalletConnectionError.unavailable("MetaMask SDK client is not configured.")
    }

    public func disconnect(sessionId: WalletSessionID) async throws {
        throw WalletConnectionError.unavailable("MetaMask SDK client is not configured.")
    }
}
