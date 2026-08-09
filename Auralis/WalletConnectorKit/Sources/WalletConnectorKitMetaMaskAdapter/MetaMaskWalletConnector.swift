import Foundation
import WalletConnectorKit

public protocol MetaMaskSDKClient: Sendable {
    /// Whether a live vendor SDK backs this client. `false` for the shipped
    /// `Unconfigured…` stub so the connector can report `.unavailable` instead of
    /// falsely inheriting the protocol's `.productionReady` default.
    var isConfigured: Bool { get }
    func connect(wallet: ThirdPartyWalletProvider?) async throws -> WalletConnectionStart
    func request(_ request: WalletRequest, in sessionId: WalletSessionID) async throws -> WalletResponse
    func disconnect(sessionId: WalletSessionID) async throws
}

public extension MetaMaskSDKClient {
    var isConfigured: Bool { true }
}

public actor MetaMaskWalletConnector: WalletConnector {
    private let client: any MetaMaskSDKClient
    private let eventsStream: AsyncStream<WalletConnectorEvent>

    public init(client: any MetaMaskSDKClient) {
        self.client = client
        self.eventsStream = AsyncStream { $0.finish() }
    }

    public nonisolated var events: AsyncStream<WalletConnectorEvent> { eventsStream }

    public nonisolated var runtimeFamily: WalletConnectorRuntimeFamily { .providerSDK }

    /// A stub client (no vendor SDK linked) reports `.unavailable`; a configured
    /// client remains `.experimental` until this wrapper delegates the full lifecycle.
    public nonisolated var readiness: WalletConnectorReadiness {
        client.isConfigured
            ? .experimental("MetaMask adapter is request-capable only; session restoration, callbacks, events, and ownership verification are not delegated yet.")
            : .unavailable("MetaMask adapter is not configured; no vendor SDK is linked. See README.")
    }

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

    public var isConfigured: Bool { false }

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
