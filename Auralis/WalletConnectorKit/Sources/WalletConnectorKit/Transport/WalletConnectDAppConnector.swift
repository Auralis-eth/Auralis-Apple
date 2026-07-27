import Foundation

public final class WalletConnectDAppConnector: WalletConnector, @unchecked Sendable {
    private let transport: any WalletTransportClient
    private let launcher: DeepLinkWalletLauncher?
    private let metadata: WalletConnectionMetadata
    private let callbackURL: URL?
    private let returnURLHandler: WalletReturnURLHandler
    private let eventsStream: AsyncStream<WalletConnectorEvent>
    private let eventsContinuation: AsyncStream<WalletConnectorEvent>.Continuation

    public init(
        transport: any WalletTransportClient,
        launcher: DeepLinkWalletLauncher? = nil,
        metadata: WalletConnectionMetadata,
        callbackURL: URL? = nil,
        returnURLHandler: WalletReturnURLHandler = WalletReturnURLHandler()
    ) {
        self.transport = transport
        self.launcher = launcher
        self.metadata = metadata
        self.callbackURL = callbackURL
        self.returnURLHandler = returnURLHandler
        let stream = AsyncStream<WalletConnectorEvent>.makeStream()
        self.eventsStream = stream.stream
        self.eventsContinuation = stream.continuation
        bridgeTransportEvents()
    }

    public var events: AsyncStream<WalletConnectorEvent> {
        eventsStream
    }

    public func connect(
        proposal: WalletNamespaceProposalSet = .defaultV1,
        wallet: ThirdPartyWalletProvider?
    ) async throws -> WalletConnectionStart {
        let provider = wallet ?? WalletConnectorCatalog.genericWallet
        let preferredChain = proposal.proposals.values
            .flatMap(\.chains)
            .compactMap(\.knownChain)
            .first

        let pairing = try await transport.createPairing(
            request: WalletPairingRequest(
                providerID: provider.id,
                preferredChain: preferredChain,
                supportedChains: provider.supportedChains,
                metadata: metadata,
                callbackURL: callbackURL
            )
        )
        guard let pairingString = pairing.uri,
              let uri = WalletConnectURI(absoluteString: pairingString) else {
            throw WalletConnectionError.invalidPairingURI
        }

        var openURL: URL?
        if let launcher, wallet != nil {
            try await launcher.launch(provider: provider, pairingURI: uri)
            if let scheme = provider.deepLinkScheme {
                openURL = WalletProviderDeepLink(providerID: provider.id, scheme: scheme).url(pairingURI: uri)
            }
        }

        eventsContinuation.yield(.pairingCreated(uri))
        return WalletConnectionStart(pairingURI: uri, walletOpenURL: openURL, qrPayload: uri.absoluteString)
    }

    public func handleCallback(url: URL) async throws {
        _ = returnURLHandler.handle(url)
    }

    public func sessions() async throws -> [WalletConnectorSession] {
        try await transport.sessions().map(\.connectorSession)
    }

    public func disconnect(sessionId: WalletSessionID) async throws {
        try await transport.disconnect(topic: WalletPairingTopic(rawValue: sessionId.rawValue))
        eventsContinuation.yield(.sessionDeleted(sessionId))
    }

    public func request(_ request: WalletRequest, in sessionId: WalletSessionID) async throws -> WalletResponse {
        try await transport.publish(request, topic: WalletPairingTopic(rawValue: sessionId.rawValue))
        throw WalletConnectionError.requestTimedOut(request.id)
    }

    private func bridgeTransportEvents() {
        Task { [transport, eventsContinuation] in
            for await event in transport.events() {
                switch event {
                case .pairingCreated(let pairing):
                    if let uri = pairing.uri.flatMap(WalletConnectURI.init(absoluteString:)) {
                        eventsContinuation.yield(.pairingCreated(uri))
                    }
                case .sessionApproved(let session):
                    eventsContinuation.yield(.sessionSettled(session.connectorSession))
                case .sessionRejected(_, let error):
                    eventsContinuation.yield(.sessionRejected(error))
                case .sessionDeleted(let sessionID):
                    eventsContinuation.yield(.sessionDeleted(sessionID))
                case .pairingExpired:
                    eventsContinuation.yield(.sessionRejected(.pairingExpired))
                case .requestExpired(let requestID):
                    eventsContinuation.yield(.requestExpired(requestID))
                case .responseReceived(let response):
                    eventsContinuation.yield(.responseReceived(response))
                case .socketStatusChanged(let status):
                    eventsContinuation.yield(.socketStatusChanged(status))
                }
            }
        }
    }
}
