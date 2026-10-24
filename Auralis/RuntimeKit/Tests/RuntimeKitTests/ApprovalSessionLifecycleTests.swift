import ArtifactCore
import AuralisPrimaryModels
import Foundation
import PlaybookCore
import PolicyCore
import ReceiptsCore
import RuntimeCore
import Testing

@testable import RuntimeKit

/// A session that escalated for approval has to end *eventually*.
///
/// `finishSession` is right not to end it at the time: the run genuinely is not over, and marking it
/// terminal would claim an outcome nobody reached. The two ways the wait can finish were covered
/// unevenly.
///
/// - A person *answers*: `GovernedToolPipeline` ends the session on whatever terminal outcome the
///   resumed proposal reaches. Already correct; the first two tests here pin it, because the
///   responsibility sits in a different package from the escalation.
/// - A person *never* answers and the process ends: nothing covered this. `ApprovalRegistry` is
///   process-local by design, so the authority was gone while the session stayed `waitingForApproval`
///   on disk — permanently, with Mission Control's active list presenting a run that could never
///   resume. `closeAbandonedApprovalSessions()` at bootstrap is the fix.
@Suite("Approval session lifecycle")
@MainActor
struct ApprovalSessionLifecycleTests {

    // MARK: - Stranded by a relaunch

    /// `ApprovalRegistry` is process-local by design, so a `waitingForApproval` session present at
    /// bootstrap is waiting on authority that cannot exist. It is closed as blocked — the run did not
    /// go wrong, it was never authorized.
    @Test("a session left waiting by a previous process is closed at bootstrap")
    func strandedSessionIsClosedAtBootstrap() async throws {
        let sessionStore = InMemoryAgentSessionStore()
        let stranded = Self.strandedSession(
            correlationID: "goal-1",
            goal: "Rebalance the portfolio",
            actor: ActorRef(kind: .workflow, identifier: "autopilot")
        )
        #expect(stranded.status == .waitingForApproval)
        await sessionStore.upsert(stranded)

        let host = Self.host(sessionStore: sessionStore)
        await host.bootstrap()

        let closed = try #require(await sessionStore.session(correlationID: "goal-1"))
        #expect(closed.status == .blocked)
        #expect(closed.endedAt != nil)
        // The reason is on the session, so a person reading the trace learns why it stopped.
        #expect(closed.executionUpdates.contains { $0.message.contains("did not survive the app closing") })
    }

    /// The sweep must not re-attribute the run it closes: the session's own actor is who was acting.
    @Test("closing a stranded session preserves its original actor")
    func closingAStrandedSessionPreservesItsActor() async throws {
        let sessionStore = InMemoryAgentSessionStore()
        let originalActor = ActorRef(kind: .operatorAgent, identifier: "operator.onchain.prepareAction")
        await sessionStore.upsert(
            Self.strandedSession(correlationID: "goal-2", goal: "Prepare a swap", actor: originalActor)
        )

        await Self.host(sessionStore: sessionStore).bootstrap()

        let closed = try #require(await sessionStore.session(correlationID: "goal-2"))
        #expect(closed.actor == originalActor)
    }

    /// Only `waitingForApproval` is stranded. An `active` session may belong to work still in flight
    /// on another host in the process, and a terminal one is already done.
    @Test("the sweep leaves sessions that are not waiting on an approval alone")
    func theSweepLeavesOtherSessionsAlone() async throws {
        let sessionStore = InMemoryAgentSessionStore()
        let active = Self.strandedSession(
            correlationID: "active",
            goal: "In flight",
            actor: .human,
            waitingForApproval: false
        )
        var completed = Self.strandedSession(
            correlationID: "done",
            goal: "Finished",
            actor: .human,
            waitingForApproval: false
        )
        completed.complete()
        await sessionStore.upsert(active)
        await sessionStore.upsert(completed)

        await Self.host(sessionStore: sessionStore).bootstrap()

        #expect(await sessionStore.session(correlationID: "active")?.status == .active)
        #expect(await sessionStore.session(correlationID: "done")?.status == .completed)
        #expect(await sessionStore.session(correlationID: "done")?.executionUpdates.isEmpty == true)
    }

    /// The bound that keeps the sweep from being destructive.
    ///
    /// "Waiting at bootstrap ⇒ stranded" holds for one host per process, and this app runs two:
    /// `RuntimeBackgroundScheduler` builds its own `ModelContainer`, `RuntimeAssembly` keys its host
    /// cache on container identity, and ``ApprovalRegistry`` is per-host. So a background wake while a
    /// person has an approval open in Mission Control bootstraps a *second* host whose registry is
    /// empty — and an unbounded sweep would close that live session, terminating a run whose approval
    /// was still pending and resumable. Worse than the stale session the sweep exists to clear.
    @Test("a sibling host does not close a session this process is legitimately waiting on")
    func aSiblingHostDoesNotCloseALiveWaitingSession() async throws {
        let sessionStore = InMemoryAgentSessionStore()

        // Host A escalates for real, so its session is waiting on an approval in *its* registry.
        let hostA = Self.host(sessionStore: sessionStore)
        await hostA.bootstrap()
        let escalated = await hostA.runPolicyAction(
            .signMessage,
            actor: .human,
            payload: .signMessage(text: "hello", address: Self.checksummedAddress, chainID: "1"),
            correlationID: "live-goal"
        )
        guard case let .needsApproval(request) = escalated else {
            Issue.record("Expected signMessage to escalate in Assist, got \(escalated).")
            return
        }
        #expect(await sessionStore.session(correlationID: "live-goal")?.status == .waitingForApproval)

        // Host B — the background refresh — bootstraps over the same session store.
        let hostB = Self.host(sessionStore: sessionStore)
        await hostB.bootstrap()

        // Untouched: the session started after this process did, so it is not this sweep's business.
        #expect(
            await sessionStore.session(correlationID: "live-goal")?.status == .waitingForApproval,
            "A sibling host must not terminate a session whose approval is still pending."
        )
        // And the approval is still resumable on the host that raised it.
        let resumed = await hostA.resumeApprovedProposal(request)
        if case .blocked(let reason) = resumed, reason.contains("invalid, stale, altered") {
            Issue.record("The pending approval should have survived the sibling host's bootstrap.")
        }
    }

    /// The sweep writes no receipt: the ledger already carries the `needsApproval` receipt from the
    /// escalation, and an unanswered approval is not a new governance act. Receipting it would add one
    /// record per stranded session per launch for a non-event.
    ///
    /// The host is built over an *empty* playbook catalog so the assertion is about the sweep alone —
    /// `seedRoutineAuthority()` mints a standing lease per installed playbook on every bootstrap, and
    /// `RuntimeReceiptObserver` receipts each grant, so a seeded catalog puts unrelated records in the
    /// ledger.
    @Test("closing stranded sessions writes no receipt")
    func closingStrandedSessionsWritesNoReceipt() async throws {
        let sessionStore = InMemoryAgentSessionStore()
        await sessionStore.upsert(
            Self.strandedSession(correlationID: "goal-3", goal: "Prepare a swap", actor: .human)
        )
        let ledger = LifecycleLedger()

        await Self.host(sessionStore: sessionStore, receiptStore: ledger).bootstrap()

        #expect(await sessionStore.session(correlationID: "goal-3")?.status == .blocked)
        #expect(await ledger.isEmpty)
    }

    /// Nothing stranded is the common case, and it must cost one read and no writes.
    @Test("a launch with nothing stranded writes nothing")
    func aCleanLaunchWritesNothing() async {
        let sessionStore = InMemoryAgentSessionStore()
        let ledger = LifecycleLedger()

        await Self.host(sessionStore: sessionStore, receiptStore: ledger).bootstrap()

        // No session invented for a sweep that had nothing to close, and nothing appended.
        #expect(await sessionStore.allSessions().isEmpty)
        #expect(await ledger.isEmpty)
    }

    /// A sibling host that closes the session *between* this sweep's scan and its write must not end
    /// up with the explanation recorded twice.
    ///
    /// The per-session re-read inside the mutation is what prevents it. `AgentSession.end(status:at:)`
    /// is guarded by `endedAt == nil`, so the status could never double-change — but
    /// `noteExecutionUpdate` is not, so the loser of the race appended a second identical explanation
    /// to a session it had not closed, and published a duplicate `sessionEnded` for it.
    ///
    /// Driven by a store that changes its answer between `allSessions()` and `session(correlationID:)`
    /// rather than by racing two real bootstraps. Racing them cannot pin this: the *other* interleaving
    /// — the sibling reading before this host writes — is a plain lost update, which leaves exactly one
    /// explanation and so passes whether the guard is present or not. A test that can only fail on one
    /// of two timings is not a regression test.
    @Test("a session closed between the scan and the write is not explained twice")
    func aSessionClosedMidSweepIsNotExplainedTwice() async throws {
        let stranded = Self.strandedSession(
            correlationID: "goal-raced",
            goal: "Prepare a swap",
            actor: .human
        )
        // What the sibling host leaves behind: already blocked, already carrying its explanation.
        var alreadyClosed = stranded
        alreadyClosed.block(reason: "This run was waiting for an approval that did not survive the app closing, so it never ran.")
        let sessionStore = SweepRacingSessionStore(
            scanResult: [stranded],
            afterScan: alreadyClosed
        )

        await Self.host(sessionStore: sessionStore).bootstrap()

        let final = try #require(await sessionStore.session(correlationID: "goal-raced"))
        let explanations = final.executionUpdates.filter {
            $0.message.contains("did not survive the app closing")
        }
        #expect(explanations.count == 1, "Only the host that actually closed the session may explain it.")
        #expect(await sessionStore.upsertCount == 1, "The losing sweep still writes, but must not change anything.")
    }

    /// Two real hosts sweeping concurrently still converge on a closed session with nothing garbled.
    ///
    /// Deliberately a smoke test rather than the regression test for the guard above — see that test
    /// for why the timing makes it unreliable as one.
    @Test("two hosts sweeping at once converge on a closed session")
    func concurrentSweepsConverge() async throws {
        let sessionStore = InMemoryAgentSessionStore()
        await sessionStore.upsert(
            Self.strandedSession(correlationID: "goal-concurrent", goal: "Prepare a swap", actor: .human)
        )

        let hostA = Self.host(sessionStore: sessionStore)
        let hostB = Self.host(sessionStore: sessionStore)
        let first = Task { await hostA.bootstrap() }
        let second = Task { await hostB.bootstrap() }
        await first.value
        await second.value

        let closed = try #require(await sessionStore.session(correlationID: "goal-concurrent"))
        #expect(closed.status == .blocked)
        #expect(closed.endedAt != nil)
        let explanations = closed.executionUpdates.filter {
            $0.message.contains("did not survive the app closing")
        }
        #expect(explanations.count == 1)
    }

    /// Idempotent across a second host over the same store: the first sweep ended the session, so the
    /// second finds nothing to do rather than re-blocking it and appending a duplicate update.
    @Test("a second launch does not re-close an already-closed session")
    func aSecondLaunchDoesNotReCloseTheSession() async throws {
        let sessionStore = InMemoryAgentSessionStore()
        await sessionStore.upsert(
            Self.strandedSession(correlationID: "goal-4", goal: "Prepare a swap", actor: .human)
        )

        await Self.host(sessionStore: sessionStore).bootstrap()
        let afterFirst = try #require(await sessionStore.session(correlationID: "goal-4"))

        await Self.host(sessionStore: sessionStore).bootstrap()
        let afterSecond = try #require(await sessionStore.session(correlationID: "goal-4"))

        #expect(afterSecond.endedAt == afterFirst.endedAt)
        #expect(afterSecond.executionUpdates.count == afterFirst.executionUpdates.count)
    }

    // MARK: - Resolved by a person

    /// An approval that cannot be found is refused, and the session is deliberately *not* touched:
    /// the outcome says nothing about whether the run concluded.
    @Test("an invalid approval leaves the waiting session open")
    func anInvalidApprovalLeavesTheSessionOpen() async throws {
        let sessionStore = InMemoryAgentSessionStore()
        let host = Self.host(sessionStore: sessionStore)
        await host.bootstrap()

        await sessionStore.upsert(
            Self.strandedSession(correlationID: "goal-5", goal: "Sign a message", actor: .human)
        )

        // Never registered, so custody fails and nothing runs.
        let outcome = await host.resumeApprovedProposal(
            ApprovalRequest(proposal: Self.proposal(correlationID: "goal-5"), prompt: "Approve?")
        )

        guard case .blocked = outcome else {
            Issue.record("Expected an unregistered approval to be blocked, got \(outcome).")
            return
        }
        // Still waiting: this refusal is about the approval's custody, not the run's conclusion.
        #expect(await sessionStore.session(correlationID: "goal-5")?.status == .waitingForApproval)
    }

    /// An approved action that actually *succeeds* ends the session it was blocking.
    ///
    /// Characterisation rather than regression: `GovernedToolPipeline` already terminates the session
    /// on every terminal outcome — `complete()` on the executed path, `fail`/`block` on the refusals —
    /// so nothing in `RuntimeKit` has to, and `resumeApprovedProposal` deliberately does not. The two
    /// tests here pin that, because "who ends the session" is split across two packages and an
    /// `AgentSession` stuck in `waitingForApproval` is invisible until someone reads Mission Control's
    /// active list.
    ///
    /// The injected executor is what makes the *success* path reachable at all: the default
    /// `UnconfiguredPolicyActionExecutor` throws rather than fabricate a signature, so without it every
    /// resume lands on the failure path and the executed branch goes untested.
    @Test("an approved action that succeeds ends the session that was waiting on it")
    func aSuccessfulResumeEndsTheWaitingSession() async throws {
        let sessionStore = InMemoryAgentSessionStore()
        let host = Self.host(sessionStore: sessionStore, policyActionExecutor: StubSigningExecutor())
        await host.bootstrap()

        // Escalate for real, so the approval is in the registry under the host's own custody.
        let escalated = await host.runPolicyAction(
            .signMessage,
            actor: .human,
            payload: .signMessage(
                text: "hello",
                address: Self.checksummedAddress,
                chainID: "1"
            ),
            correlationID: "goal-6"
        )
        guard case let .needsApproval(request) = escalated else {
            Issue.record("Expected signMessage to escalate in Assist, got \(escalated).")
            return
        }
        #expect(await sessionStore.session(correlationID: "goal-6")?.status == .waitingForApproval)

        let resumed = await host.resumeApprovedProposal(request)

        guard case .executed = resumed else {
            Issue.record("Expected the stub executor to produce an executed outcome, got \(resumed).")
            return
        }
        let session = try #require(await sessionStore.session(correlationID: "goal-6"))
        #expect(session.status == .completed)
        #expect(session.endedAt != nil, "The approval resolved successfully, so the session must not still be waiting.")
    }

    /// The refusal path, pinned alongside the success one so the pipeline cannot start closing only
    /// half of them.
    @Test("an approved action that fails when it runs also ends the session")
    func aFailedResumeAlsoEndsTheWaitingSession() async throws {
        let sessionStore = InMemoryAgentSessionStore()
        // No executor injected, so the fail-closed default throws and the outcome is `.failed`.
        let host = Self.host(sessionStore: sessionStore)
        await host.bootstrap()

        let escalated = await host.runPolicyAction(
            .signMessage,
            actor: .human,
            payload: .signMessage(text: "hello", address: Self.checksummedAddress, chainID: "1"),
            correlationID: "goal-7"
        )
        guard case let .needsApproval(request) = escalated else {
            Issue.record("Expected signMessage to escalate in Assist, got \(escalated).")
            return
        }

        _ = await host.resumeApprovedProposal(request)

        let session = try #require(await sessionStore.session(correlationID: "goal-7"))
        #expect(session.status != .waitingForApproval)
        #expect(session.endedAt != nil)
    }

    // MARK: - Fixtures

    /// An empty playbook catalog, so `bootstrap()` seeds no standing authority and the ledger contains
    /// only what the behaviour under test wrote. `cryptoMode` defaults to Assist because Observe
    /// *blocks* crypto actions outright — an escalation, which is what a waiting session requires, only
    /// happens from Assist upwards.
    private static func host(
        sessionStore: any AgentSessionStoring,
        receiptStore: any ReceiptStore = LifecycleLedger(),
        cryptoMode: CryptoMode = .assist,
        policyActionExecutor: any ToolExecuting = UnconfiguredPolicyActionExecutor()
    ) -> RuntimeHost {
        RuntimeHost(
            receiptStore: receiptStore,
            stores: RuntimeHostStores(
                playbookStore: InMemoryPlaybookStore(seed: []),
                sessionStore: sessionStore
            ),
            operators: RuntimeOperatorStack(policyActionExecutor: policyActionExecutor),
            identity: RuntimeIdentityHooks(cryptoModeProvider: { cryptoMode })
        )
    }

    /// A valid EIP-55 address, so `policy.address.checksum` passes and the proposal reaches the judge.
    private static let checksummedAddress = "0x52908400098527886E0F7030069857D2E4169EE7"

    /// A session that started before this process built its first host, which is what the sweep is
    /// scoped to. `startedAt` has to be explicit: a session created with the default `.now` looks like
    /// one *this* process opened, and is deliberately spared — see
    /// `aSiblingHostDoesNotCloseALiveWaitingSession`.
    private static func strandedSession(
        correlationID: String,
        goal: String,
        actor: ActorRef,
        waitingForApproval: Bool = true
    ) -> AgentSession {
        var session = AgentSession(
            correlationID: correlationID,
            goal: goal,
            actor: actor,
            startedAt: RuntimeHost.processLaunchDate.addingTimeInterval(-3_600)
        )
        if waitingForApproval {
            session.note(approvalID: UUID())
        }
        return session
    }

    private static func proposal(correlationID: String) -> ActionProposal {
        ActionProposal(
            actor: .human,
            intent: "Sign Message",
            capability: .signMessage,
            impact: .highRisk,
            correlationID: correlationID
        )
    }
}

/// A session store that reports one thing to the sweep's scan and another to its per-session read,
/// standing in for a sibling host closing the session in between.
///
/// The only way to exercise that window deterministically: the real race has two orderings and the
/// other one masks the defect. See `aSessionClosedMidSweepIsNotExplainedTwice`.
private actor SweepRacingSessionStore: AgentSessionStoring {
    private let scanResult: [AgentSession]
    private var stored: AgentSession
    private(set) var upsertCount = 0

    init(scanResult: [AgentSession], afterScan: AgentSession) {
        self.scanResult = scanResult
        self.stored = afterScan
    }

    /// What the sweep's scan sees: still waiting, so it selects the session as stranded.
    func allSessions() -> [AgentSession] { scanResult }

    /// What it sees when it goes to mutate: already closed by the sibling.
    func session(correlationID: String) -> AgentSession? {
        stored.correlationID == correlationID ? stored : nil
    }

    func upsert(_ session: AgentSession) {
        upsertCount += 1
        stored = session
    }

    func resetAll() { }
}

/// Stands in for the app's wallet-backed executor: performs the approved action and reports outputs
/// that satisfy `policy.signMessage`'s strict output schema, so the pipeline reaches `.executed`.
private struct StubSigningExecutor: ToolExecuting {
    func execute(
        _ tool: ToolDefinition,
        proposal: ActionProposal,
        authorization: ToolExecutionAuthorization
    ) async throws -> ToolCallArtifact {
        ToolCallArtifact(
            toolID: tool.id,
            summary: "Signed “\(proposal.intent)”",
            outputFields: [
                "signature": "0x" + String(repeating: "ab", count: 65),
                "address": "0x52908400098527886E0F7030069857D2E4169EE7"
            ]
        )
    }
}

private actor LifecycleLedger: ReceiptStore {
    private var records: [ReceiptRecord] = []

    var isEmpty: Bool { records.isEmpty }

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
