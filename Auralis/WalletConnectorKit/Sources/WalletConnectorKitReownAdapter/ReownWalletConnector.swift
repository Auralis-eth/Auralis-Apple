import Foundation
import WalletConnectorKit

#if os(iOS)
@preconcurrency import ReownAppKit
#endif

public protocol ReownAppKitClient: Sendable {
    var events: AsyncStream<WalletConnectorEvent> { get }

    func connect(proposal: WalletNamespaceProposalSet, wallet: ThirdPartyWalletProvider?) async throws -> WalletConnectionStart
    func handleCallback(url: URL) async throws
    func sessions() async throws -> [WalletConnectorSession]
    func disconnect(sessionId: WalletSessionID) async throws
    func request(_ request: WalletRequest, in sessionId: WalletSessionID) async throws -> WalletResponse
}

public actor ReownWalletConnector: WalletConnector {
    private let client: any ReownAppKitClient

    public init(client: any ReownAppKitClient) {
        self.client = client
    }

    public nonisolated var events: AsyncStream<WalletConnectorEvent> {
        client.events
    }

    public func connect(
        proposal: WalletNamespaceProposalSet = .defaultV1,
        wallet: ThirdPartyWalletProvider?
    ) async throws -> WalletConnectionStart {
        try await client.connect(proposal: proposal, wallet: wallet)
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
}

public actor ReownPendingRequestStore {
    private var continuations: [WalletSignRequestID: CheckedContinuation<WalletResponse, Error>] = [:]
    private var expiryTasks: [WalletSignRequestID: Task<Void, Never>] = [:]

    public init() {}

    public func wait(for request: WalletRequest) async throws -> WalletResponse {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                continuations[request.id] = continuation
                expiryTasks[request.id]?.cancel()
                expiryTasks[request.id] = Task { [requestID = request.id, expiryDate = request.expiryDate] in
                    let delay = max(0, expiryDate.timeIntervalSinceNow)
                    try? await Task.sleep(for: .seconds(delay))
                    await self.expire(requestID)
                }
            }
        } onCancel: {
            Task { await self.reject(request.id, error: WalletConnectionError.cancelled) }
        }
    }

    public func resolve(_ response: WalletResponse) {
        expiryTasks.removeValue(forKey: response.id)?.cancel()
        continuations.removeValue(forKey: response.id)?.resume(returning: response)
    }

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
