#if os(iOS)
@preconcurrency import CoinbaseWalletSDK
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
    private let connectTimeout: TimeInterval
    private let requestTimeout: TimeInterval
    private let sessionValidity: TimeInterval
    private var sessionsByTopic: [String: WalletConnectorSession] = [:]

    /// Coinbase Mobile Wallet Protocol has no session-expiry concept, so the
    /// adapter stamps a **synthetic** expiry this far in the future. A wallet that
    /// is reset/revoked out-of-band still reads as live locally until this window
    /// elapses; keep it short if the host wants restore to re-handshake sooner.
    public static let defaultSessionValidity: TimeInterval = 60 * 60 * 24 * 30

    /// - Parameters:
    ///   - callback: The app's universal link / custom scheme Coinbase returns to
    ///     (must be registered in the host app and allow-listed).
    ///   - host: Coinbase Wallet segue host. Defaults to the production MWP host.
    ///   - connectTimeout: Maximum time to wait for the SDK handshake callback.
    ///   - requestTimeout: Maximum time to wait for a request callback.
    ///   - sessionValidity: Synthetic lifetime stamped on the connected session
    ///     (see `defaultSessionValidity`); MWP itself never expires the session.
    public init(
        callback: URL,
        host: URL = LiveCoinbaseWalletSDKClient.coinbaseWalletSegueHost,
        connectTimeout: TimeInterval = 120,
        requestTimeout: TimeInterval = 300,
        sessionValidity: TimeInterval = LiveCoinbaseWalletSDKClient.defaultSessionValidity
    ) {
        let stream = AsyncStream<WalletConnectorEvent>.makeStream()
        self.eventsStream = stream.stream
        self.eventsContinuation = stream.continuation
        self.connectTimeout = connectTimeout
        self.requestTimeout = requestTimeout
        self.sessionValidity = sessionValidity
        if !CoinbaseWalletSDK.isConfigured {
            CoinbaseWalletSDK.configure(host: host, callback: callback)
        }
    }

    public var events: AsyncStream<WalletConnectorEvent> { eventsStream }

    public func connect(wallet: ThirdPartyWalletProvider?) async throws -> WalletConnectorSession {
        let account: Account = try await awaitSDKCallback(
            timeout: connectTimeout,
            timeoutID: WalletSignRequestID(rawValue: "coinbase-connect")
        ) { resume in
            CoinbaseWalletSDK.shared.initiateHandshake(initialActions: [Action(jsonRpc: .eth_requestAccounts)]) { result, account in
                switch result {
                case .success:
                    guard let account else {
                        resume(.failure(WalletConnectionError.invalidResponse))
                        return
                    }
                    resume(.success(account))
                case .failure(let error):
                    resume(.failure(error))
                }
            }
        }

        let session = Self.session(from: account, validity: sessionValidity)
        lock.withLock { sessionsByTopic[session.topic.rawValue] = session }
        eventsContinuation.yield(.sessionSettled(session))
        return session
    }

    public func request(_ request: WalletRequest, in sessionId: WalletSessionID) async throws -> WalletResponse {
        try WalletRequestValidation.validate(request)
        guard let session = lock.withLock({ sessionsByTopic[sessionId.rawValue] }) else {
            throw WalletConnectionError.sessionExpired
        }
        try WalletSessionGrantValidator.validate(request, in: session)
        let action = try Self.action(for: request)
        let result: String = try await awaitSDKCallback(timeout: requestTimeout, timeoutID: request.id) { resume in
            CoinbaseWalletSDK.shared.makeRequest(Request(actions: [action])) { response in
                switch response {
                case .success(let message):
                    guard let first = message.content.first else {
                        resume(.failure(WalletConnectionError.invalidResponse))
                        return
                    }
                    switch first {
                    case .success(let json):
                        resume(.success(json.rawValue))
                    case .failure(let actionError):
                        resume(.failure(WalletConnectionError.internalFailure(actionError.message)))
                    }
                case .failure(let error):
                    resume(.failure(error))
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

    /// Tears down the Coinbase session. Note MWP is single-session: `resetSession`
    /// clears the **entire** SDK session regardless of `sessionId`, so
    /// disconnecting any tracked topic ends the one live Coinbase connection.
    public func disconnect(sessionId: WalletSessionID) async throws {
        _ = await MainActor.run { CoinbaseWalletSDK.shared.resetSession() }
        lock.withLock { _ = sessionsByTopic.removeValue(forKey: sessionId.rawValue) }
        eventsContinuation.yield(.sessionDeleted(sessionId))
    }

    public func sessions() async throws -> [WalletConnectorSession] {
        lock.withLock { Array(sessionsByTopic.values) }
    }

    private func awaitSDKCallback<Value: Sendable>(
        timeout: TimeInterval,
        timeoutID: WalletSignRequestID,
        start: @escaping @MainActor (@escaping @Sendable (Result<Value, Error>) -> Void) -> Void
    ) async throws -> Value {
        let callback = CoinbaseSDKContinuationBox<Value>()
        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: Value.self) { group in
                group.addTask {
                    try await withCheckedThrowingContinuation { continuation in
                        callback.install(continuation)
                        Task { @MainActor in
                            start { result in
                                callback.resume(with: result)
                            }
                        }
                    }
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(timeout))
                    let error = WalletConnectionError.requestTimedOut(timeoutID)
                    callback.resume(with: .failure(error))
                    throw error
                }

                guard let value = try await group.next() else {
                    throw WalletConnectionError.cancelled
                }
                group.cancelAll()
                return value
            }
        } onCancel: {
            callback.resume(with: .failure(WalletConnectionError.cancelled))
        }
    }

    public static var coinbaseWalletSegueHost: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "wallet.coinbase.com"
        components.path = "/wsegue"
        guard let url = components.url else {
            preconditionFailure("Coinbase Wallet default host URL is invalid.")
        }
        return url
    }

    // MARK: - Mapping

    private static func session(from account: Account, validity: TimeInterval) -> WalletConnectorSession {
        let caip10 = "eip155:\(account.networkId):\(account.address)"
        let topic = "coinbase-\(account.address.lowercased())"
        let namespace = WalletSessionNamespace(
            name: "eip155",
            accounts: [WalletAccount(caip10: caip10)],
            methods: WalletConnectionNamespaces.evmMethods.filter { $0 != WalletRequestMethod.walletSwitchEthereumChain.rawValue },
            events: WalletConnectionNamespaces.evmEvents
        )
        return WalletConnectorSession(
            id: WalletSessionID(rawValue: topic),
            topic: WalletPairingTopic(rawValue: topic),
            providerID: WalletConnectorCatalog.coinbaseWallet.id.rawValue,
            providerName: WalletConnectorCatalog.coinbaseWallet.displayName,
            accounts: [WalletAccount(caip10: caip10)],
            namespaces: [namespace],
            // Synthetic expiry: MWP has no session lifetime (see `sessionValidity`).
            expiryDate: Date().addingTimeInterval(validity)
        )
    }

    private static func action(for request: WalletRequest) throws -> Action {
        Action(jsonRpc: try web3RPC(for: request))
    }

    /// A 20-byte EVM address: `0x` followed by exactly 40 hex characters. The core
    /// `WalletRequestValidation` does not check the signer address for
    /// `personal_sign`/`signTypedData`, so the adapter guards it before handing the
    /// request to the Coinbase SDK.
    private static func isValidEVMAddress(_ value: String) -> Bool {
        guard value.hasPrefix("0x") else { return false }
        let digits = value.dropFirst(2)
        return digits.count == 40 && digits.allSatisfy(\.isHexDigit)
    }

    private static func web3RPC(for request: WalletRequest) throws -> Web3JSONRPC {
        switch request.method {
        case .ethPersonalSign:
            // WC personal_sign params are [message, address].
            guard let message = request.params.first?.stringValue,
                  let address = request.params.dropFirst().first?.stringValue,
                  Self.isValidEVMAddress(address) else {
                throw WalletConnectionError.invalidAccount(request.params.dropFirst().first?.stringValue ?? "")
            }
            return .personal_sign(address: address, message: message)
        case .ethSignTypedData, .ethSignTypedDataV4:
            // WC signTypedData params are [address, typedDataJson].
            guard let address = request.params.first?.stringValue,
                  Self.isValidEVMAddress(address) else {
                throw WalletConnectionError.invalidAccount(request.params.first?.stringValue ?? "")
            }
            // A non-JSON typed-data payload is rejected outright rather than being
            // force-unwrapped into a `{}` stand-in that the wallet would sign.
            guard let json = request.params.dropFirst().first?.stringValue,
                  let typed = JSONString(rawValue: json) else {
                throw WalletConnectionError.invalidResponse
            }
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
            // Deliberately unsupported and kept consistent with the granted grant:
            // `session(from:)` omits `wallet_switchEthereumChain` from the namespace
            // methods, so `WalletSessionGrantValidator` already rejects this method
            // before it can reach here. Throwing explicitly (rather than leaving a
            // `.wallet_switchEthereumChain` mapping arm that can never run) keeps the
            // two places in agreement. To enable it, grant the method in
            // `session(from:)` AND restore the mapping here.
            throw WalletConnectionError.unsupportedMethod(request.method.rawValue)
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

private final class CoinbaseSDKContinuationBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var pendingResult: Result<Value, Error>?

    func install(_ continuation: CheckedContinuation<Value, Error>) {
        let resultToResume: Result<Value, Error>? = lock.withLock {
            if let pendingResult {
                self.pendingResult = nil
                return pendingResult
            }
            self.continuation = continuation
            return nil
        }
        if let resultToResume {
            continuation.resume(with: resultToResume)
        }
    }

    func resume(with result: Result<Value, Error>) {
        let continuationToResume: CheckedContinuation<Value, Error>? = lock.withLock {
            if let current = self.continuation {
                self.continuation = nil
                return current
            }
            if pendingResult == nil {
                pendingResult = result
            }
            return nil
        }
        continuationToResume?.resume(with: result)
    }
}
#endif
