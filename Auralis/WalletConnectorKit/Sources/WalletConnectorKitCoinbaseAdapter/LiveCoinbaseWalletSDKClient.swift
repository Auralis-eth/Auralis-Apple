#if os(iOS)
import CoinbaseWalletSDK
import Foundation
import UIKit
import WalletConnectorKit

/// Live Coinbase adapter backed by the Coinbase Mobile Wallet Protocol SDK.
///
/// The handshake returns an account synchronously (bridged to async); requests
/// deep-link out to Coinbase Wallet and resolve when the app routes the return
/// URL back through `handleCallback` → `CoinbaseWalletSDK.handleResponse`.
public final class LiveCoinbaseWalletSDKClient: CoinbaseWalletSDKClient, @unchecked Sendable {
    private let eventsStream: AsyncStream<WalletConnectorEvent>
    private let eventsContinuation: AsyncStream<WalletConnectorEvent>.Continuation
    private let lock = NSLock()
    private var sessionsByTopic: [String: WalletConnectorSession] = [:]

    /// - Parameter callback: the app's universal link / custom scheme Coinbase
    ///   returns to (must be registered in the host app and allow-listed).
    public init(callback: URL, host: URL = URL(string: "https://wallet.coinbase.com/wsegue")!) {
        let stream = AsyncStream<WalletConnectorEvent>.makeStream()
        self.eventsStream = stream.stream
        self.eventsContinuation = stream.continuation
        if !CoinbaseWalletSDK.isConfigured {
            CoinbaseWalletSDK.configure(host: host, callback: callback)
        }
    }

    public var events: AsyncStream<WalletConnectorEvent> { eventsStream }

    public func connect(wallet: ThirdPartyWalletProvider?) async throws -> WalletConnectorSession {
        let account = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Account, Error>) in
            Task { @MainActor in
                CoinbaseWalletSDK.shared.initiateHandshake(initialActions: [Action(jsonRpc: .eth_requestAccounts)]) { result, account in
                    switch result {
                    case .success where account != nil:
                        continuation.resume(returning: account!)
                    case .success:
                        continuation.resume(throwing: WalletConnectionError.invalidResponse)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
        }

        let session = Self.session(from: account)
        lock.withLock { sessionsByTopic[session.topic.rawValue] = session }
        eventsContinuation.yield(.sessionSettled(session))
        return session
    }

    public func request(_ request: WalletRequest, in sessionId: WalletSessionID) async throws -> WalletResponse {
        try WalletRequestValidation.validate(request)
        let action = try Self.action(for: request)
        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            Task { @MainActor in
                CoinbaseWalletSDK.shared.makeRequest(Request(actions: [action])) { response in
                    switch response {
                    case .success(let message):
                        guard let first = message.content.first else {
                            continuation.resume(throwing: WalletConnectionError.invalidResponse)
                            return
                        }
                        switch first {
                        case .success(let json):
                            continuation.resume(returning: json.rawValue)
                        case .failure(let actionError):
                            continuation.resume(throwing: WalletConnectionError.internalFailure(actionError.message))
                        }
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
        return WalletResponse(id: request.id, result: result)
    }

    public func handleCallback(url: URL) async throws {
        _ = try await MainActor.run {
            try CoinbaseWalletSDK.shared.handleResponse(url)
        }
    }

    public func disconnect(sessionId: WalletSessionID) async throws {
        _ = await MainActor.run { CoinbaseWalletSDK.shared.resetSession() }
        lock.withLock { sessionsByTopic.removeValue(forKey: sessionId.rawValue) }
        eventsContinuation.yield(.sessionDeleted(sessionId))
    }

    public func sessions() async throws -> [WalletConnectorSession] {
        lock.withLock { Array(sessionsByTopic.values) }
    }

    // MARK: - Mapping

    private static func session(from account: Account) -> WalletConnectorSession {
        let caip10 = "eip155:\(account.networkId):\(account.address)"
        let topic = "coinbase-\(account.address.lowercased())"
        let namespace = WalletSessionNamespace(
            name: "eip155",
            accounts: [WalletAccount(caip10: caip10)],
            methods: WalletConnectionNamespaces.evmMethods,
            events: WalletConnectionNamespaces.evmEvents
        )
        return WalletConnectorSession(
            id: WalletSessionID(rawValue: topic),
            topic: WalletPairingTopic(rawValue: topic),
            providerID: WalletConnectorCatalog.coinbaseWallet.id.rawValue,
            providerName: WalletConnectorCatalog.coinbaseWallet.displayName,
            accounts: [WalletAccount(caip10: caip10)],
            namespaces: [namespace],
            expiryDate: Date().addingTimeInterval(60 * 60 * 24 * 30)
        )
    }

    private static func action(for request: WalletRequest) throws -> Action {
        Action(jsonRpc: try web3RPC(for: request))
    }

    private static func web3RPC(for request: WalletRequest) throws -> Web3JSONRPC {
        switch request.method {
        case .ethPersonalSign:
            // WC personal_sign params are [message, address].
            let message = request.params.first?.stringValue ?? ""
            let address = request.params.dropFirst().first?.stringValue ?? ""
            return .personal_sign(address: address, message: message)
        case .ethSignTypedData, .ethSignTypedDataV4:
            // WC signTypedData params are [address, typedDataJson].
            let address = request.params.first?.stringValue ?? ""
            let json = request.params.dropFirst().first?.stringValue ?? "{}"
            let typed = JSONString(rawValue: json) ?? JSONString(rawValue: "{}")!
            return request.method == .ethSignTypedData
                ? .eth_signTypedData_v3(address: address, typedDataJson: typed)
                : .eth_signTypedData_v4(address: address, typedDataJson: typed)
        case .ethSendTransaction:
            guard let object = request.params.first?.jsonObject as? [String: Any],
                  let from = object["from"] as? String else {
                throw WalletConnectionError.invalidResponse
            }
            return .eth_sendTransaction(
                fromAddress: from,
                toAddress: object["to"] as? String,
                weiValue: object["value"] as? String ?? "0x0",
                data: object["data"] as? String ?? "0x",
                nonce: object["nonce"] as? Int,
                gasPriceInWei: object["gasPrice"] as? String,
                maxFeePerGas: object["maxFeePerGas"] as? String,
                maxPriorityFeePerGas: object["maxPriorityFeePerGas"] as? String,
                gasLimit: object["gasLimit"] as? String,
                chainId: object["chainId"] as? String ?? "0x1",
                actionSource: nil
            )
        case .walletSwitchEthereumChain:
            guard let chainId = request.params.first?.objectValue?["chainId"]?.stringValue else {
                throw WalletConnectionError.invalidResponse
            }
            return .wallet_switchEthereumChain(chainId: chainId)
        case .walletAddEthereumChain:
            guard let object = request.params.first?.jsonObject as? [String: Any],
                  let chainId = object["chainId"] as? String,
                  let rpcUrls = object["rpcUrls"] as? [String] else {
                throw WalletConnectionError.invalidResponse
            }
            var nativeCurrency: AddChainNativeCurrency?
            if let native = object["nativeCurrency"] as? [String: Any],
               let name = native["name"] as? String,
               let symbol = native["symbol"] as? String,
               let decimals = native["decimals"] as? Int {
                nativeCurrency = AddChainNativeCurrency(name: name, symbol: symbol, decimals: decimals)
            }
            return .wallet_addEthereumChain(
                chainId: chainId,
                blockExplorerUrls: object["blockExplorerUrls"] as? [String],
                chainName: object["chainName"] as? String,
                iconUrls: object["iconUrls"] as? [String],
                nativeCurrency: nativeCurrency,
                rpcUrls: rpcUrls
            )
        case .walletWatchAsset:
            guard let object = request.params.first?.jsonObject as? [String: Any],
                  let type = object["type"] as? String,
                  let options = object["options"] as? [String: Any],
                  let address = options["address"] as? String else {
                throw WalletConnectionError.invalidResponse
            }
            return .wallet_watchAsset(
                type: type,
                options: WatchAssetOptions(
                    address: address,
                    symbol: options["symbol"] as? String,
                    decimals: options["decimals"] as? Int,
                    image: options["image"] as? String
                )
            )
        case .solanaSignMessage, .solanaSignTransaction, .solanaSignAllTransactions, .solanaSignAndSendTransaction:
            // Coinbase Mobile Wallet Protocol is EVM-only.
            throw WalletConnectionError.unsupportedMethod(request.method.rawValue)
        }
    }
}
#endif
