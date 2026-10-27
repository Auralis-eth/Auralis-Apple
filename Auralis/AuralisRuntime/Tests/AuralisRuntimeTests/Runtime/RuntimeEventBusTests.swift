import Foundation
@testable import AuralisRuntime
import Testing

@Suite("RuntimeEventBus")
struct RuntimeEventBusTests {
    @Test
    func singleSubscriberReceivesPublishedEvent() async {
        let bus = RuntimeEventBus()
        let stream = await bus.events()
        let envelope = WorkflowEventEnvelope(event: .workflowStarted)

        await bus.publish(envelope)

        var iterator = stream.makeAsyncIterator()
        let received = await iterator.next()
        #expect(received == envelope)
    }

    @Test
    func twoSubscribersBothReceiveEvent() async {
        let bus = RuntimeEventBus()
        let first = await bus.events()
        let second = await bus.events()
        let envelope = WorkflowEventEnvelope(event: .executionUpdate("hello"))

        await bus.publish(envelope)

        var firstIterator = first.makeAsyncIterator()
        var secondIterator = second.makeAsyncIterator()
        #expect(await firstIterator.next() == envelope)
        #expect(await secondIterator.next() == envelope)
    }

    @Test
    func subscriberAddedAfterPublishMissesPriorEvents() async {
        let bus = RuntimeEventBus()
        // Published with no subscribers — must not be replayed by the live stream.
        await bus.publish(WorkflowEventEnvelope(event: .workflowStarted))

        let stream = await bus.events()
        let later = WorkflowEventEnvelope(event: .executionUpdate("later"))
        await bus.publish(later)

        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == later)
    }

    @Test
    func publishedEventsAreRecordedInBoundedHistory() async {
        let bus = RuntimeEventBus()
        let first = WorkflowEventEnvelope(event: .workflowStarted)
        let second = WorkflowEventEnvelope(event: .executionUpdate("later"))

        await bus.publish(first)
        await bus.publish(second)

        #expect(await bus.recentEvents(limit: 1) == [second])
        #expect(await bus.recentEvents(limit: 10) == [second, first])
    }

    @Test
    func historyIsBoundedToCapacityDroppingOldest() async {
        let store = InMemoryRuntimeEventHistoryStore(capacity: 3)
        let bus = RuntimeEventBus(historyStore: store)
        var published: [WorkflowEventEnvelope] = []
        for index in 0..<10 {
            let envelope = WorkflowEventEnvelope(event: .executionUpdate("e\(index)"))
            published.append(envelope)
            await bus.publish(envelope)
        }

        // Only the three most recent events are retained, newest first.
        let retained = await bus.recentEvents(limit: 100)
        #expect(retained == [published[9], published[8], published[7]])
    }

    @Test
    func historyStoreClampsNonPositiveCapacity() async {
        let store = InMemoryRuntimeEventHistoryStore(capacity: 0)
        await store.append(WorkflowEventEnvelope(event: .workflowStarted))
        let second = WorkflowEventEnvelope(event: .executionUpdate("second"))
        await store.append(second)

        // Capacity clamps to at least 1, so exactly one (the newest) event is retained.
        let retained = await store.recentEvents(limit: 100)
        #expect(retained == [second])
    }

    @Test(arguments: [0, -1, Int.min])
    func nonPositiveHistoryLimitsReturnNoEvents(limit: Int) async {
        let bus = RuntimeEventBus()
        await bus.publish(WorkflowEventEnvelope(event: .workflowStarted))

        #expect(await bus.recentEvents(limit: limit).isEmpty)
    }

    @Test
    func deliveryOrderIsPreservedPerPublisher() async {
        let bus = RuntimeEventBus()
        let stream = await bus.events()
        let a = WorkflowEventEnvelope(event: .executionUpdate("a"))
        let b = WorkflowEventEnvelope(event: .executionUpdate("b"))

        await bus.publish(a)
        await bus.publish(b)

        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == a)
        #expect(await iterator.next() == b)
    }

    @Test
    func terminatedSubscriptionIsRemoved() async {
        let bus = RuntimeEventBus()
        do {
            let stream = await bus.events()
            _ = stream // dropped at end of scope, terminating the continuation
        }
        // Give the onTermination task a chance to run.
        try? await Task.sleep(nanoseconds: 50_000_000)
        let count = await bus.subscriberCount
        #expect(count == 0)
    }

    @Test
    func bufferOverflowIsBoundedAndObservable() async {
        let bus = RuntimeEventBus(subscriptionBufferSize: 1)
        let stream = await bus.events()
        let first = WorkflowEventEnvelope(event: .executionUpdate("first"))
        let second = WorkflowEventEnvelope(event: .executionUpdate("second"))
        let third = WorkflowEventEnvelope(event: .executionUpdate("third"))

        await bus.publish(first)
        await bus.publish(second)
        await bus.publish(third)

        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == third)
        #expect(await bus.droppedEventCount == 2)
        #expect(await bus.recentEvents(limit: 3) == [third, second, first])
    }

    @Test
    func concurrentPublishersDoNotLoseOrDuplicateEvents() async {
        let publisherCount = 4
        let eventsPerPublisher = 50
        let bus = RuntimeEventBus(subscriptionBufferSize: publisherCount * eventsPerPublisher)
        let stream = await bus.events()

        await withTaskGroup(of: Void.self) { group in
            for publisher in 0..<publisherCount {
                group.addTask {
                    for sequence in 0..<eventsPerPublisher {
                        await bus.publish(
                            WorkflowEventEnvelope(event: .executionUpdate("p\(publisher)-\(sequence)"))
                        )
                    }
                }
            }
        }

        var iterator = stream.makeAsyncIterator()
        var messages: [String] = []
        for _ in 0..<(publisherCount * eventsPerPublisher) {
            guard let envelope = await iterator.next(),
                  case let .executionUpdate(message) = envelope.event else { break }
            messages.append(message)
        }

        #expect(messages.count == publisherCount * eventsPerPublisher)
        #expect(Set(messages).count == messages.count)
        for publisher in 0..<publisherCount {
            let sequence = messages
                .filter { $0.hasPrefix("p\(publisher)-") }
                .compactMap { Int($0.split(separator: "-").last ?? "") }
            #expect(sequence == Array(0..<eventsPerPublisher))
        }
        #expect(await bus.droppedEventCount == 0)
    }

    @Test
    func reliableSubscriberSurvivesBurstWithoutDrops() async {
        let bus = RuntimeEventBus(subscriptionBufferSize: 1)
        let checkpoints = InMemoryRuntimeEventCheckpointStore()
        let stream = await bus.reliableEvents(subscriberID: "audit", checkpointStore: checkpoints)
        let events = (0..<1_000).map {
            WorkflowEventEnvelope(event: .executionUpdate("event-\($0)"))
        }

        for event in events { await bus.publish(event) }

        var iterator = stream.makeAsyncIterator()
        var received: [WorkflowEventEnvelope] = []
        for _ in events.indices {
            if let event = await iterator.next() { received.append(event) }
        }
        #expect(received == events)
        let health = await bus.subscriberHealth().first { $0.subscriberID == "audit" }
        #expect(health?.droppedCount == 0)
        #expect(health?.deliveredCount == events.count)
    }

    @Test
    func reliableSubscriberReplaysOnlyEventsAfterCheckpoint() async {
        let history = InMemoryRuntimeEventHistoryStore(capacity: 10)
        let bus = RuntimeEventBus(historyStore: history)
        let checkpoints = InMemoryRuntimeEventCheckpointStore()
        let events = (0..<3).map {
            WorkflowEventEnvelope(event: .executionUpdate("event-\($0)"))
        }
        for event in events { await bus.publish(event) }
        await checkpoints.saveCheckpoint(events[0].id, for: "audit")

        let stream = await bus.reliableEvents(subscriberID: "audit", checkpointStore: checkpoints)
        var iterator = stream.makeAsyncIterator()

        #expect(await iterator.next() == events[1])
        #expect(await iterator.next() == events[2])
    }

    @Test
    func unknownCheckpointReplaysAllRetainedEvents() async {
        let history = InMemoryRuntimeEventHistoryStore(capacity: 2)
        let bus = RuntimeEventBus(historyStore: history)
        let checkpoints = InMemoryRuntimeEventCheckpointStore()
        let discarded = WorkflowEventEnvelope(event: .executionUpdate("discarded"))
        let retained = (0..<2).map {
            WorkflowEventEnvelope(event: .executionUpdate("retained-\($0)"))
        }
        await bus.publish(discarded)
        for event in retained { await bus.publish(event) }
        await checkpoints.saveCheckpoint(discarded.id, for: "audit")

        let stream = await bus.reliableEvents(subscriberID: "audit", checkpointStore: checkpoints)
        var iterator = stream.makeAsyncIterator()

        #expect(await iterator.next() == retained[0])
        #expect(await iterator.next() == retained[1])
        let health = await bus.subscriberHealth().first { $0.subscriberID == "audit" }
        #expect(health?.replayGapCount == 1)
        #expect(health?.isHealthy == false)
    }

    @Test
    func reliableBufferOverflowTerminatesAndReportsUnhealthyInsteadOfGrowingWithoutBound() async {
        let bus = RuntimeEventBus(reliableSubscriptionBufferSize: 2)
        let checkpoints = InMemoryRuntimeEventCheckpointStore()
        let stream = await bus.reliableEvents(subscriberID: "audit", checkpointStore: checkpoints)
        let events = (0..<3).map {
            WorkflowEventEnvelope(event: .executionUpdate("event-\($0)"))
        }

        for event in events { await bus.publish(event) }

        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == events[0])
        #expect(await iterator.next() == events[1])
        #expect(await iterator.next() == nil)
        let health = await bus.subscriberHealth().first { $0.subscriberID == "audit" }
        #expect(health?.isConnected == false)
        #expect(health?.droppedCount == 1)
        #expect(health?.isHealthy == false)
    }

    @Test
    func reliableReplaySideBufferOverflowTerminatesInsteadOfGrowingWithoutBound() async {
        let history = SuspendedRuntimeEventHistoryStore()
        let bus = RuntimeEventBus(historyStore: history, reliableSubscriptionBufferSize: 2)
        let checkpoints = InMemoryRuntimeEventCheckpointStore()
        let subscription = Task {
            await bus.reliableEvents(subscriberID: "audit", checkpointStore: checkpoints)
        }
        await history.waitUntilReadIsSuspended()

        for sequence in 0..<3 {
            await bus.publish(WorkflowEventEnvelope(event: .executionUpdate("live-\(sequence)")))
        }
        await history.resumeRead()

        let stream = await subscription.value
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == nil)
        let health = await bus.subscriberHealth().first { $0.subscriberID == "audit" }
        #expect(health?.isConnected == false)
        #expect(health?.droppedCount == 1)
        #expect(health?.isHealthy == false)
    }

    @Test
    func duplicateReliableSubscriberNameReplacesOlderStream() async {
        let bus = RuntimeEventBus()
        let checkpoints = InMemoryRuntimeEventCheckpointStore()
        let first = await bus.reliableEvents(subscriberID: "audit", checkpointStore: checkpoints)
        let second = await bus.reliableEvents(subscriberID: "audit", checkpointStore: checkpoints)
        let event = WorkflowEventEnvelope(event: .workflowStarted)
        await bus.publish(event)

        var firstIterator = first.makeAsyncIterator()
        var secondIterator = second.makeAsyncIterator()

        #expect(await firstIterator.next() == nil)
        #expect(await secondIterator.next() == event)
        #expect(await bus.subscriberCount == 1)
        let health = await bus.subscriberHealth().filter { $0.subscriberID == "audit" }
        #expect(health.count == 1)
        #expect(health.first?.isConnected == true)
    }

    @Test
    func historyPersistenceFailureDoesNotBlockLiveDeliveryAndIsUnhealthy() async {
        let bus = RuntimeEventBus(historyStore: FailingRuntimeEventHistoryStore())
        let stream = await bus.events()
        let event = WorkflowEventEnvelope(event: .workflowStarted)

        await bus.publish(event)

        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == event)
        let health = await bus.subscriberHealth().first { $0.subscriberID == "runtime.history" }
        #expect(health?.isHealthy == false)
        #expect(health?.droppedCount == 1)
        #expect(health?.deliveredCount == 0)
    }
}

private struct FailingRuntimeEventHistoryStore: RuntimeEventHistoryStoring {
    struct Failure: Error {}

    func append(_ event: WorkflowEventEnvelope) async throws { throw Failure() }
    func recentEvents(limit: Int) async -> [WorkflowEventEnvelope] { [] }
    func resetAll() async {}
}

private actor SuspendedRuntimeEventHistoryStore: RuntimeEventHistoryStoring {
    private var readContinuation: CheckedContinuation<Void, Never>?

    func append(_ event: WorkflowEventEnvelope) async throws { }

    func recentEvents(limit: Int) async -> [WorkflowEventEnvelope] {
        await withCheckedContinuation { continuation in
            readContinuation = continuation
        }
        return []
    }

    func resetAll() async { }

    func waitUntilReadIsSuspended() async {
        while readContinuation == nil {
            await Task.yield()
        }
    }

    func resumeRead() {
        readContinuation?.resume()
        readContinuation = nil
    }
}
