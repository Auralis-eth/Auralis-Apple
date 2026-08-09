import Foundation
import WalletConnectorKit

/// Client abstraction over the Coinbase Mobile Wallet Protocol SDK. Coinbase is
/// a direct request/response wallet (not a WalletConnect IRN session): the
/// handshake returns an account synchronously, so `connect` yields a settled
/// `WalletConnectorSession` rather than a pairing URI.
public protocol CoinbaseWalletSDKClient: Sendable {
    var events: AsyncStream<WalletConnectorEvent> { get }
    var isConfigured: Bool { get }
    func connect(wallet: ThirdPartyWalletProvider?) async throws -> WalletConnectorSession
    func request(_ request: WalletRequest, in sessionId: WalletSessionID) async throws -> WalletResponse
    func disconnect(sessionId: WalletSessionID) async throws
    func handleCallback(url: URL) async throws
    func sessions() async throws -> [WalletConnectorSession]
}

public extension CoinbaseWalletSDKClient {
    var isConfigured: Bool { true }
}

public actor CoinbaseWalletConnector: WalletConnector {
    public nonisolated let runtimeFamily: WalletConnectorRuntimeFamily = .providerSDK
    private let client: any CoinbaseWalletSDKClient
    private let cryptoProvider: any WalletConnectorCryptoProvider
    private let metadata: WalletConnectionMetadata
    private let hasProductionMetadata: Bool

    public init(
        client: any CoinbaseWalletSDKClient,
        cryptoProvider: any WalletConnectorCryptoProvider = DefaultWalletConnectorCryptoProvider(),
        metadata: WalletConnectionMetadata? = nil
    ) {
        self.client = client
        self.cryptoProvider = cryptoProvider
        self.hasProductionMetadata = metadata != nil
        self.metadata = metadata ?? Self.defaultOwnershipMetadata()
    }

    public nonisolated var events: AsyncStream<WalletConnectorEvent> { client.events }

    /// Production readiness is gated on the dependencies EVM ownership
    /// verification needs. Coinbase is EVM-only, so a recovery-capable
    /// `WalletConnectorCryptoProvider` and real `WalletConnectionMetadata` are
    /// both required; otherwise `verifyOwnership` fails closed / binds the SIWE
    /// challenge to a placeholder domain, and readiness stays `.experimental`.
    public nonisolated var readiness: WalletConnectorReadiness {
        guard client.isConfigured else {
            return .unavailable("Coinbase Wallet SDK adapter is not configured; no live client is available. See README.")
        }
        guard cryptoProvider.supportsRecovery else {
            return .experimental("Coinbase adapter is configured but no recovery-capable WalletConnectorCryptoProvider was injected; EVM ownership verification fails closed. Inject a secp256k1 recovery provider for production use.")
        }
        guard hasProductionMetadata else {
            return .experimental("Coinbase adapter is configured but no production WalletConnectionMetadata was injected; ownership challenges are bound to a placeholder domain. Inject real app metadata for production use.")
        }
        return .productionReady
    }

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

    @discardableResult
    public func verifyOwnership(
        of address: String,
        chain: WalletChain = .ethereum,
        in sessionId: WalletSessionID,
        statement: String = "Verify wallet ownership.",
        expiryDate: Date = Date().addingTimeInterval(300)
    ) async throws -> Bool {
        guard chain.namespace == "eip155" else {
            throw WalletConnectionError.unsupportedChain(chain)
        }

        let nonce = try WalletOwnershipChallengeMessageBuilder.nonce()
        let message = WalletOwnershipChallengeMessageBuilder.evmSIWEMessage(
            address: address,
            chain: chain,
            statement: statement,
            nonce: nonce,
            issuedAt: Date(),
            expiration: expiryDate,
            metadata: metadata
        )
        let response = try await request(
            WalletRequestBuilder.personalSignText(
                id: WalletSignRequestID(rawValue: "ownership-\(UUID().uuidString)"),
                address: address,
                text: message,
                chain: chain,
                expiryDate: expiryDate
            ),
            in: sessionId
        )
        // Accepts an EOA signature (secp256k1 recovery) or, when the injected
        // provider supports it, an EIP-1271 smart-contract-wallet signature. The
        // Coinbase Smart Wallet is a contract account, so EOA-only verification
        // would reject it.
        return try await WalletOwnershipVerifier.verifyPersonalSign(
            expectedAddress: address,
            message: Data(message.utf8),
            signatureHex: response.result,
            chain: chain,
            using: cryptoProvider
        )
    }

    private static func defaultOwnershipMetadata() -> WalletConnectionMetadata {
        let url = URL(string: "https://walletconnectorkit.local") ?? URL(fileURLWithPath: "/")
        return WalletConnectionMetadata(
            appName: "WalletConnectorKit",
            appDescription: "Wallet ownership verification",
            appURL: url
        )
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

    public var isConfigured: Bool { false }

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
