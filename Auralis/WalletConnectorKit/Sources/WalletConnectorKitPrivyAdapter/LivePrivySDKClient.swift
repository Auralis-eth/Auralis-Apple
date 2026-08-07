#if canImport(PrivySDK)
import Foundation
import PrivySDK
import WalletConnectorKit

/// Live Privy adapter backed by the Privy embedded-wallet SDK
/// (`github.com/privy-io/privy-ios`).
///
/// Privy is **auth-first**: the user logs in through a host-owned Privy UI flow
/// (email code / OAuth / passkey / SIWE) and Privy provisions a non-custodial
/// embedded wallet. This client therefore does **not** drive login — the host
/// owns that. `connect` surfaces the *already authenticated* embedded Ethereum
/// wallet as a settled session (there is no WalletConnect pairing URI), and
/// `request` routes JSON-RPC through the embedded wallet's provider.
///
/// Written against the Privy SDK `.swiftinterface` (module `PrivySDK`):
/// `PrivySdk.initialize(config:) -> any Privy`, `Privy.getUser() async`,
/// `PrivyUser.embeddedEthereumWallets`, `EmbeddedEthereumWallet.provider`,
/// `EmbeddedEthereumWalletProvider.request(_:) async throws -> String`,
/// `EthereumRpcRequest.personalSign(message:address:)`.
public final class LivePrivySDKClient: PrivySDKClient, @unchecked Sendable {
    private let privy: any Privy
    private let chain: WalletChain

    /// Synthetic session lifetime — Privy embedded wallets have no session expiry;
    /// liveness is really the auth state, re-read on every `sessions()`.
    public static let defaultSessionValidity: TimeInterval = 60 * 60 * 24 * 30

    /// - Parameters:
    ///   - privy: A `Privy` instance the host created via
    ///     `PrivySdk.initialize(config:)` with its own app ID.
    ///   - chain: The EVM chain the embedded wallet is surfaced on (Privy embedded
    ///     wallets are EVM here). Defaults to Ethereum mainnet.
    public init(privy: any Privy, chain: WalletChain = .ethereum) {
        self.privy = privy
        self.chain = chain
    }

    /// Convenience initializer that builds the `Privy` instance from a config.
    public convenience init(config: PrivyConfig, chain: WalletChain = .ethereum) {
        self.init(privy: PrivySdk.initialize(config: config), chain: chain)
    }

    public var isConfigured: Bool { true }

    public func connect(wallet: ThirdPartyWalletProvider?) async throws -> WalletConnectorSession {
        guard let embedded = await currentEthereumWallet() else {
            throw WalletConnectionError.unavailable(
                "Privy: no authenticated embedded Ethereum wallet. Complete the Privy login flow (host-owned UI) and create/import an embedded wallet before connecting."
            )
        }
        return Self.session(address: embedded.address, chain: chain)
    }

    public func request(_ request: WalletRequest, in sessionId: WalletSessionID) async throws -> WalletResponse {
        try WalletRequestValidation.validate(request)
        guard let embedded = await currentEthereumWallet() else {
            throw WalletConnectionError.sessionExpired
        }
        // Re-run the grant guard against the live wallet's session, matching the
        // safety the Coinbase/Reown live clients apply before submitting.
        try WalletSessionGrantValidator.validate(request, in: Self.session(address: embedded.address, chain: chain))
        let rpc = try Self.rpcRequest(for: request, walletAddress: embedded.address)
        let result = try await embedded.provider.request(rpc)
        return WalletResponse(id: request.id, result: result)
    }

    public func sessions() async throws -> [WalletConnectorSession] {
        guard let embedded = await currentEthereumWallet() else { return [] }
        return [Self.session(address: embedded.address, chain: chain)]
    }

    public func disconnect(sessionId: WalletSessionID) async throws {
        await privy.getUser()?.logout()
    }

    private func currentEthereumWallet() async -> (any EmbeddedEthereumWallet)? {
        await privy.getUser()?.embeddedEthereumWallets.first
    }

    private static func session(address: String, chain: WalletChain) -> WalletConnectorSession {
        let caip10 = "\(chain.namespace):\(chain.chainReference):\(address)"
        let topic = "privy-\(address.lowercased())"
        let namespace = WalletSessionNamespace(
            name: "eip155",
            accounts: [WalletAccount(caip10: caip10)],
            methods: WalletConnectionNamespaces.evmMethods,
            events: WalletConnectionNamespaces.evmEvents
        )
        return WalletConnectorSession(
            id: WalletSessionID(rawValue: topic),
            topic: WalletPairingTopic(rawValue: topic),
            providerID: WalletConnectorCatalog.privy.id.rawValue,
            providerName: WalletConnectorCatalog.privy.displayName,
            accounts: [WalletAccount(caip10: caip10)],
            namespaces: [namespace],
            expiryDate: Date().addingTimeInterval(defaultSessionValidity)
        )
    }

    /// Maps a `WalletRequest` onto Privy's `EthereumRpcRequest`. `personal_sign`
    /// uses the typed convenience (message ‖ address, EIP-191); typed-data uses the
    /// generic `init(method:params:)` string form. Chain-admin/asset methods are
    /// not exposed by embedded wallets and are rejected as unsupported.
    private static func rpcRequest(for request: WalletRequest, walletAddress: String) throws -> EthereumRpcRequest {
        switch request.method {
        case .ethPersonalSign:
            // WC personal_sign params are [message, address].
            guard let message = request.params.first?.stringValue,
                  let address = request.params.dropFirst().first?.stringValue else {
                throw WalletConnectionError.invalidResponse
            }
            return .personalSign(message: message, address: address)
        case .ethSignTypedData, .ethSignTypedDataV4:
            // WC signTypedData params are [address, typedDataJson].
            guard let address = request.params.first?.stringValue,
                  let typedDataJson = request.params.dropFirst().first?.stringValue else {
                throw WalletConnectionError.invalidResponse
            }
            return EthereumRpcRequest(method: request.method.rawValue, params: [address, typedDataJson])
        default:
            throw WalletConnectionError.unsupportedMethod(request.method.rawValue)
        }
    }
}
#endif
