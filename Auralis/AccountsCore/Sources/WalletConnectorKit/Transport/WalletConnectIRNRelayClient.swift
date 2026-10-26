import Foundation
import Security

public struct WalletConnectRelayPublish: Hashable, Codable, Sendable {
    public let topic: String
    public let message: String
    public let tag: Int
    public let ttl: Int
    public let prompt: Bool

    public init(topic: String, message: String, tag: Int, ttl: Int, prompt: Bool = true) {
        self.topic = topic
        self.message = message
        self.tag = tag
        self.ttl = ttl
        self.prompt = prompt
    }
}

public enum WalletConnectRelayEvent: Hashable, Sendable {
    case subscription(topic: String, message: String, tag: Int?)
    case socketStatusChanged(WalletSocketStatus)
}

public protocol WalletConnectRelayTask: Sendable {
    func send(_ string: String) async throws
    func receive() async throws -> String
    func close() async
}

public protocol WalletConnectRelayTaskFactory: Sendable {
    func makeTask(url: URL) async throws -> any WalletConnectRelayTask
}

public actor WalletConnectIRNRelayClient {
    private struct SubscribeParams: Encodable {
        let topic: String
    }

    private struct UnsubscribeParams: Encodable {
        let topic: String
        let id: String
    }

    private struct FetchMessagesParams: Encodable {
        let topic: String
    }

    private struct PublishParams: Encodable {
        let topic: String
        let message: String
        let ttl: Int
        let tag: Int
        let prompt: Bool
    }

    private struct RelayAcknowledgement: Decodable {
        let id: Int64
        // The relay's ack `result` is not always a bool: `irn_publish` acks with
        // `true`, but `irn_subscribe` acks with a subscription-id *string* and
        // `irn_fetchMessages` with an object. Decoding as `WalletJSONValue`
        // accepts every shape so subscribe/fetch acks are recognized instead of
        // being dropped (which previously stalled every subscribe until timeout).
        let result: WalletJSONValue?
        let error: WalletConnectJSONRPCResponse<WalletConnectEmptyResult>.Failure?

        var isAcknowledgement: Bool {
            result != nil || error != nil
        }
    }

    private struct SubscriptionAcknowledgement: Encodable {
        let id: Int64
        let jsonrpc = "2.0"
        let result = true
    }

    private struct SubscriptionEnvelope: Decodable {
        struct Params: Decodable {
            struct DataPayload: Decodable {
                let topic: String
                let message: String
                let tag: Int?
            }

            let data: DataPayload
        }

        let id: Int64?
        let method: String
        let params: Params
    }

    /// The body of an `irn_fetchMessages` acknowledgement: the relay hands back
    /// the messages it queued for a topic while we were not subscribed. Optional
    /// throughout so an empty mailbox (or a differently-shaped ack) decodes to
    /// "nothing to replay" instead of failing.
    private struct FetchMessagesResult: Decodable {
        struct Message: Decodable {
            let topic: String
            let message: String
            let tag: Int?
        }

        let messages: [Message]?
        let hasMore: Bool?
    }

    private let configuration: WalletConnectRelayConfiguration
    private let taskFactory: any WalletConnectRelayTaskFactory
    private let authProvider: (any WalletConnectRelayAuthProviding)?
    private let acknowledgementTimeout: Duration
    private let eventsStream: AsyncStream<WalletConnectRelayEvent>
    private let eventsContinuation: AsyncStream<WalletConnectRelayEvent>.Continuation
    private var task: (any WalletConnectRelayTask)?
    // Coalesces concurrent `connect()` calls into one in-flight attempt. Actors
    // are re-entrant across `await`, so a bare `task == nil` check ahead of the
    // `makeTask` suspension would let two callers each open a socket; everyone
    // awaits this single task instead.
    private var connectTask: Task<Void, Error>?
    private var relayIDCounter: Int64 = 0
    private var lastIssuedRelayID: Int64 = 0
    // Proactive reconnect: a dropped socket schedules reconnection with capped
    // exponential backoff so inbound session/settle/response messages are not
    // missed until the next outbound request.
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private var isIntentionallyDisconnected = false
    private let maxReconnectBackoffSeconds: Double = 30
    private var pendingAcknowledgements: [Int64: CheckedContinuation<RelayAcknowledgement, Error>] = [:]
    private var cachedAcknowledgements: [Int64: RelayAcknowledgement] = [:]
    private var cachedAcknowledgementOrder: [Int64] = []
    private var acknowledgementTimeoutTasks: [Int64: Task<Void, Never>] = [:]
    private var subscribedTopics: Set<String> = []
    private var subscriptionIDByTopic: [String: String] = [:]
    // Caps ack messages buffered before their waiter registers, so a relay that
    // emits acks for request IDs we never await cannot grow this dictionary
    // without bound. Evicted oldest-first.
    private let maxCachedAcknowledgements = 256

    public init(
        configuration: WalletConnectRelayConfiguration,
        taskFactory: any WalletConnectRelayTaskFactory = URLSessionWalletConnectRelayTaskFactory(),
        authProvider: (any WalletConnectRelayAuthProviding)? = WalletConnectKeychainRelayAuthProvider(),
        acknowledgementTimeout: Duration = .seconds(15)
    ) {
        self.configuration = configuration
        self.taskFactory = taskFactory
        self.authProvider = authProvider
        self.acknowledgementTimeout = acknowledgementTimeout
        let stream = AsyncStream<WalletConnectRelayEvent>.makeStream()
        self.eventsStream = stream.stream
        self.eventsContinuation = stream.continuation
    }

    public nonisolated var events: AsyncStream<WalletConnectRelayEvent> {
        eventsStream
    }

    public func connect() async throws {
        guard !configuration.projectID.isEmpty else {
            throw WalletConnectRelayConfigurationError.missingProjectID
        }
        // Refuse a plaintext relay endpoint even though payloads are E2E encrypted.
        guard configuration.isSecure else {
            throw WalletConnectRelayConfigurationError.insecureRelayURL
        }
        isIntentionallyDisconnected = false
        // Join an in-flight connect rather than starting a second one.
        if let connectTask {
            try await connectTask.value
            return
        }
        guard task == nil else { return }

        let connectTask = Task<Void, Error> { [weak self] in
            guard let self else { return }
            try await self.performConnect()
        }
        self.connectTask = connectTask
        do {
            try await connectTask.value
            self.connectTask = nil
        } catch {
            self.connectTask = nil
            throw error
        }
    }

    private func performConnect() async throws {
        // Another coalesced attempt may have already established the socket.
        guard task == nil else { return }

        eventsContinuation.yield(.socketStatusChanged(.connecting))
        do {
            // The relay rejects unauthenticated sockets; attach the signed
            // Ed25519 DID-JWT alongside the projectId when a provider is present.
            let authToken = try authProvider?.authToken(audience: configuration.relayURL.absoluteString)
            task = try await taskFactory.makeTask(url: configuration.websocketURL(authToken: authToken))
        } catch {
            // A failed connect must not strand observers on `.connecting`.
            eventsContinuation.yield(.socketStatusChanged(.disconnected))
            throw error
        }
        reconnectAttempt = 0
        eventsContinuation.yield(.socketStatusChanged(.connected))
        startReceiveLoop()
        // If this is a reconnect after a dropped socket, the relay no longer
        // holds our subscriptions, so re-establish them.
        await resubscribeAll()
    }

    public func disconnect() async {
        isIntentionallyDisconnected = true
        reconnectTask?.cancel()
        reconnectTask = nil
        connectTask?.cancel()
        connectTask = nil
        await task?.close()
        task = nil
        rejectAllAcknowledgements(error: WalletConnectionError.relayDisconnected)
        cachedAcknowledgements.removeAll()
        cachedAcknowledgementOrder.removeAll()
        subscribedTopics.removeAll()
        subscriptionIDByTopic.removeAll()
        eventsContinuation.yield(.socketStatusChanged(.disconnected))
    }

    private func scheduleReconnect() {
        // Retain `subscribedTopics`; `connect()` → `resubscribeAll()` restores them.
        guard !isIntentionallyDisconnected, reconnectTask == nil, !subscribedTopics.isEmpty else { return }
        let attempt = reconnectAttempt
        reconnectAttempt += 1
        // Capped exponential backoff with full jitter so a relay blip does not
        // resynchronize every client into a reconnect thundering herd.
        let ceilingSeconds = min(maxReconnectBackoffSeconds, pow(2.0, Double(min(attempt, 5))))
        let backoff = Duration.seconds(Double.random(in: 0...ceilingSeconds))
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: backoff)
            guard let self else { return }
            await self.performReconnect()
        }
    }

    private func performReconnect() async {
        reconnectTask = nil
        guard !isIntentionallyDisconnected, task == nil else { return }
        do {
            try await connect()
        } catch {
            scheduleReconnect()
        }
    }

    public func subscribe(topic: String) async throws {
        try await connect()
        // Idempotent on a live socket: if we already hold a subscription id for
        // this topic on the current connection, re-subscribing would only re-run
        // the fetch/replay for no benefit. A reconnect clears the id map (and
        // `resubscribeAll` repopulates it), so this still re-subscribes after a
        // drop.
        if task != nil, subscriptionIDByTopic[topic] != nil { return }
        try await recoverTopic(topic)
    }

    /// Best-effort unsubscribe: drops the topic from the restored set so a later
    /// reconnect does not resurrect it, then tells the relay to stop delivering.
    public func unsubscribe(topic: String) async {
        subscribedTopics.remove(topic)
        guard task != nil, let subscriptionID = subscriptionIDByTopic.removeValue(forKey: topic) else { return }
        _ = try? await sendRequest(method: "irn_unsubscribe", params: UnsubscribeParams(topic: topic, id: subscriptionID))
    }

    private func resubscribeAll() async {
        let topics = subscribedTopics
        subscriptionIDByTopic.removeAll()
        for topic in topics {
            // Isolate per-topic recovery: a single topic that cannot be recovered
            // on reconnect (e.g. an oversized queued mailbox that exceeds the
            // fetch-page cap in `recoverTopic`) must not fail the whole reconnect
            // and strand every *other* subscription. The topic stays in
            // `subscribedTopics`, so a later reconnect retries it, and
            // `subscribe()`/`request()` recover it on demand.
            try? await recoverTopic(topic)
        }
    }

    private func recoverTopic(_ topic: String) async throws {
        for page in 0..<20 {
            let hasMore = try await fetchMessagesWithoutConnecting(topic: topic)
            if !hasMore { break }
            if page == 19 {
                throw WalletConnectionError.relayAcknowledgementFailed("Relay returned too many fetchMessages pages for topic \(topic).")
            }
        }
        try await subscribeWithoutConnecting(topic: topic)
    }

    @discardableResult
    public func fetchMessages(topic: String) async throws -> Bool {
        try await connect()
        return try await fetchMessagesWithoutConnecting(topic: topic)
    }

    private func fetchMessagesWithoutConnecting(topic: String) async throws -> Bool {
        let acknowledgement = try await sendRequest(method: "irn_fetchMessages", params: FetchMessagesParams(topic: topic))
        return deliverFetchedMessages(acknowledgement)
    }

    private func subscribeWithoutConnecting(topic: String) async throws {
        let acknowledgement = try await sendRequest(method: "irn_subscribe", params: SubscribeParams(topic: topic))
        guard let subscriptionID = acknowledgement.result?.stringValue, !subscriptionID.isEmpty else {
            throw WalletConnectionError.relayAcknowledgementFailed("Relay subscribe acknowledgement did not include a subscription id for topic \(topic).")
        }
        subscriptionIDByTopic[topic] = subscriptionID
        subscribedTopics.insert(topic)
    }

    public func publish(_ publish: WalletConnectRelayPublish) async throws {
        try await connect()
        try await sendRequest(
            method: "irn_publish",
            params: PublishParams(
                topic: publish.topic,
                message: publish.message,
                ttl: publish.ttl,
                tag: publish.tag,
                prompt: publish.prompt
            )
        )
    }

    @discardableResult
    private func sendRequest<Params: Encodable>(method: String, params: Params) async throws -> RelayAcknowledgement {
        guard let task else {
            throw WalletConnectionError.relayDisconnected
        }
        let requestID = nextRequestID()
        let request = WalletConnectJSONRPCRequest(id: requestID, method: method, params: params)
        let data = try WalletConnectJSONCoding.encoder.encode(request)
        guard let string = String(data: data, encoding: .utf8) else {
            throw WalletConnectionError.invalidResponse
        }

        try await task.send(string)
        return try await waitForAcknowledgement(id: requestID)
    }

    // Internal so the relay RPC id format is unit-testable.
    func nextRequestID() -> Int64 {
        relayIDCounter += 1
        let millis = Int64(Date().timeIntervalSince1970 * 1000)
        let entropy = Int64(Self.randomLowOrder(upperBound: 1_000_000) ?? UInt32(truncatingIfNeeded: relayIDCounter) % 1_000_000)
        let candidate = millis * 1_000_000 + entropy
        let id = max(candidate, lastIssuedRelayID + 1)
        lastIssuedRelayID = id
        return id
    }

    private static func randomLowOrder(upperBound: UInt32) -> UInt32? {
        var raw: UInt32 = 0
        let status = withUnsafeMutableBytes(of: &raw) { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else { return nil }
        return raw % upperBound
    }

    private func waitForAcknowledgement(id: Int64) async throws -> RelayAcknowledgement {
        if let cachedAcknowledgement = removeCachedAcknowledgement(id: id) {
            try evaluateAcknowledgement(cachedAcknowledgement)
            return cachedAcknowledgement
        }

        return try await withCheckedThrowingContinuation { continuation in
            pendingAcknowledgements[id] = continuation
            if let cachedAcknowledgement = removeCachedAcknowledgement(id: id) {
                resolveAcknowledgement(cachedAcknowledgement)
            } else {
                scheduleAcknowledgementTimeout(id: id)
            }
        }
    }

    private func cacheAcknowledgement(_ acknowledgement: RelayAcknowledgement) {
        if cachedAcknowledgements[acknowledgement.id] == nil {
            cachedAcknowledgementOrder.append(acknowledgement.id)
        }
        cachedAcknowledgements[acknowledgement.id] = acknowledgement
        while cachedAcknowledgementOrder.count > maxCachedAcknowledgements {
            let evicted = cachedAcknowledgementOrder.removeFirst()
            cachedAcknowledgements.removeValue(forKey: evicted)
        }
    }

    private func removeCachedAcknowledgement(id: Int64) -> RelayAcknowledgement? {
        guard let acknowledgement = cachedAcknowledgements.removeValue(forKey: id) else {
            return nil
        }
        cachedAcknowledgementOrder.removeAll { $0 == id }
        return acknowledgement
    }

    private func scheduleAcknowledgementTimeout(id: Int64) {
        acknowledgementTimeoutTasks[id] = Task { [weak self, acknowledgementTimeout] in
            try? await Task.sleep(for: acknowledgementTimeout)
            await self?.timeoutAcknowledgement(id: id)
        }
    }

    private func timeoutAcknowledgement(id: Int64) {
        acknowledgementTimeoutTasks.removeValue(forKey: id)
        guard let continuation = pendingAcknowledgements.removeValue(forKey: id) else { return }
        continuation.resume(
            throwing: WalletConnectionError.relayAcknowledgementFailed(
                "Timed out waiting for relay acknowledgement of request \(id)."
            )
        )
    }

    private func startReceiveLoop() {
        Task { [weak self] in
            guard let self else { return }
            await receiveLoop()
        }
    }

    private func receiveLoop() async {
        while let task {
            do {
                let string = try await task.receive()
                handleIncoming(string)
            } catch {
                self.task = nil
                subscriptionIDByTopic.removeAll()
                rejectAllAcknowledgements(error: WalletConnectionError.relayDisconnected)
                eventsContinuation.yield(.socketStatusChanged(.disconnected))
                // Proactively reconnect with capped exponential backoff so
                // inbound session/settle/response messages are not missed until
                // the next outbound request. `subscribedTopics` is retained and
                // restored by `resubscribeAll()` on reconnect.
                scheduleReconnect()
                return
            }
        }
    }

    private func handleIncoming(_ string: String) {
        guard let data = string.data(using: .utf8) else {
            return
        }

        if let acknowledgement = try? WalletConnectJSONCoding.decoder.decode(RelayAcknowledgement.self, from: data),
           acknowledgement.isAcknowledgement {
            if pendingAcknowledgements[acknowledgement.id] != nil {
                resolveAcknowledgement(acknowledgement)
            } else {
                cacheAcknowledgement(acknowledgement)
            }
            return
        }

        guard let envelope = try? WalletConnectJSONCoding.decoder.decode(SubscriptionEnvelope.self, from: data),
              envelope.method == "irn_subscription"
        else {
            return
        }

        eventsContinuation.yield(
            .subscription(
                topic: envelope.params.data.topic,
                message: envelope.params.data.message,
                tag: envelope.params.data.tag
            )
        )
        if let id = envelope.id {
            sendSubscriptionAcknowledgement(id: id)
        }
    }

    private func sendSubscriptionAcknowledgement(id: Int64) {
        guard let task,
              let data = try? WalletConnectJSONCoding.encoder.encode(SubscriptionAcknowledgement(id: id)),
              let string = String(data: data, encoding: .utf8) else {
            return
        }
        Task {
            try? await task.send(string)
        }
    }

    private func resolveAcknowledgement(_ acknowledgement: RelayAcknowledgement) {
        acknowledgementTimeoutTasks.removeValue(forKey: acknowledgement.id)?.cancel()
        guard let continuation = pendingAcknowledgements.removeValue(forKey: acknowledgement.id) else { return }
        do {
            try evaluateAcknowledgement(acknowledgement)
            continuation.resume(returning: acknowledgement)
        } catch {
            continuation.resume(throwing: error)
        }
    }

    /// If `acknowledgement` is an `irn_fetchMessages` reply carrying queued
    /// messages, replays each onto the subscription event stream so the transport
    /// processes it exactly as if the relay had pushed it live. Non-fetch acks
    /// (a bare `true`, a subscription-id string) decode to no messages and are
    /// ignored. Redelivery is harmless: the transport dedups on decrypted
    /// identity, so a message seen via both fetch and a live push runs once.
    private func deliverFetchedMessages(_ acknowledgement: RelayAcknowledgement) -> Bool {
        guard let result = acknowledgement.result,
              let fetched = try? result.decoded(as: FetchMessagesResult.self) else {
            return false
        }
        for message in fetched.messages ?? [] {
            eventsContinuation.yield(
                .subscription(topic: message.topic, message: message.message, tag: message.tag)
            )
        }
        return fetched.hasMore ?? false
    }

    private func evaluateAcknowledgement(_ acknowledgement: RelayAcknowledgement) throws {
        if let error = acknowledgement.error {
            throw WalletConnectionError.relayAcknowledgementFailed(error.message)
        }
        // Any non-`false` result is a success; only an explicit `false` fails.
        if case .bool(false) = acknowledgement.result {
            throw WalletConnectionError.relayAcknowledgementFailed("Relay returned false for request \(acknowledgement.id).")
        }
    }

    private func rejectAllAcknowledgements(error: Error) {
        for task in acknowledgementTimeoutTasks.values {
            task.cancel()
        }
        acknowledgementTimeoutTasks.removeAll()
        let continuations = pendingAcknowledgements.values
        pendingAcknowledgements.removeAll()
        for continuation in continuations {
            continuation.resume(throwing: error)
        }
    }
}

public final class URLSessionWalletConnectRelayTaskFactory: WalletConnectRelayTaskFactory, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func makeTask(url: URL) async throws -> any WalletConnectRelayTask {
        let task = session.webSocketTask(with: url)
        task.resume()
        return URLSessionWalletConnectRelayTask(task: task)
    }
}

public final class URLSessionWalletConnectRelayTask: WalletConnectRelayTask, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    public func send(_ string: String) async throws {
        try await task.send(.string(string))
    }

    public func receive() async throws -> String {
        let message = try await task.receive()
        switch message {
        case .string(let string):
            return string
        case .data(let data):
            guard let string = String(data: data, encoding: .utf8) else {
                throw WalletConnectionError.invalidResponse
            }
            return string
        @unknown default:
            throw WalletConnectionError.invalidResponse
        }
    }

    public func close() async {
        task.cancel(with: .goingAway, reason: nil)
    }
}
