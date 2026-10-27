import Foundation
import AuralisRuntime

/// Subscribes to the runtime event bus and derives *planner-level* performance from workflow
/// lifecycle events (P0.5-302: the bus is "observable by eval/performance").
///
/// This is the eval/performance observer of the event bus, and it complements — rather than
/// duplicates — the tool-call granularity recorded by ``PerformancePipelineSink``. That sink records
/// one `PerformanceEvent` per governed *tool call*; this observer records one per end-to-end *planner
/// run* (`plannerStarted` → `plannerCompleted`/`plannerFailed`), keyed by ``plannerPlaybookID`` so
/// goal-planning health surfaces in Mission Control alongside tool and operator health. The two grains
/// never overlap, so there is no double counting.
public actor RuntimePerformanceObserver {
    public static let subscriberID = "runtime.performance"
    /// The playbook bucket planner runs are grouped under in ``PerformanceStoring``.
    public static let plannerPlaybookID = "planner"

    private let events: @Sendable () async -> AsyncStream<WorkflowEventEnvelope>
    /// Write-only, and deliberately the *narrow* protocol. This was widened to ``PerformanceStoring``
    /// while the observer still seeded its de-duplication set from the run history; that seeding is
    /// gone (see ``recordedTerminalEventIDs``), so the read half of the wider protocol is unused and
    /// asking for it would only shrink what a composition root may inject. ``PerformancePipelineSink``
    /// takes the same narrow type for the same reason.
    private let store: any PerformanceRecording
    private let checkpointStore: any RuntimeEventCheckpointStoring
    private var registrationTask: Task<AsyncStream<WorkflowEventEnvelope>, Never>?
    private var task: Task<Void, Never>?
    private var lifecycleGeneration = 0
    /// Terminal runtime event IDs already recorded *by this observer instance*, so a replay within
    /// one process cannot double-count a run.
    ///
    /// Bounded, for the same reason ``RuntimeReceiptObserver`` bounds its equivalent: the only events
    /// that can be replayed are the ones after the last durable checkpoint, so the window that
    /// matters is the recent tail and an unbounded set would accumulate one UUID per planner run for
    /// the life of the process. ``recordedTerminalEventIDOrder`` carries the insertion order the set
    /// itself does not have, so eviction drops the oldest rather than an arbitrary member.
    ///
    /// Cross-*process* de-duplication is deliberately not this set's job. It was previously seeded
    /// from the performance store, which meant reading and JSON-decoding the entire planner run
    /// history on the path ``RuntimeHost/bootstrap()`` awaits — the same cost
    /// ``RuntimeReceiptObserver/seedScanLimit`` was cut from 10,000 to 512 to avoid, except unbounded,
    /// because `PerformanceStoring.events(forPlaybook:)` takes no limit. It also bought nothing: the
    /// in-memory store does not outlive the process, and the persistent one keys rows by this same
    /// event ID under a unique attribute, so a replayed event overwrites its own row instead of
    /// double-counting (see ``SwiftDataPerformanceStore/record(_:)``). The store provides that
    /// guarantee; this set only covers the in-process case.
    private var recordedTerminalEventIDs: Set<UUID> = []
    private var recordedTerminalEventIDOrder: [UUID] = []
    /// Matches ``RuntimeReceiptObserver``'s retained-ID ceiling, and for the same reason: it only has
    /// to cover the replay window, which the checkpoint store keeps within 32 saves or 5 seconds.
    private static let maxRecordedTerminalEventIDs = 1_024
    /// `plannerStarted` timestamps keyed by correlation ID, so the matching completion/failure can
    /// compute a real end-to-end duration. Kept only until the run terminates.
    private var startedAt: [String: Date] = [:]
    /// Insertion order for ``startedAt``, so the oldest pending run can be dropped once the map is
    /// full. A planner run cancelled before it published `plannerCompleted`/`plannerFailed` leaves
    /// its entry behind — unbounded, that leaked for the lifetime of the process.
    private var startedOrder: [String] = []
    private static let maxPendingRuns = 256

    public init(
        events: @escaping @Sendable () async -> AsyncStream<WorkflowEventEnvelope>,
        store: any PerformanceRecording,
        checkpointStore: any RuntimeEventCheckpointStoring = InMemoryRuntimeEventCheckpointStore()
    ) {
        self.events = events
        self.store = store
        self.checkpointStore = checkpointStore
    }

    /// Begins consuming the event stream. Idempotent — a second call while a stream is live is a no-op.
    ///
    /// Awaits the subscription's creation *before* spawning the consume task, so once `start()` returns
    /// the observer is guaranteed registered on the bus and cannot miss an event published immediately
    /// afterwards (the bus only delivers to subscriptions that exist at publish time).
    public func start() async {
        guard task == nil else { return }
        let generation = lifecycleGeneration
        let registration: Task<AsyncStream<WorkflowEventEnvelope>, Never>
        if let registrationTask {
            registration = registrationTask
        } else {
            registration = Task { [weak self] in
                guard let self else {
                    return AsyncStream { $0.finish() }
                }
                return await self.events()
            }
            registrationTask = registration
        }
        let stream = await registration.value
        guard generation == lifecycleGeneration else { return }
        registrationTask = nil
        guard task == nil else { return }
        task = Task { [weak self] in
            var activeStream = stream
            while Task.isCancelled == false {
                for await envelope in activeStream {
                    guard Task.isCancelled == false else { return }
                    await self?.handle(envelope)
                    guard Task.isCancelled == false else { return }
                    await self?.checkpointStore.saveCheckpoint(envelope.id, for: Self.subscriberID)
                }
                // See RuntimeReceiptObserver: overflow closes the bounded live stream and this
                // reconnect replays from the last successfully processed durable checkpoint.
                guard Task.isCancelled == false else { return }
                try? await Task.sleep(for: .seconds(1))
                guard Task.isCancelled == false else { return }
                guard let nextStream = await self?.events() else { return }
                activeStream = nextStream
            }
        }
    }

    /// Cancels the consume task and clears any in-flight run timings.
    public func stop() {
        lifecycleGeneration += 1
        registrationTask?.cancel()
        registrationTask = nil
        task?.cancel()
        task = nil
        startedAt.removeAll()
        startedOrder.removeAll()
    }

    private func handle(_ envelope: WorkflowEventEnvelope) async {
        switch envelope.event {
        case .plannerStarted:
            guard let correlationID = envelope.correlationID else { return }
            noteStart(correlationID, at: envelope.timestamp)
        case .plannerCompleted:
            await recordPlanner(for: envelope, outcome: .success, failureReason: nil)
        case .plannerFailed(let reason):
            await recordPlanner(for: envelope, outcome: .failed, failureReason: reason)
        default:
            break
        }
    }

    /// Records a run's start, evicting the oldest pending run when the map is full. A run whose
    /// terminal event never arrives (a cancelled task, a process torn down mid-plan) would otherwise
    /// hold its entry forever; the eviction only costs that run its measured latency, and
    /// ``recordPlanner(for:outcome:failureReason:)`` already handles a missing start honestly.
    private func noteStart(_ correlationID: String, at timestamp: Date) {
        if startedAt.updateValue(timestamp, forKey: correlationID) == nil {
            startedOrder.append(correlationID)
        }
        while startedOrder.count > Self.maxPendingRuns {
            startedAt.removeValue(forKey: startedOrder.removeFirst())
        }
    }

    private func forgetStart(_ correlationID: String) -> Date? {
        guard let started = startedAt.removeValue(forKey: correlationID) else { return nil }
        startedOrder.removeAll { $0 == correlationID }
        return started
    }

    private func recordPlanner(
        for envelope: WorkflowEventEnvelope,
        outcome: PlaybookRunOutcome,
        failureReason: String?
    ) async {
        guard remember(envelope.id) else { return }
        let duration: Double
        if let correlationID = envelope.correlationID,
           let started = forgetStart(correlationID) {
            duration = max(0, envelope.timestamp.timeIntervalSince(started))
        } else {
            // No matching start (e.g. the observer subscribed mid-run); record the run without a
            // fabricated latency rather than dropping it.
            duration = 0
        }
        await store.record(
            PerformanceEvent(
                id: envelope.id,
                playbookID: Self.plannerPlaybookID,
                outcome: outcome,
                durationSeconds: duration,
                triggerSource: "planner",
                failureReason: failureReason
            )
        )
    }

    /// Marks `id` as recorded, evicting the oldest once the window is full.
    /// - Returns: `false` when this observer has already recorded `id`.
    private func remember(_ id: UUID) -> Bool {
        guard recordedTerminalEventIDs.insert(id).inserted else { return false }
        recordedTerminalEventIDOrder.append(id)
        if recordedTerminalEventIDOrder.count > Self.maxRecordedTerminalEventIDs {
            recordedTerminalEventIDs.remove(recordedTerminalEventIDOrder.removeFirst())
        }
        return true
    }
}
