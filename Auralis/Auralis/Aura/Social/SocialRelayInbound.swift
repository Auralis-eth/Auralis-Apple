import Foundation
import AuralisOperators
import WalletConnectorKit

/// One decrypted-once-more-hop inbound relay message: the raw (still-sealed) payload plus its topic.
struct SocialRelayInboundMessage: Equatable, Sendable {
    let topic: String
    let message: String
}

/// A source of inbound relay messages the pump can drain. Abstracted so the app wires the live
/// WalletConnect/IRN socket while tests drive a controllable stream with a fake.
protocol SocialRelayInboundStreaming: Sendable {
    /// `async` so a source that must register itself upstream (see ``SocialRelayInboundBroadcaster``)
    /// can finish doing so before returning. The pump awaits this before `subscribeToSavedInvites`,
    /// which is what makes `SocialRelaySessionRuntime`'s "inbound-first" ordering real rather than
    /// merely intended.
    func inboundMessages() async -> AsyncStream<SocialRelayInboundMessage>
}

/// Fans one relay socket out to every live session.
///
/// `WalletConnectIRNRelayClient.events` is a single stored `AsyncStream`, and `AsyncStream` is
/// **unicast**: each yielded element goes to exactly one iterator. Handing that stream directly to every
/// session meant two live sessions split the inbound traffic between their pumps rather than each seeing
/// all of it — and because a pump discards anything not on its bound topic, roughly half of each
/// session's messages were silently dropped, non-deterministically, with no retry and no local record.
///
/// This consumes the socket exactly once and re-yields every message to all registered subscribers, so
/// per-topic filtering stays where it belongs: in the coordinator.
actor SocialRelayInboundBroadcaster {
    /// The upstream socket events. A closure rather than the concrete client so the fan-out can be
    /// tested without a relay: this type is pure routing logic, and routing logic that cannot be
    /// tested is where the original unicast bug lived unnoticed.
    private let events: @Sendable () -> AsyncStream<WalletConnectRelayEvent>
    private var continuations: [UUID: AsyncStream<SocialRelayInboundMessage>.Continuation] = [:]
    private var pumpTask: Task<Void, Never>?

    init(relayClient: WalletConnectIRNRelayClient) {
        self.events = { relayClient.events }
    }

    /// Test seam: fan out an arbitrary event stream.
    init(events: @escaping @Sendable () -> AsyncStream<WalletConnectRelayEvent>) {
        self.events = events
    }

    /// A stream carrying every inbound relay message, independent of any other subscriber's stream.
    ///
    /// `async` so registration is *ordered*: it returns only once this subscriber is in
    /// `continuations`. A fire-and-forget registration left `SocialRelaySessionRuntime.start()`'s
    /// documented "inbound-first so a message arriving during subscribe is not missed" ordering
    /// unenforced — the pump had started but the continuation was not yet installed, and the relay's
    /// `irn_fetchMessages` mailbox replay is delivered exactly once.
    func subscribe() async -> AsyncStream<SocialRelayInboundMessage> {
        let id = UUID()
        var installed: AsyncStream<SocialRelayInboundMessage>.Continuation?
        let stream = AsyncStream<SocialRelayInboundMessage> { continuation in
            installed = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSubscriber(id) }
            }
        }
        if let installed {
            continuations[id] = installed
            startPumpIfNeeded()
        }
        return stream
    }

    /// Registration is installed synchronously inside ``subscribe()`` with no suspension between
    /// building the stream and storing its continuation, so this can only ever run after the
    /// subscriber is present — there is no "terminated before registered" case to defend against.
    private func removeSubscriber(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }

    /// Starts the single socket-draining task. Idempotent, and deliberately never torn down when the
    /// last subscriber leaves: the relay client outlives individual sessions, and a restart would race
    /// a new session's `subscribe()` against messages already in flight.
    private func startPumpIfNeeded() {
        guard pumpTask == nil else { return }
        let events = events()
        pumpTask = Task { [weak self] in
            for await event in events {
                guard case let .subscription(topic, message, _) = event else { continue }
                await self?.broadcast(SocialRelayInboundMessage(topic: topic, message: message))
            }
            await self?.finishAll()
        }
    }

    private func broadcast(_ message: SocialRelayInboundMessage) {
        for continuation in continuations.values {
            continuation.yield(message)
        }
    }

    private func finishAll() {
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
        pumpTask = nil
    }
}

/// Live inbound source over the WalletConnect/IRN relay client. Maps the client's `.subscription`
/// relay events (both live pushes and messages replayed from `irn_fetchMessages` on subscribe/reconnect)
/// into ``SocialRelayInboundMessage`` values, dropping non-message socket events.
///
/// Every session's source shares one ``SocialRelayInboundBroadcaster`` so they do not compete for the
/// relay client's unicast event stream.
struct WalletConnectSocialRelayInboundSource: SocialRelayInboundStreaming {
    private let broadcaster: SocialRelayInboundBroadcaster

    init(broadcaster: SocialRelayInboundBroadcaster) {
        self.broadcaster = broadcaster
    }

    func inboundMessages() async -> AsyncStream<SocialRelayInboundMessage> {
        await broadcaster.subscribe()
    }
}

/// Drains inbound relay messages into a session's ``SocialRelayCoordinator``.
///
/// Each message is handed to `handleInbound`, which opens it with the session cipher and appends it to
/// the event log. A payload that fails to decrypt (wrong key — i.e. a message for another session on a
/// shared/colliding topic), is malformed, or is oversized fails closed inside the coordinator; the pump
/// swallows that per-message error so one bad payload cannot tear down the whole subscription. The pump
/// owns exactly one draining task and is idempotent on `start`/`stop`.
actor SocialRelayInboundPump {
    private let coordinator: SocialRelayCoordinator
    private let source: any SocialRelayInboundStreaming
    /// Fired after each inbound message is handled — the seam a queue coordinator hooks to reconcile the
    /// linked playlist when a peer's accepted-queue event arrives. Runs whether or not the message
    /// decrypted (a foreign/dropped payload leaves the projection unchanged, so reconcile is a no-op).
    private let onProcessed: @Sendable () async -> Void
    private var task: Task<Void, Never>?

    init(
        coordinator: SocialRelayCoordinator,
        source: any SocialRelayInboundStreaming,
        onProcessed: @escaping @Sendable () async -> Void = { }
    ) {
        self.coordinator = coordinator
        self.source = source
        self.onProcessed = onProcessed
    }

    /// Idempotent. `async` because the source's registration is awaited before the draining task is
    /// installed, so by the time this returns the pump is genuinely attached to the stream — which is
    /// what `SocialRelaySessionRuntime.start()` relies on when it runs this before subscribing.
    func start() async {
        guard task == nil else { return }
        let coordinator = coordinator
        let onProcessed = onProcessed
        let stream = await source.inboundMessages()
        // Re-check after the suspension: this actor is reentrant, so a concurrent `start()` could have
        // installed a task while the source was registering.
        guard task == nil else { return }
        task = Task {
            for await inbound in stream {
                try? await coordinator.handleInbound(message: inbound.message, topic: inbound.topic)
                await onProcessed()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
