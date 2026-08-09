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
        Task { @MainActor in
            self.bridgeAppKitEvents()
        }
    }

    public var events: AsyncStream<WalletConnectorEvent> {
        eventsStream
    }

    public func connect(proposalRequest: WalletSessionProposalRequest = .defaultV1Optional, wallet: ThirdPartyWalletProvider?) async throws -> WalletConnectionStart {
        let universalLink = wallet?.universalLinkString
        let pairingURI = try await Task { @MainActor in
            AppKit.set(
                sessionParams: SessionParams(
                    requiredNamespaces: proposalRequest.requiredNamespaces.reownNamespaces,
                    optionalNamespaces: proposalRequest.optionalNamespaces.reownOptionalNamespaces
                )
            )
            let pairingURI = try await AppKit.instance.connect(walletUniversalLink: universalLink)
            AppKit.present(from: nil)
            return pairingURI
        }.value

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

    public func connect(proposal: WalletNamespaceProposalSet = .defaultV1, wallet: ThirdPartyWalletProvider?) async throws -> WalletConnectionStart {
        try await connect(proposalRequest: WalletSessionProposalRequest(requiredNamespaces: .empty, optionalNamespaces: proposal), wallet: wallet)
    }

    public func handleCallback(url: URL) async throws {
        let handled = await MainActor.run {
            AppKit.instance.handleDeeplink(url)
        }
        guard handled else {
            throw WalletConnectionError.invalidResponse
        }
    }

    public func sessions() async throws -> [WalletConnectorSession] {
        await MainActor.run {
            AppKit.instance.getSessions().map(Self.connectorSession(from:))
        }
    }

    public func disconnect(sessionId: WalletSessionID) async throws {
        try await Task { @MainActor in
            try await AppKit.instance.disconnect(topic: sessionId.rawValue)
        }.value
    }

    public func request(_ request: WalletRequest, in sessionId: WalletSessionID) async throws -> WalletResponse {
        try WalletRequestValidation.validate(request)
        let liveSessions = await MainActor.run {
            AppKit.instance.getSessions().map(Self.connectorSession(from:))
        }
        guard let session = liveSessions.first(where: { $0.id == sessionId }) else {
            throw WalletConnectionError.sessionExpired
        }
        try WalletSessionGrantValidator.validate(request, in: session)
        // The SDK assigns its own JSON-RPC id when the `Request` is created; the
        // caller's `request.id` never reaches the wallet. Build the request once,
        // then correlate the response by the id the SDK actually used.
        let reownReq = try reownRequest(from: request, sessionId: sessionId)
        let wireID = WalletSignRequestID(rawValue: reownReq.id.string)
        let task = Task {
            try await pendingRequests.wait(id: wireID, expiryDate: request.expiryDate)
        }
        do {
            try await Task { @MainActor in
                try await AppKit.instance.request(params: reownReq)
            }.value
            let response = try await task.value
            // Hand the caller a response tagged with the id they supplied.
            return WalletResponse(id: request.id, result: response.result)
        } catch {
            task.cancel()
            await pendingRequests.reject(wireID, error: WalletSDKErrorMapper.connectionError(message: error.localizedDescription, fallback: .internalFailure(error.localizedDescription)))
            throw error
        }
    }

    @MainActor
    private func bridgeAppKitEvents() {
        // ReownAppKit exposes session/response/socket updates only through Combine
        // publishers, so the bridge subscribes with `sink` and republishes onto
        // WalletConnectorKit's `AsyncStream`. Combine is confined to this SDK
        // boundary; the rest of the kit stays async/await.
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
                    guard let requestID = Self.requestID(from: response) else { return }
                    switch response.result {
                    case .response(let value):
                        if let result = Self.encode(value) {
                            await pendingRequests.resolve(WalletResponse(id: requestID, result: result))
                        } else {
                            // A successful result we cannot re-encode is surfaced as
                            // an error rather than a misleading empty-string result.
                            await pendingRequests.fail(requestID, error: WalletConnectionError.invalidResponse)
                        }
                    case .error(let rpcError):
                        // An error response must fail the pending request rather
                        // than resolve it with the error encoded as a "result".
                        await pendingRequests.fail(
                            requestID,
                            error: WalletSDKErrorMapper.connectionError(code: rpcError.code, message: rpcError.message, fallback: .invalidResponse)
                        )
                    }
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
        case .ethPersonalSign, .ethSignTypedData, .ethSignTypedDataV4, .solanaSignMessage:
            guard request.params.count == 2 else { throw WalletConnectionError.invalidResponse }
            return request.params.map { $0.jsonObject as Any }
        case .ethSendTransaction, .walletSwitchEthereumChain, .walletAddEthereumChain, .walletWatchAsset, .solanaSignTransaction, .solanaSignAllTransactions, .solanaSignAndSendTransaction:
            guard request.params.count == 1 else { throw WalletConnectionError.invalidResponse }
            return request.params.map { $0.jsonObject as Any }
        }
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

    private static func requestID(from response: W3MResponse) -> WalletSignRequestID? {
        // `RPCID.string` is the canonical wire form (matches `Request.id.string`
        // used when the request was submitted).
        response.id.map { WalletSignRequestID(rawValue: $0.string) }
    }

    private static func encode(_ value: AnyCodable) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func socketStatus(from status: SocketConnectionStatus) -> WalletSocketStatus {
        switch status {
        case .connected:
            return .connected
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

    var reownOptionalNamespaces: [String: ProposalNamespace]? {
        isEmpty ? nil : reownNamespaces
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

#endif
