import AuralisFoundation
import Foundation
import PerformanceCore
import PlaybookCore
import RuntimeCore
@testable import SchedulingCore
import Testing

private actor InMemoryRoutineArtifactPersister: RoutineArtifactPersisting {
    private var drafts: [(id: UUID, draft: RoutineArtifactDraft)] = []

    func create(_ draft: RoutineArtifactDraft) async throws -> UUID {
        let id = UUID()
        drafts.append((id, draft))
        return id
    }

    func latest(limit: Int) -> [RoutineArtifactDraft] {
        Array(drafts.suffix(limit).reversed().map(\.draft))
    }
}

private struct StaticContext: ContextProviding {
    func gather(for playbook: Playbook) async -> ContextBundle {
        ContextBundle(fields: [
            ContextField(key: "k", stringValue: "v", dataClass: .publicIdentifier, source: .runtimeHost, lastRefreshed: .now)
        ])
    }
}

private struct FixedOperator: RoutineOperator {
    let result: RoutineRunResult
    func run(playbook: Playbook, context: GovernedContext) async -> RoutineRunResult { result }
}

@Suite("TriggerEvaluator")
struct TriggerEvaluatorTests {
    @Test
    func scheduleFiresAfterInterval() {
        let now = Date()
        #expect(TriggerEvaluator.shouldFire(.schedule(intervalSeconds: 60), lastRun: nil, now: now))
        #expect(TriggerEvaluator.shouldFire(.schedule(intervalSeconds: 60), lastRun: now.addingTimeInterval(-120), now: now))
        #expect(TriggerEvaluator.shouldFire(.schedule(intervalSeconds: 60), lastRun: now.addingTimeInterval(-30), now: now) == false)
        #expect(TriggerEvaluator.shouldFire(.maintenance(intervalSeconds: 60), lastRun: now.addingTimeInterval(-120), now: now))
        #expect(TriggerEvaluator.shouldFire(.maintenance(intervalSeconds: 60), lastRun: now.addingTimeInterval(-30), now: now) == false)
    }

    @Test
    func manualNeverAutoFiresAndEventsFollowSignals() {
        #expect(TriggerEvaluator.shouldFire(.manual, lastRun: nil) == false)
        #expect(TriggerEvaluator.shouldFire(.event(.artifactStale), lastRun: nil, staleSignal: true))
        #expect(TriggerEvaluator.shouldFire(.event(.artifactStale), lastRun: nil, staleSignal: false) == false)
        #expect(TriggerEvaluator.shouldFire(.event(.approvalPendingTooLong), lastRun: nil, approvalPendingSignal: false) == false)
    }

    @Test
    func timestampedEventFiresOnceUntilANewerEventArrives() {
        let now = Date()
        let firstEvent = now.addingTimeInterval(-60)
        let signals = RoutineEventSignals(artifactStaleAt: firstEvent)

        #expect(TriggerEvaluator.evaluate(
            .event(.artifactStale),
            lastRun: nil,
            now: now,
            eventSignals: signals
        ).isDue)
        #expect(TriggerEvaluator.evaluate(
            .event(.artifactStale),
            lastRun: now.addingTimeInterval(-30),
            now: now,
            eventSignals: signals
        ).isDue == false)
        #expect(TriggerEvaluator.evaluate(
            .event(.artifactStale),
            lastRun: now.addingTimeInterval(-90),
            now: now,
            eventSignals: signals
        ).isDue)
    }

    /// `shouldFire` delegates to `evaluate`, so the two can't disagree — and every verdict carries a
    /// reason a due-scan can put on the worklog.
    @Test(arguments: [
        (PlaybookTrigger.manual, false),
        (PlaybookTrigger.schedule(intervalSeconds: 60), true),
        (PlaybookTrigger.maintenance(intervalSeconds: 60), true),
        (PlaybookTrigger.event(.artifactStale), false),
        (PlaybookTrigger.event(.approvalPendingTooLong), false)
    ])
    func evaluationAgreesWithShouldFireAndAlwaysExplainsItself(trigger: PlaybookTrigger, expectedDue: Bool) {
        let now = Date()
        let evaluation = TriggerEvaluator.evaluate(trigger, lastRun: nil, now: now)
        #expect(evaluation.isDue == expectedDue)
        #expect(evaluation.isDue == TriggerEvaluator.shouldFire(trigger, lastRun: nil, now: now))
        #expect(evaluation.rationale.isEmpty == false)
    }

    /// A not-yet-due interval routine explains *how long is left*, which is the whole point of
    /// tracing skips: "why didn't it run" should be answerable without re-deriving the schedule.
    @Test
    func notDueIntervalRationaleNamesTheRemainingWait() {
        let now = Date()
        let evaluation = TriggerEvaluator.evaluate(
            .schedule(intervalSeconds: 60),
            lastRun: now.addingTimeInterval(-30),
            now: now
        )
        #expect(evaluation.isDue == false)
        #expect(evaluation.rationale.contains("30s"))
    }

    /// An interval carrying no cadence must not reach the due-check. `TriggerEvaluator` is public and
    /// takes a *bare* trigger, so these values arrive without `Playbook`'s construction/decode guard:
    /// zero and negative would read as due on every single scan, and `NaN` loses every comparison, so
    /// it would formerly fall into the not-due branch and abort the process while formatting.
    @Test(arguments: [0, -1, -86_400, Double.nan, .infinity, -.infinity])
    func unschedulableIntervalFallsBackToTheModelCadenceInsteadOfFiringOrTrapping(interval: Double) {
        let now = Date()

        for trigger in [PlaybookTrigger.schedule(intervalSeconds: interval), .maintenance(intervalSeconds: interval)] {
            // Just ran: the hourly fallback cadence says "not due", where zero/negative said "due".
            let justRan = TriggerEvaluator.evaluate(trigger, lastRun: now.addingTimeInterval(-30), now: now)
            #expect(justRan.isDue == false)
            #expect(justRan.rationale.isEmpty == false)

            // Past the fallback cadence: still a real schedule, so it does fire.
            #expect(TriggerEvaluator.evaluate(
                trigger,
                lastRun: now.addingTimeInterval(-PlaybookTrigger.fallbackIntervalSeconds - 1),
                now: now
            ).isDue)
        }
    }

    /// A finite-but-absurd cadence is a *valid* declaration — the model layer bounds intervals below
    /// but deliberately not above — so it has to survive the due-scan. `Int(_:)` aborts on a `Double`
    /// past `Int.max`, which formerly crashed while only building the "not due yet" explanation.
    @Test(arguments: [1e19, 1e30, Double.greatestFiniteMagnitude])
    func absurdlyLongButFiniteIntervalExplainsItselfInsteadOfTrapping(interval: Double) {
        let now = Date()
        let evaluation = TriggerEvaluator.evaluate(
            .schedule(intervalSeconds: interval),
            lastRun: now.addingTimeInterval(-60),
            now: now
        )
        #expect(evaluation.isDue == false)
        #expect(evaluation.rationale.isEmpty == false)
    }

    /// The clock moving *backwards* must not retire a routine. `Date` is absolute, so DST and
    /// time-zone changes can never produce this — only the device clock itself moving can — but when
    /// it does, waiting for wall-clock to catch up stalls the routine for however far the clock jumped.
    @Test
    func lastRunDatedInTheFutureReAnchorsInsteadOfStallingForYears() {
        let now = Date()
        // Clock was briefly set to 2030, a run was recorded, then the clock was corrected.
        let fromABadClock = now.addingTimeInterval(4 * 365 * 86_400)

        for trigger in [PlaybookTrigger.schedule(intervalSeconds: 3_600), .maintenance(intervalSeconds: 3_600)] {
            let evaluation = TriggerEvaluator.evaluate(trigger, lastRun: fromABadClock, now: now)
            #expect(evaluation.isDue)
            #expect(evaluation.rationale.contains("future"))
        }
    }

    /// Interval arithmetic is on absolute time, so a routine must keep its cadence across a DST
    /// transition and read identically in every time zone — a 24h routine is due 24h later, not 23 or
    /// 25, and the verdict cannot depend on the evaluating process's `TimeZone`.
    @Test(arguments: ["America/New_York", "Europe/London", "Australia/Lord_Howe", "UTC", "Asia/Kolkata"])
    func intervalCadenceIsUnaffectedByDSTAndTimeZone(zoneID: String) throws {
        let zone = try #require(TimeZone(identifier: zoneID))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let daily = PlaybookTrigger.schedule(intervalSeconds: 86_400)

        // The US spring-forward instant (2026-03-08 07:00Z) and the autumn fall-back instant
        // (2026-11-01 06:00Z): one local day either side of each is still one absolute day.
        for transition in [Date(timeIntervalSince1970: 1_772_953_200), Date(timeIntervalSince1970: 1_793_512_800)] {
            let lastRun = transition.addingTimeInterval(-43_200)

            #expect(TriggerEvaluator.evaluate(
                daily,
                lastRun: lastRun,
                now: lastRun.addingTimeInterval(86_400 - 1)
            ).isDue == false)
            #expect(TriggerEvaluator.evaluate(
                daily,
                lastRun: lastRun,
                now: lastRun.addingTimeInterval(86_400)
            ).isDue)

            // A local wall-clock day across spring-forward is only 23 absolute hours, so the routine
            // is genuinely not yet due — the schedule is absolute, not calendar-based.
            let oneLocalDayLater = try #require(calendar.date(byAdding: .day, value: 1, to: lastRun))
            let localDaySeconds = oneLocalDayLater.timeIntervalSince(lastRun)
            #expect(TriggerEvaluator.evaluate(daily, lastRun: lastRun, now: oneLocalDayLater).isDue
                == (localDaySeconds >= 86_400))
        }
    }
}

@Suite("SchedulingEngine")
struct SchedulingEngineTests {
    private func playbook(
        _ state: PlaybookInstallState,
        outputs: [ArtifactOutputType] = [.brief],
        supportedFlows: [PlaybookFlowKind] = [.read, .prepare]
    ) -> Playbook {
        Playbook(
            id: "pb", name: "PB", summary: "s",
            trigger: .manual,
            authority: PlaybookAuthority(capabilities: [.autoOrganization], allowedOutputs: outputs),
            completionCondition: "done",
            supportedFlows: supportedFlows,
            contextContract: .noContext(identifier: "test.pb"),
            installState: state
        )
    }

    private func makeEngine(playbook: Playbook, result: RoutineRunResult) async -> (SchedulingEngine, InMemoryRoutineArtifactPersister, PerformanceStore) {
        let artifacts = InMemoryRoutineArtifactPersister()
        let perf = PerformanceStore()
        let engine = SchedulingEngine(
            playbooks: InMemoryPlaybookStore(seed: [playbook]),
            context: StaticContext(),
            contracts: ContextContractRegistry(contracts: [
                playbook.id: ContextBundleContract(requirements: [
                    ContextFieldRequirement(key: "k", allowedDataClasses: [.publicIdentifier], maxAge: 3_600, authoritativeSource: .runtimeHost, missingFieldBehavior: .fail)
                ])
            ]),
            operator: FixedOperator(result: result),
            artifacts: artifacts,
            performance: perf
        )
        return (engine, artifacts, perf)
    }

    private func brief() -> RoutineArtifactDraft {
        RoutineArtifactDraft(type: .brief, title: "b", actor: .system, content: "x")
    }

    private struct FailingArtifactStore: RoutineArtifactPersisting {
        private struct PersistenceFailure: Error { }

        func create(_ draft: RoutineArtifactDraft) async throws -> UUID { throw PersistenceFailure() }
    }

    @Test
    func installedPlaybookRunsAndProducesArtifact() async {
        let (engine, artifacts, perf) = await makeEngine(
            playbook: playbook(.installed),
            result: RoutineRunResult(outcome: .success, artifact: brief())
        )
        let record = await engine.runOnce(playbookID: "pb", trigger: .manual)
        #expect(record.outcome == .success)
        #expect(record.artifactID != nil)
        #expect(await artifacts.latest(limit: 10).count == 1)
        #expect(await perf.health(forPlaybook: "pb").totalRuns == 1)
    }

    @Test("approval-gated routine remains waiting instead of completing its trace")
    func approvalGatedRoutineRecordsAwaitingApproval() async {
        let subject = playbook(.installed)
        let worklog = InMemoryWorklog()
        let engine = SchedulingEngine(
            playbooks: InMemoryPlaybookStore(seed: [subject]),
            context: StaticContext(),
            contracts: ContextContractRegistry(contracts: [
                subject.id: ContextBundleContract(requirements: [
                    ContextFieldRequirement(
                        key: "k",
                        allowedDataClasses: [.publicIdentifier],
                        maxAge: 3_600,
                        authoritativeSource: .runtimeHost,
                        missingFieldBehavior: .fail
                    )
                ])
            ]),
            operator: FixedOperator(result: RoutineRunResult(outcome: .needsApproval)),
            artifacts: InMemoryRoutineArtifactPersister(),
            performance: PerformanceStore(),
            worklog: worklog
        )

        let record = await engine.runOnce(playbookID: subject.id, trigger: .manual)
        let steps = await worklog.steps(forCorrelationID: record.correlationID)

        #expect(record.outcome == .needsApproval)
        #expect(steps.contains {
            if case .routinePhase(.awaitingApproval, _) = $0.event { return true }
            return false
        })
        #expect(steps.contains {
            if case .routinePhase(.completed, _) = $0.event { return true }
            return false
        } == false)
    }

    @Test("artifact persistence failure records an infrastructure failure instead of success")
    func artifactPersistenceFailureFailsRun() async {
        let performance = PerformanceStore()
        let engine = SchedulingEngine(
            playbooks: InMemoryPlaybookStore(seed: [playbook(.installed)]),
            context: StaticContext(),
            contracts: ContextContractRegistry(contracts: [
                "pb": ContextBundleContract(requirements: [
                    ContextFieldRequirement(
                        key: "k",
                        allowedDataClasses: [.publicIdentifier],
                        maxAge: 3_600,
                        authoritativeSource: .runtimeHost,
                        missingFieldBehavior: .fail
                    )
                ])
            ]),
            operator: FixedOperator(result: RoutineRunResult(outcome: .success, artifact: brief())),
            artifacts: FailingArtifactStore(),
            performance: performance
        )

        let record = await engine.runOnce(playbookID: "pb", trigger: .manual)
        let event = await performance.events(forPlaybook: "pb").first

        #expect(record.outcome == .failed)
        #expect(record.artifactID == nil)
        #expect(record.failureReason?.contains("Artifact persistence failed") == true)
        #expect(event?.outcome == .failed)
        #expect(event?.blockCategory == .infrastructure)
    }

    @Test
    func pausedPlaybookRecordsNoOp() async {
        let (engine, artifacts, _) = await makeEngine(
            playbook: playbook(.paused),
            result: RoutineRunResult(outcome: .success, artifact: brief())
        )
        let record = await engine.runOnce(playbookID: "pb", trigger: .schedule)
        #expect(record.outcome == .noOp)
        #expect(record.artifactID == nil)
        #expect(await artifacts.latest(limit: 10).isEmpty)
    }

    @Test
    func globalPauseShortCircuitsInstalledPlaybook() async {
        let (engine, _, _) = await makeEngine(
            playbook: playbook(.installed),
            result: RoutineRunResult(outcome: .success, artifact: brief())
        )
        await engine.setPaused(true)
        let record = await engine.runOnce(playbookID: "pb", trigger: .manual)
        #expect(record.outcome == .noOp)
    }

    @Test
    func disallowedOutputTypeIsNotPersisted() async {
        // Playbook only allows .report, operator returns a .brief → artifact rejected.
        let (engine, artifacts, _) = await makeEngine(
            playbook: playbook(.installed, outputs: [.report]),
            result: RoutineRunResult(outcome: .success, artifact: brief())
        )
        let record = await engine.runOnce(playbookID: "pb", trigger: .manual)
        #expect(record.artifactID == nil)
        #expect(await artifacts.latest(limit: 10).isEmpty)
    }

    @Test
    func executeFlowIsBlockedInV0() async {
        let (engine, artifacts, _) = await makeEngine(
            playbook: playbook(.installed, supportedFlows: [.read, .execute]),
            result: RoutineRunResult(outcome: .success, artifact: brief())
        )
        let record = await engine.runOnce(playbookID: "pb", trigger: .manual)
        #expect(record.outcome == .blocked)
        #expect(record.artifactID == nil)
        #expect(await artifacts.latest(limit: 10).isEmpty)
    }

    @Test
    func executionRecordsAccumulate() async {
        let (engine, _, _) = await makeEngine(
            playbook: playbook(.installed),
            result: RoutineRunResult(outcome: .noOp)
        )
        _ = await engine.runOnce(playbookID: "pb", trigger: .manual)
        _ = await engine.runOnce(playbookID: "pb", trigger: .schedule)
        #expect(await engine.executionRecords().count == 2)
        #expect(await engine.latestExecution(forPlaybookID: "pb")?.triggerSource == .schedule)
    }

    // MARK: - Actor attribution (P0.5-602)

    @Test
    func automatedTriggersAreAttributedToScheduledRoutine() async {
        let (engine, _, _) = await makeEngine(
            playbook: playbook(.installed),
            result: RoutineRunResult(outcome: .success, artifact: brief())
        )
        for trigger in [TriggerSource.schedule, .maintenance, .artifactStale, .approvalPendingTooLong] {
            let record = await engine.runOnce(playbookID: "pb", trigger: trigger)
            #expect(record.actor.kind == .scheduledRoutine)
        }
    }

    @Test
    func manualTriggerIsAttributedToHuman() async {
        let (engine, _, _) = await makeEngine(
            playbook: playbook(.installed),
            result: RoutineRunResult(outcome: .success, artifact: brief())
        )
        let record = await engine.runOnce(playbookID: "pb", trigger: .manual)
        #expect(record.actor.kind == .human)
    }

    @Test
    func explicitActorOverridesTriggerDefault() async {
        let (engine, _, _) = await makeEngine(
            playbook: playbook(.installed),
            result: RoutineRunResult(outcome: .success, artifact: brief())
        )
        // An operator pack running a nominally-manual playbook must not be recorded as the human.
        let pack = ActorRef(kind: .operatorAgent, identifier: "operator.research.brief", displayName: "Research")
        let record = await engine.runOnce(playbookID: "pb", trigger: .manual, actor: pack)
        #expect(record.actor == pack)
        #expect(await engine.latestExecution(forPlaybookID: "pb")?.actor.identifier == "operator.research.brief")
    }

    @Test
    func recordedNoOpsAndBlocksStillCarryTheActor() async {
        // Global pause: short-circuits before the playbook is even looked up.
        let (paused, _, _) = await makeEngine(
            playbook: playbook(.installed),
            result: RoutineRunResult(outcome: .success, artifact: brief())
        )
        await paused.setPaused(true)
        let pausedRecord = await paused.runOnce(playbookID: "pb", trigger: .schedule)
        #expect(pausedRecord.outcome == .noOp)
        #expect(pausedRecord.actor.kind == .scheduledRoutine)

        // Blocked flow: bails out on the authority check rather than the happy path.
        let (blocked, _, _) = await makeEngine(
            playbook: playbook(.installed, supportedFlows: [.read, .execute]),
            result: RoutineRunResult(outcome: .success, artifact: brief())
        )
        let blockedRecord = await blocked.runOnce(playbookID: "pb", trigger: .manual, actor: .human)
        #expect(blockedRecord.outcome == .blocked)
        #expect(blockedRecord.actor.kind == .human)
    }

    /// Duration is measured on a monotonic clock, so it can never come back negative or non-finite —
    /// values a wall-clock delta produces when an NTP correction lands mid-run, and which would enter
    /// routine health indistinguishable from a real measurement.
    @Test
    func runDurationIsNonNegativeAndFinite() async {
        let (engine, _, perf) = await makeEngine(
            playbook: playbook(.installed),
            result: RoutineRunResult(outcome: .success, artifact: brief())
        )
        let record = await engine.runOnce(playbookID: "pb", trigger: .manual)
        let event = await perf.events(forPlaybook: "pb").first

        #expect(record.durationSeconds >= 0)
        #expect(record.durationSeconds.isFinite)
        // The performance event must agree with the record rather than re-deriving its own timing.
        #expect(event?.durationSeconds == record.durationSeconds)
    }
}

@Suite("InMemoryExecutionRecordStore")
struct InMemoryExecutionRecordStoreTests {
    private func record(trigger: TriggerSource, startedAt: Date) -> ExecutionRecord {
        ExecutionRecord(
            playbookID: "pb",
            triggerSource: trigger,
            actor: .system,
            outcome: .success,
            artifactID: nil,
            startedAt: startedAt,
            durationSeconds: 0
        )
    }

    /// Two runs can land in the same instant, and "latest" then has to mean the one recorded last.
    /// `max(by:)` keeps the *first* of a tie, so an unreversed search returned the older run — whose
    /// trigger and outcome are what the due-scan and the UI read back.
    @Test
    func latestPrefersTheMostRecentlyRecordedRunOnATie() async {
        let store = InMemoryExecutionRecordStore()
        let sameInstant = Date(timeIntervalSince1970: 1_700_000_000)

        await store.store(record(trigger: .manual, startedAt: sameInstant))
        await store.store(record(trigger: .schedule, startedAt: sameInstant))

        #expect(await store.latest(forPlaybookID: "pb")?.triggerSource == .schedule)
    }

    @Test
    func latestPrefersTheNewestStartedAtRegardlessOfInsertionOrder() async {
        let store = InMemoryExecutionRecordStore()
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        // Newest inserted first, so insertion order and timestamp order disagree.
        await store.store(record(trigger: .schedule, startedAt: base.addingTimeInterval(60)))
        await store.store(record(trigger: .manual, startedAt: base))

        #expect(await store.latest(forPlaybookID: "pb")?.triggerSource == .schedule)
        #expect(await store.latest(forPlaybookID: "other") == nil)
    }

    @Test
    func resetAllErasesHistory() async {
        let store = InMemoryExecutionRecordStore()
        await store.store(record(trigger: .manual, startedAt: .now))
        await store.resetAll()

        #expect(await store.all().isEmpty)
        #expect(await store.latest(forPlaybookID: "pb") == nil)
    }
}

/// ``ExecutionRecord`` is persisted as a Codable blob (`StoredExecutionRecordRow`), so actor
/// attribution only survives relaunch if it round-trips through the coder — and old rows written
/// before the field existed must still decode. (P0.5-602)
@Suite("ExecutionRecord actor persistence")
struct ExecutionRecordActorCodingTests {
    private func record(actor: ActorRef) -> ExecutionRecord {
        ExecutionRecord(
            playbookID: "pb",
            triggerSource: .schedule,
            actor: actor,
            outcome: .success,
            artifactID: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: 1.5
        )
    }

    private func roundTrip(_ original: ExecutionRecord) throws -> ExecutionRecord {
        let data = try JSONEncoder().encode(original)
        return try JSONDecoder().decode(ExecutionRecord.self, from: data)
    }

    @Test
    func actorSurvivesRoundTrip() throws {
        let original = record(actor: ActorRef(kind: .scheduledRoutine, identifier: "cron.morning", displayName: "Morning"))
        let decoded = try roundTrip(original)
        #expect(decoded == original)
        #expect(decoded.actor.kind == .scheduledRoutine)
        #expect(decoded.actor.identifier == "cron.morning")
        #expect(decoded.actor.displayName == "Morning")
    }

    @Test
    func modelActorInferenceProvenanceSurvivesRoundTrip() throws {
        let original = record(
            actor: .model(
                identifier: "foundation.on-device",
                inference: InferenceProvenance(locality: .local, provider: "apple", modelClass: "afm")
            )
        )
        let decoded = try roundTrip(original)
        #expect(decoded.actor.inference?.locality == .local)
        #expect(decoded.actor.inference?.provider == "apple")
        #expect(decoded.actor.inference?.modelClass == "afm")
    }

    @Test
    func legacyRowWithoutActorDecodesAsSystem() throws {
        // A row written before the actor column existed — decoding must not throw.
        let legacy = """
        {
            "id": "5F7E4C6A-0000-4000-8000-000000000001",
            "playbookID": "pb",
            "triggerSource": "schedule",
            "outcome": "success",
            "startedAt": 715000000,
            "durationSeconds": 1.5
        }
        """
        let decoded = try JSONDecoder().decode(ExecutionRecord.self, from: Data(legacy.utf8))
        #expect(decoded.actor == .system)
        #expect(decoded.artifactID == nil)
        #expect(decoded.authority == nil)
    }

    @Test
    func authoritySurvivesRoundTrip() throws {
        let lease = CapabilityLease(
            capability: .autoOrganization,
            reason: "Morning brief may organize.",
            scope: CapabilityLeaseScope.defaultScope(for: .autoOrganization),
            grantedTo: ActorRef(kind: .scheduledRoutine, identifier: "cron.morning"),
            grantedAt: Date(timeIntervalSince1970: 1_700_000_000),
            expiresAt: Date(timeIntervalSince1970: 1_700_003_600)
        )
        let original = ExecutionRecord(
            playbookID: "pb",
            triggerSource: .schedule,
            actor: ActorRef(kind: .scheduledRoutine, identifier: "cron.morning"),
            authority: AuthorityRef(lease: lease),
            outcome: .success,
            artifactID: nil,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: 1
        )
        let decoded = try roundTrip(original)
        #expect(decoded == original)
        #expect(decoded.authority?.source == .lease)
        #expect(decoded.authority?.leaseID == lease.id)
        #expect(decoded.authority?.reason == "Morning brief may organize.")
    }

    /// A run recorded by a build that knows a further `AuthorityRef.Source` must still load here.
    /// Records are stored as JSON blobs read back through `compactMap`, so throwing on the authority
    /// column would delete the whole run — losing the fact that it happened, what it produced, and who
    /// ran it — over one unreadable field. The authority degrades to "not recorded"; nothing else does.
    ///
    /// The unknown source is injected into encoded JSON because this build has no `Source` case that
    /// could produce it.
    @Test
    func unreadableAuthoritySourceKeepsTheRun() throws {
        let artifactID = UUID()
        let original = ExecutionRecord(
            playbookID: "pb",
            triggerSource: .schedule,
            actor: ActorRef(kind: .scheduledRoutine, identifier: "cron.morning"),
            authority: .humanApproval(capability: .autoOrganization, reason: "approved once"),
            outcome: .success,
            artifactID: artifactID,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: 1
        )

        let encoded = try JSONEncoder().encode(original)
        let raw = try JSONSerialization.jsonObject(with: encoded)
        var object = try #require(raw as? [String: Any])
        var authority = try #require(object["authority"] as? [String: Any])
        authority["source"] = "delegatedMandate"
        object["authority"] = authority

        let decoded = try JSONDecoder().decode(
            ExecutionRecord.self,
            from: try JSONSerialization.data(withJSONObject: object)
        )

        #expect(decoded.authority == nil)
        #expect(decoded.actor.identifier == "cron.morning")
        #expect(decoded.artifactID == artifactID)
        #expect(decoded.outcome == .success)
        #expect(decoded.correlationID == original.correlationID)
    }
}

/// The "under what authority" leg for scheduled work (P0.5-601/602). Without a lease registry the
/// engine must behave exactly as it did before the field existed; with one, every declared capability
/// must be covered by a live grant, and the grant must land on the execution record.
@Suite("SchedulingEngine authority")
struct SchedulingEngineAuthorityTests {
    private let routineActor = ActorRef(kind: .scheduledRoutine, identifier: "routine.pb")

    private func playbook(capabilities: [CapabilityID] = [.autoOrganization]) -> Playbook {
        Playbook(
            id: "pb", name: "PB", summary: "s",
            trigger: .schedule(intervalSeconds: 60),
            authority: PlaybookAuthority(capabilities: capabilities, allowedOutputs: [.brief]),
            completionCondition: "done",
            supportedFlows: [.read, .prepare],
            contextContract: .noContext(identifier: "test.pb"),
            installState: .installed
        )
    }

    private func makeEngine(
        playbook: Playbook,
        leaseRegistry: CapabilityLeaseRegistry?
    ) -> SchedulingEngine {
        SchedulingEngine(
            playbooks: InMemoryPlaybookStore(seed: [playbook]),
            context: StaticContext(),
            contracts: ContextContractRegistry(contracts: [
                playbook.id: ContextBundleContract(requirements: [
                    ContextFieldRequirement(key: "k", allowedDataClasses: [.publicIdentifier], maxAge: 3_600, authoritativeSource: .runtimeHost, missingFieldBehavior: .fail)
                ])
            ]),
            operator: FixedOperator(
                result: RoutineRunResult(
                    outcome: .success,
                    artifact: RoutineArtifactDraft(
                        type: .brief,
                        title: "b",
                        actor: .system,
                        content: "x"
                    )
                )
            ),
            artifacts: InMemoryRoutineArtifactPersister(),
            performance: PerformanceStore(),
            leaseRegistry: leaseRegistry
        )
    }

    private func registryGranting(_ capabilities: [CapabilityID], to actor: ActorRef) async -> CapabilityLeaseRegistry {
        let registry = CapabilityLeaseRegistry()
        for capability in capabilities {
            _ = await registry.grant(
                CapabilityLease(
                    capability: capability,
                    reason: "granted for test",
                    scope: CapabilityLeaseScope.defaultScope(for: capability),
                    grantedTo: actor,
                    grantedAt: Date().addingTimeInterval(-60),
                    expiresAt: Date().addingTimeInterval(3600)
                )
            )
        }
        return registry
    }

    @Test
    func runWithoutRegistryRecordsPolicyDefaultAuthority() async {
        let engine = makeEngine(playbook: playbook(), leaseRegistry: nil)

        let record = await engine.runOnce(playbookID: "pb", trigger: .schedule, actor: routineActor)

        #expect(record.outcome == .success)
        #expect(record.authority?.source == .policyDefault)
        #expect(record.authority?.capability == .autoOrganization)
    }

    @Test
    func runWithGrantingLeaseRecordsThatLease() async {
        let registry = await registryGranting([.autoOrganization], to: routineActor)
        let engine = makeEngine(playbook: playbook(), leaseRegistry: registry)

        let record = await engine.runOnce(playbookID: "pb", trigger: .schedule, actor: routineActor)

        #expect(record.outcome == .success)
        #expect(record.authority?.source == .lease)
        #expect(record.authority?.capability == .autoOrganization)
        #expect(record.authority?.reason == "granted for test")
        #expect(record.authority?.leaseID != nil)
    }

    @Test
    func runWithoutAGrantIsBlockedAndRecordsNoAuthority() async {
        // Fails closed: an attached registry means scheduled work must be granted, not assumed.
        let registry = CapabilityLeaseRegistry()
        let engine = makeEngine(playbook: playbook(), leaseRegistry: registry)

        let record = await engine.runOnce(playbookID: "pb", trigger: .schedule, actor: routineActor)

        #expect(record.outcome == .blocked)
        #expect(record.authority == nil)
        #expect(record.actor == routineActor)
    }

    @Test
    func everyDeclaredCapabilityMustBeGranted() async {
        // Only one of the two declared capabilities is leased — the run must still be refused.
        let registry = await registryGranting([.autoOrganization], to: routineActor)
        let engine = makeEngine(
            playbook: playbook(capabilities: [.autoOrganization, .runPlugin]),
            leaseRegistry: registry
        )

        let record = await engine.runOnce(playbookID: "pb", trigger: .schedule, actor: routineActor)

        #expect(record.outcome == .blocked)
        #expect(record.authority == nil)
    }

    @Test
    func leaseGrantedToADifferentActorDoesNotAuthorize() async {
        let registry = await registryGranting(
            [.autoOrganization],
            to: ActorRef(kind: .scheduledRoutine, identifier: "routine.other")
        )
        let engine = makeEngine(playbook: playbook(), leaseRegistry: registry)

        let record = await engine.runOnce(playbookID: "pb", trigger: .schedule, actor: routineActor)

        #expect(record.outcome == .blocked)
    }

    @Test
    func pausedEngineRecordsNoAuthority() async {
        // Short-circuits before authority is resolved, so the record must not claim one.
        let registry = await registryGranting([.autoOrganization], to: routineActor)
        let engine = makeEngine(playbook: playbook(), leaseRegistry: registry)
        await engine.setPaused(true)

        let record = await engine.runOnce(playbookID: "pb", trigger: .schedule, actor: routineActor)

        #expect(record.outcome == .noOp)
        #expect(record.authority == nil)
    }

    @Test
    func playbookDeclaringNoCapabilitiesRunsUnderStandingPolicy() async {
        let registry = CapabilityLeaseRegistry()
        let engine = makeEngine(playbook: playbook(capabilities: []), leaseRegistry: registry)

        let record = await engine.runOnce(playbookID: "pb", trigger: .schedule, actor: routineActor)

        #expect(record.outcome == .success)
        #expect(record.authority?.source == .policyDefault)
    }
}

@Suite("ContextBundleContract enforcement")
struct ContextContractEnforcementTests {
    /// A provider that hands back exactly the fields given to it, so a test can drive the contract.
    private struct FixedBundleContext: ContextProviding {
        let fields: [ContextField]
        func gather(for playbook: Playbook) async -> ContextBundle { ContextBundle(fields: fields) }
    }

    private struct FixedOperator: RoutineOperator {
        let result: RoutineRunResult
        func run(playbook: Playbook, context: GovernedContext) async -> RoutineRunResult { result }
    }

    private struct ContextEchoOperator: RoutineOperator {
        func run(playbook: Playbook, context: GovernedContext) async -> RoutineRunResult {
            RoutineRunResult(outcome: .success, failureReason: context.bundle.fields.map(\.key).sorted().joined(separator: ","))
        }
    }

    private func playbook() -> Playbook {
        Playbook(
            id: "pb", name: "PB", summary: "s",
            trigger: .manual,
            authority: PlaybookAuthority(capabilities: [.autoOrganization], allowedOutputs: [.brief]),
            completionCondition: "done",
            supportedFlows: [.read, .prepare],
            contextContract: .noContext(identifier: "test.pb"),
            installState: .installed
        )
    }

    private func brief() -> RoutineArtifactDraft {
        RoutineArtifactDraft(type: .brief, title: "b", actor: .system, content: "x")
    }

    private func makeEngine(
        fields: [ContextField],
        contract: ContextBundleContract
    ) -> (SchedulingEngine, InMemoryRoutineArtifactPersister) {
        let artifacts = InMemoryRoutineArtifactPersister()
        let engine = SchedulingEngine(
            playbooks: InMemoryPlaybookStore(seed: [playbook()]),
            context: FixedBundleContext(fields: fields),
            contracts: ContextContractRegistry(contracts: ["pb": contract]),
            operator: FixedOperator(result: RoutineRunResult(outcome: .success, artifact: brief())),
            artifacts: artifacts,
            performance: PerformanceStore()
        )
        return (engine, artifacts)
    }

    @Test
    func satisfiedContractLetsRunProceed() async {
        let (engine, artifacts) = makeEngine(
            fields: [ContextField(key: "wallet", stringValue: "0xabc", dataClass: .publicIdentifier, source: .chainProvider, lastRefreshed: .now)],
            contract: ContextBundleContract(requirements: [
                ContextFieldRequirement(key: "wallet", allowedDataClasses: [.publicIdentifier], maxAge: 3_600, authoritativeSource: .chainProvider, missingFieldBehavior: .fail)
            ])
        )
        let record = await engine.runOnce(playbookID: "pb", trigger: .manual)
        #expect(record.outcome == .success)
        #expect(record.artifactID != nil)
        #expect(await artifacts.latest(limit: 10).count == 1)
    }

    @Test
    func missingRequiredFieldBlocksRun() async {
        let (engine, artifacts) = makeEngine(
            fields: [],
            contract: ContextBundleContract(requirements: [
                ContextFieldRequirement(key: "wallet", allowedDataClasses: [.publicIdentifier], maxAge: 3_600, authoritativeSource: .runtimeHost, missingFieldBehavior: .fail)
            ])
        )
        let record = await engine.runOnce(playbookID: "pb", trigger: .manual)
        #expect(record.outcome == .blocked)
        #expect(record.artifactID == nil)
        #expect(await artifacts.latest(limit: 10).isEmpty)
    }

    @Test
    func disallowedDataClassBlocksRun() async {
        let (engine, _) = makeEngine(
            fields: [ContextField(key: "secret", stringValue: "shhh", dataClass: .sensitive)],
            contract: ContextBundleContract(requirements: [
                ContextFieldRequirement(key: "secret", allowedDataClasses: [.publicIdentifier], maxAge: 3_600, authoritativeSource: .runtimeHost, missingFieldBehavior: .fail)
            ])
        )
        let record = await engine.runOnce(playbookID: "pb", trigger: .manual)
        #expect(record.outcome == .blocked)
    }

    @Test
    func staleFieldBlocksUnlessUseStale() async {
        let stale = ContextField(
            key: "price", stringValue: "1.00", dataClass: .derived, source: .runtimeHost,
            lastRefreshed: Date().addingTimeInterval(-3_600)
        )
        let requirement = ContextFieldRequirement(key: "price", allowedDataClasses: [.derived], maxAge: 60, authoritativeSource: .runtimeHost, missingFieldBehavior: .fail)

        let (blocking, _) = makeEngine(
            fields: [stale],
            contract: ContextBundleContract(requirements: [requirement])
        )
        #expect(await blocking.runOnce(playbookID: "pb", trigger: .manual).outcome == .blocked)

        let (tolerant, _) = makeEngine(
            fields: [stale],
            contract: ContextBundleContract(requirements: [
                ContextFieldRequirement(key: "price", allowedDataClasses: [.derived], maxAge: 60, authoritativeSource: .runtimeHost, missingFieldBehavior: .useStale)
            ], missingFieldBehavior: .useStale)
        )
        #expect(await tolerant.runOnce(playbookID: "pb", trigger: .manual).outcome == .success)
    }

    @Test
    func missingContractFailsClosed() async {
        let engine = SchedulingEngine(
            playbooks: InMemoryPlaybookStore(seed: [playbook()]),
            context: FixedBundleContext(fields: []),
            contracts: ContextContractRegistry(contracts: [:]),
            operator: FixedOperator(result: RoutineRunResult(outcome: .success)),
            artifacts: InMemoryRoutineArtifactPersister(),
            performance: PerformanceStore()
        )

        let record = await engine.runOnce(playbookID: "pb", trigger: .manual)

        #expect(record.outcome == .blocked)
        #expect(record.failureReason == "context contract missing for playbook pb")
    }

    @Test
    func operatorReceivesOnlyApprovedProjection() async {
        let engine = SchedulingEngine(
            playbooks: InMemoryPlaybookStore(seed: [playbook()]),
            context: FixedBundleContext(fields: [
                ContextField(key: "wallet", stringValue: "0xabc", dataClass: .publicIdentifier, source: .runtimeHost, lastRefreshed: .now),
                ContextField(key: "plugin.secret", stringValue: "hidden", dataClass: .sensitive)
            ]),
            contracts: ContextContractRegistry(contracts: [
                "pb": ContextBundleContract(
                    requirements: [
                        ContextFieldRequirement(key: "wallet", allowedDataClasses: [.publicIdentifier], maxAge: 3_600, authoritativeSource: .runtimeHost, missingFieldBehavior: .fail)
                    ],
                    additionalFieldBehavior: .omit
                )
            ]),
            operator: ContextEchoOperator(),
            artifacts: InMemoryRoutineArtifactPersister(),
            performance: PerformanceStore()
        )

        let record = await engine.runOnce(playbookID: "pb", trigger: .manual)

        #expect(record.outcome == .success)
        #expect(record.failureReason == "wallet")
    }

    @Test
    func proceedWithoutFieldOmitsStaleFieldEndToEnd() async {
        let engine = SchedulingEngine(
            playbooks: InMemoryPlaybookStore(seed: [playbook()]),
            context: FixedBundleContext(fields: [
                ContextField(
                    key: "price",
                    stringValue: "1.00",
                    dataClass: .derived,
                    source: .runtimeHost,
                    lastRefreshed: Date().addingTimeInterval(-3_600)
                )
            ]),
            contracts: ContextContractRegistry(contracts: [
                "pb": ContextBundleContract(requirements: [
                    ContextFieldRequirement(
                        key: "price",
                        allowedDataClasses: [.derived],
                        maxAge: 60,
                        authoritativeSource: .runtimeHost,
                        missingFieldBehavior: .proceedWithoutField
                    )
                ])
            ]),
            operator: ContextEchoOperator(),
            artifacts: InMemoryRoutineArtifactPersister(),
            performance: PerformanceStore()
        )

        let record = await engine.runOnce(playbookID: "pb", trigger: .manual)

        #expect(record.outcome == .success)
        #expect(record.failureReason == "")
    }

    @Test
    func rejectUndeclaredFieldBlocksEndToEnd() async {
        let (engine, artifacts) = makeEngine(
            fields: [
                ContextField(key: "wallet", stringValue: "0xabc", dataClass: .publicIdentifier),
                ContextField(key: "unexpected", stringValue: "value", dataClass: .derived)
            ],
            contract: ContextBundleContract(requirements: [
                ContextFieldRequirement(key: "wallet", allowedDataClasses: [.publicIdentifier], maxAge: 3_600, authoritativeSource: .runtimeHost, missingFieldBehavior: .fail)
            ])
        )

        let record = await engine.runOnce(playbookID: "pb", trigger: .manual)

        #expect(record.outcome == .blocked)
        #expect(await artifacts.latest(limit: 10).isEmpty)
    }

    @Test
    func duplicateWorkflowDeclarationsAreRejectedWithoutTrapping() {
        let contract = ContextBundleContract.noContext(identifier: "test.duplicate")
        let registry = ContextContractRegistry(declarations: [
            ContextContractDeclaration(playbookID: "pb", contract: contract),
            ContextContractDeclaration(playbookID: "pb", contract: contract)
        ])

        #expect(registry.contract(for: playbook()) == nil)
        #expect(registry.registrationErrors == [.duplicateWorkflowIdentifier("pb")])
    }

    @Test
    func invalidContractIsRejectedDuringRegistration() {
        let invalid = ContextBundleContract(
            identifier: "",
            requirements: [
                ContextFieldRequirement(key: "wallet", allowedDataClasses: [], maxAge: -1, authoritativeSource: .runtimeHost, missingFieldBehavior: .fail)
            ],
            maximumFutureSkew: -1
        )
        let registry = ContextContractRegistry(contracts: ["pb": invalid])

        #expect(registry.contract(for: playbook()) == nil)
        guard case let .invalidContract(workflowID, violations) = registry.registrationErrors.first else {
            Issue.record("Expected a typed invalid-contract registration error")
            return
        }
        #expect(workflowID == "pb")
        #expect(violations.contains("contract identifier is empty"))
        #expect(violations.contains("maximum future skew cannot be negative"))
        #expect(violations.contains("field “wallet” has no allowed data classes"))
        #expect(violations.contains("field “wallet” has a negative maximum age"))
    }

    @Test
    func invalidExplicitContractCannotFallThroughToDerivedContract() {
        let invalid = ContextBundleContract(identifier: "", requirements: [])
        let registry = ContextContractRegistry(
            contracts: ["pb": invalid],
            derived: { playbook in .noContext(identifier: "derived.\(playbook.id)") }
        )

        #expect(registry.contract(for: playbook()) == nil)
    }
}

@Suite("RoutineOperatorRegistry")
struct RoutineOperatorRegistryTests {
    private func playbook(id: String) -> Playbook {
        Playbook(
            id: id, name: id, summary: "s",
            trigger: .manual,
            authority: PlaybookAuthority(capabilities: [.autoOrganization], allowedOutputs: [.brief]),
            completionCondition: "done",
            supportedFlows: [.read, .prepare],
            contextContract: .noContext(identifier: "test.\(id)"),
            installState: .installed
        )
    }

    /// An operator that stamps its identity into the result's `failureReason` so a test can tell which
    /// operator actually ran without reaching for a shared mutable spy.
    private struct TaggedOperator: RoutineOperator {
        let tag: String
        func run(playbook: Playbook, context: GovernedContext) async -> RoutineRunResult {
            RoutineRunResult(outcome: .success, failureReason: tag)
        }
    }

    private func registry() -> RoutineOperatorRegistry {
        RoutineOperatorRegistry(
            operators: ["music.autoOrganize": TaggedOperator(tag: "music")],
            fallback: TaggedOperator(tag: "fallback")
        )
    }

    private func emptyContext() throws -> GovernedContext {
        try ContextGovernanceBoundary().authorize(
            ContextBundle(fields: []),
            against: .noContext(identifier: "test.routine-operator-registry"),
            at: .now
        ).get()
    }

    @Test
    func dispatchesToRegisteredOperatorByPlaybookID() async throws {
        let result = await registry().run(playbook: playbook(id: "music.autoOrganize"), context: try emptyContext())
        #expect(result.failureReason == "music")
    }

    @Test
    func fallsBackForUnmappedPlaybook() async throws {
        let result = await registry().run(playbook: playbook(id: "research.brief"), context: try emptyContext())
        #expect(result.failureReason == "fallback")
    }

    @Test
    func hasOperatorReflectsRegistration() {
        let registry = registry()
        #expect(registry.hasOperator(forPlaybookID: "music.autoOrganize"))
        #expect(registry.hasOperator(forPlaybookID: "research.brief") == false)
    }
}
