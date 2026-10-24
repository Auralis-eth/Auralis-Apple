import Foundation

/// Publishes runtime events to any current subscribers.
public protocol RuntimeEventPublishing: Sendable {
    func publish(_ event: WorkflowEventEnvelope) async
}

/// Vends an async stream of runtime events. Each call returns an independent subscription.
public protocol RuntimeEventObserving: Sendable {
    func events() async -> AsyncStream<WorkflowEventEnvelope>
}

/// Durable progress for a named, replayable runtime-event consumer.
public protocol RuntimeEventCheckpointStoring: Sendable {
    func checkpoint(for subscriberID: String) async -> UUID?
    func saveCheckpoint(_ eventID: UUID, for subscriberID: String) async
    func resetAll() async

    /// Writes any cursor still held in memory through to durable storage.
    ///
    /// Part of the protocol so a composition root can force durability at a known-good moment
    /// (app backgrounding, above all) without knowing which implementation it holds.
    ///
    /// Deliberately *not* given a no-op default in a protocol extension. A `nonisolated` default
    /// there shadows an actor's own isolated `flush()` at the call site — the conformance still
    /// compiles, `await store.flush()` still typechecks, and it silently does nothing, which is
    /// exactly the bug this method exists to prevent. Every conformer states its own durability
    /// behaviour instead, even when that statement is "nothing to write".
    func flush() async
}

public actor InMemoryRuntimeEventCheckpointStore: RuntimeEventCheckpointStoring {
    private var checkpoints: [String: UUID] = [:]

    public init() {}

    public func checkpoint(for subscriberID: String) -> UUID? { checkpoints[subscriberID] }
    public func saveCheckpoint(_ eventID: UUID, for subscriberID: String) { checkpoints[subscriberID] = eventID }
    public func resetAll() { checkpoints.removeAll() }
    /// Nothing to flush: this store is the in-memory cursor, so there is no durable copy behind it.
    public func flush() { }
}

public struct RuntimeEventSubscriberHealth: Equatable, Sendable {
    public let subscriberID: String
    public let isConnected: Bool
    public let deliveredCount: Int
    public let droppedCount: Int
    public let lastDeliveredEventID: UUID?
    public let replayGapCount: Int

    public init(
        subscriberID: String,
        isConnected: Bool,
        deliveredCount: Int,
        droppedCount: Int,
        lastDeliveredEventID: UUID?,
        replayGapCount: Int = 0
    ) {
        self.subscriberID = subscriberID
        self.isConnected = isConnected
        self.deliveredCount = deliveredCount
        self.droppedCount = droppedCount
        self.lastDeliveredEventID = lastDeliveredEventID
        self.replayGapCount = replayGapCount
    }

    public var isHealthy: Bool { isConnected && droppedCount == 0 && replayGapCount == 0 }
}

/// Durable storage for recent runtime events. The event bus still fans out live events, but this store
/// lets Mission Control hydrate a bounded event timeline after relaunch.
public protocol RuntimeEventHistoryStoring: Sendable {
    func append(_ event: WorkflowEventEnvelope) async throws
    func recentEvents(limit: Int) async -> [WorkflowEventEnvelope]
    func resetAll() async
}

public actor InMemoryRuntimeEventHistoryStore: RuntimeEventHistoryStoring {
    /// Default cap on retained events. Chosen to comfortably exceed the typical
    /// `recentEvents(limit:)` read of 100 while keeping the process-lifetime footprint bounded.
    public static let defaultCapacity = 500

    private var events: [WorkflowEventEnvelope] = []
    private let capacity: Int

    /// - Parameter capacity: Maximum number of most-recent events retained. Older events are
    ///   dropped once this bound is exceeded, so memory does not grow for the process lifetime.
    public init(capacity: Int = InMemoryRuntimeEventHistoryStore.defaultCapacity) {
        self.capacity = max(1, capacity)
    }

    public func append(_ event: WorkflowEventEnvelope) {
        events.insert(event, at: 0)
        if events.count > capacity {
            events.removeLast(events.count - capacity)
        }
    }

    public func recentEvents(limit: Int) -> [WorkflowEventEnvelope] {
        guard limit > 0 else { return [] }
        return Array(events.prefix(limit))
    }

    public func resetAll() {
        events.removeAll()
    }
}

/// The runtime's nervous system: a multi-subscriber, async-safe event fan-out.
///
/// Deliberately built on `AsyncStream` rather than Combine (per project convention). Delivery policy:
/// events are only delivered to subscriptions that exist *at publish time*. A subscriber that calls
/// `events()` after an event was published will not receive that earlier event from the stream. Recent
/// history is retained through ``RuntimeEventHistoryStoring`` and can be read with ``recentEvents(limit:)``.
///
/// Ordinary UI subscriptions are bounded via `.bufferingNewest`. Named critical consumers use
/// ``reliableEvents(subscriberID:checkpointStore:replayLimit:)`` for unbounded live delivery plus
/// durable replay after their last successfully processed checkpoint.
public actor RuntimeEventBus: RuntimeEventPublishing, RuntimeEventObserving {
    /// Default per-subscription buffer size. Large enough to avoid drops for consumers that drain
    /// continuously, while still bounding memory for a subscriber that stops reading.
    public static let defaultSubscriptionBufferSize = 256
    public static let defaultReliableSubscriptionBufferSize = 1_024

    private struct Subscription {
        let id: UUID
        let subscriberID: String
        let reportsHealth: Bool
        let continuation: AsyncStream<WorkflowEventEnvelope>.Continuation
        var isReplaying: Bool
        var pendingLiveEvents: [WorkflowEventEnvelope]
        var deliveredCount: Int
        var droppedCount: Int
        var replayGapCount: Int
        var lastDeliveredEventID: UUID?
    }

    private var subscriptions: [UUID: Subscription] = [:]
    private var lastKnownHealth: [String: RuntimeEventSubscriberHealth] = [:]
    private var droppedDeliveryCount = 0
    private var persistedEventCount = 0
    private var historyPersistenceFailureCount = 0
    private var lastPersistedEventID: UUID?
    private let historyStore: (any RuntimeEventHistoryStoring)?
    private let subscriptionBufferSize: Int
    private let reliableSubscriptionBufferSize: Int

    public init(
        historyStore: (any RuntimeEventHistoryStoring)? = InMemoryRuntimeEventHistoryStore(),
        subscriptionBufferSize: Int = RuntimeEventBus.defaultSubscriptionBufferSize,
        reliableSubscriptionBufferSize: Int = RuntimeEventBus.defaultReliableSubscriptionBufferSize
    ) {
        self.historyStore = historyStore
        self.subscriptionBufferSize = max(1, subscriptionBufferSize)
        self.reliableSubscriptionBufferSize = max(1, reliableSubscriptionBufferSize)
    }

    public func publish(_ event: WorkflowEventEnvelope) async {
        if let historyStore {
            do {
                try await historyStore.append(event)
                persistedEventCount += 1
                lastPersistedEventID = event.id
            } catch {
                // Live delivery must remain available when local persistence is temporarily
                // unavailable. Surface the failure through subscriber health so Mission Control
                // cannot mistake a live-only event stream for a healthy durable audit trail.
                historyPersistenceFailureCount += 1
            }
        }
        var overflowedSubscriptionIDs: [UUID] = []
        // Iterate an explicit id snapshot rather than the live `keys` view. The view holds a
        // reference to the dictionary's storage for the whole loop, so the first `subscriptions[id] =`
        // below would copy the entire subscription table on every publish. Correct either way — the
        // snapshot is what makes it free.
        for id in Array(subscriptions.keys) {
            guard var subscription = subscriptions[id] else { continue }
            if subscription.isReplaying {
                if subscription.pendingLiveEvents.count < reliableSubscriptionBufferSize {
                    subscription.pendingLiveEvents.append(event)
                } else if subscription.reportsHealth {
                    // `reliableEvents` suspends while it reads the durable checkpoint and history.
                    // Actor reentrancy lets publishers arrive during that window, so this side queue
                    // needs the same bound as the stream it eventually feeds. Termination makes the
                    // consumer reconnect from its last checkpoint instead of silently losing work.
                    subscription.droppedCount += 1
                    droppedDeliveryCount += 1
                    overflowedSubscriptionIDs.append(id)
                }
                subscriptions[id] = subscription
                continue
            }
            if !deliver(event, to: &subscription), subscription.reportsHealth {
                overflowedSubscriptionIDs.append(id)
            }
            subscriptions[id] = subscription
        }
        for id in overflowedSubscriptionIDs {
            subscriptions[id]?.continuation.finish()
            unregister(id: id)
        }
    }

    public func events() -> AsyncStream<WorkflowEventEnvelope> {
        // The build closure runs synchronously within this actor-isolated method, so the subscriber
        // is registered before `events()` returns. That closes the race where a publish that happens
        // immediately after subscribing could be missed.
        makeSubscription(subscriberID: "live.\(UUID().uuidString)", bufferingPolicy: .bufferingNewest(subscriptionBufferSize))
    }

    /// A named, replayable subscription for audit-critical consumers. Events retained after the saved
    /// checkpoint are replayed oldest-first before live delivery begins. Its in-memory buffer is
    /// bounded; overflow terminates the stream so the consumer can reconnect from its checkpoint.
    /// A checkpoint missing from retained history is reported as an unhealthy replay gap.
    public func reliableEvents(
        subscriberID: String,
        checkpointStore: any RuntimeEventCheckpointStoring,
        replayLimit: Int = 10_000
    ) async -> AsyncStream<WorkflowEventEnvelope> {
        let id = UUID()
        // A durable checkpoint belongs to one logical consumer. Allowing two live streams to share
        // the same name would let either one advance the other's cursor and silently skip work after
        // a restart. Re-subscribing therefore replaces the older stream deterministically.
        let existingIDs = subscriptions.compactMap { id, subscription in
            subscription.subscriberID == subscriberID ? id : nil
        }
        for existingID in existingIDs {
            subscriptions[existingID]?.continuation.finish()
            unregister(id: existingID)
        }
        let stream = makeSubscription(
            id: id,
            subscriberID: subscriberID,
            bufferingPolicy: .bufferingOldest(reliableSubscriptionBufferSize),
            isReplaying: true,
            reportsHealth: true
        )
        let checkpoint = await checkpointStore.checkpoint(for: subscriberID)
        let history = await historyStore?.recentEvents(limit: max(1, replayLimit)) ?? []
        let ascending = Array(history.reversed())
        let replay: ArraySlice<WorkflowEventEnvelope>
        if let checkpoint, let index = ascending.firstIndex(where: { $0.id == checkpoint }) {
            replay = ascending[ascending.index(after: index)...]
        } else {
            replay = ascending[...]
            if checkpoint != nil {
                subscriptionReplayGap(id: id)
            }
        }
        guard var subscription = subscriptions[id] else { return stream }
        var overflowed = false
        for event in replay where !overflowed {
            overflowed = !deliver(event, to: &subscription)
        }
        for event in subscription.pendingLiveEvents where !history.contains(where: { $0.id == event.id }) {
            guard !overflowed else { break }
            overflowed = !deliver(event, to: &subscription)
        }
        subscription.pendingLiveEvents.removeAll(keepingCapacity: false)
        subscription.isReplaying = false
        subscriptions[id] = subscription
        if overflowed {
            subscription.continuation.finish()
            unregister(id: id)
        }
        return stream
    }

    /// Number of live subscriptions. Intended for tests and diagnostics.
    public var subscriberCount: Int {
        subscriptions.count
    }

    /// Number of per-subscriber live deliveries dropped because a bounded stream was full.
    /// Durable history is appended before fan-out and is unaffected by this diagnostic counter.
    public var droppedEventCount: Int {
        droppedDeliveryCount
    }

    public func subscriberHealth() -> [RuntimeEventSubscriberHealth] {
        var health = lastKnownHealth
        if historyStore != nil {
            health["runtime.history"] = RuntimeEventSubscriberHealth(
                subscriberID: "runtime.history",
                isConnected: true,
                deliveredCount: persistedEventCount,
                droppedCount: historyPersistenceFailureCount,
                lastDeliveredEventID: lastPersistedEventID
            )
        }
        for subscription in subscriptions.values where subscription.reportsHealth {
            health[subscription.subscriberID] = healthSnapshot(for: subscription, connected: true)
        }
        return health.values.sorted { $0.subscriberID < $1.subscriberID }
    }

    public func recentEvents(limit: Int = 100) async -> [WorkflowEventEnvelope] {
        guard limit > 0 else { return [] }
        return await historyStore?.recentEvents(limit: limit) ?? []
    }

    private func unregister(id: UUID) {
        guard let subscription = subscriptions.removeValue(forKey: id) else { return }
        if subscription.reportsHealth {
            lastKnownHealth[subscription.subscriberID] = healthSnapshot(for: subscription, connected: false)
        }
    }

    private func makeSubscription(
        id: UUID = UUID(),
        subscriberID: String,
        bufferingPolicy: AsyncStream<WorkflowEventEnvelope>.Continuation.BufferingPolicy,
        isReplaying: Bool = false,
        reportsHealth: Bool = false
    ) -> AsyncStream<WorkflowEventEnvelope> {
        let priorHealth = reportsHealth ? lastKnownHealth[subscriberID] : nil
        return AsyncStream(WorkflowEventEnvelope.self, bufferingPolicy: bufferingPolicy) { continuation in
            subscriptions[id] = Subscription(
                id: id,
                subscriberID: subscriberID,
                reportsHealth: reportsHealth,
                continuation: continuation,
                isReplaying: isReplaying,
                pendingLiveEvents: [],
                deliveredCount: priorHealth?.deliveredCount ?? 0,
                droppedCount: priorHealth?.droppedCount ?? 0,
                replayGapCount: priorHealth?.replayGapCount ?? 0,
                lastDeliveredEventID: priorHealth?.lastDeliveredEventID
            )
            continuation.onTermination = { [weak self] _ in
                Task { await self?.unregister(id: id) }
            }
        }
    }

    @discardableResult
    private func deliver(_ event: WorkflowEventEnvelope, to subscription: inout Subscription) -> Bool {
        switch subscription.continuation.yield(event) {
        case .enqueued:
            subscription.deliveredCount += 1
            subscription.lastDeliveredEventID = event.id
            return true
        case .dropped:
            subscription.droppedCount += 1
            droppedDeliveryCount += 1
            return false
        case .terminated:
            return false
        @unknown default:
            return false
        }
    }

    private func subscriptionReplayGap(id: UUID) {
        guard var subscription = subscriptions[id] else { return }
        subscription.replayGapCount += 1
        subscriptions[id] = subscription
    }

    private func healthSnapshot(for subscription: Subscription, connected: Bool) -> RuntimeEventSubscriberHealth {
        RuntimeEventSubscriberHealth(
            subscriberID: subscription.subscriberID,
            isConnected: connected,
            deliveredCount: subscription.deliveredCount,
            droppedCount: subscription.droppedCount,
            lastDeliveredEventID: subscription.lastDeliveredEventID,
            replayGapCount: subscription.replayGapCount
        )
    }
}
