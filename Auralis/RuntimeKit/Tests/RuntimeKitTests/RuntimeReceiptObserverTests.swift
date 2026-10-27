import AuralisPrimaryModels
import AuralisFoundation
import Foundation
import ReceiptsCore
import AuralisRuntime
@testable import RuntimeKit
import Testing

private actor EventReceiptStore: ReceiptStore {
    private var drafts: [ReceiptDraft] = []

    func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord {
        drafts.append(receipt)
        return ReceiptRecord(
            id: UUID(),
            sequenceID: drafts.count,
            createdAt: receipt.createdAt,
            actor: receipt.actor,
            actorDetail: receipt.actorDetail,
            authorityDetail: receipt.authorityDetail,
            mode: receipt.mode,
            trigger: receipt.trigger,
            scope: receipt.scope,
            summary: receipt.summary,
            provenance: receipt.provenance,
            isSuccess: receipt.isSuccess,
            correlationID: receipt.correlationID,
            details: receipt.details
        )
    }

    func latest(limit: Int) async throws -> [ReceiptRecord] { [] }
    func receipts(forCorrelationID correlationID: String, limit: Int) async throws -> [ReceiptRecord] { [] }
    func exportAll() async throws -> Data { Data() }
    func resetAll() async throws { drafts.removeAll() }
    func appendedDrafts() -> [ReceiptDraft] { drafts }
}

private struct FailingEventReceiptStore: ReceiptStore {
    struct PersistenceFailure: Error { }

    func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord { throw PersistenceFailure() }
    func latest(limit: Int) async throws -> [ReceiptRecord] { [] }
    func receipts(forCorrelationID correlationID: String, limit: Int) async throws -> [ReceiptRecord] { [] }
    func exportAll() async throws -> Data { Data() }
    func resetAll() async throws { }
}

/// Records what the observer reported to its failure reporter, so a test can assert on the count as
/// well as the payload.
private actor ReportRecorder {
    private(set) var correlationIDs: [String?] = []
    var count: Int { correlationIDs.count }
    var isEmpty: Bool { correlationIDs.isEmpty }

    func record(_ correlationID: String?) {
        correlationIDs.append(correlationID)
    }
}

private actor SuspendedReceiptEventSource {
    private var requestCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var continuations: [AsyncStream<WorkflowEventEnvelope>.Continuation] = []

    func stream() async -> AsyncStream<WorkflowEventEnvelope> {
        requestCount += 1
        await withCheckedContinuation { waiters.append($0) }
        let (stream, continuation) = AsyncStream<WorkflowEventEnvelope>.makeStream()
        continuations.append(continuation)
        return stream
    }

    func requests() -> Int { requestCount }

    func releaseRegistrations() {
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }

    func finishStreams() {
        continuations.forEach { $0.finish() }
        continuations.removeAll()
    }
}

@Suite("Runtime receipt event observer")
struct RuntimeReceiptObserverTests {
    private func waitForRequests(_ count: Int, from source: SuspendedReceiptEventSource) async {
        for _ in 0..<200 where await source.requests() < count {
            await Task.yield()
        }
    }

    @Test("concurrent starts share one receipt subscription")
    func concurrentStartsShareOneSubscription() async {
        let source = SuspendedReceiptEventSource()
        let observer = RuntimeReceiptObserver(
            events: { await source.stream() },
            store: EventReceiptStore(),
            publisher: RuntimeEventBus()
        )

        async let first: Void = observer.start()
        async let second: Void = observer.start()
        await waitForRequests(1, from: source)
        await source.releaseRegistrations()
        _ = await (first, second)

        #expect(await source.requests() == 1)
        await observer.stop()
        await source.finishStreams()
    }

    @Test("stop during receipt startup cannot install an orphan consumer")
    func stopDuringStartupThenRestartUsesOnlyTheNewGeneration() async {
        let source = SuspendedReceiptEventSource()
        let observer = RuntimeReceiptObserver(
            events: { await source.stream() },
            store: EventReceiptStore(),
            publisher: RuntimeEventBus()
        )

        let stoppedStart = Task { await observer.start() }
        await waitForRequests(1, from: source)
        await observer.stop()
        let restarted = Task { await observer.start() }
        await waitForRequests(2, from: source)
        await source.releaseRegistrations()
        await stoppedStart.value
        await restarted.value

        #expect(await source.requests() == 2)
        await observer.stop()
        await source.finishStreams()
    }

    @Test
    func governanceEventCreatesOneCorrelatedReceiptAndPublishesItsID() async throws {
        let bus = RuntimeEventBus()
        let store = EventReceiptStore()
        let observer = RuntimeReceiptObserver(
            events: { await bus.events() },
            store: store,
            publisher: bus
        )
        await observer.start()
        let confirmationStream = await bus.events()
        let timestamp = Date(timeIntervalSince1970: 100)
        let envelope = WorkflowEventEnvelope(
            event: .capabilityRevoked(.runPlugin),
            correlationID: "correlation-1",
            timestamp: timestamp
        )

        await bus.publish(envelope)
        let confirmation = try await nextReceiptCreated(from: confirmationStream)
        let draft = try #require(await store.appendedDrafts().first)

        #expect(confirmation.correlationID == "correlation-1")
        #expect(draft.createdAt == timestamp)
        #expect(draft.correlationID == "correlation-1")
        #expect(draft.trigger == "runtime.capability.revoked")
        #expect(draft.details.values["runtimeEventID"] == .string(envelope.id.uuidString))
        await observer.stop()
    }

    @Test
    func duplicateEnvelopeAndReceiptCreatedDoNotCreateRecursiveReceipts() async throws {
        let bus = RuntimeEventBus()
        let store = EventReceiptStore()
        let observer = RuntimeReceiptObserver(
            events: { await bus.events() },
            store: store,
            publisher: bus
        )
        await observer.start()
        let confirmationStream = await bus.events()
        let duplicated = WorkflowEventEnvelope(event: .capabilityRevoked(.runPlugin))
        let unique = WorkflowEventEnvelope(event: .capabilityLeaseExpired(.runPlugin))

        await bus.publish(duplicated)
        _ = try await nextReceiptCreated(from: confirmationStream)
        await bus.publish(duplicated)
        let syntheticReceiptCreated = WorkflowEventEnvelope(event: .receiptCreated(id: UUID()))
        await bus.publish(syntheticReceiptCreated)
        await bus.publish(unique)
        // Skip the synthetic envelope: it is a `receiptCreated` too, so waiting for "the next
        // receiptCreated" would return *it* rather than the observer's confirmation for `unique`,
        // and the count below would race the observer instead of observing settled state.
        _ = try await nextReceiptCreated(from: confirmationStream, ignoring: syntheticReceiptCreated.id)

        #expect(await store.appendedDrafts().count == 2)
        await observer.stop()
    }

    /// The de-duplication window has to stay dedicated to the events it actually receipts.
    ///
    /// `handle` used to remember *every* event it saw, including the overwhelming majority it does not
    /// receipt — tool calls, checks, artifacts, workflow blocks. The window holds 1,024 IDs, so
    /// ordinary traffic evicted the capability grant/revoke/expiry IDs the cache exists to protect:
    /// the protection was present in structure and absent in effect, and a replayed governance event
    /// would be receipted a second time, duplicating a record in a ledger whose worth is that it says
    /// what happened once.
    ///
    /// Asserted on the window directly rather than by publishing a window's worth of traffic and
    /// watching for a duplicate: ``RuntimeEventBus/events()`` buffers newest-first and drops under
    /// load, so a test cannot guarantee the observer ever saw the events it published — which would
    /// make the eviction, and therefore the assertion, non-deterministic.
    @Test("only the events it receipts enter the dedupe window")
    func onlyReceiptedEventsEnterTheDedupeWindow() async throws {
        let bus = RuntimeEventBus()
        let store = EventReceiptStore()
        let observer = RuntimeReceiptObserver(
            events: { await bus.events() },
            store: store,
            publisher: bus
        )
        await observer.start()
        let confirmationStream = await bus.events()

        // One governance event, which is receipted and therefore remembered.
        await bus.publish(WorkflowEventEnvelope(event: .capabilityRevoked(.runPlugin)))
        _ = try await nextReceiptCreated(from: confirmationStream)
        #expect(await observer.retainedEventIDCount == 1)

        // Ordinary traffic, none of it receipted. A second governance event afterwards gives the test
        // settled state to wait on without depending on how much of the traffic was delivered.
        for index in 0..<50 {
            await bus.publish(WorkflowEventEnvelope(event: .executionUpdate("ordinary traffic \(index)")))
        }
        await bus.publish(WorkflowEventEnvelope(event: .capabilityLeaseExpired(.runPlugin)))
        _ = try await nextReceiptCreated(from: confirmationStream)

        // Exactly the two receipted events. Anything more means non-governance traffic is consuming
        // the window, which is what lets a replay slip past it.
        #expect(await observer.retainedEventIDCount == 2)
        #expect(await store.appendedDrafts().count == 2)
        await observer.stop()
    }

    /// The window's actual job, end to end: a replayed governance event is not receipted twice.
    @Test("a replayed governance event is recognised rather than receipted again")
    func replayedGovernanceEventIsNotReceiptedTwice() async throws {
        let bus = RuntimeEventBus()
        let store = EventReceiptStore()
        let observer = RuntimeReceiptObserver(
            events: { await bus.events() },
            store: store,
            publisher: bus
        )
        await observer.start()
        let confirmationStream = await bus.events()
        let governance = WorkflowEventEnvelope(event: .capabilityRevoked(.runPlugin))

        await bus.publish(governance)
        _ = try await nextReceiptCreated(from: confirmationStream)

        // The same envelope again, which is what a reconnect from the last checkpoint produces.
        await bus.publish(governance)
        let marker = WorkflowEventEnvelope(event: .capabilityLeaseExpired(.draftTransaction))
        await bus.publish(marker)
        _ = try await nextReceiptCreated(from: confirmationStream)

        #expect(await store.appendedDrafts().count == 2)
        await observer.stop()
    }

    @Test
    func startingTwiceKeepsOneReceiptSubscription() async throws {
        let bus = RuntimeEventBus()
        let store = EventReceiptStore()
        let observer = RuntimeReceiptObserver(
            events: { await bus.events() },
            store: store,
            publisher: bus
        )

        await observer.start()
        await observer.start()
        #expect(await bus.subscriberCount == 1)

        let confirmationStream = await bus.events()
        await bus.publish(WorkflowEventEnvelope(event: .capabilityRevoked(.runPlugin)))
        _ = try await nextReceiptCreated(from: confirmationStream)
        #expect(await store.appendedDrafts().count == 1)
        await observer.stop()
    }

    @Test
    func persistenceFailureIsExposedThroughObserverDiagnostics() async {
        let bus = RuntimeEventBus()
        let observer = RuntimeReceiptObserver(
            events: { await bus.events() },
            store: FailingEventReceiptStore(),
            publisher: bus
        )
        await observer.start()
        let envelope = WorkflowEventEnvelope(event: .capabilityRevoked(.runPlugin))

        await bus.publish(envelope)
        // Polled with a real sleep rather than `Task.yield()`: handling an event now hops to the
        // MainActor to read the crypto mode it stamps, and yielding only reschedules this task on
        // the cooperative pool — it does not give another executor a turn, so a yield-only spin can
        // exhaust its iterations before the hop is ever serviced.
        for _ in 0..<200 where await observer.persistenceFailureCount == 0 {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(await observer.persistenceFailureCount == 1)
        #expect(await observer.lastFailedEventID == envelope.id)
        await observer.stop()
    }

    /// A failed governance receipt must reach the host's degraded-evidence banner, and must do so
    /// *once* — the reconnect replays the same unwritable event from the checkpoint, so reporting
    /// per attempt would inflate one lost receipt into thousands at one per second.
    @Test("a failed audit receipt is reported once per event, not once per retry")
    func persistenceFailureIsReportedOncePerEvent() async {
        let bus = RuntimeEventBus()
        let reports = ReportRecorder()
        let observer = RuntimeReceiptObserver(
            events: { await bus.events() },
            store: FailingEventReceiptStore(),
            publisher: bus,
            failureReporter: { correlationID in await reports.record(correlationID) }
        )
        await observer.start()
        let envelope = WorkflowEventEnvelope(
            event: .capabilityRevoked(.runPlugin),
            correlationID: "corr-audit"
        )

        await bus.publish(envelope)
        for _ in 0..<200 where await reports.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
        // Past the observer's first retry delay, so any per-attempt reporting would show up here.
        try? await Task.sleep(for: .milliseconds(1_200))

        #expect(await reports.count == 1)
        #expect(await reports.correlationIDs == ["corr-audit"])
        #expect(await observer.persistenceFailureCount == 1)
        await observer.stop()
    }

    private func nextReceiptCreated(
        from stream: AsyncStream<WorkflowEventEnvelope>,
        ignoring ignoredEnvelopeID: UUID? = nil
    ) async throws -> WorkflowEventEnvelope {
        for await envelope in stream {
            if case .receiptCreated = envelope.event, envelope.id != ignoredEnvelopeID {
                return envelope
            }
        }
        Issue.record("Runtime event stream ended before receiptCreated")
        throw CancellationError()
    }
}
