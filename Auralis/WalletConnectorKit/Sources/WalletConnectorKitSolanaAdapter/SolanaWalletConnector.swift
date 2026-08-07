import Foundation
import WalletConnectorKit

public protocol SolanaSDKClient: Sendable {
    func request(_ request: WalletRequest, in sessionId: WalletSessionID) async throws -> WalletResponse
}

public actor SolanaWalletConnector: WalletConnector {
    private let client: any SolanaSDKClient
    private let eventsStream: AsyncStream<WalletConnectorEvent>

    public init(client: any SolanaSDKClient) {
        self.client = client
        self.eventsStream = AsyncStream { $0.finish() }
    }

    public nonisolated var events: AsyncStream<WalletConnectorEvent> { eventsStream }

    public func connect(proposal: WalletNamespaceProposalSet = .defaultV1, wallet: ThirdPartyWalletProvider?) async throws -> WalletConnectionStart {
        throw WalletConnectionError.unavailable("Solana SDK does not provide wallet discovery in this adapter. Use Reown or a Solana wallet deep link for connection, then route Solana requests here.")
    }

    public func handleCallback(url: URL) async throws {}
    public func sessions() async throws -> [WalletConnectorSession] { [] }
    public func disconnect(sessionId: WalletSessionID) async throws {}

    public func request(_ request: WalletRequest, in sessionId: WalletSessionID) async throws -> WalletResponse {
        guard request.chain.namespace == "solana" else {
            throw WalletConnectionError.unsupportedChain(request.chain.knownChain ?? .solana)
        }
        return try await client.request(request, in: sessionId)
    }
}

public struct UnconfiguredSolanaSDKClient: SolanaSDKClient {
    public init() {}

    public func request(_ request: WalletRequest, in sessionId: WalletSessionID) async throws -> WalletResponse {
        throw WalletConnectionError.unavailable("Solana SDK client is not configured.")
    }
}
