import Foundation

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

    private struct PublishParams: Encodable {
        let topic: String
        let message: String
        let ttl: Int
        let tag: Int
        let prompt: Bool
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

        let method: String
        let params: Params
    }

    private let configuration: WalletConnectRelayConfiguration
    private let taskFactory: any WalletConnectRelayTaskFactory
    private let eventsStream: AsyncStream<WalletConnectRelayEvent>
    private let eventsContinuation: AsyncStream<WalletConnectRelayEvent>.Continuation
    private var task: (any WalletConnectRelayTask)?
    private var nextID: Int64 = 1

    public init(
        configuration: WalletConnectRelayConfiguration,
        taskFactory: any WalletConnectRelayTaskFactory = URLSessionWalletConnectRelayTaskFactory()
    ) {
        self.configuration = configuration
        self.taskFactory = taskFactory
        let stream = AsyncStream<WalletConnectRelayEvent>.makeStream()
        self.eventsStream = stream.stream
        self.eventsContinuation = stream.continuation
    }

    public nonisolated var events: AsyncStream<WalletConnectRelayEvent> {
        eventsStream
    }

    public func connect() async throws {
        guard configuration.isUsable else {
            throw WalletConnectRelayConfigurationError.missingProjectID
        }
        guard task == nil else { return }

        eventsContinuation.yield(.socketStatusChanged(.connecting))
        task = try await taskFactory.makeTask(url: configuration.websocketURL)
        eventsContinuation.yield(.socketStatusChanged(.connected))
        startReceiveLoop()
    }

    public func disconnect() async {
        await task?.close()
        task = nil
        eventsContinuation.yield(.socketStatusChanged(.disconnected))
    }

    public func subscribe(topic: String) async throws {
        try await connect()
        try await sendRequest(method: "irn_subscribe", params: SubscribeParams(topic: topic))
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

    private func sendRequest<Params: Encodable>(method: String, params: Params) async throws {
        guard let task else {
            throw WalletConnectionError.relayDisconnected
        }
        let requestID = nextID
        nextID += 1
        let request = WalletConnectJSONRPCRequest(id: requestID, method: method, params: params)
        let data = try WalletConnectJSONCoding.encoder.encode(request)
        guard let string = String(data: data, encoding: .utf8) else {
            throw WalletConnectionError.invalidResponse
        }
        try await task.send(string)
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
                eventsContinuation.yield(.socketStatusChanged(.disconnected))
                return
            }
        }
    }

    private func handleIncoming(_ string: String) {
        guard let data = string.data(using: .utf8),
              let envelope = try? WalletConnectJSONCoding.decoder.decode(SubscriptionEnvelope.self, from: data),
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
