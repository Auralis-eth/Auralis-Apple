import Foundation

/// Serializes governed work that shares one correlation ID, so only one run under a given ID is ever
/// in flight.
///
/// Four places used to document this as a guarantee the *callers* provided rather than one the
/// runtime enforced: ``RuntimeHost/noteRuntimeSession(correlationID:goal:actor:_:)``,
/// ``ReceiptStoreSink/noteSessionReceipt(_:correlationID:goal:actor:)``,
/// ``AutopilotStepExecutor/noteReceipt(_:actor:)``, and ``RuntimeHost/trace(ofRun:in:)``. Each reads
/// or writes state keyed only by correlation ID, and each said some version of "what rules this out
/// is the call graph, not this method".
///
/// The call graph stopped ruling it out. `MissionControlHomeModel.sharePlaybook(_:toSession:)` is a
/// plain `async` method with no in-flight guard, and every playbook shared into a session runs under
/// *that session's* correlation ID — so two taps in quick succession dispatch two concurrent
/// ``RuntimeHost/runRoutine(id:trigger:actor:correlationID:)`` calls under one ID. Two things break:
///
/// - The session evidence index is a read → mutate → upsert with no compare-and-set, so one run's
///   `receiptID` or telemetry is silently dropped from the session Mission Control reads. The
///   receipts themselves are durable, so the loss is to the index only — but the index is the
///   surface.
/// - ``RuntimeHost/trace(ofRun:in:)`` scopes a run's worklog entries by its own `startedAt ...
///   startedAt + durationSeconds` window. Overlapping runs have overlapping windows, so each run's
///   grade absorbs the other's entries: `completedWithin(seconds:)` measures across both, and the
///   existential criteria are satisfied by whichever run happened to meet them. That is exactly the
///   defect `trace(ofRun:in:)` was written to fix for the sequential case, reopened in the concurrent
///   one.
///
/// Serializing at the governed entry points is the narrow fix. The alternative — carrying a run ID on
/// every `WorkflowStepLog` and making the session upsert a store-side merge — reaches
/// `SchedulingCore`, `AgentSessionStoring`, and the durable row format, and is what the notes on those
/// methods describe as the prerequisite for running plan steps or routines *concurrently on purpose*.
/// This makes the documented invariant true today without buying that.
///
/// ## Why this is not a deadlock risk
///
/// Only the four top-level governed entry points acquire it, and nothing reachable from inside one
/// re-enters another under the same ID. `bootstrap()`, the scheduling engine, the governed pipeline,
/// and the session/receipt helpers all run *inside* the gate and never take it. The two collaborators
/// a composition root injects that could in principle call back — `policyActionExecutor` and
/// `routineOperators` — do not: the app supplies `WalletActionExecutor` and no routine operators at
/// all. A caller that passes no correlation ID gets a freshly minted one, which nothing else can
/// name, so it never contends.
///
/// ``RuntimeHost/runAutopilotGoal(_:surface:correlationID:)`` deliberately does **not** acquire it:
/// it dispatches cleared steps through ``RuntimeHost/runOperator(toolID:request:correlationID:)``
/// under the goal's own ID, so holding the gate across the plan would deadlock on its own first step.
/// It needs no protection — `SequentialPlanOrchestrator` clears one step at a time and halts at the
/// first that does not — and each step it dispatches is itself serialized here.
@MainActor
final class CorrelationGate {
    /// The tail of each correlation ID's wait chain: a task that finishes exactly when the work most
    /// recently enqueued under that ID finishes, tagged so its owner can recognise it later.
    ///
    /// The task is erased to `Task<Void, Never>` so one chain can carry bodies with different result
    /// types — a routine run returns an `ExecutionRecord`, a tool call a `ToolCallOutcome`. The tag is
    /// needed because `Task` is a struct: there is no identity to compare, so "am I still the tail?"
    /// has to be asked of a token rather than of the task itself.
    private struct Tail {
        let token: Int
        let task: Task<Void, Never>
    }

    private var tails: [String: Tail] = [:]
    private var nextToken = 0

    /// Runs `body` once every body already enqueued under `correlationID` has finished, in the order
    /// callers arrived.
    ///
    /// The ordering rests on this type being `@MainActor` and on the synchronous prefix below
    /// containing no suspension point: a second caller cannot begin until the first has installed its
    /// link, so the chain is FIFO rather than racy.
    ///
    /// Cancellation is *forwarded* into `body`, and that is load-bearing rather than tidiness. The
    /// body has to run in its own `Task` — the chain needs a handle to await, and the result type has
    /// to be erased for the tail — and a `Task` created here inherits priority and task-locals but
    /// **not** cancellation. So without the handler below, `Task.isCancelled` inside a gated body is
    /// permanently `false`: a background refresh whose task expires would keep running governed work,
    /// and any future cancellation check added to `SchedulingEngine` or `GovernedToolPipeline` would
    /// silently never fire. Nothing inside the gate reads it today, which is exactly why this is worth
    /// closing now — it would fail as a quiet no-op rather than as a visible bug.
    ///
    /// Cancelling only makes cancellation *visible*; it does not abandon the body. That is deliberate:
    /// a governed run must not be torn down between writing its effect and writing the receipt for it,
    /// so a body that wants to stop early has to check and unwind on its own. The gate is released
    /// when the body returns either way.
    func withLock<T: Sendable>(
        _ correlationID: String,
        _ body: @escaping @MainActor () async -> T
    ) async -> T {
        let predecessor = tails[correlationID]?.task
        let work = Task { @MainActor () -> T in
            await predecessor?.value
            return await body()
        }
        nextToken += 1
        let token = nextToken
        tails[correlationID] = Tail(
            token: token,
            // `_ = await work.value` is a statement rather than a trailing expression, so this infers
            // `Task<Void, Never>` without the explicit annotation `RuntimeHost.bootstrap()` needs.
            task: Task { @MainActor in
                _ = await work.value
            }
        )
        let result = await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
        // Dropped only while still the tail, which is what keeps the map bounded without stranding a
        // waiter: a caller that arrived after this one has already replaced the entry with its own
        // link, and that link is what the *next* arrival has to wait behind.
        if tails[correlationID]?.token == token {
            tails.removeValue(forKey: correlationID)
        }
        return result
    }

    /// How many correlation IDs currently have work in flight or queued. Test-only: the map emptying
    /// out is the observable form of "the gate leaks nothing".
    var inFlightCount: Int { tails.count }
}
