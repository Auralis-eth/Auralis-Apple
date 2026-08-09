import Foundation
import WalletConnectorKit

#if os(iOS)
@preconcurrency import ReownAppKit
#endif

public protocol ReownAppKitClient: Sendable {
    var events: AsyncStream<WalletConnectorEvent> { get }
    var isConfigured: Bool { get }

    func connect(proposalRequest: WalletSessionProposalRequest, wallet: ThirdPartyWalletProvider?) async throws -> WalletConnectionStart
    func connect(proposal: WalletNamespaceProposalSet, wallet: ThirdPartyWalletProvider?) async throws -> WalletConnectionStart
    func handleCallback(url: URL) async throws
    func sessions() async throws -> [WalletConnectorSession]
    func disconnect(sessionId: WalletSessionID) async throws
    func request(_ request: WalletRequest, in sessionId: WalletSessionID) async throws -> WalletResponse
}

public extension ReownAppKitClient {
    var isConfigured: Bool { true }
}

public actor ReownWalletConnector: WalletConnector {
    public nonisolated let runtimeFamily: WalletConnectorRuntimeFamily = .walletConnectSDK
    private let client: any ReownAppKitClient
    private let cryptoProvider: any WalletConnectorCryptoProvider
    private let metadata: WalletConnectionMetadata
    private let hasProductionMetadata: Bool

    public init(
        client: any ReownAppKitClient,
        cryptoProvider: any WalletConnectorCryptoProvider = DefaultWalletConnectorCryptoProvider(),
        metadata: WalletConnectionMetadata? = nil
    ) {
        self.client = client
        self.cryptoProvider = cryptoProvider
        self.hasProductionMetadata = metadata != nil
        self.metadata = metadata ?? Self.defaultOwnershipMetadata()
    }

    public nonisolated var events: AsyncStream<WalletConnectorEvent> {
        client.events
    }

    /// Production readiness is gated on the dependencies EVM ownership
    /// verification actually needs. A configured live client is necessary but not
    /// sufficient: without a recovery-capable `WalletConnectorCryptoProvider` the
    /// connector's own `verifyOwnership` fails closed, and without real
    /// `WalletConnectionMetadata` the SIWE challenge is bound to a placeholder
    /// domain. In either case readiness stays `.experimental` so the host cannot
    /// route production traffic through a connector that cannot complete the
    /// default `.requireVerified` lifecycle.
    public nonisolated var readiness: WalletConnectorReadiness {
        guard client.isConfigured else {
            return .unavailable("Reown AppKit adapter is not configured; no live client is available. See README.")
        }
        guard cryptoProvider.supportsRecovery else {
            return .experimental("Reown adapter is configured but no recovery-capable WalletConnectorCryptoProvider was injected; EVM ownership verification fails closed. Inject a secp256k1 recovery provider for production use.")
        }
        guard hasProductionMetadata else {
            return .experimental("Reown adapter is configured but no production WalletConnectionMetadata was injected; ownership challenges are bound to a placeholder domain. Inject real app metadata for production use.")
        }
        return .productionReady
    }

    public func connect(
        proposalRequest: WalletSessionProposalRequest = .defaultV1Optional,
        wallet: ThirdPartyWalletProvider?
    ) async throws -> WalletConnectionStart {
        try await client.connect(proposalRequest: proposalRequest, wallet: wallet)
    }

    public func connect(
        proposal: WalletNamespaceProposalSet = .defaultV1,
        wallet: ThirdPartyWalletProvider?
    ) async throws -> WalletConnectionStart {
        try await client.connect(proposalRequest: WalletSessionProposalRequest(requiredNamespaces: .empty, optionalNamespaces: proposal), wallet: wallet)
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
        let nonce = try WalletOwnershipChallengeMessageBuilder.nonce()
        let issuedAt = Date()
        let message = WalletOwnershipChallengeMessageBuilder.evmSIWEMessage(
            address: address,
            chain: chain,
            statement: statement,
            nonce: nonce,
            issuedAt: issuedAt,
            expiration: expiryDate,
            metadata: metadata
        )
        switch chain.namespace {
        case "eip155":
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
            // provider supports it, an EIP-1271 smart-contract-wallet signature.
            return try await WalletOwnershipVerifier.verifyPersonalSign(
                expectedAddress: address,
                message: Data(message.utf8),
                signatureHex: response.result,
                chain: chain,
                using: cryptoProvider
            )
        case "solana":
            // Solana ownership is self-contained ed25519 (a Solana address is its
            // public key) — no crypto provider needed. Shared with the custom
            // transport so verification is identical across connectors.
            let solanaMessage = WalletOwnershipChallengeMessageBuilder.solanaMessage(
                address: address,
                statement: statement,
                nonce: nonce,
                issuedAt: issuedAt,
                expiration: expiryDate,
                metadata: metadata
            )
            return try await WalletSolanaOwnershipVerifier.verifyChallenge(
                address: address,
                challengeText: solanaMessage,
                expiryDate: expiryDate,
                send: { try await request($0, in: sessionId) }
            )
        default:
            throw WalletConnectionError.unsupportedChain(chain)
        }
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

/// Correlates outbound wallet requests with the responses the relay delivers.
///
/// Waiters and responses are keyed by the **JSON-RPC id the SDK actually puts on
/// the wire** — not the caller's `WalletRequest.id`, which never travels (see
/// `ReownAppKitLiveClient.request`). Responses can also arrive before the waiter
/// has registered (the submit call and the response publisher race), so early
/// outcomes are buffered and handed to the next matching waiter.
public actor ReownPendingRequestStore {
    private enum Outcome {
        case success(WalletResponse)
        case failure(Error)
    }

    private var continuations: [WalletSignRequestID: CheckedContinuation<WalletResponse, Error>] = [:]
    private var expiryTasks: [WalletSignRequestID: Task<Void, Never>] = [:]
    private var bufferedOutcomes: [WalletSignRequestID: Outcome] = [:]
    private var bufferedOrder: [WalletSignRequestID] = []
    private let maxBufferedOutcomes = 128

    public init() {}

    public func wait(for request: WalletRequest) async throws -> WalletResponse {
        try await wait(id: request.id, expiryDate: request.expiryDate)
    }

    /// Waits for the response correlated with `id` (the on-the-wire JSON-RPC id).
    public func wait(id: WalletSignRequestID, expiryDate: Date) async throws -> WalletResponse {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // A response may have landed before we registered; consume it.
                if let outcome = takeBufferedOutcome(id) {
                    resume(continuation, with: outcome)
                    return
                }
                continuations[id] = continuation
                expiryTasks[id]?.cancel()
                expiryTasks[id] = Task { [id, expiryDate] in
                    let delay = max(0, expiryDate.timeIntervalSinceNow)
                    try? await Task.sleep(for: .seconds(delay))
                    self.expire(id)
                }
            }
        } onCancel: {
            Task { await self.reject(id, error: WalletConnectionError.cancelled) }
        }
    }

    /// Delivers a successful response, buffering it if no waiter has registered.
    public func resolve(_ response: WalletResponse) {
        deliver(id: response.id, outcome: .success(response))
    }

    /// Delivers a failure for a specific request, buffering it if no waiter has
    /// registered yet (e.g. an error response that races the submit call).
    public func fail(_ requestID: WalletSignRequestID, error: Error) {
        deliver(id: requestID, outcome: .failure(error))
    }

    /// Rejects an outstanding waiter without buffering — used for cancellation
    /// and other cases where a late waiter must not inherit a stale error.
    public func reject(_ requestID: WalletSignRequestID, error: Error) {
        expiryTasks.removeValue(forKey: requestID)?.cancel()
        continuations.removeValue(forKey: requestID)?.resume(throwing: error)
    }

    public func expire(_ requestID: WalletSignRequestID) {
        reject(requestID, error: WalletConnectionError.requestTimedOut(requestID))
    }

    public func pendingRequestIDs() -> [WalletSignRequestID] {
        Array(continuations.keys).sorted { $0.rawValue < $1.rawValue }
    }

    private func deliver(id: WalletSignRequestID, outcome: Outcome) {
        expiryTasks.removeValue(forKey: id)?.cancel()
        if let continuation = continuations.removeValue(forKey: id) {
            resume(continuation, with: outcome)
        } else {
            bufferOutcome(id, outcome)
        }
    }

    private func resume(_ continuation: CheckedContinuation<WalletResponse, Error>, with outcome: Outcome) {
        switch outcome {
        case .success(let response):
            continuation.resume(returning: response)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    private func bufferOutcome(_ id: WalletSignRequestID, _ outcome: Outcome) {
        if bufferedOutcomes[id] == nil {
            bufferedOrder.append(id)
        }
        bufferedOutcomes[id] = outcome
        while bufferedOrder.count > maxBufferedOutcomes {
            let evicted = bufferedOrder.removeFirst()
            bufferedOutcomes.removeValue(forKey: evicted)
        }
    }

    private func takeBufferedOutcome(_ id: WalletSignRequestID) -> Outcome? {
        guard let outcome = bufferedOutcomes.removeValue(forKey: id) else { return nil }
        bufferedOrder.removeAll { $0 == id }
        return outcome
    }
}

public enum ReownWalletSessionMapper {
    public static func session(
        id: String,
        topic: String,
        providerID: String,
        providerName: String,
        accountCAIP10Values: [String],
        namespaces: [WalletSessionNamespace],
        expiryDate: Date
    ) -> WalletConnectorSession {
        WalletConnectorSession(
            id: WalletSessionID(rawValue: id),
            topic: WalletPairingTopic(rawValue: topic),
            providerID: providerID,
            providerName: providerName,
            accounts: accountCAIP10Values.map(WalletAccount.init(caip10:)),
            namespaces: namespaces,
            expiryDate: expiryDate
        )
    }
}

public struct UnconfiguredReownAppKitClient: ReownAppKitClient {
    private let message: String

    public init(message: String = "Reown AppKit client is not configured. Provide a live ReownAppKitClient backed by ReownAppKit.") {
        self.message = message
    }

    public var events: AsyncStream<WalletConnectorEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    public var isConfigured: Bool { false }

    public func connect(proposalRequest: WalletSessionProposalRequest, wallet: ThirdPartyWalletProvider?) async throws -> WalletConnectionStart {
        throw WalletConnectionError.unavailable(message)
    }

    public func connect(proposal: WalletNamespaceProposalSet, wallet: ThirdPartyWalletProvider?) async throws -> WalletConnectionStart {
        throw WalletConnectionError.unavailable(message)
    }

    public func handleCallback(url: URL) async throws {
        throw WalletConnectionError.unavailable(message)
    }

    public func sessions() async throws -> [WalletConnectorSession] {
        throw WalletConnectionError.unavailable(message)
    }

    public func disconnect(sessionId: WalletSessionID) async throws {
        throw WalletConnectionError.unavailable(message)
    }

    public func request(_ request: WalletRequest, in sessionId: WalletSessionID) async throws -> WalletResponse {
        throw WalletConnectionError.unavailable(message)
    }
}
