import Combine
import Foundation
import WalletConnectorKit

#if os(iOS)
@preconcurrency import ReownAppKit
import UIKit

public final class ReownAppKitLiveClient: ReownAppKitClient, @unchecked Sendable {
    private let pendingRequests: ReownPendingRequestStore
    private let eventsStream: AsyncStream<WalletConnectorEvent>
    private let eventsContinuation: AsyncStream<WalletConnectorEvent>.Continuation
    private var cancellables: Set<AnyCancellable> = []

    public init(pendingRequests: ReownPendingRequestStore = ReownPendingRequestStore()) {
        self.pendingRequests = pendingRequests
        let stream = AsyncStream<WalletConnectorEvent>.makeStream()
        self.eventsStream = stream.stream
        self.eventsContinuation = stream.continuation
        bridgeAppKitEvents()
    }

    public var events: AsyncStream<WalletConnectorEvent> {
        eventsStream
    }

    public func connect(proposal: WalletNamespaceProposalSet = .defaultV1, wallet: ThirdPartyWalletProvider?) async throws -> WalletConnectionStart {
        AppKit.set(sessionParams: SessionParams(namespaces: proposal.reownNamespaces))
        let universalLink = wallet?.universalLinkString
        let pairingURI = try await AppKit.instance.connect(walletUniversalLink: universalLink)
        await MainActor.run {
            AppKit.present(from: nil)
        }

        guard let pairingURI else {
            throw WalletConnectionError.invalidPairingURI
        }
        let connectorURI = WalletConnectorKit.WalletConnectURI(
            topic: pairingURI.topic,
            symKey: pairingURI.symKey,
            relayProtocol: pairingURI.relay.protocol,
            relayData: pairingURI.relay.data,
            expiryTimestamp: Int64(pairingURI.expiryTimestamp),
            methods: pairingURI.methods,
            version: pairingURI.version
        )
        return WalletConnectionStart(pairingURI: connectorURI, qrPayload: connectorURI.absoluteString)
    }

    public func handleCallback(url: URL) async throws {
        guard AppKit.instance.handleDeeplink(url) else {
            throw WalletConnectionError.invalidResponse
        }
    }

    public func sessions() async throws -> [WalletConnectorSession] {
        AppKit.instance.getSessions().map(Self.connectorSession(from:))
    }

    public func disconnect(sessionId: WalletSessionID) async throws {
        try await AppKit.instance.disconnect(topic: sessionId.rawValue)
    }

    public func request(_ request: WalletRequest, in sessionId: WalletSessionID) async throws -> WalletResponse {
        let task = Task {
            try await pendingRequests.wait(for: request)
        }
        do {
            try await AppKit.instance.request(params: try reownRequest(from: request, sessionId: sessionId))
            return try await task.value
        } catch {
            task.cancel()
            await pendingRequests.reject(request.id, error: WalletSDKErrorMapper.connectionError(message: error.localizedDescription, fallback: .internalFailure(error.localizedDescription)))
            throw error
        }
    }

    private func bridgeAppKitEvents() {
        AppKit.instance.sessionSettlePublisher
            .sink { [eventsContinuation] session in
                eventsContinuation.yield(.sessionSettled(Self.connectorSession(from: session)))
            }
            .store(in: &cancellables)

        AppKit.instance.sessionRejectionPublisher
            .sink { [eventsContinuation] _, reason in
                eventsContinuation.yield(.sessionRejected(WalletSDKErrorMapper.connectionError(message: reason.message, fallback: .userRejected)))
            }
            .store(in: &cancellables)

        AppKit.instance.sessionDeletePublisher
            .sink { [eventsContinuation] topic, _ in
                eventsContinuation.yield(.sessionDeleted(WalletSessionID(rawValue: topic)))
            }
            .store(in: &cancellables)

        AppKit.instance.sessionResponsePublisher
            .sink { [pendingRequests] response in
                Task {
                    await pendingRequests.resolveOldest(result: Self.responseString(from: response))
                }
            }
            .store(in: &cancellables)

        AppKit.instance.socketConnectionStatusPublisher
            .sink { [eventsContinuation] status in
                eventsContinuation.yield(.socketStatusChanged(Self.socketStatus(from: status)))
            }
            .store(in: &cancellables)
    }

    private func reownRequest(from request: WalletRequest, sessionId: WalletSessionID) throws -> Request {
        guard let blockchain = Blockchain(request.chain.caip2) else {
            throw WalletConnectionError.invalidChain(request.chain.caip2)
        }
        return try Request(
            topic: sessionId.rawValue,
            method: request.method.rawValue,
            params: AnyCodable(any: try reownParams(from: request)),
            chainId: blockchain,
            ttl: max(300, request.expiryDate.timeIntervalSinceNow)
        )
    }

    private func reownParams(from request: WalletRequest) throws -> Any {
        switch request.method {
        case .ethPersonalSign:
            guard request.params.count == 2 else { throw WalletConnectionError.invalidResponse }
            return [request.params[0], request.params[1]]
        case .ethSignTypedData, .ethSignTypedDataV4:
            guard request.params.count == 2 else { throw WalletConnectionError.invalidResponse }
            return [request.params[0], request.params[1]]
        case .ethSendTransaction:
            guard let transaction = try decodeFirstParam(WalletTransactionRequest.self, from: request) else {
                throw WalletConnectionError.invalidResponse
            }
            return [transaction.reownDictionary]
        case .walletSwitchEthereumChain:
            guard let chainId = request.params.first else { throw WalletConnectionError.invalidResponse }
            return [["chainId": chainId]]
        case .walletAddEthereumChain:
            guard let addChain = try decodeFirstParam(WalletAddEthereumChainRequest.self, from: request) else {
                throw WalletConnectionError.invalidResponse
            }
            return [addChain.reownDictionary]
        case .solanaSignMessage, .solanaSignTransaction, .solanaSignAllTransactions:
            return request.params
        }
    }

    private func decodeFirstParam<Value: Decodable>(_ type: Value.Type, from request: WalletRequest) throws -> Value? {
        guard let first = request.params.first, let data = first.data(using: .utf8) else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }

    private static func connectorSession(from session: Session) -> WalletConnectorSession {
        WalletConnectorSession(
            id: WalletSessionID(rawValue: session.topic),
            topic: WalletPairingTopic(rawValue: session.topic),
            providerID: session.peer.name.lowercased().replacingOccurrences(of: " ", with: "-"),
            providerName: session.peer.name,
            accounts: session.accounts.map { WalletAccount(caip10: $0.absoluteString) },
            namespaces: session.namespaces.map { name, namespace in
                WalletConnectorKit.WalletSessionNamespace(
                    name: name,
                    accounts: namespace.accounts.map { WalletAccount(caip10: $0.absoluteString) },
                    methods: Array(namespace.methods).sorted(),
                    events: Array(namespace.events).sorted()
                )
            }.sorted { $0.name < $1.name },
            expiryDate: session.expiryDate
        )
    }

    private static func responseString(from response: W3MResponse) -> String {
        if let data = try? JSONEncoder().encode(response.result), let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: response.result)
    }

    private static func socketStatus(from status: SocketConnectionStatus) -> WalletSocketStatus {
        switch status {
        case .connected:
            return .connected
        case .connecting:
            return .connecting
        case .disconnected:
            return .disconnected
        }
    }
}

private extension WalletNamespaceProposalSet {
    var reownNamespaces: [String: ProposalNamespace] {
        proposals.mapValues { proposal in
            ProposalNamespace(
                chains: proposal.chains.compactMap { Blockchain($0.caip2) },
                methods: Set(proposal.methods),
                events: Set(proposal.events)
            )
        }
    }
}

private extension ThirdPartyWalletProvider {
    var universalLinkString: String? {
        for method in connectionMethods {
            if case .universalLink(let value) = method {
                return value
            }
        }
        return nil
    }
}

private extension WalletTransactionRequest {
    var reownDictionary: [String: Any] {
        var value: [String: Any] = [
            "from": from,
            "value": self.value,
            "data": data,
            "chainId": chainId,
        ]
        value["to"] = to
        value["nonce"] = nonce
        value["gas"] = gas
        value["gasPrice"] = gasPrice
        value["maxFeePerGas"] = maxFeePerGas
        value["maxPriorityFeePerGas"] = maxPriorityFeePerGas
        value["gasLimit"] = gasLimit
        return value.compactMapValues { $0 }
    }
}

private extension WalletAddEthereumChainRequest {
    var reownDictionary: [String: Any] {
        var value: [String: Any] = [
            "chainId": chainId,
            "rpcUrls": rpcUrls,
        ]
        value["blockExplorerUrls"] = blockExplorerUrls
        value["chainName"] = chainName
        value["iconUrls"] = iconUrls
        if let nativeCurrency {
            value["nativeCurrency"] = [
                "name": nativeCurrency.name,
                "symbol": nativeCurrency.symbol,
                "decimals": nativeCurrency.decimals,
            ]
        }
        return value.compactMapValues { $0 }
    }
}
#endif
