import Foundation
import WalletConnectorKit

public protocol PrivySDKClient: Sendable {
    func connect(wallet: ThirdPartyWalletProvider?) async throws -> WalletConnectionStart
    func request(_ request: WalletRequest, in sessionId: WalletSessionID) async throws -> WalletResponse
    func disconnect(sessionId: WalletSessionID) async throws
}

public actor PrivyWalletConnector: WalletConnector {
    private let client: any PrivySDKClient
    private let eventsStream: AsyncStream<WalletConnectorEvent>

    public init(client: any PrivySDKClient) {
        self.client = client
        self.eventsStream = AsyncStream { $0.finish() }
    }

    public nonisolated var events: AsyncStream<WalletConnectorEvent> { eventsStream }

    public func connect(proposal: WalletNamespaceProposalSet = .defaultV1, wallet: ThirdPartyWalletProvider?) async throws -> WalletConnectionStart {
        try await client.connect(wallet: wallet ?? WalletConnectorCatalog.privy)
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

public struct UnconfiguredPrivySDKClient: PrivySDKClient {
    public init() {}

    public func connect(wallet: ThirdPartyWalletProvider?) async throws -> WalletConnectionStart {
        throw WalletConnectionError.unavailable("Privy SDK client is not configured.")
    }

    public func request(_ request: WalletRequest, in sessionId: WalletSessionID) async throws -> WalletResponse {
        throw WalletConnectionError.unavailable("Privy SDK client is not configured.")
    }

    public func disconnect(sessionId: WalletSessionID) async throws {
        throw WalletConnectionError.unavailable("Privy SDK client is not configured.")
    }
}
