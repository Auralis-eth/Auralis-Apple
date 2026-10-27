import Foundation
import AuralisRuntime
@testable import RuntimeKit
import Testing

private actor SuspendedPerformanceEventSource {
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

@Suite("Runtime performance observer")
struct RuntimePerformanceObserverTests {
    /// Polls the store until the planner bucket has at least `count` runs, so the test doesn't race the
    /// observer's async consume task. Returns nil if it never reaches the count.
    private func waitForPlannerHealth(in store: PerformanceStore, count: Int) async -> PlaybookHealth? {
        for _ in 0..<200 {
            let health = await store.health(forPlaybook: RuntimePerformanceObserver.plannerPlaybookID)
            if health.totalRuns >= count { return health }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return nil
    }

    private func waitForRequests(_ count: Int, from source: SuspendedPerformanceEventSource) async {
        for _ in 0..<200 where await source.requests() < count {
            await Task.yield()
        }
    }

    @Test("concurrent starts share one performance subscription")
    func concurrentStartsShareOneSubscription() async {
        let source = SuspendedPerformanceEventSource()
        let observer = RuntimePerformanceObserver(events: { await source.stream() }, store: PerformanceStore())

        async let first: Void = observer.start()
        async let second: Void = observer.start()
        await waitForRequests(1, from: source)
        await source.releaseRegistrations()
        _ = await (first, second)

        #expect(await source.requests() == 1)
        await observer.stop()
        await source.finishStreams()
    }

    @Test("stop during performance startup cannot install an orphan consumer")
    func stopDuringStartupThenRestartUsesOnlyTheNewGeneration() async {
        let source = SuspendedPerformanceEventSource()
        let observer = RuntimePerformanceObserver(events: { await source.stream() }, store: PerformanceStore())

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

    /// A completed planner run is recorded as a success with the real end-to-end latency measured
    /// between `plannerStarted` and `plannerCompleted`.
    @Test
    func recordsPlannerSuccessWithMeasuredDuration() async {
        let (stream, continuation) = AsyncStream<WorkflowEventEnvelope>.makeStream()
        let store = PerformanceStore()
        let observer = RuntimePerformanceObserver(events: { stream }, store: store)
        await observer.start()

        let start = Date()
        continuation.yield(
            WorkflowEventEnvelope(event: .plannerStarted(goal: "tidy"), correlationID: "c1", timestamp: start)
        )
        continuation.yield(
            WorkflowEventEnvelope(
                event: .plannerCompleted(selectedCount: 2, rejectedCount: 1),
                correlationID: "c1",
                timestamp: start.addingTimeInterval(1.5)
            )
        )
        continuation.finish()

        let health = await waitForPlannerHealth(in: store, count: 1)
        #expect(health?.totalRuns == 1)
        #expect(health?.successRate == 1.0)
        #expect(health?.failureCount == 0)
        #expect(abs((health?.averageLatencySeconds ?? 0) - 1.5) < 0.001)
    }

    /// Holds across observer lifetimes because the *store* is idempotent by event ID — the observer
    /// reuses the runtime envelope's ID for exactly that reason (see `PerformanceRecording.record`).
    /// It used to hold because `start()` rebuilt this set by reading the store's entire planner
    /// history on the path `bootstrap()` awaits; the guarantee now comes from where it belongs and
    /// the observer's own cache only covers in-process replay.
    @Test("replayed planner terminal events are not recorded twice after restart")
    func replayedTerminalEventIsIdempotentAcrossObserverLifetimes() async {
        let store = PerformanceStore()
        let terminal = WorkflowEventEnvelope(
            event: .plannerCompleted(selectedCount: 1, rejectedCount: 0),
            correlationID: "replayed-run"
        )

        let (firstStream, firstContinuation) = AsyncStream<WorkflowEventEnvelope>.makeStream()
        let firstObserver = RuntimePerformanceObserver(events: { firstStream }, store: store)
        await firstObserver.start()
        firstContinuation.yield(terminal)
        firstContinuation.finish()
        _ = await waitForPlannerHealth(in: store, count: 1)
        await firstObserver.stop()

        let (replayStream, replayContinuation) = AsyncStream<WorkflowEventEnvelope>.makeStream()
        let restartedObserver = RuntimePerformanceObserver(events: { replayStream }, store: store)
        await restartedObserver.start()
        replayContinuation.yield(terminal)
        replayContinuation.finish()

        try? await Task.sleep(nanoseconds: 20_000_000)
        #expect(await store.health(forPlaybook: RuntimePerformanceObserver.plannerPlaybookID).totalRuns == 1)
        await restartedObserver.stop()
    }

    /// A failed planner run is recorded as a failure and its reason becomes a failure-pattern key.
    @Test
    func recordsPlannerFailureWithReason() async {
        let (stream, continuation) = AsyncStream<WorkflowEventEnvelope>.makeStream()
        let store = PerformanceStore()
        let observer = RuntimePerformanceObserver(events: { stream }, store: store)
        await observer.start()

        let start = Date()
        continuation.yield(
            WorkflowEventEnvelope(event: .plannerStarted(goal: "tidy"), correlationID: "c2", timestamp: start)
        )
        continuation.yield(
            WorkflowEventEnvelope(
                event: .plannerFailed(reason: "no candidate cleared"),
                correlationID: "c2",
                timestamp: start.addingTimeInterval(0.2)
            )
        )
        continuation.finish()

        let health = await waitForPlannerHealth(in: store, count: 1)
        #expect(health?.failureCount == 1)
        #expect(health?.successRate == 0.0)
        #expect(health?.failurePatterns.first?.key == "no candidate cleared")
    }

    /// Non-planner events are ignored — the observer must not pollute performance with, e.g., receipts.
    @Test
    func ignoresNonPlannerEvents() async {
        let (stream, continuation) = AsyncStream<WorkflowEventEnvelope>.makeStream()
        let store = PerformanceStore()
        let observer = RuntimePerformanceObserver(events: { stream }, store: store)
        await observer.start()

        continuation.yield(WorkflowEventEnvelope(event: .receiptCreated(id: UUID())))
        continuation.yield(WorkflowEventEnvelope(event: .workflowStarted))
        continuation.yield(
            WorkflowEventEnvelope(event: .plannerStarted(goal: "tidy"), correlationID: "c3")
        )
        continuation.yield(
            WorkflowEventEnvelope(
                event: .plannerCompleted(selectedCount: 1, rejectedCount: 0),
                correlationID: "c3"
            )
        )
        continuation.finish()

        // Exactly one planner run recorded; the receipt/workflow events produced no performance rows.
        let health = await waitForPlannerHealth(in: store, count: 1)
        #expect(health?.totalRuns == 1)
        let all = await store.allHealth()
        #expect(all.count == 1)
        #expect(all.first?.playbookID == RuntimePerformanceObserver.plannerPlaybookID)
    }
}
