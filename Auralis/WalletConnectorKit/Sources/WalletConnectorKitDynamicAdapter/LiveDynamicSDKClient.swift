#if canImport(DynamicSDKSwift)
import Foundation
import DynamicSDKSwift
import WalletConnectorKit

/// Live Dynamic adapter backed by the Dynamic embedded-wallet SDK
/// (`github.com/dynamic-labs/swift-sdk-and-sample-app`, module `DynamicSDKSwift`).
///
/// Like Privy, Dynamic is **auth-first**: the user authenticates through a
/// host-owned Dynamic UI flow and Dynamic manages the embedded wallet. This
/// client does not drive login — `connect` surfaces the already-authenticated
/// primary EVM wallet as a settled session, and `request` routes EVM JSON-RPC
/// through `DynamicSDK.evm.request`.
///
/// Written against the Dynamic SDK `.swiftinterface` (module `DynamicSDKSwift`):
/// `DynamicSDK.initialize(props:)`, `DynamicSDK.auth.authenticatedUser`,
/// `DynamicSDK.wallets.primary` / `.userWallets` (`[BaseWallet]`),
/// `DynamicSDK.evm.request(method:params:wallet:chainId:) async throws -> String`,
/// `DynamicSDK.auth.logout() async throws`.
///
/// The client is `@MainActor`-isolated because `DynamicSDK` (a UIKit/WebView-backed
/// binary class) is not `Sendable` and its `initialize` is `@MainActor`; keeping
/// all SDK access on the main actor is both correct and satisfies `Sendable`.
@MainActor
public final class LiveDynamicSDKClient: DynamicSDKClient {
    private let sdk: DynamicSDK
    private let chain: WalletChain

    /// Synthetic session lifetime — Dynamic embedded wallets have no session
    /// expiry; liveness is really the auth state, re-read on every `sessions()`.
    public static let defaultSessionValidity: TimeInterval = 60 * 60 * 24 * 30

    /// - Parameters:
    ///   - sdk: A `DynamicSDK` instance the host created via
    ///     `DynamicSDK.initialize(props:)` with its own environment ID.
    ///   - chain: The EVM chain the embedded wallet is surfaced on. Defaults to
    ///     Ethereum mainnet.
    public init(sdk: DynamicSDK, chain: WalletChain = .ethereum) {
        self.sdk = sdk
        self.chain = chain
    }

    public func connect(wallet: ThirdPartyWalletProvider?) async throws -> WalletConnectorSession {
        guard let evmWallet = currentEVMWallet() else {
            throw WalletConnectionError.unavailable(
                "Dynamic: no authenticated EVM wallet. Complete the Dynamic login flow (host-owned UI) before connecting."
            )
        }
        return Self.session(address: evmWallet.address, chain: chain)
    }

    public func request(_ request: WalletRequest, in sessionId: WalletSessionID) async throws -> WalletResponse {
        try WalletRequestValidation.validate(request)
        guard request.chain.namespace == "eip155" else {
            throw WalletConnectionError.unsupportedChain(request.chain.knownChain ?? .ethereum)
        }
        guard let evmWallet = currentEVMWallet() else {
            throw WalletConnectionError.sessionExpired
        }
        try WalletSessionGrantValidator.validate(request, in: Self.session(address: evmWallet.address, chain: chain))
        // Route through the generic EIP-1193 surface so every EVM method the grant
        // validator allowed (personal_sign, signTypedData, sendTransaction, …) maps
        // 1:1 to the wallet's JSON-RPC without lossy re-encoding.
        let result = try await sdk.evm.request(
            method: request.method.rawValue,
            params: request.params.map { $0.jsonObject },
            wallet: evmWallet,
            chainId: Int(request.chain.reference)
        )
        return WalletResponse(id: request.id, result: result)
    }

    public func sessions() async throws -> [WalletConnectorSession] {
        guard let evmWallet = currentEVMWallet() else { return [] }
        return [Self.session(address: evmWallet.address, chain: chain)]
    }

    public func disconnect(sessionId: WalletSessionID) async throws {
        try await sdk.auth.logout()
    }

    /// The primary (or first) EVM `BaseWallet` for the authenticated user, or `nil`
    /// when no one is logged in. `BaseWallet.chain` is Dynamic's `ChainEnum` raw
    /// value — EVM wallets report `"evm"` (or the legacy `"eth"`).
    private func currentEVMWallet() -> BaseWallet? {
        guard sdk.auth.authenticatedUser != nil else { return nil }
        func isEVM(_ wallet: BaseWallet) -> Bool { wallet.chain == "evm" || wallet.chain == "eth" }
        if let primary = sdk.wallets.primary, isEVM(primary) {
            return primary
        }
        return sdk.wallets.userWallets.first(where: isEVM)
    }

    private static func session(address: String, chain: WalletChain) -> WalletConnectorSession {
        let caip10 = "\(chain.namespace):\(chain.chainReference):\(address)"
        let topic = "dynamic-\(address.lowercased())"
        let namespace = WalletSessionNamespace(
            name: "eip155",
            accounts: [WalletAccount(caip10: caip10)],
            methods: WalletConnectionNamespaces.evmMethods,
            events: WalletConnectionNamespaces.evmEvents
        )
        return WalletConnectorSession(
            id: WalletSessionID(rawValue: topic),
            topic: WalletPairingTopic(rawValue: topic),
            providerID: WalletConnectorCatalog.dynamic.id.rawValue,
            providerName: WalletConnectorCatalog.dynamic.displayName,
            accounts: [WalletAccount(caip10: caip10)],
            namespaces: [namespace],
            expiryDate: Date().addingTimeInterval(defaultSessionValidity)
        )
    }
}
#endif
