import Foundation

public struct WalletCallbackExpectation: Hashable, Codable, Sendable {
    public let operationID: String
    public let expiresAt: Date?

    public init(operationID: String, expiresAt: Date? = nil) {
        self.operationID = operationID
        self.expiresAt = expiresAt
    }

    public func isExpired(now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now
    }
}

public actor WalletInboundURLCoordinator {
    private let handler: WalletReturnURLHandler
    private let maxHandledSignatures: Int
    private let maxExpectations: Int
    private var handledSignatures: Set<String> = []
    private var handledSignatureOrder: [String] = []
    private var queuedPayloads: [WalletReturnPayload] = []
    private var expectationsByOperationID: [String: WalletCallbackExpectation] = [:]
    private var expectationOrder: [String] = []

    public init(
        handler: WalletReturnURLHandler = WalletReturnURLHandler(),
        maxHandledSignatures: Int = 256,
        maxExpectations: Int = 256
    ) {
        self.handler = handler
        self.maxHandledSignatures = max(1, maxHandledSignatures)
        self.maxExpectations = max(1, maxExpectations)
    }

    /// Scoped convenience initializer: builds a `WalletReturnURLHandler` limited
    /// to the app's own callback scheme(s) and host(s), so an inbound URL from
    /// another origin is rejected before any dedup/operation-ID checks. Prefer
    /// this over the default `init` whenever the coordinator ingests untrusted
    /// URLs (SceneDelegate / `.onOpenURL` / universal links).
    public init(
        allowedSchemes: Set<String>,
        allowedHosts: Set<String>,
        maxHandledSignatures: Int = 256,
        maxExpectations: Int = 256
    ) {
        self.handler = WalletReturnURLHandler(allowedSchemes: allowedSchemes, allowedHosts: allowedHosts)
        self.maxHandledSignatures = max(1, maxHandledSignatures)
        self.maxExpectations = max(1, maxExpectations)
    }

    /// Registers a callback expectation. The map is bounded and evicted
    /// oldest-first, so a caller that registers expectations without a matching
    /// callback (including ones with no `expiresAt`, which the expiry sweep never
    /// prunes) cannot grow it without bound.
    public func registerExpectation(_ expectation: WalletCallbackExpectation) {
        if expectationsByOperationID[expectation.operationID] == nil {
            expectationOrder.append(expectation.operationID)
        }
        expectationsByOperationID[expectation.operationID] = expectation
        while expectationOrder.count > maxExpectations {
            let evicted = expectationOrder.removeFirst()
            expectationsByOperationID.removeValue(forKey: evicted)
        }
    }

    public func cancelExpectation(operationID: String) {
        if expectationsByOperationID.removeValue(forKey: operationID) != nil {
            expectationOrder.removeAll { $0 == operationID }
        }
    }

    public func capture(_ url: URL, isReady: Bool, expectedOperationID: String? = nil) -> WalletReturnPayload? {
        guard let payload = handler.handle(url) else {
            return nil
        }
        // Only record the signature once the callback passes the expectation
        // gate, so a URL rejected for a non-matching operation does not poison a
        // later legitimate retry of the same URL. `markHandled` still runs last
        // so genuine duplicate deliveries are suppressed.
        guard consumeMatchingExpectation(from: url, expectedOperationID: expectedOperationID),
              markHandled(Self.signature(for: url)) else {
            return nil
        }

        if isReady {
            return payload
        }
        queuedPayloads.append(payload)
        return nil
    }

    public func drainQueuedPayloads() -> [WalletReturnPayload] {
        let payloads = queuedPayloads
        queuedPayloads.removeAll()
        return payloads
    }

    public func reset() {
        handledSignatures.removeAll()
        handledSignatureOrder.removeAll()
        queuedPayloads.removeAll()
        expectationsByOperationID.removeAll()
        expectationOrder.removeAll()
    }

    /// Removes an expectation from both the map and the eviction order, returning
    /// whether it was present.
    @discardableResult
    private func removeExpectation(operationID: String) -> Bool {
        guard expectationsByOperationID.removeValue(forKey: operationID) != nil else { return false }
        expectationOrder.removeAll { $0 == operationID }
        return true
    }

    /// Records a callback signature, returning `false` if it was already seen.
    /// Retains at most `maxHandledSignatures` signatures, evicting oldest-first,
    /// so a long-lived coordinator does not accumulate URLs without bound.
    private func markHandled(_ signature: String) -> Bool {
        guard handledSignatures.insert(signature).inserted else {
            return false
        }
        handledSignatureOrder.append(signature)
        if handledSignatureOrder.count > maxHandledSignatures {
            let evicted = handledSignatureOrder.removeFirst()
            handledSignatures.remove(evicted)
        }
        return true
    }

    private func consumeMatchingExpectation(from url: URL, expectedOperationID: String?) -> Bool {
        pruneExpiredExpectations()
        let callbackOperationID = Self.operationID(in: url)
        if let expectedOperationID {
            guard callbackOperationID == expectedOperationID else { return false }
            removeExpectation(operationID: expectedOperationID)
            return true
        }
        guard expectationsByOperationID.isEmpty == false else { return true }
        guard let callbackOperationID,
              removeExpectation(operationID: callbackOperationID) else {
            return false
        }
        return true
    }

    private func pruneExpiredExpectations(now: Date = Date()) {
        for (operationID, expectation) in expectationsByOperationID where expectation.isExpired(now: now) {
            removeExpectation(operationID: operationID)
        }
    }

    private static func signature(for url: URL) -> String {
        // Normalize query-item ordering so the same callback with reordered
        // parameters is still recognized as a duplicate.
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        if let items = components.queryItems {
            components.queryItems = items.sorted { lhs, rhs in
                lhs.name == rhs.name ? (lhs.value ?? "") < (rhs.value ?? "") : lhs.name < rhs.name
            }
        }
        return components.string ?? url.absoluteString
    }

    private static func operationID(in url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let names = ["state", "requestId", "request_id", "id"]
        return components.queryItems?.first { names.contains($0.name) }?.value
    }
}
