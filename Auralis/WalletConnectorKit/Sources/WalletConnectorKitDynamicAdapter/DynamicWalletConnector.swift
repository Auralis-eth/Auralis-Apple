import Foundation
import WalletConnectorKit

/// Client abstraction over the Dynamic embedded-wallet SDK.
///
/// Dynamic is a **provider-managed embedded wallet**: the SDK provisions/returns
/// an account on connect (there is no WalletConnect pairing URI), so `connect`
/// yields a settled `WalletConnectorSession` — the same shape the Coinbase MWP
/// adapter uses. The live client that backs this protocol must be built against
/// the Dynamic iOS SDK in the host app (the SDK is not linked in this package);
/// ship `UnconfiguredDynamicSDKClient` until then so the connector reports
/// `.unavailable`.
public protocol DynamicSDKClient: Sendable {
    /// Whether a live vendor SDK backs this client. `false` for the shipped
    /// `Unconfigured…` stub so the connector reports `.unavailable` instead of
    /// falsely inheriting the protocol's `.productionReady` default.
    var isConfigured: Bool { get }
    /// Session/socket updates the live client emits (settled/deleted/etc.). The
    /// default is a finished stream for clients that do not surface events.
    var events: AsyncStream<WalletConnectorEvent> { get }
    /// Provisions/returns the embedded account and yields a settled session.
    func connect(wallet: ThirdPartyWalletProvider?) async throws -> WalletConnectorSession
    func request(_ request: WalletRequest, in sessionId: WalletSessionID) async throws -> WalletResponse
    /// Routes a wallet return URL back into the SDK. No-op by default (embedded
    /// wallets typically resolve in-process without a deep-link round-trip).
    func handleCallback(url: URL) async throws
    /// The live sessions the SDK currently holds, for cross-launch restore.
    func sessions() async throws -> [WalletConnectorSession]
    func disconnect(sessionId: WalletSessionID) async throws
}

public extension DynamicSDKClient {
    var isConfigured: Bool { true }
    var events: AsyncStream<WalletConnectorEvent> { AsyncStream { $0.finish() } }
    func handleCallback(url: URL) async throws {}
    func sessions() async throws -> [WalletConnectorSession] { [] }
}

public actor DynamicWalletConnector: WalletConnector {
    public nonisolated let runtimeFamily: WalletConnectorRuntimeFamily = .embeddedWallet
    private let client: any DynamicSDKClient
    private let cryptoProvider: any WalletConnectorCryptoProvider
    private let metadata: WalletConnectionMetadata
    private let hasProductionMetadata: Bool

    public init(
        client: any DynamicSDKClient,
        cryptoProvider: any WalletConnectorCryptoProvider = DefaultWalletConnectorCryptoProvider(),
        metadata: WalletConnectionMetadata? = nil
    ) {
        self.client = client
        self.cryptoProvider = cryptoProvider
        self.hasProductionMetadata = metadata != nil
        self.metadata = metadata ?? Self.defaultOwnershipMetadata()
    }

    public nonisolated var events: AsyncStream<WalletConnectorEvent> { client.events }

    public nonisolated var capabilities: WalletConnectorCapabilities {
        [.embeddedWallet, .evm, .messageSigning, .transactionSigning]
    }

    /// Production readiness is gated on the dependencies EVM ownership
    /// verification actually needs. Dynamic is an EVM embedded wallet, so a
    /// configured live client is necessary but not sufficient: without a
    /// recovery-capable `WalletConnectorCryptoProvider` the connector's own
    /// `verifyOwnership` fails closed, and without real `WalletConnectionMetadata`
    /// the SIWE challenge is bound to a placeholder domain. In either case
    /// readiness stays `.experimental` so the host cannot route production traffic
    /// through a connector that cannot complete the default `.requireVerified`
    /// lifecycle.
    public nonisolated var readiness: WalletConnectorReadiness {
        guard client.isConfigured else {
            return .unavailable("Dynamic adapter is not configured; no vendor SDK is linked. See README.")
        }
        guard cryptoProvider.supportsRecovery else {
            return .experimental("Dynamic adapter is configured but no recovery-capable WalletConnectorCryptoProvider was injected; EVM ownership verification fails closed. Inject a secp256k1 recovery provider for production use.")
        }
        guard hasProductionMetadata else {
            return .experimental("Dynamic adapter is configured but no production WalletConnectionMetadata was injected; ownership challenges are bound to a placeholder domain. Inject real app metadata for production use.")
        }
        return .productionReady
    }

    public func connect(proposal: WalletNamespaceProposalSet = .defaultV1, wallet: ThirdPartyWalletProvider?) async throws -> WalletConnectionStart {
        let session = try await client.connect(wallet: wallet ?? WalletConnectorCatalog.dynamic)
        // Embedded wallets have no pairing URI; surface the connected account for display.
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
        // provider supports it, an EIP-1271 smart-contract-wallet signature —
        // Dynamic embedded wallets may be provisioned as smart accounts.
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

public struct UnconfiguredDynamicSDKClient: DynamicSDKClient {
    public init() {}

    public var isConfigured: Bool { false }

    public func connect(wallet: ThirdPartyWalletProvider?) async throws -> WalletConnectorSession {
        throw WalletConnectionError.unavailable("Dynamic SDK client is not configured.")
    }

    public func request(_ request: WalletRequest, in sessionId: WalletSessionID) async throws -> WalletResponse {
        throw WalletConnectionError.unavailable("Dynamic SDK client is not configured.")
    }

    public func disconnect(sessionId: WalletSessionID) async throws {
        throw WalletConnectionError.unavailable("Dynamic SDK client is not configured.")
    }
}
