import Foundation
import WalletConnectorKit

public protocol SolanaSDKClient: Sendable {
    /// Whether a live vendor SDK backs this client. `false` for the shipped
    /// `Unconfigured…` stub so the connector reports `.unavailable` instead of
    /// falsely inheriting the protocol's `.productionReady` default.
    var isConfigured: Bool { get }
    func request(_ request: WalletRequest, in sessionId: WalletSessionID) async throws -> WalletResponse
}

public extension SolanaSDKClient {
    var isConfigured: Bool { true }
}

public actor SolanaWalletConnector: WalletConnector {
    public nonisolated let runtimeFamily: WalletConnectorRuntimeFamily = .solanaRPC
    private let client: any SolanaSDKClient
    private let eventsStream: AsyncStream<WalletConnectorEvent>

    public init(client: any SolanaSDKClient) {
        self.client = client
        self.eventsStream = AsyncStream { $0.finish() }
    }

    public nonisolated var events: AsyncStream<WalletConnectorEvent> { eventsStream }

    /// A stub client (no vendor SDK linked) reports `.unavailable`; a live client
    /// is still request-only because this adapter cannot establish sessions.
    public nonisolated var readiness: WalletConnectorReadiness {
        client.isConfigured
            ? .experimental("Solana adapter is request-only; connect is unavailable. Use Reown or WalletConnect for pairing.")
            : .unavailable("Solana adapter is not configured; no vendor SDK is linked. See README.")
    }

    public func connect(proposal: WalletNamespaceProposalSet = .defaultV1, wallet: ThirdPartyWalletProvider?) async throws -> WalletConnectionStart {
        throw WalletConnectionError.unavailable("Solana SDK does not provide wallet discovery in this adapter. Use Reown or a Solana wallet deep link for connection, then route Solana requests here.")
    }

    public func handleCallback(url: URL) async throws {}
    public func sessions() async throws -> [WalletConnectorSession] { [] }
    public func disconnect(sessionId: WalletSessionID) async throws {}

    public func request(_ request: WalletRequest, in sessionId: WalletSessionID) async throws -> WalletResponse {
        try WalletRequestValidation.validate(request)
        guard request.chain.namespace == "solana" else {
            throw WalletConnectionError.unsupportedChain(request.chain.knownChain ?? .solana)
        }
        return try await client.request(request, in: sessionId)
    }
}

public struct UnconfiguredSolanaSDKClient: SolanaSDKClient {
    public init() {}

    public var isConfigured: Bool { false }

    public func request(_ request: WalletRequest, in sessionId: WalletSessionID) async throws -> WalletResponse {
        throw WalletConnectionError.unavailable("Solana SDK client is not configured.")
    }
}
