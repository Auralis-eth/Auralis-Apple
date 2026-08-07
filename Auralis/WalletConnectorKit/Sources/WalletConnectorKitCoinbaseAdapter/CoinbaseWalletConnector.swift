import Foundation
import WalletConnectorKit

/// Client abstraction over the Coinbase Mobile Wallet Protocol SDK. Coinbase is
/// a direct request/response wallet (not a WalletConnect IRN session): the
/// handshake returns an account synchronously, so `connect` yields a settled
/// `WalletConnectorSession` rather than a pairing URI.
public protocol CoinbaseWalletSDKClient: Sendable {
    var events: AsyncStream<WalletConnectorEvent> { get }
    func connect(wallet: ThirdPartyWalletProvider?) async throws -> WalletConnectorSession
    func request(_ request: WalletRequest, in sessionId: WalletSessionID) async throws -> WalletResponse
    func disconnect(sessionId: WalletSessionID) async throws
    func handleCallback(url: URL) async throws
    func sessions() async throws -> [WalletConnectorSession]
}

public actor CoinbaseWalletConnector: WalletConnector {
    public nonisolated let runtimeFamily: WalletConnectorRuntimeFamily = .providerSDK
    private let client: any CoinbaseWalletSDKClient

    public init(client: any CoinbaseWalletSDKClient) {
        self.client = client
    }

    public nonisolated var events: AsyncStream<WalletConnectorEvent> { client.events }

    public func connect(proposal: WalletNamespaceProposalSet = .defaultV1, wallet: ThirdPartyWalletProvider?) async throws -> WalletConnectionStart {
        let session = try await client.connect(wallet: wallet ?? WalletConnectorCatalog.coinbaseWallet)
        // Coinbase has no pairing URI; surface the connected account for display.
        return WalletConnectionStart(pairingURI: nil, qrPayload: session.accounts.first?.caip10 ?? "")
    }

    public func handleCallback(url: URL) async throws {
        try await client.handleCallback(url: url)
    }

    public func sessions() async throws -> [WalletConnectorSession] {
        try await client.sessions()
    }

    public func disconnect(sessionId: WalletSessionID) async throws {
        try await client.disconnect(sessionId: sessionId)
    }

    public func request(_ request: WalletRequest, in sessionId: WalletSessionID) async throws -> WalletResponse {
        try await client.request(request, in: sessionId)
    }
}

public struct UnconfiguredCoinbaseWalletSDKClient: CoinbaseWalletSDKClient {
    private let message: String

    public init(message: String = "Coinbase Wallet SDK client is not configured. Provide a LiveCoinbaseWalletSDKClient (iOS).") {
        self.message = message
    }

    public var events: AsyncStream<WalletConnectorEvent> {
        AsyncStream { $0.finish() }
    }

    public func connect(wallet: ThirdPartyWalletProvider?) async throws -> WalletConnectorSession {
        throw WalletConnectionError.unavailable(message)
    }

    public func request(_ request: WalletRequest, in sessionId: WalletSessionID) async throws -> WalletResponse {
        throw WalletConnectionError.unavailable(message)
    }

    public func disconnect(sessionId: WalletSessionID) async throws {
        throw WalletConnectionError.unavailable(message)
    }

    public func handleCallback(url: URL) async throws {
        throw WalletConnectionError.unavailable(message)
    }

    public func sessions() async throws -> [WalletConnectorSession] { [] }
}
