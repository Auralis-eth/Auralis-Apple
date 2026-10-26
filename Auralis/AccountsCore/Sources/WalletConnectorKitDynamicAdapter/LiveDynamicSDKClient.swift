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
/// `DynamicSDK` (a UIKit/WebView-backed binary class) is not `Sendable` and its
/// async module methods are nonisolated, so this client stays fully nonisolated
/// and holds the SDK via `nonisolated(unsafe)` — the same `@unchecked Sendable`
/// contract the Coinbase live client uses for its non-`Sendable` SDK. All SDK
/// access happens in one nonisolated region, so no non-`Sendable` value is ever
/// sent across an isolation boundary; the host is responsible for constructing
/// the SDK on the main actor (as `DynamicSDK.initialize` requires).
public final class LiveDynamicSDKClient: DynamicSDKClient, @unchecked Sendable {
    private nonisolated(unsafe) let sdk: DynamicSDK
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
        // Honor `sessionId`: it must name this wallet's derived session. Previously
        // `sessionId` was ignored and every request was served by the primary/first
        // EVM wallet, so a request routed at a different wallet silently signed with
        // that one. A mismatch now fails closed.
        guard sessionId.rawValue == Self.topic(forAddress: evmWallet.address) else {
            throw WalletConnectionError.sessionExpired
        }
        try WalletSessionGrantValidator.validate(request, in: Self.session(address: evmWallet.address, chain: chain))
        // Route through the generic EIP-1193 surface so every EVM method the grant
        // validator allowed (personal_sign, signTypedData, sendTransaction, …) maps
        // 1:1 to the wallet's JSON-RPC without lossy re-encoding.
        let result = try await sdk.evm.request(
            method: request.method.rawValue,
            params: request.params.map { $0.jsonObject as Any },
            wallet: evmWallet,
            chainId: Int(request.chain.reference)
        )
        return WalletResponse(id: request.id, result: result)
    }

    public func sessions() async throws -> [WalletConnectorSession] {
        guard let evmWallet = currentEVMWallet() else { return [] }
        return [Self.session(address: evmWallet.address, chain: chain)]
    }

    /// Single-session contract: `logout` tears down the whole authenticated Dynamic
    /// user, so only honor a disconnect that targets the live wallet's derived
    /// session id; any other id is a no-op rather than logging the user out from an
    /// unrelated session.
    public func disconnect(sessionId: WalletSessionID) async throws {
        guard let evmWallet = currentEVMWallet(),
              sessionId.rawValue == Self.topic(forAddress: evmWallet.address) else { return }
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

    private static let supportedEVMMethods: [String] = [
        WalletRequestMethod.ethPersonalSign.rawValue,
        WalletRequestMethod.ethSendTransaction.rawValue,
        WalletRequestMethod.ethSignTypedData.rawValue,
        WalletRequestMethod.ethSignTypedDataV4.rawValue,
    ]

    /// The stable session id/topic for an embedded wallet — derived from its
    /// address so `request`/`disconnect` can honor the `sessionId` they are handed
    /// instead of silently operating on the primary/first EVM wallet.
    private static func topic(forAddress address: String) -> String {
        "dynamic-\(address.lowercased())"
    }

    private static func session(address: String, chain: WalletChain) -> WalletConnectorSession {
        // An embedded wallet is a single EOA valid on every EVM chain, so advertise
        // the account across all supported EVM chains rather than pinning the grant
        // to one. Pinning to a single chain made `WalletSessionGrantValidator` reject
        // any request on a different EVM chain even though the key controls it (and
        // `request` already routes to `sdk.evm.request(chainId:)` per-request). The
        // configured `chain` is listed first so `accounts.first` is the primary net.
        let evmChains = WalletChain.evmChains
        let orderedChains = evmChains.contains(chain) ? [chain] + evmChains.filter { $0 != chain } : evmChains
        let accounts = orderedChains.map { WalletAccount(caip10: "\($0.namespace):\($0.chainReference):\(address)") }
        let topic = topic(forAddress: address)
        let namespace = WalletSessionNamespace(
            name: "eip155",
            accounts: accounts,
            methods: Self.supportedEVMMethods,
            events: WalletConnectionNamespaces.evmEvents
        )
        return WalletConnectorSession(
            id: WalletSessionID(rawValue: topic),
            topic: WalletPairingTopic(rawValue: topic),
            providerID: WalletConnectorCatalog.dynamic.id.rawValue,
            providerName: WalletConnectorCatalog.dynamic.displayName,
            accounts: accounts,
            namespaces: [namespace],
            expiryDate: Date().addingTimeInterval(defaultSessionValidity)
        )
    }
}
#endif
