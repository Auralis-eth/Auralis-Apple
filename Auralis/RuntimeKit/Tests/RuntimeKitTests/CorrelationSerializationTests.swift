import AuralisReceipts
import AuralisRuntime
import Foundation
import SocialCore
import Testing

@testable import RuntimeKit

/// One run at a time per correlation ID, enforced by the runtime rather than promised by its callers.
///
/// Four methods documented "sequential per correlation id" as a property of the call graph. It stopped
/// being one: `MissionControlHomeModel.sharePlaybook(_:toSession:)` has no in-flight guard and every
/// shared playbook runs under its session's correlation ID, so two taps dispatched two concurrent
/// `runRoutine` calls under one ID — racing the session evidence index and overlapping the eval trace
/// windows that ``RuntimeHost/trace(ofRun:in:)`` scopes grades by. See ``CorrelationGate``.
@Suite("Correlation serialization")
@MainActor
struct CorrelationSerializationTests {

    // MARK: - The gate itself

    @Test("bodies under one id never overlap")
    func bodiesUnderOneIDNeverOverlap() async {
        let gate = CorrelationGate()
        let tracker = OverlapTracker()

        // `Task {}` from a `@MainActor` test inherits that isolation, which is what the gate requires.
        // A task *group* cannot express it — `addTask` with an explicit `@MainActor` closure defeats
        // the region-based isolation checker — so the concurrency here is a plain array of tasks.
        var tasks: [Task<Void, Never>] = []
        for _ in 0..<8 {
            tasks.append(Task {
                await gate.withLock("shared") {
                    await tracker.enter()
                    // A real suspension inside the critical section: without the gate this is where
                    // a second body would interleave.
                    await Task.yield()
                    try? await Task.sleep(for: .milliseconds(1))
                    await tracker.exit()
                }
            })
        }
        for task in tasks { await task.value }

        #expect(await tracker.maximumConcurrent == 1)
        #expect(await tracker.completed == 8)
    }

    /// The gate is per ID, not global — serializing unrelated work would make it a throughput bug.
    @Test("bodies under different ids still overlap")
    func bodiesUnderDifferentIDsStillOverlap() async {
        let gate = CorrelationGate()
        let tracker = OverlapTracker()

        var tasks: [Task<Void, Never>] = []
        for index in 0..<6 {
            tasks.append(Task {
                await gate.withLock("id-\(index)") {
                    await tracker.enter()
                    try? await Task.sleep(for: .milliseconds(20))
                    await tracker.exit()
                }
            })
        }
        for task in tasks { await task.value }

        #expect(await tracker.maximumConcurrent > 1)
    }

    @Test("callers are served in the order they arrived")
    func callersAreServedInArrivalOrder() async {
        let gate = CorrelationGate()
        let order = OrderRecorder()

        // Hold the gate, then queue three behind it while it is held, so arrival order is determined.
        let blocker = Task { @MainActor in
            await gate.withLock("shared") {
                try? await Task.sleep(for: .milliseconds(50))
                await order.record(0)
            }
        }
        try? await Task.sleep(for: .milliseconds(10))
        var queued: [Task<Void, Never>] = []
        for index in 1...3 {
            queued.append(Task { @MainActor in
                await gate.withLock("shared") { await order.record(index) }
            })
            // Each `withLock` installs its link synchronously before suspending, so a yield between
            // spawns is enough to fix the arrival order deterministically.
            await Task.yield()
        }
        await blocker.value
        for task in queued { await task.value }

        #expect(await order.recorded == [0, 1, 2, 3])
    }

    /// The map has to empty out, or the host accumulates one entry per correlation ID for its life.
    @Test("the gate retains nothing once its work drains")
    func theGateRetainsNothingOnceDrained() async {
        let gate = CorrelationGate()

        var tasks: [Task<Void, Never>] = []
        for index in 0..<20 {
            tasks.append(Task {
                await gate.withLock("id-\(index % 4)") { await Task.yield() }
            })
        }
        for task in tasks { await task.value }

        #expect(gate.inFlightCount == 0)
    }

    /// Nested acquisition of a *different* id is safe, which is what the governed entry points do when
    /// one gated call is reached from inside another under a fresh id.
    @Test("nesting a different id does not deadlock")
    func nestingADifferentIDDoesNotDeadlock() async {
        let gate = CorrelationGate()
        let result = await gate.withLock("outer") {
            await gate.withLock("inner") { 42 }
        }
        #expect(result == 42)
    }

    /// The body has to *see* its caller's cancellation.
    ///
    /// It runs in a `Task` the gate creates, and such a task inherits priority and task-locals but not
    /// cancellation — so without the forwarding handler in ``CorrelationGate/withLock(_:_:)``,
    /// `Task.isCancelled` inside any gated body would be permanently `false`. That fails as a silent
    /// no-op: a background refresh whose task expires keeps doing governed work, and a cancellation
    /// check added later to `SchedulingEngine` never fires.
    @Test("a cancelled caller's cancellation reaches the body")
    func cancellationReachesTheBody() async {
        let gate = CorrelationGate()
        let observed = CancellationProbe()

        let task = Task { @MainActor in
            await gate.withLock("shared") {
                // Give the cancellation somewhere to land, then report what the body actually saw.
                try? await Task.sleep(for: .milliseconds(200))
                await observed.record(Task.isCancelled)
            }
        }
        // Let the body reach its sleep before cancelling, so this tests forwarding rather than the
        // already-cancelled-at-entry case.
        try? await Task.sleep(for: .milliseconds(30))
        task.cancel()
        await task.value

        #expect(await observed.sawCancellation == true)
    }

    /// Cancellation makes itself *visible* without abandoning the body, and the gate still releases.
    ///
    /// A governed run must not be torn down between writing its effect and writing the receipt for it,
    /// so the body runs to completion and a waiter behind it is not stranded.
    @Test("a cancelled body still completes and still releases the gate")
    func aCancelledBodyStillCompletesAndReleases() async {
        let gate = CorrelationGate()
        let observed = CancellationProbe()

        let first = Task { @MainActor in
            await gate.withLock("shared") {
                try? await Task.sleep(for: .milliseconds(100))
                await observed.markFinished()
            }
        }
        try? await Task.sleep(for: .milliseconds(20))
        first.cancel()
        await first.value

        #expect(await observed.didFinish, "The body must run to completion rather than be abandoned.")

        // A later caller under the same id still gets through, so the cancelled run released its slot.
        let second = await gate.withLock("shared") { "ran" }
        #expect(second == "ran")
        #expect(gate.inFlightCount == 0)
    }

    // MARK: - The host paths that needed it

    /// The regression this exists for: two shares into one session, concurrently.
    ///
    /// Both runs must appear in the session's receipt index. Before the gate, the two read → mutate →
    /// upsert cycles interleaved and one run's `receiptID` was dropped — durable in the ledger, absent
    /// from the surface Mission Control reads.
    @Test("concurrent shared workflows under one session keep both runs' evidence")
    func concurrentSharedWorkflowsKeepBothRunsEvidence() async throws {
        let sessionStore = InMemoryAgentSessionStore()
        let host = Self.host(sessionStore: sessionStore)
        await host.bootstrap()
        let shared = await host.sharedSessionStore.create(
            SharedSession(correlationID: "shared-session", title: "Weekly review", createdBy: .human)
        )

        var tasks: [Task<Void, Never>] = []
        for playbookID in ["alpha", "beta"] {
            tasks.append(Task {
                await host.runSharedWorkflow(sessionID: shared.id, playbookID: playbookID)
            })
        }
        for task in tasks { await task.value }

        let session = try #require(await sessionStore.session(correlationID: "shared-session"))
        // One routine receipt per run, both filed. The count is the assertion: a lost interleaved
        // upsert shows up here as 1.
        #expect(session.receiptIDs.count == 2)
    }

    /// The other half: overlapping trace windows made each run's grade a function of the other's
    /// entries, and in the direction that *masks* failure.
    ///
    /// Constructed so the leak would be visible. `slowFailing` sleeps and then fails, producing no
    /// artifact and never reaching `.completed`; `quickSuccess` finishes inside that sleep, producing
    /// both. The criteria are the two existential ones — ``SuccessCriterion/producedArtifact`` and
    /// ``SuccessCriterion/reachedRoutinePhase(_:)`` — which are satisfied by *any* matching entry in
    /// the trace they are handed. Unserialized, `slowFailing`'s window contains `quickSuccess`'s
    /// artifact and completion entries, so a run that produced nothing and failed grades as passed on
    /// another run's evidence. That is the masking case ``RuntimeHost/trace(ofRun:in:)`` exists to
    /// prevent, and the one the sequential-callers assumption left open.
    @Test("a failing run cannot inherit a concurrent run's success")
    func aFailingRunCannotInheritAConcurrentRunsSuccess() async throws {
        let evalStore = InMemoryEvalResultStore()
        let host = Self.host(
            sessionStore: InMemoryAgentSessionStore(),
            evalStore: evalStore,
            playbooks: [
                Self.playbook("slowFailing", criteria: [.producedArtifact, .reachedRoutinePhase(.completed)]),
                Self.playbook("quickSuccess", criteria: [.producedArtifact, .reachedRoutinePhase(.completed)])
            ],
            routineOperators: [
                "slowFailing": SlowFailingRoutineOperator(),
                "quickSuccess": QuickSuccessRoutineOperator()
            ]
        )
        await host.bootstrap()

        var tasks: [Task<Void, Never>] = []
        for playbookID in ["slowFailing", "quickSuccess"] {
            tasks.append(Task {
                await host.runRoutine(id: playbookID, correlationID: "shared-session")
            })
            // Ensures the two are genuinely in flight together rather than accidentally sequential.
            await Task.yield()
        }
        for task in tasks { await task.value }

        let results = await evalStore.allResults()
        #expect(results.count == 2)
        let failing = try #require(results.first { $0.playbookID == "slowFailing" })
        let succeeding = try #require(results.first { $0.playbookID == "quickSuccess" })
        #expect(
            failing.grade != .passed,
            "The failing run produced no artifact and never completed, so it must not grade as passed."
        )
        #expect(succeeding.grade == .passed)
    }

    /// A run with no caller-supplied id must not contend with anything, or the background scan would
    /// serialize every due routine behind one another.
    @Test("runs without a correlation id do not contend")
    func runsWithoutACorrelationIDDoNotContend() async {
        let host = Self.host(sessionStore: InMemoryAgentSessionStore())
        await host.bootstrap()

        var tasks: [Task<ExecutionRecord, Never>] = []
        for playbookID in ["alpha", "beta"] {
            tasks.append(Task { await host.runRoutine(id: playbookID) })
        }
        var records: [ExecutionRecord] = []
        for task in tasks { records.append(await task.value) }

        #expect(records.count == 2)
        // Distinct minted ids, so nothing shared a gate slot.
        #expect(Set(records.map(\.correlationID)).count == 2)
    }

    // MARK: - Fixtures

    private static func host(
        sessionStore: any AgentSessionStoring,
        evalStore: any EvalResultStoring = InMemoryEvalResultStore(),
        playbooks: [Playbook] = [playbook("alpha"), playbook("beta")],
        routineOperators: [String: any RoutineOperator] = [:]
    ) -> RuntimeHost {
        RuntimeHost(
            receiptStore: SerializationLedger(),
            stores: RuntimeHostStores(
                playbookStore: InMemoryPlaybookStore(seed: playbooks),
                evalResultStore: evalStore,
                sessionStore: sessionStore
            ),
            operators: RuntimeOperatorStack(routineOperators: routineOperators)
        )
    }

    private static func playbook(
        _ id: String,
        criteria: [SuccessCriterion] = [.producedArtifact, .noFailedSteps]
    ) -> Playbook {
        Playbook(
            id: id,
            name: id,
            summary: "s",
            trigger: .manual,
            authority: PlaybookAuthority(capabilities: [.runPlugin], allowedOutputs: [.brief]),
            completionCondition: "done",
            contextContract: SystemPlaybookContracts.contract(for: id, identifier: "test.\(id)"),
            outcome: OutcomeSpec(summary: "An artifact exists.", criteria: criteria),
            installState: .installed
        )
    }
}

/// Fails, and slowly — long enough that a concurrent run under the same correlation id finishes
/// entirely inside this run's trace window. Produces no artifact and never reaches `.completed`, so
/// anything it appears to have achieved came from somewhere else.
private struct SlowFailingRoutineOperator: RoutineOperator {
    func run(playbook: Playbook, context: GovernedContext) async -> RoutineRunResult {
        try? await Task.sleep(for: .milliseconds(150))
        return RoutineRunResult(outcome: .failed, failureReason: "operator fault")
    }
}

/// Succeeds immediately with an artifact, so its evidence lands in the middle of the slow run's
/// window and is available to be wrongly inherited.
private struct QuickSuccessRoutineOperator: RoutineOperator {
    func run(playbook: Playbook, context: GovernedContext) async -> RoutineRunResult {
        RoutineRunResult(
            outcome: .success,
            artifact: RoutineArtifactDraft(
                type: .brief,
                title: "\(playbook.name) brief",
                creatorPlaybookID: playbook.id,
                actor: ActorRef(kind: .scheduledRoutine, identifier: playbook.id),
                content: "produced promptly"
            )
        )
    }
}

/// Counts how many bodies are inside a critical section at once.
private actor OverlapTracker {
    private var current = 0
    private(set) var maximumConcurrent = 0
    private(set) var completed = 0

    func enter() {
        current += 1
        maximumConcurrent = max(maximumConcurrent, current)
    }

    func exit() {
        current -= 1
        completed += 1
    }
}

private actor CancellationProbe {
    private(set) var sawCancellation: Bool?
    private(set) var didFinish = false

    func record(_ isCancelled: Bool) {
        sawCancellation = isCancelled
        didFinish = true
    }

    func markFinished() { didFinish = true }
}

private actor OrderRecorder {
    private(set) var recorded: [Int] = []
    func record(_ value: Int) { recorded.append(value) }
}

private actor SerializationLedger: ReceiptStore {
    private var records: [ReceiptRecord] = []

    func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord {
        let record = ReceiptRecord(
            id: UUID(), sequenceID: records.count + 1, createdAt: receipt.createdAt,
            actor: receipt.actor, actorDetail: receipt.actorDetail,
            authorityDetail: receipt.authorityDetail, mode: receipt.mode, trigger: receipt.trigger,
            scope: receipt.scope, summary: receipt.summary, provenance: receipt.provenance,
            isSuccess: receipt.isSuccess, correlationID: receipt.correlationID, details: receipt.details
        )
        records.insert(record, at: 0)
        return record
    }

    func latest(limit: Int) async throws -> [ReceiptRecord] { Array(records.prefix(limit)) }

    func receipts(forCorrelationID correlationID: String, limit: Int) async throws -> [ReceiptRecord] {
        Array(records.filter { $0.correlationID == correlationID }.prefix(limit))
    }

    func exportAll() async throws -> Data { Data() }
    func resetAll() async throws { records.removeAll() }
}
