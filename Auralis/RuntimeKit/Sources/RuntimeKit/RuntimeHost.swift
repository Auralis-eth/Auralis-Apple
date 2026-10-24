import ArtifactCore
import AuralisPrimaryModels
import AutopilotCore
import CapabilitiesCore
import EvalCore
import Foundation
import Observation
@_spi(ToolRegistration) import OperatorsFeature
import OSLog
import PerformanceCore
import PlannerCore
import PlaybookCore
import PolicyCore
import ReceiptsCore
@_spi(RuntimeComposition) @_spi(ToolRegistration) import RuntimeCore
import SchedulingCore
import SocialCore

/// Where the host reports a failure it cannot propagate to its caller.
///
/// Distinct from the `bootstrap` category used by ``RuntimeHost/failClosed(violations:)``: these are
/// degraded-but-continuing conditions, not refusals to run.
///
/// Module-scoped rather than file-private so the ritual/social surface in
/// `RuntimeHost+Coordination.swift` reports its own unpropagatable failures here too, instead of
/// growing a second logger for the same type.
let runtimeHostLogger = Logger(subsystem: "com.auralis.runtime", category: "runtime-host")

public protocol RitualRunNotifying: Sendable {
    func notify(ritual: RitualDefinition, status: RuntimeHost.RitualRunStatus) async
}

public struct NoOpRitualRunNotifier: RitualRunNotifying {
    public init() { }
    public func notify(ritual: RitualDefinition, status: RuntimeHost.RitualRunStatus) async { }
}

/// The app-facing runtime host: owns the process-wide governance singletons and the global pause
/// (kill-switch) state, and constructs the one governed pipeline every tool call flows through.
///
/// `@Observable` + `@MainActor` so Mission Control can bind to `isPaused` and the crypto-mode label.
/// The registries/bus are actors (Sendable); the host just holds and vends them.
@MainActor
@Observable
public final class RuntimeHost {
    /// When this process built its first runtime host, used by ``closeAbandonedApprovalSessions()`` to
    /// tell a session stranded by an *earlier* process from one a sibling host in *this* process is
    /// legitimately waiting on.
    ///
    /// Read in `init` rather than at the point of use, and that is the whole reason it is written this
    /// way: a `static let` initialises on first *access*, so reading it only inside the sweep would
    /// stamp it at bootstrap — after a sibling host could already have escalated something, which is
    /// exactly the case it has to exclude. Touching it in `init` pins it to the first host's
    /// construction, and nothing can escalate an approval without a host, so every session this
    /// process opens necessarily starts later.
    ///
    /// Not derived from the OS: `ProcessInfo.systemUptime` measures time since *boot*, which is
    /// earlier than process start and would let a previous process's sessions past the bound.
    static let processLaunchDate = Date()

    /// The actor an autopilot goal run's session is attributed to (P0.5-602). A goal run is the
    /// workflow itself acting, not a person and not the planning model — the model actor is recorded on
    /// the planning receipt, and individual steps carry their own actor via `AutopilotStepExecutor`.
    /// Shares the `"autopilot"` identifier with that executor so the two agree.
    static let autopilotActor = ActorRef(kind: .workflow, identifier: "autopilot")

    /// The actor a shell context refresh or memory touch is attributed to (P0.5-602). The Aura shell
    /// rebuilding its own home-context snapshot is the shell workflow acting, not the person who
    /// happened to open a tab. Named rather than `ActorRef.system` because `.system` is byte-identical
    /// to the legacy-migration fallback in `AgentSession.init(from:)`, which would leave a context
    /// refresh indistinguishable from a row written before attribution existed.
    public static let shellContextActor = ActorRef(kind: .workflow, identifier: "shell.context")

    /// Instance access to ``shellContextActor``. Shell callers reach the host through
    /// `RuntimeAssembly` and import neither RuntimeKit nor RuntimeCore, so they cannot name
    /// `RuntimeHost` or `ActorRef` to attribute an instrumentation call; this lets them pass the
    /// named actor off the host value they already hold.
    public var shellContextActor: ActorRef { Self.shellContextActor }

    public let eventBus: RuntimeEventBus
    public let eventCheckpointStore: any RuntimeEventCheckpointStoring
    public let contextRecorder: RuntimeContextRecorder
    private let toolRegistry: ToolRegistry
    public let checkRegistry: DeterministicCheckRegistry
    public let leaseRegistry: CapabilityLeaseRegistry
    public let approvalRegistry: ApprovalRegistry
    public let receiptSink: ReceiptStoreSink
    public let pauseGate: PauseGate
    public let sessionStore: any AgentSessionStoring
    public let playbookStore: any PlaybookStore
    public private(set) var playbookPersistenceError: String?
    /// Why ``bootstrap()`` refused to vouch for the registries, when it did. Observable so Mission
    /// Control can explain a runtime that is paused for a governance-integrity reason rather than
    /// because a person pressed the kill switch. `nil` on a healthy host; see ``failClosed(violations:)``.
    public private(set) var bootstrapFailureReason: String?
    /// A receipt write failed. Observable so Mission Control can surface degraded audit evidence instead
    /// of presenting an execution as fully receipted when durable persistence was unavailable.
    ///
    /// **Sticky.** A later receipt succeeding does not clear this, because it does not bring the
    /// missing one back: the gap in the ledger is permanent, so the signal has to be too. This
    /// previously reset to `nil` on every successful append, which meant the banner vanished as soon
    /// as any unrelated receipt was written and the run went back to presenting itself as fully
    /// evidenced. Cleared only by ``acknowledgeReceiptPersistenceFailure()`` — a person saying they
    /// have seen it — or by ``resetAllHistory()``, after which the history it describes is gone.
    public private(set) var receiptPersistenceError: String?

    /// How many receipts have failed to persist since the last acknowledgement or reset, so the
    /// banner can say how much evidence is missing rather than only that some is.
    public private(set) var missingReceiptCount: Int = 0
    public let artifactStore: any ArtifactStore
    public let performanceStore: any PerformanceStoring
    public let schedulingEngine: SchedulingEngine
    public let worklogStore: any WorklogStoring
    private let worklogRecorder: any WorklogRecording
    /// Graded runs, written on workflow completion and read by the operator report cards.
    public let evalResultStore: any EvalResultStoring
    public let improvementRecommendationStore: any ImprovementRecommendationStoring
    /// Advisory model opinion on run quality. ``NoRubricJudge`` by default, so nothing in the
    /// shipping path depends on inference; see ``RubricJudging``.
    private let rubricJudge: any RubricJudging
    /// Retained solely so ``resetAllHistory()`` can clear them. Both are otherwise consumed by the
    /// collaborators built in `init` (the scheduling engine and the event bus) and read back through
    /// those; a privacy reset needs to reach the stores themselves.
    private let executionRecordStore: any ExecutionRecordStoring
    private let eventHistoryStore: any RuntimeEventHistoryStoring
    /// Shared, multi-actor sessions (P1-SOCIAL-101). Observed by Mission Control's collaboration surface.
    public let sharedSessionStore: SharedSessionStore
    /// Named rituals composed from installed playbooks (P1-SOCIAL-102).
    public let ritualStore: RitualStore
    /// Durable Social v1 sync event log and pending outbound queue.
    public let socialEventLogStore: SocialEventLogStore
    /// The durable backings of the three coordination stores, for quarantine health and recovery.
    private let coordinationPersistence: [any SocialPersistenceQuarantining]
    /// A coordination store's durable payload could not be decoded, so it has stopped accepting
    /// writes. Observable so Mission Control can offer the discard that is the only way out.
    ///
    /// Names each affected store and why, because the three fail independently and the instruction
    /// differs: a quarantined ritual backing means enabled-state resets every launch, while a
    /// quarantined event log means the outbound relay queue is not durable. `nil` when every backing
    /// is healthy, and when the host has no quarantinable backing at all. See
    /// ``SocialPersistenceQuarantining``.
    public private(set) var coordinationPersistenceError: String?
    /// Rituals, shared sessions, and the Social v1 event log (P1-SOCIAL-101/102). The host's public
    /// ritual API in `RuntimeHost+Coordination.swift` delegates here.
    ///
    /// `lazy` because the coordinator takes `self` as its ``RoutineRunning`` and
    /// ``RuntimeDegradationReporting`` collaborators, which `init` cannot express: `self` is not
    /// available until every stored property — including this one — holds a value. The coordinator
    /// keeps both references weakly, so the host still owns it outright and there is no cycle.
    @ObservationIgnored
    lazy var ritualCoordinator: RitualCoordinator = RitualCoordinator(
        rituals: ritualStore,
        sharedSessions: sharedSessionStore,
        socialEventLog: socialEventLogStore,
        playbooks: playbookStore,
        receipts: receiptStore,
        events: eventBus,
        notifier: ritualRunNotifier,
        cryptoMode: cryptoModeProvider,
        routines: self,
        degradation: self
    )
    /// `internal` rather than `private` only so the ritual/social surface in
    /// `RuntimeHost+Coordination.swift` can reach it. Still module-scoped — nothing outside
    /// `RuntimeKit` can see it, and the receipt-writing helpers remain the intended way in.
    let receiptStore: any ReceiptStore
    private let operatorExecutor: OperatorExecutor
    /// Performs cleared ``PolicyControlledAction``s. Defaults to the fail-closed
    /// ``UnconfiguredPolicyActionExecutor`` (which throws rather than fabricate a success, for
    /// tests/previews that never clear a policy action); the app injects a real wallet-backed executor so
    /// an approved Operate action actually signs/submits.
    private let policyActionExecutor: any ToolExecuting
    private let modelRouter: any ModelRouting
    private let modelInferenceClient: any ModelInferring
    /// `internal` for the same reason as ``receiptStore``: the ritual surface lives in
    /// `RuntimeHost+Coordination.swift`.
    let ritualRunNotifier: any RitualRunNotifying

    /// Test seam: pins the planner used by autopilot runs. `nil` uses the default (on-device
    /// ``ModelGoalPlanner`` when available, else ``DeterministicGoalPlanner``). Internal so only
    /// `@testable` tests can make planning deterministic.
    @ObservationIgnored
    var autopilotPlannerOverride: (any GoalPlanning)?

    /// Test seam: pins the per-step inference performer used by autopilot runs. `nil` uses the default
    /// (on-device FoundationModels when available, else a no-inference performer).
    @ObservationIgnored
    var autopilotStepPerformerOverride: (any AutopilotStepPerforming)?

    /// Test seam: additional bootstrap violations, merged with the ones ``performBootstrap()`` detects.
    ///
    /// Every real violation is a registration conflict — a duplicate tool ID, a tool naming a check
    /// nobody registered, a state-changing tool that does not demand a receipt — and the registries
    /// are private and filled from static catalogs, so no composed host can be made to produce one
    /// from the outside. That left ``failClosed(violations:)`` untestable: the runtime's strongest
    /// refusal, and the thing that replaced release-build `precondition`s, had no coverage at all.
    ///
    /// A non-empty value also suppresses the `assertionFailure` in ``failClosed(violations:)``, which
    /// would otherwise trap the process on exactly the behaviour under observation.
    ///
    /// `#if DEBUG` rather than merely `internal`: this is the one seam that can *disable a safety
    /// assertion*, so it should not exist in a shipping binary at all. `internal` would already keep
    /// it unreachable from outside the module, but the release build now cannot express the state
    /// where the assertion is skipped, which is a stronger guarantee than a defaulted-empty property.
    /// Tests build in debug, so their coverage of ``failClosed(violations:)`` is unaffected.
    #if DEBUG
    @ObservationIgnored
    var injectedBootstrapViolations: [String] = []
    #endif
    /// `@Sendable` because ``receiptSink`` is a `Sendable` value that carries the provider across
    /// isolation boundaries. Declaring it here lets the compiler verify what the sink previously had
    /// to assert with `@unchecked Sendable`; `@MainActor` still confines the call itself.
    private let cryptoModeProvider: @MainActor @Sendable () -> CryptoMode
    private let cryptoModeSetter: @MainActor @Sendable (CryptoMode) -> Void
    private var activeIdentityID: String?
    /// Chain scope and context-freshness window for the standard deterministic checks, applied at
    /// ``bootstrap()``. Injectable because these are governance policy, not implementation detail:
    /// they were previously fixed inside `registerStandardChecks()`, so no composition root could
    /// tighten either one.
    private let standardCheckConfiguration: StandardCheckConfiguration
    /// Durable-store preparation that must finish before ``seedRoutineAuthority()`` reads the playbook
    /// catalog. `RuntimeHost.persistent(...)` supplies the system-playbook seed here; `nil` means
    /// nothing to prepare. Awaited inside ``bootstrap()`` rather than run as a detached task, because
    /// the authority seed's result depends on it having completed.
    private let playbookPreparation: (@Sendable () async throws -> Void)?
    /// Durable backing for the kill switch, read in ``bootstrap()`` and written by
    /// ``applyPause(_:reason:origin:)`` for operator flips only. `nil` keeps the pause process-local;
    /// see ``RuntimeGovernanceOptions/pauseStateStore``.
    private let pauseStateStore: (any RuntimePauseStateStoring)?
    /// Reused rather than constructed per receipt: `ISO8601DateFormatter` is not cheap to create, and
    /// an instance property confines this one to the host's `@MainActor` isolation — as static
    /// storage a non-`Sendable` reference type would be unprotected global state.
    @ObservationIgnored
    private let timestampFormatter = ISO8601DateFormatter()
    /// Makes "one run at a time per correlation ID" an enforced property of the runtime rather than a
    /// promise its callers were asked to keep. Acquired by the four governed entry points; see
    /// ``CorrelationGate`` for what was reachable without it and why `runAutopilotGoal` is excluded.
    @ObservationIgnored
    private let correlationGate = CorrelationGate()
    /// The one in-flight (or completed) bootstrap. Concurrent callers await *this* rather than
    /// checking a flag, so a second caller cannot observe a half-registered registry; see
    /// ``bootstrap()``.
    @ObservationIgnored
    private var bootstrapTask: Task<Void, Never>?

    /// The eval/performance observer of the event bus, subscribed in ``bootstrap()`` and held for the
    /// host's lifetime so planner-run health keeps flowing into ``performanceStore`` (P0.5-302).
    @ObservationIgnored
    private var performanceObserver: RuntimePerformanceObserver?

    /// Receipts governance-only events that do not pass through the governed tool receipt sink.
    @ObservationIgnored
    private var receiptObserver: RuntimeReceiptObserver?

    /// Global kill switch. When paused, the pipeline refuses to start new governed work. (P1-204)
    /// Set through ``setPaused(_:reason:)`` so the observable state and the pipeline's gate stay in sync.
    ///
    /// Starts `false` and is restored from ``RuntimeGovernanceOptions/pauseStateStore`` in
    /// ``bootstrap()``, so read it only after bootstrapping — which every governed entry point now
    /// awaits. It was previously process memory only, which made the switch weaker than it reads;
    /// see ``RuntimePauseStateStoring``.
    public private(set) var isPaused: Bool = false

    /// Why operator activity is currently paused, surfaced by Mission Control alongside the resume
    /// control. `nil` when not paused. (P1-204)
    public private(set) var pauseReason: String?

    /// The pause state that has been *requested*, updated synchronously by ``setPaused(_:reason:)``
    /// before it awaits the gates. ``isPaused`` cannot serve as the de-duplication guard any more:
    /// it is now published only after enforcement is in place, so two concurrent flips would both
    /// pass a guard written against it.
    @ObservationIgnored
    private var requestedPause: Bool = false

    /// The most recent pause flip. A new flip chains onto it rather than racing it; see
    /// ``setPaused(_:reason:)``.
    @ObservationIgnored
    private var pauseTask: Task<Void, Never>?

    /// The crypto posture label for the Mode Surface (crypto-scoped; the rest of the app is full CRUD).
    public var cryptoMode: CryptoMode { cryptoModeProvider() }
    public var cryptoModeLabel: String { cryptoMode.rawValue }

    /// - Parameters:
    ///   - receiptStore: The append-only ledger. The one dependency with no sensible default: a
    ///     runtime that cannot write receipts cannot do the thing this runtime is for.
    ///   - stores: Durable trace storage. See ``RuntimeHostStores``.
    ///   - coordination: The `UserDefaults`-backed human-coordination stores. See
    ///     ``RuntimeCoordinationStores``.
    ///   - models: Model routing, inference, and the advisory rubric judge. See ``RuntimeModelStack``.
    ///   - operators: What performs work. See ``RuntimeOperatorStack``.
    ///   - governance: Launch pause, check scope, and store preparation. See
    ///     ``RuntimeGovernanceOptions``.
    ///   - identity: Live hooks into app-shell state. See ``RuntimeIdentityHooks``.
    ///
    /// Grouped rather than flat; see `RuntimeHostConfiguration.swift` for why thirty parameters
    /// became six. `RuntimeHost(receiptStore:)` is unaffected.
    public init(
        receiptStore: any ReceiptStore,
        stores: RuntimeHostStores = RuntimeHostStores(),
        coordination: RuntimeCoordinationStores = RuntimeCoordinationStores(),
        models: RuntimeModelStack = RuntimeModelStack(),
        operators: RuntimeOperatorStack = RuntimeOperatorStack(),
        governance: RuntimeGovernanceOptions = RuntimeGovernanceOptions(),
        identity: RuntimeIdentityHooks = RuntimeIdentityHooks()
    ) {
        let artifactStore = stores.artifactStore
        let playbookStore = stores.playbookStore
        let performanceStore = stores.performanceStore
        let executionRecordStore = stores.executionRecordStore
        let worklogStore = stores.worklogStore
        let evalResultStore = stores.evalResultStore
        let improvementRecommendationStore = stores.improvementRecommendationStore
        let sessionStore = stores.sessionStore
        let eventHistoryStore = stores.eventHistoryStore
        let eventCheckpointStore = stores.eventCheckpointStore
        let capabilityLeaseStore = stores.capabilityLeaseStore
        let contextRecorder = stores.contextRecorder
        let sharedSessionStore = coordination.sharedSessionStore
        let ritualStore = coordination.ritualStore
        let socialEventLogStore = coordination.socialEventLogStore
        let coordinationPersistence = coordination.quarantinablePersistence
        let modelRouter = models.modelRouter
        let modelInferenceClient = models.modelInferenceClient
        let rubricJudge = models.rubricJudge
        let operatorDataSource = operators.operatorDataSource
        let routineOperators = operators.routineOperators
        let routineOperatorFallback = operators.routineOperatorFallback
        let policyActionExecutor = operators.policyActionExecutor
        let ritualRunNotifier = operators.ritualRunNotifier
        let initialPauseReason = governance.initialPauseReason
        let standardCheckConfiguration = governance.standardCheckConfiguration
        let playbookPreparation = governance.playbookPreparation
        let pauseStateStore = governance.pauseStateStore
        let activeIdentityProvider = identity.activeIdentityProvider
        let cryptoModeProvider = identity.cryptoModeProvider
        let cryptoModeSetter = identity.cryptoModeSetter

        // Forces ``processLaunchDate`` to initialise now, at the first host's construction, rather
        // than lazily at first read inside `closeAbandonedApprovalSessions()`. See that property.
        _ = Self.processLaunchDate
        let initiallyPaused = initialPauseReason != nil
        self.eventBus = RuntimeEventBus(historyStore: eventHistoryStore)
        self.eventCheckpointStore = eventCheckpointStore
        self.contextRecorder = contextRecorder
        self.toolRegistry = ToolRegistry()
        self.checkRegistry = DeterministicCheckRegistry()
        self.leaseRegistry = CapabilityLeaseRegistry(store: capabilityLeaseStore)
        self.approvalRegistry = ApprovalRegistry()
        self.pauseGate = PauseGate(paused: initiallyPaused)
        self.receiptStore = receiptStore
        self.artifactStore = artifactStore
        self.worklogStore = worklogStore
        self.worklogRecorder = EvidenceReportingWorklogRecorder(base: worklogStore, events: eventBus)
        self.evalResultStore = evalResultStore
        self.improvementRecommendationStore = improvementRecommendationStore
        self.rubricJudge = rubricJudge
        self.executionRecordStore = executionRecordStore
        self.eventHistoryStore = eventHistoryStore
        self.sessionStore = sessionStore
        self.sharedSessionStore = sharedSessionStore
        self.ritualStore = ritualStore
        self.socialEventLogStore = socialEventLogStore
        self.coordinationPersistence = coordinationPersistence
        self.modelRouter = modelRouter
        self.modelInferenceClient = modelInferenceClient
        self.ritualRunNotifier = ritualRunNotifier
        self.policyActionExecutor = policyActionExecutor
        self.standardCheckConfiguration = standardCheckConfiguration
        self.playbookPreparation = playbookPreparation
        self.pauseStateStore = pauseStateStore
        self.activeIdentityID = activeIdentityProvider()
        self.cryptoModeProvider = cryptoModeProvider
        self.cryptoModeSetter = cryptoModeSetter
        self.receiptSink = ReceiptStoreSink(
            store: receiptStore,
            artifactStore: artifactStore,
            eventBus: eventBus,
            sessionStore: sessionStore,
            modeProvider: cryptoModeProvider
        )
        self.isPaused = initiallyPaused
        self.pauseReason = initialPauseReason
        self.requestedPause = initiallyPaused
        let resolvedPlaybookStore = playbookStore ?? InMemoryPlaybookStore(seed: SystemPlaybooks.all)
        let resolvedPerformanceStore = performanceStore ?? PerformanceStore()
        self.playbookStore = resolvedPlaybookStore
        self.performanceStore = resolvedPerformanceStore
        self.schedulingEngine = SchedulingEngine(
            playbooks: resolvedPlaybookStore,
            context: DefaultContextProvider(),
            contracts: SystemPlaybookContracts.registry,
            operator: RoutineOperatorRegistry(
                operators: routineOperators,
                fallback: routineOperatorFallback
            ),
            artifacts: ArtifactStoreRoutineArtifactPersister(store: artifactStore),
            performance: resolvedPerformanceStore,
            executionRecords: executionRecordStore,
            // Scheduled work resolves a real grant and writes a real trace, same as interactive work.
            // Both were previously absent: routine runs recorded `.policyDefault` because no registry
            // was reachable, and wrote no worklog at all. Standing leases for installed playbooks are
            // seeded in `seedRoutineAuthority()`.
            leaseRegistry: leaseRegistry,
            worklog: worklogRecorder,
            initiallyPaused: initiallyPaused
        )
        self.operatorExecutor = OperatorExecutor(
            artifactStore: artifactStore,
            dataSource: operatorDataSource,
            modelRouter: modelRouter,
            modelInferenceClient: modelInferenceClient
        )
    }

    /// Registers built-in operators, policy-action tools, and the standard deterministic checks
    /// (idempotent). Call once before first use.
    ///
    /// Concurrent callers all await the *same* bootstrap rather than testing a flag. A `didBootstrap`
    /// Bool set before the first `await` let a second caller through while registration was still in
    /// flight: it saw "already bootstrapped", returned, and then queried an empty registry — which
    /// surfaced as a spurious `Unknown operator` block or an empty Mission Control tool catalog on
    /// cold start, where two surfaces commonly race to be first.
    public func bootstrap() async {
        if let bootstrapTask {
            await bootstrapTask.value
            return
        }
        // Assigned before any suspension point, so a caller arriving during `performBootstrap` finds
        // the task and awaits completion instead of proceeding.
        //
        // The `-> Void` is load-bearing despite what `redundant_void_return` reads it as: the body's
        // last expression is `self?.performBootstrap()`, whose value is `()?`, so without the
        // annotation this infers `Task<()?, Never>` and no longer matches `bootstrapTask`.
        // swiftlint:disable:next redundant_void_return
        let task = Task { @MainActor [weak self] () -> Void in
            await self?.performBootstrap()
        }
        bootstrapTask = task
        await task.value
    }

    private func performBootstrap() async {
        // The kill switch before anything else, so a durable pause is in force before this method
        // seeds standing authority or the routine entry points below start work.
        await rehydratePauseState()
        // Durable stores first: `seedRoutineAuthority()` below reads the playbook catalog, so a
        // detached seed would race it and grant standing authority for an empty catalog.
        if let playbookPreparation {
            do {
                try await playbookPreparation()
            } catch {
                reportPlaybookPersistenceError(error)
            }
        }
        // Registration problems are collected rather than trapped one at a time, so a single launch
        // reports every violation instead of only the first.
        #if DEBUG
        var violations: [String] = injectedBootstrapViolations
        #else
        var violations: [String] = []
        #endif
        let operatorConflicts = await toolRegistry.registerOperators()
        if !operatorConflicts.isEmpty {
            violations.append("Conflicting operator tool IDs: \(operatorConflicts.map(\.id))")
        }
        for tool in PolicyActionCatalog.tools {
            let result = await toolRegistry.register(tool)
            if !result.succeeded {
                violations.append("Conflicting policy tool ID: \(tool.id)")
            }
        }
        // Conflicts are a bootstrap failure, not a warning: three check sets register onto one
        // registry, and a silently-replaced governance check would still report a pass to every tool
        // that required the original ID.
        var checkConflicts = await checkRegistry.registerStandardChecks(standardCheckConfiguration)
        checkConflicts += await checkRegistry.registerPolicyToolChecks(standardCheckConfiguration)
        checkConflicts += await checkRegistry.registerSchemaChecks()
        if !checkConflicts.isEmpty {
            violations.append("Conflicting deterministic check IDs: \(checkConflicts)")
        }
        for tool in await toolRegistry.allTools {
            for checkID in tool.requiredCheckIDs where await checkRegistry.check(id: checkID) == nil {
                violations.append("Tool \(tool.id) requires unregistered deterministic check \(checkID)")
            }
            if tool.impact != .readOnly, !tool.requiresReceipt {
                violations.append("State-changing tool \(tool.id) must require a receipt")
            }
            // A tool may not declare an impact *below* the floor its capability implies. Without
            // this the invariant lived only in `OperatorCatalogContractTests`, which covers the four
            // catalog operators and nothing else — so a policy or music tool registering
            // `.approveSpending` at `.readOnly` would sail past bootstrap and reach the approval
            // surface describing itself as harmless. `ToolRegistry.register` validates
            // `definitionProblems` only, which is shape, not authority. Checked here because this
            // loop already exists for exactly this class of cross-cutting registration invariant,
            // and failing closed at bootstrap is what makes it structural rather than test-only.
            //
            // Note this is `minimumImpact`, the capability's *floor* — not `defaultImpact`, which is
            // the impact an execute-style call would carry. Using the latter here would reject
            // legitimate read-only `runPlugin` tools.
            if tool.impact < CapabilityImpactMapping.minimumImpact(for: tool.capability) {
                violations.append(
                    "Tool \(tool.id) declares impact \(tool.impact.rawValue), below the "
                        + "\(CapabilityImpactMapping.minimumImpact(for: tool.capability).rawValue) floor "
                        + "for capability \(tool.capability.rawValue)"
                )
            }
        }
        if !violations.isEmpty {
            await failClosed(violations: violations)
        }
        // Wire the eval/performance observer onto the event bus so planner-run health surfaces
        // alongside tool-call health (P0.5-302). `start()` registers its subscription synchronously
        // before returning, so bootstrapping before the first planner run cannot miss its events.
        let observer = RuntimePerformanceObserver(
            events: { [eventBus, eventCheckpointStore] in
                await eventBus.reliableEvents(
                    subscriberID: RuntimePerformanceObserver.subscriberID,
                    checkpointStore: eventCheckpointStore
                )
            },
            store: performanceStore,
            checkpointStore: eventCheckpointStore
        )
        await observer.start()
        performanceObserver = observer
        let receiptObserver = RuntimeReceiptObserver(
            events: { [eventBus, eventCheckpointStore] in
                await eventBus.reliableEvents(
                    subscriberID: RuntimeReceiptObserver.subscriberID,
                    checkpointStore: eventCheckpointStore
                )
            },
            store: receiptStore,
            publisher: eventBus,
            checkpointStore: eventCheckpointStore,
            // The live posture, so a governance receipt written in Assist or Operate does not claim
            // Observe. Read through the provider rather than captured as a value because the mode
            // can change while the observer is running.
            modeProvider: { [cryptoModeProvider] in cryptoModeProvider().receiptMode },
            // A capability grant/revocation/expiry receipt that cannot be written raises the same
            // degraded-evidence banner as a failed host receipt. This observer is the only writer of
            // those, so without the hop they were lost with nothing on screen.
            failureReporter: { [weak self] correlationID in
                await self?.noteReceiptPersistenceFailure(
                    // The event's own trace when it has one, so the gap sits in the run whose
                    // authority went unrecorded rather than in a bucket of its own.
                    correlationID: correlationID ?? "runtime.capability",
                    goal: "Runtime governance audit",
                    actor: RuntimeReceiptObserver.actor
                )
            }
        )
        await receiptObserver.start()
        self.receiptObserver = receiptObserver
        // Once per launch, and deliberately not conditional on the relay being enabled; see
        // ``pruneCoordinationHistory(now:policy:)``. Awaited rather than detached because it is a
        // single snapshot read with no ordering dependency, and the codebase prefers a bounded
        // await to an unobservable background race.
        await pruneCoordinationHistory()
        // After the prune, because that is what forces the event log to attempt its load.
        await refreshCoordinationPersistenceHealth()
        // Before any new work can raise an approval of its own, which is what makes the sweep's
        // reasoning sound; see ``closeAbandonedApprovalSessions()``.
        await closeAbandonedApprovalSessions()
        // Not seeded on a host that failed closed. A runtime that cannot verify its own registration
        // has no business *creating* authority: the bulk seed mints a 24-hour standing lease per
        // capability per installed playbook, so Mission Control's active-grants list would show
        // authority nobody asked for, issued by a runtime that had just refused to vouch for itself.
        //
        // Only the seed is skipped, not the observers or the prune above: those record and maintain,
        // they do not grant, and a paused runtime still wants its audit observers attached. Nothing
        // is broken by skipping it either — ``runRoutine(id:trigger:actor:correlationID:)`` re-grants
        // standing authority for the run's own actor before every run, so the leases would be minted
        // on the spot if the pause were ever lifted. It cannot be: ``setPaused(_:reason:)`` refuses to
        // lift a governance-integrity pause, which is what makes skipping this free.
        guard bootstrapFailureReason == nil else { return }
        await seedRoutineAuthority()
    }

    /// Restores a pause a person set in an earlier process, before any governed work can start.
    ///
    /// Applied the way ``initialPauseReason`` is — gates closed, observable state set, **no receipt
    /// and no event** — because remaining paused is not a new governance act. The ledger already
    /// carries the `runtime.paused` receipt from the flip that caused this; receipting the rehydration
    /// would add a pause decision per launch that nobody made. Same reasoning as the comment on
    /// ``enqueuePauseFlip(_:reason:origin:)``: a host that starts paused writes no pause receipt.
    ///
    /// Only ever *applies* a pause, never lifts one. A stored `isPaused: false` is deliberately
    /// ignored: by the time this runs, ``initialPauseReason`` may already have paused the host because
    /// the storage container failed to open, and a stale "not paused" from a previous healthy launch
    /// must not resume a runtime whose artifacts cannot be written. Resuming is a person's decision,
    /// through ``setPaused(_:reason:)``.
    private func rehydratePauseState() async {
        guard let pauseStateStore,
              let durable = await pauseStateStore.load(),
              durable.isPaused else { return }
        // Already paused for a cause resolved *this* launch (storage unavailable, or a launch-time
        // pause the composition root asked for). That reason is the more actionable one, so it stands.
        //
        // This guard is also what makes setting the gates directly — outside the serialized
        // ``enqueuePauseFlip(_:reason:origin:)`` chain — safe. Going through that chain would receipt
        // the rehydration, which is what must not happen; the cost is that this does not serialize
        // against a concurrent flip. It does not need to, because this only ever *pauses*: a
        // concurrent ``setPaused(true)`` agrees with it, and a concurrent ``setPaused(false)`` can
        // only be in flight once `requestedPause` is `true`, which sends this down the guard above.
        // So the gate and the observable state cannot be left disagreeing, which is the property the
        // chain exists to guarantee.
        guard requestedPause == false else { return }
        requestedPause = true
        await pauseGate.setPaused(true)
        await schedulingEngine.setPaused(true)
        isPaused = true
        pauseReason = durable.reason ?? PauseOrigin.operatorRequest.defaultPauseReason
    }

    /// Ends every session a previous process left waiting on an approval that no longer exists.
    ///
    /// ``ApprovalRegistry`` is deliberately process-local and fail-closed: pending approvals are not
    /// persisted, so nothing that was awaiting one survives relaunch. ``finishSession(correlationID:conclusion:)``
    /// is right to leave an escalated run open — the run is genuinely unfinished, and marking it
    /// terminal would claim an outcome nobody reached — but nothing ever closed it afterwards either.
    /// A person who opened the Approval Inbox, did not answer, and relaunched kept a session reading
    /// as live in Mission Control's active list permanently, waiting on authority that had already
    /// been dropped.
    ///
    /// Run at ``bootstrap()``, *before this host's* own governed entry points can escalate anything
    /// new, so it cannot end a session whose approval this host is about to raise. That ordering is
    /// necessary but **not sufficient**, because it says nothing about the other host in the process —
    /// which is what the launch-date bound below is for. An earlier draft of this method claimed
    /// "the registry is empty at bootstrap, so every waiting session is stranded"; that premise is
    /// false here and the bound is what replaces it. Stated plainly because a future reader who
    /// believes the old premise would see the bound as redundant and remove it.
    ///
    /// Blocked rather than failed: the run did not go wrong, it was never authorized. Deliberately
    /// **no receipt** — the same reasoning as ``rehydratePauseState()``. The ledger already carries the
    /// `needsApproval` receipt from the escalation, and nothing new happened here; the approval simply
    /// went unanswered. Writing one per stranded session at every launch would add governance records
    /// for a non-event, on the path `bootstrap()` awaits.
    ///
    /// Scoped to sessions that started before this *process* did, which is the part that makes it
    /// safe rather than destructive. "Waiting at bootstrap ⇒ stranded" is only true of one host per
    /// process, and this app has two: `RuntimeBackgroundScheduler` builds its own `ModelContainer`
    /// and `RuntimeAssembly` keys its host cache on container identity, so a background refresh gets
    /// a second ``RuntimeHost`` over the same session store — with its own empty
    /// ``ApprovalRegistry``, because that registry is per-host. Without this bound, a background wake
    /// while a person had an approval open in Mission Control would close *that* session as
    /// abandoned, terminating a run whose approval was still pending and perfectly resumable. That is
    /// a worse outcome than the stale session this method exists to clear, so the bound is load-bearing.
    ///
    /// A clock moved backwards between launches makes an older session look like it belongs to this
    /// process, so it is spared. That is the fail-safe direction: leaving a dead session open is
    /// recoverable, closing a live one is not.
    ///
    /// - Note: This reads every session, which ``AgentSessionStoring`` offers no bounded or filtered
    ///   form of. Accepted rather than overlooked: sessions are one row per workflow run (orders of
    ///   magnitude fewer than the receipts ``RuntimeReceiptObserver/seedScanLimit`` was cut to bound),
    ///   Mission Control already calls `allSessions()` on every history refresh, and the write half is
    ///   skipped entirely in the overwhelmingly common case of nothing being stranded — so a healthy
    ///   launch pays one read. Narrowing it needs a status-filtered read on the protocol, which for
    ///   the SwiftData store means denormalising `status` out of the JSON blob it lives in today.
    private func closeAbandonedApprovalSessions() async {
        let launchedAt = Self.processLaunchDate
        let stranded = await sessionStore.allSessions().filter {
            $0.status == .waitingForApproval && $0.startedAt < launchedAt
        }
        guard !stranded.isEmpty else { return }
        let reason = "This run was waiting for an approval that did not survive the app closing, so it never ran."
        var closedCount = 0
        for stale in stranded {
            var didClose = false
            await noteRuntimeSession(
                correlationID: stale.correlationID,
                goal: stale.goal,
                // The session's own actor, not a sweep identity: this closes *that* run, and
                // re-attributing it here would rewrite who was acting (P0.5-602). Only reached when
                // the session already exists, so this argument is never the one used.
                actor: stale.actor
            ) { session in
                // Re-checked against the *freshly read* session rather than trusting the scan's
                // snapshot, because the two hosts this process runs can sweep concurrently (see
                // above) and `AgentSession` has no compare-and-set. `end(status:at:)` is already
                // guarded by `endedAt == nil`, so the status could never double-change — but
                // `noteExecutionUpdate` is not, so without this the loser of the race appended a
                // second identical explanation to a session it did not close, and published a
                // duplicate `sessionEnded` for it. Narrowed to the read-modify-write of one session
                // rather than the whole scan; a true simultaneous interleave is still possible and is
                // the residual `AgentSessionStoring` would need a merging upsert to remove.
                guard session.status == .waitingForApproval, session.endedAt == nil else { return }
                session.block(reason: reason)
                didClose = true
            }
            guard didClose else { continue }
            closedCount += 1
            await eventBus.publish(
                WorkflowEventEnvelope(
                    event: .sessionEnded(correlationID: stale.correlationID, status: .blocked),
                    correlationID: stale.correlationID
                )
            )
        }
        guard closedCount > 0 else { return }
        runtimeHostLogger.info(
            "Closed \(closedCount, privacy: .public) session(s) left waiting on approvals that did not survive relaunch."
        )
    }

    /// Refuses to run governed work because ``bootstrap()`` found the registries in a state it cannot
    /// vouch for, and says why.
    ///
    /// These violations — a duplicate tool ID, a tool requiring a check nobody registered, a
    /// state-changing tool that does not demand a receipt — used to be `precondition`s. That is right
    /// in development and wrong in the field: `precondition` is live in release builds, so a
    /// governance-registry problem crashed the app at cold start with no diagnostic a person could
    /// act on. But it must not simply be downgraded to a log either, because every one of these means
    /// the pipeline can no longer prove that a call was checked.
    ///
    /// So the runtime pauses instead. The kill switch already exists for exactly this shape of
    /// problem, ``RuntimeHost/persistent(...)`` already uses it when storage is unavailable, and a
    /// paused runtime refuses new governed work while leaving Mission Control readable and the reason
    /// on screen. ``assertionFailure`` keeps the loud, immediate failure in debug and in tests, where
    /// these are always programming errors and should never be quietly absorbed.
    private func failClosed(violations: [String]) async {
        let detail = violations.joined(separator: "; ")
        // Suppressed only when a test injected the violations; see ``injectedBootstrapViolations``.
        // The release build has no such seam, so the assertion is unconditional there.
        #if DEBUG
        if injectedBootstrapViolations.isEmpty {
            assertionFailure("Runtime bootstrap invariants violated: \(detail)")
        }
        #else
        assertionFailure("Runtime bootstrap invariants violated: \(detail)")
        #endif
        Logger(subsystem: "com.auralis.runtime", category: "bootstrap")
            .fault("Runtime bootstrap invariants violated: \(detail, privacy: .public)")
        bootstrapFailureReason = detail
        let reason = "The governed runtime could not verify its own tool and check registration, so operator activity is paused. \(detail)"
        // Through the same serialized chain as the kill switch, not around it. Setting the gate,
        // the engine, and `isPaused` directly here meant a fail-closed pause could interleave with
        // an in-flight `applyPause` from an operator resume — leaving the gate on one value and the
        // observable state on the other, which is the exact interleaving the chain exists to rule
        // out. Reachable because `bootstrap()` is awaited by Mission Control's own first read, so a
        // person can press resume while this is still deciding.
        await enqueuePauseFlip(true, reason: reason, origin: .governanceIntegrity)
        // A runtime already paused for some other cause does not flip, so `applyPause` never runs
        // and the reason on screen would still describe that earlier cause. State the stronger one:
        // an integrity failure outranks a storage outage or an operator pause, and it is the only
        // one `setPaused(false)` refuses to lift. Redundant when the flip did happen — `applyPause`
        // assigns the same value — which is why it is safe to do unconditionally.
        pauseReason = reason
    }

    /// Reads the coordination stores' persistence health onto ``coordinationPersistenceError``.
    ///
    /// Each store is touched first, and that is the load-bearing part. Quarantine is detected on a
    /// backing's *first* `load()`, which `SharedSessionStore` and `RitualStore` defer until first
    /// access — so polling health alone would report every backing healthy on a launch that had not
    /// yet opened the collaboration surface, and the banner would appear only once a person went
    /// looking. Each touch is one `UserDefaults` read and decode, which is what the stores would do
    /// on first access anyway; doing it here makes the answer complete at bootstrap instead of
    /// eventually.
    ///
    /// Skipped entirely when nothing quarantinable is registered, so a test or preview host with
    /// ephemeral backings pays none of it.
    public func refreshCoordinationPersistenceHealth() async {
        guard !coordinationPersistence.isEmpty else { return }
        _ = await sharedSessionStore.allSessions()
        _ = await ritualStore.all()
        _ = await socialEventLogStore.currentSnapshot()
        var quarantined: [String] = []
        for persistence in coordinationPersistence {
            guard case let .quarantined(reason) = await persistence.persistenceHealth() else { continue }
            quarantined.append("\(persistence.quarantineDisplayName): \(reason)")
        }
        coordinationPersistenceError = quarantined.isEmpty ? nil : quarantined.joined(separator: "; ")
    }

    /// Discards every quarantined coordination payload, returning those stores to writable.
    ///
    /// The escape hatch ``SocialPersistenceQuarantining`` exists for, and it has to be a person's
    /// explicit decision: the discarded bytes may be a readable snapshot from a newer build, so
    /// overwriting them implicitly on the next mutation is exactly what quarantine refuses to do.
    ///
    /// This restores the store's *ability to persist*; it does not recover the unreadable state. The
    /// in-memory stores already hold the empty fallback their hydration produced, so what the next
    /// mutation makes durable is that fallback — for rituals, every ritual disabled. That is the
    /// honest outcome: the previous enabled-state is not decodable by this build, and pretending
    /// otherwise would mean inventing it.
    public func discardQuarantinedCoordinationState() async {
        for persistence in coordinationPersistence {
            await persistence.discardQuarantinedPayload()
        }
        coordinationPersistenceError = nil
    }

    /// Writes any runtime event-checkpoint cursor still held in memory through to durable storage.
    ///
    /// ``PersistentRuntimeEventCheckpointStore`` coalesces its writes to keep steady `UserDefaults`
    /// churn off the event path, which leaves the most recent cursor in memory until the next
    /// interval elapses. Call this at a known-good moment — app backgrounding — so a process that is
    /// then terminated resumes where it left off instead of replaying the tail of the burst.
    /// Harmless on stores with nothing buffered; see ``RuntimeEventCheckpointStoring/flush()``.
    public func flushEventCheckpoints() async {
        await eventCheckpointStore.flush()
    }

    /// Erases every durable trace of what the runtime has done, for the privacy reset (MC-Device-012).
    ///
    /// The runtime's history lives in its own on-disk container (`OperatorRuntimeStorage`), separate
    /// from the app's main model container, so the app-side reset that deletes receipts and wallet
    /// data does not reach it. Without this the worklog, agent sessions, execution records, artifacts,
    /// and event history all survived "delete all local data" — including proposal parameters, planner
    /// rationales, and actor/authority attribution.
    ///
    /// Every store is attempted even if an earlier one fails, and the first error is rethrown
    /// afterwards: a partial failure must not leave the remaining history on disk. Playbooks are
    /// deliberately untouched — the installed catalog is configuration, not a record of activity, and
    /// system playbooks are re-seeded on the next bootstrap regardless.
    ///
    /// The three human-coordination stores are cleared here too. They are `UserDefaults`-backed
    /// rather than SwiftData-backed (see `SocialCorePersistence`), so they sat outside both the app
    /// reset *and* the runtime container this method was written for, and survived "delete all local
    /// data" carrying session titles, shared-context titles, and the CAIP-10 accounts — wallet
    /// addresses — of everyone who took part. Ritual *structure* is spared for the same reason
    /// playbooks are; only its run history goes (``RitualStore/resetRunHistory()``).
    ///
    /// Capability leases are cleared too, which fails closed (the pipeline refuses a capability it
    /// cannot find a grant for). Standing routine authority is *not* re-seeded here: ``bootstrap()``
    /// is memoised, so the ``seedRoutineAuthority()`` it performs will not run again for the life of
    /// this host. It does not need to. ``runRoutine(id:trigger:actor:correlationID:)`` re-grants
    /// standing authority for the run's own actor before every run, so a routine started after a
    /// reset mints the lease it needs on the spot; until then Mission Control correctly shows no
    /// active grants, because there are none.
    public func resetAllHistory() async throws {
        var firstError: Error?

        // Artifacts first, and deliberately not `try` here: it is the only store that can fail, and
        // failing it must not abandon the trace stores below.
        do {
            try await artifactStore.resetAll()
        } catch {
            firstError = error
        }
        await worklogStore.resetAll()
        await evalResultStore.resetAll()
        await improvementRecommendationStore.resetAll()
        await sessionStore.resetAll()
        await executionRecordStore.resetAll()
        await performanceStore.resetAll()
        await eventHistoryStore.resetAll()
        await eventCheckpointStore.resetAll()
        await contextRecorder.resetAll()
        await leaseRegistry.resetAll()
        // Pending approvals go with the leases, and for the same reason: both are authority to act,
        // and a pending approval additionally *carries* the proposal it was raised for — the
        // address, amount, and calldata this method exists to erase. Nothing here is durable, so
        // this is not about surviving relaunch; it is that a reset performed while the app is
        // running previously left those proposals in memory and still executable through
        // ``resumeApprovedProposal(_:)``, so a person could delete all local data and then resume an
        // approval raised before they did. Fails closed — a dropped approval is simply asked again.
        await approvalRegistry.resetAll()
        // Before the three coordination resets, not after, and this ordering is the whole point.
        // A quarantined backing refuses *every* write — including the empty snapshot `reset()`
        // issues — so a privacy reset over a quarantined payload silently left it on disk, together
        // with the `.quarantine` copy the quarantine itself wrote. Two durable copies of the session
        // titles and CAIP-10 accounts this method exists to erase, and nothing reported the failure
        // because the `save` seams are non-throwing. Discarding first removes both keys and returns
        // the stores to healthy, which is what lets the resets below actually take effect.
        await discardQuarantinedCoordinationState()
        await sharedSessionStore.reset()
        await socialEventLogStore.reset()
        await ritualStore.resetRunHistory()

        // Both degraded-evidence banners describe history that no longer exists.
        playbookPersistenceError = nil
        receiptPersistenceError = nil
        missingReceiptCount = 0

        if let firstError {
            throw firstError
        }
    }

    /// Grants the standing capability leases that scheduled work runs under (P0.5-601/602).
    ///
    /// `SchedulingEngine` resolves — and enforces — a real grant for every routine run, and fails
    /// closed. Without these leases no playbook could run at all, so this is what makes the
    /// registry's attachment safe: each installed playbook's declared capabilities are leased to the
    /// routine itself (for automated triggers) and to the person (for manual runs), which is exactly
    /// the pair of actors ``TriggerSource/defaultActor(playbookID:)`` produces.
    ///
    /// Idempotent and renewing: a capability already covered comfortably past `renewalMargin` is left
    /// alone, so repeated calls neither duplicate grants nor let one lapse mid-sweep.
    ///
    /// Wallet-category capabilities are deliberately **excluded** here; see
    /// ``grantStandingAuthority(for:to:duration:renewalMargin:at:includingCryptoCapabilities:)``.
    ///
    /// - Note: This re-grants leases, so revoking an individual routine lease is not durable — the
    ///   next seed restores it. The durable "no" is a restriction (``denyCapability(_:to:reason:)``),
    ///   which `grantingLease` honours ahead of any grant, so a denied capability keeps refusing the
    ///   run even though this re-seeds.
    public func seedRoutineAuthority(
        duration: TimeInterval = 24 * 60 * 60,
        renewalMargin: TimeInterval = 60 * 60,
        at now: Date = .now
    ) async {
        let playbooks: [Playbook]
        do {
            playbooks = try await playbookStore.all()
        } catch {
            reportPlaybookPersistenceError(error)
            return
        }
        for playbook in playbooks where playbook.installState == .installed {
            let routine = ActorRef(
                kind: .scheduledRoutine,
                identifier: playbook.id,
                displayName: playbook.name
            )
            for actor in [routine, ActorRef.human] {
                await grantStandingAuthority(
                    for: playbook,
                    to: actor,
                    duration: duration,
                    renewalMargin: renewalMargin,
                    at: now,
                    includingCryptoCapabilities: false
                )
            }
        }
    }

    /// Ensures `actor` holds a current standing lease for each capability `playbook` declares.
    ///
    /// Separate from the bulk seed because a run's actor isn't always one of the two defaults — a
    /// ritual runs its playbooks as the ritual, an operator run as the operator pack — and the engine
    /// resolves the grant against *the actor that actually runs*. Seeding only the defaults would fail
    /// those runs closed.
    ///
    /// - Parameter includingCryptoCapabilities: Whether wallet-category capabilities may be granted.
    ///   `false` from the launch-time bulk seed, `true` (the default) from the per-run grant in
    ///   ``runRoutine(id:trigger:actor:correlationID:)``.
    ///
    ///   The distinction exists because the bulk seed runs on every ``bootstrap()``, before anyone has
    ///   asked for anything. `onchain.watch` ships installed and declares ``CapabilityID/draftTransaction``,
    ///   which ``CapabilityDomain/isCrypto(_:)`` classifies as wallet — so the seed was minting a
    ///   24-hour standing transaction-drafting lease to the *person* (and to the routine) at every cold
    ///   start, with no user action. Standing policy and `DomainJudge` still gated execution on the
    ///   crypto mode, so nothing could actually sign; but the lease layer is what this app offers as
    ///   least-privilege authority, and a wallet grant sitting in Mission Control's active-grants list
    ///   that nobody requested is not that.
    ///
    ///   Excluding them costs nothing, because it does not disable a single run: `runRoutine` re-grants
    ///   standing authority for the run's own actor immediately before every run, and does so *with*
    ///   crypto capabilities. So `onchain.watch` mints the `draftTransaction` lease it needs on the
    ///   spot, scoped to the run that is actually happening, and it lapses with the rest.
    private func grantStandingAuthority(
        for playbook: Playbook,
        to actor: ActorRef,
        duration: TimeInterval = 24 * 60 * 60,
        renewalMargin: TimeInterval = 60 * 60,
        at now: Date = .now,
        includingCryptoCapabilities: Bool = true
    ) async {
        let horizon = now.addingTimeInterval(renewalMargin)
        for capability in playbook.authority.capabilities {
            guard includingCryptoCapabilities || !CapabilityDomain.isCrypto(capability) else { continue }
            // A denied capability is left alone, and stays refused. `grantingLease` reports nil for a
            // denial as well as for an absent grant, so without this the seed would mint a fresh
            // (correctly inert) lease on every pass — unbounded churn for a capability the operator
            // has already said no to.
            guard await !leaseRegistry.isDenied(capability, to: actor, at: horizon) else { continue }
            // Checked against the horizon rather than `now`: a lease expiring in minutes would
            // otherwise be judged fine here and then lapse partway through the run.
            let existing = await leaseRegistry.grantingLease(
                capability,
                to: actor,
                scope: CapabilityLeaseScope.defaultScope(for: capability),
                at: horizon
            )
            guard existing == nil else { continue }
            await grantCapabilityLease(
                capability: capability,
                grantedTo: actor,
                reason: "Standing authority for “\(playbook.name)”.",
                duration: duration
            )
        }
    }

    /// Runs a `PolicyControlledAction` through the governed pipeline (the unified governance path).
    ///
    /// `payload` carries the concrete operation (message bytes, transaction, …) on the proposal's
    /// parameters so it survives the escalate → approve → ``resumeApprovedProposal(_:)`` round-trip and
    /// the executor that finally runs sees exactly what the user reviewed. High-risk actions escalate for
    /// approval under `DomainJudge`; the real effect happens on resume, not here.
    /// - Parameter actor: Who is attempting the action (P0.5-602). Required: this is the shipping
    ///   policy path, and it previously hardcoded `.human`, so every agent-initiated policy action
    ///   produced a proposal — and therefore a receipt and worklog entry — claiming a person acted.
    /// - Parameter correlationID: The trace this action belongs to, for exactly the reason
    ///   ``runOperator(toolID:request:correlationID:)`` takes one: a caller already inside a workflow
    ///   must file the pipeline's worklog entries under the run that chose this action, or the
    ///   deliberation and the act it authorized split across two ids and surface as two workflows in
    ///   Mission Control. This was hardcoded to a fresh id, which no caller could override.
    ///
    ///   Unreachable from autopilot today — ``AutopilotStepExecutor/operatorToolID(for:)`` maps only
    ///   `.runPlugin`, and that routes to an operator — so nothing currently passes one. It is here
    ///   so the first caller that does dispatch a policy action from inside a plan step has the
    ///   parameter rather than the bug. `nil` mints a new id, which is right for a standalone
    ///   attempt from the policy gate.
    public func runPolicyAction(
        _ action: PolicyControlledAction,
        actor: ActorRef,
        payload: PolicyActionPayload? = nil,
        correlationID: String? = nil
    ) async -> ToolCallOutcome {
        await bootstrap()
        let toolID = PolicyActionCatalog.toolID(for: action)
        guard let tool = await toolRegistry.tool(id: toolID) else {
            return .blocked(reason: "Unknown policy action “\(action.rawValue)”.")
        }
        // A caller-supplied id can collide with another run; a minted one cannot, so the gate costs
        // nothing on the standalone path. See ``CorrelationGate``.
        let resolvedCorrelationID = correlationID ?? UUID().uuidString
        let proposal = ActionProposal(
            actor: actor,
            intent: tool.title,
            capability: tool.capability,
            impact: tool.impact,
            // Carried the same way ``runOperator(toolID:request:correlationID:)`` carries them, and
            // this is not what decides whether the checks run: `BeforeToolCallHook` evaluates
            // `orderedUnion(tool.requiredCheckIDs, proposal.requiredCheckIDs)`, so the tool
            // definition has always supplied them. What it decides is whether the *receipt* can say
            // so — ``ReceiptStoreSink`` renders its "Pass checks:" plan line from the proposal — and
            // omitting them here meant `signMessage`, `approveSpending`, and `draftTransaction`
            // wrote receipts that named none of the checks they had passed, while every operator
            // receipt listed its own. The readable receipt was least informative on the three
            // highest-impact actions in the app.
            requiredCheckIDs: tool.requiredCheckIDs,
            correlationID: resolvedCorrelationID,
            parameters: Self.schemaStamped(payload?.parameters ?? [:])
        )
        return await correlationGate.withLock(resolvedCorrelationID) { [self] in
            await makePipeline(executor: policyActionExecutor).run(toolID: toolID, proposal: proposal)
        }
    }

    /// Runs a registered operator through the governed pipeline with no scope. Read operators
    /// (research, on-chain watch, identity review) execute in Observe and produce an artifact + receipt;
    /// the crypto prepared-action tool is blocked in Observe and escalated in Assist. (P1-701..703)
    ///
    /// An operator whose input schema requires a scope is sent back for revision rather than seeded.
    /// There used to be an `OperatorSpec.defaultParameters` seed here, but it was empty for every
    /// operator in the catalog and could not honestly be anything else: a catalog-constant chain and
    /// address would be *fabricated* scope inside a governed, receipted run, which is worse than a
    /// clean refusal naming the fields it needs.
    public func runOperator(toolID: String) async -> ToolCallOutcome {
        await bootstrap()
        return await runOperator(toolID: toolID, request: OperatorRequest())
    }

    /// Runs a registered operator with an explicit request (query / watchlist / identity). The request
    /// is encoded into the proposal parameters so deterministic checks and the receipt stay reproducible.
    ///
    /// - Parameter correlationID: The trace this run belongs to. Callers that are already *inside* a
    ///   workflow — autopilot clearing a planned step, above all — must pass their own id, or the
    ///   pipeline's worklog entries (`proposed`, `checksEvaluated`, `decided`, `executed`) file under
    ///   a fresh key while the deliberation that chose the step files under the goal's, splitting one
    ///   run across two correlation ids and surfacing the step as a phantom second workflow in
    ///   Mission Control. `nil` mints a new id, which is right only for a standalone run.
    public func runOperator(
        toolID: String,
        request: OperatorRequest,
        correlationID: String? = nil
    ) async -> ToolCallOutcome {
        await bootstrap()
        guard let tool = await toolRegistry.tool(id: toolID) else {
            return .blocked(reason: "Unknown operator “\(toolID)”.")
        }
        if let kind = OperatorCatalog.spec(for: toolID)?.kind {
            switch kind {
            case .research:
                guard request.query?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                    return .blocked(reason: "Research Brief requires a defined query.")
                }
            case .identityReview:
                guard request.identityID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                    return .blocked(reason: "Identity Review requires the active identity.")
                }
            case .onChainWatch, .preparedAction:
                break
            }
        }
        let correlationID = correlationID ?? UUID().uuidString
        // Unconditional, where this used to branch on `request.isEmpty` to substitute a catalog seed.
        // Besides the seed always being empty, `isEmpty` does not consider `playbookID`, so a request
        // carrying only a playbook id took the seed branch and silently dropped it — losing the
        // playbook attribution on exactly the path that was supposed to preserve scope.
        let parameters = request.toParameters()
        let proposal = ActionProposal(
            actor: ActorRef(kind: .operatorAgent, identifier: toolID),
            intent: tool.title,
            capability: tool.capability,
            impact: tool.impact,
            requiredCheckIDs: tool.requiredCheckIDs,
            correlationID: correlationID,
            parameters: Self.schemaStamped(
                parameters,
                artifactType: OperatorCatalog.spec(for: toolID)?.artifactType.rawValue
            )
        )
        // The grant is inside the gate with the run it authorizes: it writes to the same session index
        // the run does, so leaving it outside would reintroduce the race for the one field
        // (`capabilities`) it touches. See ``CorrelationGate``.
        return await correlationGate.withLock(correlationID) { [self] in
            if !tool.impact.requiresConfirmation {
                await grantRequiredLease(for: proposal, reason: "Operator run requested: \(tool.title)")
            }
            return await makePipeline(executor: operatorExecutor).run(toolID: toolID, proposal: proposal)
        }
    }

    /// Declares the record shapes this build writes onto a proposal's parameters, so `receipt.schema`
    /// and `artifact.schema` evaluate a real version rather than taking their pass-when-absent branch.
    ///
    /// A check that only ever sees "nothing declared" enforces nothing — which is how `ens.format`
    /// and `context.fresh` came to be registered but never exercised. For the *schema versions*,
    /// caller-supplied values win, so a proposal replayed from an older build keeps the version it
    /// was built under and is refused here if this build can no longer read it. The freshness
    /// timestamps are the deliberate exception; see the body.
    private static func schemaStamped(
        _ parameters: [String: String],
        artifactType: String? = nil
    ) -> [String: String] {
        var stamped = RecordSchemaKey.currentDeclaration
        if let artifactType {
            stamped[RecordSchemaKey.artifactType] = artifactType
        }
        var merged = stamped.merging(parameters) { _, callerSupplied in callerSupplied }
        // The freshness timestamps are the one exception to caller-wins, because they are the input
        // to a check *about* the caller. `contextRefreshedAt` records when this host gathered the
        // parameters it is about to propose, which is now; a caller that could supply its own would
        // simply assert that its stale context was fresh. `freshnessEvaluatedAt` is not stamped here
        // at all — the governed pipeline stamps it when it actually evaluates the check, so an
        // approval cleared long after it was raised is measured against the moment it was cleared.
        // Stamping both from one instant here is what made `context.fresh` always compute age 0.
        merged[StandardCheckParameterKey.contextRefreshedAt] = String(Date().timeIntervalSince1970)
        merged[StandardCheckParameterKey.freshnessEvaluatedAt] = nil
        return merged
    }

    /// Read-only catalog projection for Mission Control. Registry ownership and mutation stay private.
    public func registeredTools() async -> [ToolDefinition] {
        await bootstrap()
        return await toolRegistry.allTools
    }

    /// P1-701 — Research Brief: bounded, local, read-only research over a query and optional watchlist.
    public func runResearchBrief(query: String, watchlist: [WatchTarget] = []) async -> ToolCallOutcome {
        await runOperator(
            toolID: OperatorCatalog.researchBriefID,
            request: OperatorRequest(query: query, watchlist: watchlist, playbookID: "research.brief")
        )
    }

    /// P1-702 — On-Chain Watch: read-only monitoring of an account/asset that produces a report + alerts
    /// and never executes. A concrete target is required; an empty request fails closed at schema validation.
    public func runOnChainWatch(chain: String = "ethereum", address: String? = nil, ens: String? = nil) async -> ToolCallOutcome {
        guard let address, !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return await runOperator(toolID: OperatorCatalog.onChainWatchID, request: OperatorRequest())
        }
        return await runOperator(
            toolID: OperatorCatalog.onChainWatchID,
            request: OperatorRequest(
                watchlist: [WatchTarget(chain: chain, address: address, ens: ens)],
                playbookID: "onchain.watch"
            )
        )
    }

    /// P1-703 — Identity / Account Review: bounded review scoped to a single identity.
    public func runIdentityReview(identityID: String) async -> ToolCallOutcome {
        let requested = identityID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let active = activeIdentityID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !active.isEmpty,
              requested.caseInsensitiveCompare(active) == .orderedSame else {
            return .blocked(reason: "Identity Review is limited to the active identity.")
        }
        return await runOperator(
            toolID: OperatorCatalog.identityReviewID,
            request: OperatorRequest(identityID: active)
        )
    }

    /// Keeps the identity boundary current when the app shell switches accounts while reusing the
    /// app-lifetime runtime host.
    public func updateActiveIdentity(_ identityID: String?) {
        let normalized = identityID?.trimmingCharacters(in: .whitespacesAndNewlines)
        activeIdentityID = normalized?.isEmpty == false ? normalized : nil
    }

    /// P1-702 — Escalate a prepared, confirm-first on-chain action to the Approval Inbox. This never
    /// executes autonomously: blocked in Observe, escalated for human approval in Assist. `rationale`
    /// is carried as the intent so the approval prompt and receipt explain what is being prepared.
    public func runPreparedAction(chain: String, address: String, rationale: String) async -> ToolCallOutcome {
        await runOperator(
            toolID: OperatorCatalog.preparedActionID,
            request: OperatorRequest(query: rationale, watchlist: [WatchTarget(chain: chain, address: address)])
        )
    }

    /// Resumes a proposal that the operator explicitly approved from Mission Control.
    ///
    /// Approval is converted into the same temporary, actor-scoped capability lease that normal
    /// governed execution requires, then the proposal is rerun through the registry, deterministic
    /// checks, worklog, receipts, and event bus. The only thing skipped is re-escalating the exact
    /// proposal that has already been approved.
    /// Resolving the approval is also what *closes* the session the escalation left waiting, and that
    /// is `GovernedToolPipeline`'s job rather than this method's: it ends the session on every terminal
    /// outcome — `complete()` on the executed path, `fail`/`block` on the refusals — so no extra
    /// bookkeeping belongs here. A session left waiting because the approval was *never* answered is
    /// the case nothing covered; see ``closeAbandonedApprovalSessions()``.
    public func resumeApprovedProposal(_ request: ApprovalRequest) async -> ToolCallOutcome {
        await bootstrap()
        let proposal = request.proposal
        guard let toolID = await approvalRegistry.toolID(for: request) else {
            return .blocked(reason: "Approval is invalid, stale, altered, or already used.")
        }
        return await correlationGate.withLock(proposal.resolvedCorrelationID) { [self] in
            await grantRequiredLease(
                for: proposal,
                reason: "Approved in Mission Control: \(proposal.intent)"
            )
            return await makePipeline(executor: executor(for: toolID)).resumeApproved(request)
        }
    }

    /// Plans `goalText` on autopilot and runs it under the runtime's governance, recording the
    /// planner's deliberation — every option it considered and rejected, and why — plus each executed
    /// step to the shared worklog/receipt trace Mission Control reads. Authorization uses the
    /// RuntimeCore-native ``JudgeStepAuthorizer`` (DomainJudge + the host's deterministic checks), so
    /// state-changing steps stay gated exactly like the rest of the app. Returns the plan and the run
    /// result so a caller can show the plan review alongside what actually happened. (P1-101)
    @discardableResult
    public func runAutopilotGoal(
        _ goalText: String,
        surface: String? = nil,
        correlationID: String = UUID().uuidString
    ) async -> (plan: Plan, result: OrchestrationResult) {
        // Ensure the eval/performance observer (and the rest of the runtime) is subscribed before the
        // first planner event is published, so planner-run health is never dropped (P0.5-302).
        await bootstrap()
        let goal = PlanningGoal(text: goalText, surface: surface ?? correlationID)
        // The kill switch, before a planner exists. This was the one governed entry point it did not
        // reach: ``PauseGate`` is wired into ``makePipeline(executor:)`` and the scheduling engine, so
        // pausing refused `runOperator`, `runPolicyAction`, and routines — while a goal run consulted
        // neither. A paused runtime went on to plan on device, write an `autopilot.planning.model`
        // receipt, perform every read-only and advisory step through real inference, and record
        // `autopilot.step.ran` with `isSuccess: true`. Only steps that happened to map to a governed
        // operator were refused, and then by the pipeline rather than by autopilot.
        //
        // Refused here rather than left to ``JudgeStepAuthorizer``'s gate (which is the defence in
        // depth behind this) because by the time an authorizer sees a step, planning has already run
        // the model. "Paused" has to mean no inference, not merely no executed steps — and this is
        // also the pause ``failClosed(violations:)`` uses, where the runtime cannot prove a call was
        // checked and must not be deliberating at all.
        if isPaused {
            let reason = pauseReason ?? PauseOrigin.operatorRequest.defaultPauseReason
            let message = "Autopilot refused: operator activity is paused. \(reason)"
            // Announced, not silent — the same reasoning as the resume refusal in
            // ``setPaused(_:reason:)``: a run that does nothing and says nothing is
            // indistinguishable from a broken button. Deliberately no receipt: nothing happened, and
            // this ledger records acts rather than attempts that were turned away at the door.
            await eventBus.publish(
                WorkflowEventEnvelope(event: .executionUpdate(message), correlationID: correlationID)
            )
            // An empty plan with the refusal as its summary, so a caller rendering the plan review
            // shows the reason. `OrchestrationResult.isComplete` is false for an empty report set, so
            // no caller can read this as a successful run.
            return (
                plan: Plan(goal: goal, steps: [], summary: message),
                result: OrchestrationResult(plan: Plan(goal: goal, steps: [], summary: message), reports: [])
            )
        }
        let executor = AutopilotStepExecutor(
            receiptStore: receiptStore,
            eventBus: eventBus,
            sessionStore: sessionStore,
            correlationID: correlationID,
            // Live, not a snapshot: a goal run outlives a mode switch. See `modeProvider` there.
            modeProvider: { [cryptoModeProvider] in cryptoModeProvider().receiptMode },
            goal: goal,
            performer: autopilotStepPerformerOverride ?? AutopilotStepPerformers.makeDefault(
                modelRouter: modelRouter,
                modelInferenceClient: modelInferenceClient
            ),
            // Cleared steps whose capability maps to a governed operator run it through the real
            // pipeline (which stamps its own artifact + telemetry receipt). The goal's correlation id
            // goes with it so the pipeline's trace joins this workflow instead of starting its own.
            operatorRunner: { toolID, request, stepCorrelationID in
                await self.runOperator(
                    toolID: toolID,
                    request: request,
                    correlationID: stepCorrelationID
                )
            },
            // A step receipt that cannot be written raises the same degraded-evidence banner and
            // session/bus update as a failed host receipt, instead of vanishing.
            receiptFailureReporter: { [weak self] stepActor in
                await self?.noteReceiptPersistenceFailure(
                    correlationID: correlationID,
                    goal: goalText,
                    actor: stepActor
                )
            }
        )
        let planner = autopilotPlannerOverride ?? makeDefaultAutopilotPlanner()
        let runner = AutopilotRunner(
            planner: planner,
            authorizer: JudgeStepAuthorizer(
                // Same reason as `makePipeline`: the authorizer's default judge is Observe-scoped, so
                // an unpassed mode silently held autopilot to Observe rules in Assist and Operate.
                judge: DomainJudge(cryptoMode: cryptoMode),
                checks: checkRegistry,
                // Defence in depth behind the `isPaused` refusal above: a pause that lands *during* a
                // run stops the remaining steps at the authorizer, rather than letting a plan that
                // started before the kill switch was thrown carry on to completion.
                pauseGate: pauseGate,
                // Name the planner on every proposal it authorizes rather than letting them fall back
                // to the anonymous `"planner"` default (P0.5-602).
                //
                // This is the *installed* planner, which is the best answer available here: the goal
                // has not been planned yet, and a model-backed planner that fails to ground its
                // output writes template steps instead. `AutopilotRunner` therefore rebinds the
                // authorizer via `attributing(to:)` once the deliberation exists, deriving both the
                // proposal actor and the `considered` worklog entry from
                // `PlanDeliberation.plannerActor`. That rebind is what makes the proposal and the
                // reasoning that produced it joinable; this value survives only for a caller that
                // orchestrates without the runner.
                actor: ActorRef(kind: .workflow, identifier: "planner.\(planner.name)"),
                // File step proposals under this run's correlation id, the same key the session,
                // events, and receipts above use. Left unset, the authorizer fell back to
                // `goal.surface` — a screen name shared by every run launched from it — so the
                // proposals the judge evaluated sat in a different trace from the run that made them.
                correlationID: correlationID
                // `requiredCheckIDs` is deliberately left at its empty default, which is a decision
                // and not an oversight. `PlanStepProposal.makeProposal` builds proposals with no
                // `parameters` — a `PlanStep` is a capability plus a title — so every deterministic
                // check would have nothing to read: the address/ENS/chain/schema checks would pass
                // vacuously, and `context.fresh` would fail closed on "missing context timestamp"
                // and block autopilot outright. The judge gates the step here; the checks run for
                // real once a cleared step is routed through `runOperator`/`runPolicyAction`, where
                // the proposal carries stamped parameters. Requiring checks at step level needs
                // `PlanStep` to carry parameters first.
            ),
            executor: executor,
            worklog: worklogRecorder
        )
        await startSession(correlationID: correlationID, goal: goal.text)
        await eventBus.publish(WorkflowEventEnvelope(event: .plannerStarted(goal: goal.text), correlationID: correlationID))
        let result = await runner.run(goal, correlationID: correlationID)
        if let planningTelemetry = result.plan.deliberation.telemetry {
            // A model produced this plan, so attribute the receipt to the model actor and carry the
            // inference provenance (P0.5-602) rather than collapsing it to an anonymous `.system`.
            let planningActor = ActorRef.model(
                identifier: "planner.\(result.plan.deliberation.planner)",
                route: planningTelemetry.route
            )
            await appendRuntimeReceipt(
                ReceiptDraft(
                    category: "autopilot",
                    kind: "autopilot.planning.model",
                    correlationID: correlationID,
                    payload: Self.planningReceiptPayload(
                        planner: result.plan.deliberation.planner,
                        telemetry: planningTelemetry
                    ),
                    actorDetail: planningActor.receiptActorDetail,
                    // Planning is deliberation, not action: no grant is consulted, standing policy
                    // is what permits the model to run at all.
                    authorityDetail: ReceiptAuthorityDetail(source: "policyDefault", reason: "Autopilot planning allowed by standing policy."),
                    mode: cryptoMode.receiptMode,
                    summary: "Autopilot planned “\(goal.text)” with model routing",
                    provenance: "autopilot",
                    isSuccess: true
                ),
                goal: goal.text,
                actor: planningActor,
                telemetry: planningTelemetry,
                executionUpdate: "Planned goal with \(planningTelemetry.route.provider)"
            )
        }
        // Derived once and used for both the planner event and the session's terminal state, so the
        // two cannot disagree about how the run ended.
        let conclusion = Self.conclusion(for: result.result)
        if let failureReason = conclusion.plannerFailureReason {
            await eventBus.publish(
                WorkflowEventEnvelope(event: .plannerFailed(reason: failureReason), correlationID: correlationID)
            )
        } else {
            let selected = result.plan.deliberation.candidates.filter(\.isSelected).count
            let rejected = result.plan.deliberation.candidates.count - selected
            await eventBus.publish(
                WorkflowEventEnvelope(event: .plannerCompleted(selectedCount: selected, rejectedCount: rejected), correlationID: correlationID)
            )
        }
        await finishSession(correlationID: correlationID, conclusion: conclusion)
        return result
    }

    /// How an autopilot run ended.
    ///
    /// Exists because the planner performance signal and the session's terminal state were derived
    /// separately, and only the latter could express failure: ``runAutopilotGoal(_:surface:correlationID:)``
    /// published `.plannerCompleted` unconditionally, and nothing anywhere published
    /// `.plannerFailed`. So ``RuntimePerformanceObserver`` recorded `.success` for the `planner`
    /// bucket on every run — including one where every step was blocked — and Mission Control's
    /// planner health was structurally pinned at 100%.
    enum AutopilotRunConclusion: Equatable {
        case completed
        case failed(reason: String)
        case blocked(reason: String)
        /// The run paused on a step that needs a person's confirmation. Not a planner failure: the
        /// plan is sound and the gate firing is the Observe → Assist → Confirm loop working, the
        /// same reason `onchain.watch` omits `judgeDidNotEscalate` from its outcome spec.
        case awaitingConfirmation

        /// The reason to report on `.plannerFailed`, or `nil` when the run is not a planner failure.
        var plannerFailureReason: String? {
            switch self {
            case .completed, .awaitingConfirmation:
                return nil
            case let .failed(reason), let .blocked(reason):
                return reason
            }
        }
    }

    /// Classifies a finished run. Ordered failure-first to match the orchestrator, which halts at
    /// the first step that does not clear and reports the rest as `.skipped` — so at most one
    /// non-`.ran` terminal status is ever present.
    static func conclusion(for result: OrchestrationResult) -> AutopilotRunConclusion {
        if result.isComplete { return .completed }
        for report in result.reports {
            if case let .failed(reason) = report.status {
                return .failed(reason: reason)
            }
        }
        if let blocked = result.reports.first(where: { $0.status == .blocked }) {
            return .blocked(reason: blocked.authorization.message ?? "Autopilot step blocked")
        }
        if result.pendingConfirmation != nil { return .awaitingConfirmation }
        // `isComplete` is false for an empty report set, so everything else having been ruled out
        // means the planner returned nothing runnable. That is a planning failure, not a silent
        // success, and it is the case a model planner degrades into.
        return .failed(reason: "The planner produced no runnable steps.")
    }

    /// The default autopilot planner: the on-device ``ModelGoalPlanner`` (which itself degrades to the
    /// template planner when the system model is unavailable) when the OS supports it, else the
    /// deterministic planner. Planning stays dependable while gaining real on-device decomposition.
    private func makeDefaultAutopilotPlanner() -> any GoalPlanning {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return ModelGoalPlanner(modelRouter: modelRouter, modelInferenceClient: modelInferenceClient)
        }
        #endif
        return DeterministicGoalPlanner()
    }

    /// Toggles the global kill switch, closing the pipeline's ``PauseGate`` and the scheduling engine
    /// before publishing the new state. `reason` is retained for the paused-state surface so Mission
    /// Control can show *why* activity is paused; when omitted a default operator reason is recorded.
    ///
    /// `async`, and the enforcement is awaited in order, because this is a safety control. Previously
    /// the observable ``isPaused`` flipped synchronously while the gate and the engine were handed to
    /// two detached, unawaited tasks — so Mission Control reported "paused" while governed work could
    /// still start, and a caller had no way to wait for the pause to actually take hold. Gate first in
    /// both directions: pausing is then never announced early, and resuming at worst reports activity
    /// as still paused for a moment, which fails closed.
    ///
    /// Flips are also *serialized* against each other. `requestedPause` de-duplicates repeated
    /// flips of the same value but cannot order opposite ones: two concurrent calls each awaited
    /// `pauseGate` and `schedulingEngine` independently, and Swift actors guarantee no FIFO
    /// ordering, so the gate could settle on one value while the engine and the observable
    /// `isPaused` settled on the other — a kill switch reporting "paused" over an open gate, which
    /// is the very state the awaited ordering above exists to rule out. Chaining means flip N's
    /// enforcement and publication both complete before flip N+1 begins.
    public func setPaused(_ paused: Bool, reason: String? = nil) async {
        // Bootstrap first, like every other governed entry point — and this one *writes* the state
        // whose doc comment states that invariant, so it was the remaining gap. Two things depend on
        // it having run: ``rehydratePauseState()`` has to have applied any durable pause before a flip
        // is compared against `requestedPause`, and `bootstrapFailureReason` has to be populated
        // before the resume refusal below can consult it.
        //
        // Without this, a resume arriving in the window before `performBootstrap()` reached
        // `rehydratePauseState()` was silently swallowed — `requestedPause` was still `false`, so
        // `enqueuePauseFlip` saw no flip to make — and rehydration then paused the host anyway. A
        // person pressed resume, stayed paused, and nothing said why. Fail-safe, but wrong.
        //
        // No cycle: nothing on the bootstrap path calls back into `setPaused`. `rehydratePauseState()`
        // sets the gates directly and ``failClosed(violations:)`` goes through
        // ``enqueuePauseFlip(_:reason:origin:)``, precisely because neither may re-enter here.
        // Memoised, so this costs nothing after the first call.
        await bootstrap()
        // A resume cannot clear a governance-integrity failure. ``failClosed(violations:)`` pauses
        // because the runtime cannot prove a call was checked, and nothing a person does from
        // Mission Control repairs that — only a relaunch that re-registers cleanly does. Without
        // this, the kill switch could lift a pause whose cause was still present, and
        // `bootstrapFailureReason` would sit populated beside a running pipeline.
        if paused == false, let bootstrapFailureReason {
            await eventBus.publish(
                WorkflowEventEnvelope(
                    event: .executionUpdate(
                        "Resume refused: the governed runtime still cannot verify its own tool and check registration. \(bootstrapFailureReason)"
                    )
                )
            )
            return
        }
        await enqueuePauseFlip(paused, reason: reason, origin: .operatorRequest)
    }

    /// Chains a pause flip onto the previous one and awaits its enforcement *and* publication.
    /// The single funnel for every pause transition, so no caller can bypass the ordering.
    ///
    /// De-duplication lives here rather than in ``setPaused(_:reason:)`` because that is not the only
    /// caller. ``failClosed(violations:)`` needs a different ``PauseOrigin`` so it cannot go through
    /// `setPaused`, and it therefore used to skip the guard entirely: a runtime already paused — by a
    /// person during launch, or by ``RuntimeHost/persistent(...)`` when storage is unavailable — took a
    /// second flip to the value it already held, publishing a duplicate "Operator activity paused"
    /// event and writing a duplicate `runtime.paused` receipt into a ledger whose worth is that it
    /// records what actually happened.
    private func enqueuePauseFlip(_ paused: Bool, reason: String?, origin: PauseOrigin) async {
        let needsFlip = requestedPause != paused
        // A governance-integrity failure is recorded even when no flip is needed. The flip *is*
        // redundant — the runtime is already paused, by an operator or by
        // ``RuntimeHost/persistent(...)`` when storage is unavailable — but the runtime being unable
        // to verify its own registration is a distinct governance act, not a repeat of the pause
        // already in force, and it is the strongest refusal this runtime can make.
        //
        // Tying the record to the flip meant that act left nothing in the ledger at all. The
        // storage-unavailable path is the reachable case: `persistent(...)` returns a host with
        // `initialPauseReason` set, so `requestedPause` is already `true` before `bootstrap()` runs,
        // and a subsequent integrity failure was de-duplicated away — no receipt, no event, only an
        // in-memory `pauseReason`. A host that starts paused writes no pause receipt either, so
        // nothing anywhere recorded that governance had failed closed.
        let recordsOnly = needsFlip == false && origin.isGovernanceIntegrity
        guard needsFlip || recordsOnly else {
            // Enforcement for this same value may still be in flight. Returning here without
            // awaiting it told the caller the flip had taken hold while the gate was potentially
            // still open — reintroducing, for the second of two concurrent callers, the very
            // property the awaited ordering below exists to guarantee.
            await pauseTask?.value
            return
        }
        if needsFlip {
            requestedPause = paused
        }
        let previous = pauseTask
        // `-> Void` is load-bearing here for the same reason as in ``bootstrap()``: the trailing
        // `self?.applyPause(...)` produces `()?`, which would infer `Task<()?, Never>`.
        // swiftlint:disable:next redundant_void_return
        let task = Task { @MainActor [weak self] () -> Void in
            await previous?.value
            // Chained even when it only records, so the ledger's ordering of pause decisions
            // matches the order enforcement actually took hold in.
            if needsFlip {
                await self?.applyPause(paused, reason: reason, origin: origin)
            } else {
                await self?.recordPauseDecision(paused, origin: origin)
            }
        }
        pauseTask = task
        await task.value
    }

    /// Who changed the pause state, and therefore how the pause receipt is attributed. A person
    /// pressing the kill switch and the runtime refusing to vouch for its own registries are not
    /// the same act — recording the second as `humanApproval` by `.human` would name a person who
    /// did nothing, on the one surface whose value is that it says who did what (P0.5-602).
    private enum PauseOrigin {
        case operatorRequest
        case governanceIntegrity

        var isGovernanceIntegrity: Bool {
            if case .governanceIntegrity = self { return true }
            return false
        }

        /// Whether a flip from this origin is written through to ``RuntimePauseStateStoring``.
        ///
        /// Only an operator's decision is. The runtime's two self-derived pauses are re-derived on
        /// every launch — the storage-unavailable pause from whether the container opens, the
        /// integrity pause from whether registration succeeds — so persisting either would report a
        /// fault on a later launch that did not have it, and the integrity wording ("could not verify
        /// its own registration") would be a claim about a process that registered cleanly.
        var persistsAcrossLaunches: Bool {
            switch self {
            case .operatorRequest:
                return true
            case .governanceIntegrity:
                return false
            }
        }

        /// The stable key recorded on the pause receipt, so the ledger can be *queried* for
        /// fail-closed events rather than only read. The actor and authority already differ, but
        /// both are free-text columns shared with every other receipt kind.
        var identifier: String {
            switch self {
            case .operatorRequest:
                return "operator"
            case .governanceIntegrity:
                return "governanceIntegrity"
            }
        }

        /// The status line used for both the bus event and the receipt summary.
        ///
        /// The operator wording is unchanged. The integrity wording names the cause, because
        /// otherwise a reader of the ledger cannot tell a kill-switch press from the runtime
        /// refusing to vouch for itself — the two carry very different instructions for whoever
        /// finds them.
        func statusMessage(paused: Bool) -> String {
            switch self {
            case .operatorRequest:
                return paused ? "Operator activity paused" : "Operator activity resumed"
            case .governanceIntegrity:
                // Only ever reached with `paused == true`: nothing resumes on this origin, because
                // an integrity failure is the one pause `setPaused(false)` refuses to lift.
                return "Operator activity paused: the governed runtime could not verify its own registration"
            }
        }

        var actor: ActorRef {
            switch self {
            case .operatorRequest:
                return .human
            case .governanceIntegrity:
                return ActorRef(kind: .workflow, identifier: "runtime.bootstrap")
            }
        }

        var authorityDetail: ReceiptAuthorityDetail {
            switch self {
            case .operatorRequest:
                return ReceiptAuthorityDetail(
                    source: "humanApproval",
                    reason: "Operator toggled the runtime pause state."
                )
            case .governanceIntegrity:
                return ReceiptAuthorityDetail(
                    source: "policyDefault",
                    reason: "Standing policy requires the runtime to fail closed when it cannot verify its own registration."
                )
            }
        }

        var defaultPauseReason: String {
            switch self {
            case .operatorRequest:
                return "Paused by the operator from Mission Control."
            case .governanceIntegrity:
                return "Paused because the governed runtime could not verify its own registration."
            }
        }
    }

    private func applyPause(_ paused: Bool, reason: String?, origin: PauseOrigin) async {
        await pauseGate.setPaused(paused)
        await schedulingEngine.setPaused(paused)
        isPaused = paused
        pauseReason = paused ? (reason ?? origin.defaultPauseReason) : nil
        // Written after the gates are closed and before the decision is receipted, so a process that
        // dies mid-flip has already made the *safe* half of the change durable: the enforcement is in
        // place and the next launch restores it. See ``PauseOrigin/persistsAcrossLaunches``.
        if origin.persistsAcrossLaunches, let pauseStateStore {
            await pauseStateStore.save(RuntimePauseState(isPaused: paused, reason: pauseReason))
        }
        await recordPauseDecision(paused, origin: origin)
    }

    /// Publishes and receipts a pause decision, without touching the gate or the observable state.
    ///
    /// Split out of ``applyPause(_:reason:origin:)`` because the two are not the same concern and do
    /// not always happen together: a governance-integrity failure on an already-paused runtime has
    /// nothing left to enforce but still has to be recorded. See ``enqueuePauseFlip(_:reason:origin:)``.
    private func recordPauseDecision(_ paused: Bool, origin: PauseOrigin) async {
        let message = origin.statusMessage(paused: paused)
        await eventBus.publish(WorkflowEventEnvelope(event: .executionUpdate(message)))
        let actor = origin.actor
        await noteRuntimeSession(correlationID: "runtime.pause", goal: "Operator pause state", actor: actor) { session in
            session.noteExecutionUpdate(message)
        }
        await appendRuntimeReceipt(
            ReceiptDraft(
                category: "runtime",
                kind: paused ? "runtime.paused" : "runtime.resumed",
                // The same key the session above is filed under, so the kill-switch receipt and
                // its session/worklog entries are retrievable as one workflow (P0.5-602).
                correlationID: "runtime.pause",
                payload: ReceiptPayload(values: [
                    "paused": .bool(paused),
                    "origin": .string(origin.identifier)
                ]),
                actorDetail: actor.receiptActorDetail,
                authorityDetail: origin.authorityDetail,
                mode: cryptoMode.receiptMode,
                summary: message,
                provenance: "local",
                isSuccess: true
            ),
            goal: "Operator pause state",
            actor: actor
        )
    }

    public func setCryptoMode(_ mode: CryptoMode) {
        cryptoModeSetter(mode)
    }

    /// Stops a visible workflow from Mission Control by recording a terminal blocked worklog entry,
    /// emitting a runtime event, and appending a durable receipt.
    public func stopWorkflow(correlationID: String, reason: String = "Stopped by operator") async {
        await worklogRecorder.record(
            WorkflowStepLog(
                correlationID: correlationID,
                toolID: nil,
                event: .blocked(reason: reason),
                actor: .human
            )
        )
        await eventBus.publish(
            WorkflowEventEnvelope(
                event: .workflowBlocked(reason: reason),
                correlationID: correlationID
            )
        )
        await noteRuntimeSession(correlationID: correlationID, goal: "Stopped workflow", actor: .human) { session in
            session.block(reason: reason)
        }
        await eventBus.publish(
            WorkflowEventEnvelope(event: .sessionEnded(correlationID: correlationID, status: .blocked), correlationID: correlationID)
        )
        await appendRuntimeReceipt(
            ReceiptDraft(
                category: "runtime",
                kind: "workflow.stopped",
                correlationID: correlationID,
                payload: ReceiptPayload(values: [
                    "reason": .string(reason)
                ]),
                // Matches the `.human` worklog entry recorded above for the same stop.
                actorDetail: ActorRef.human.receiptActorDetail,
                authorityDetail: ReceiptAuthorityDetail(source: "humanApproval", reason: "Operator stopped this workflow."),
                mode: cryptoMode.receiptMode,
                summary: "Workflow stopped",
                provenance: "operator",
                isSuccess: false
            ),
            goal: "Stopped workflow",
            actor: .human
        )
    }

    /// How many recent artifacts the staleness sweep inspects.
    private static let staleArtifactScanLimit = 100
    /// How long a draft artifact may sit before it is considered stale.
    private static let staleArtifactAge: TimeInterval = 24 * 60 * 60
    /// How long an approval may sit pending before it is considered overdue.
    private static let pendingApprovalTimeout: TimeInterval = 30 * 60

    /// Computes event-trigger inputs from durable runtime state so event routines can run from app wiring.
    ///
    /// A failed artifact read reports *no* stale signal, which is the fail-safe direction — an
    /// unreadable store is not evidence that something is stale, and firing a cleanup routine on a
    /// guess is worse than not firing it. But it is indistinguishable from a genuinely clean store,
    /// so the read failure is logged: "my maintenance routine never runs" otherwise has no trace
    /// anywhere, and this is the only reason it would silently stop.
    public func routineEventSignals(now: Date = .now) async -> RoutineEventSignals {
        let artifacts: [Artifact]
        do {
            artifacts = try await artifactStore.latest(limit: Self.staleArtifactScanLimit)
        } catch {
            runtimeHostLogger.error(
                """
                Failed to read artifacts for routine event signals; reporting no stale-artifact \
                signal, so artifact-triggered routines will not fire this pass: \
                \(error.localizedDescription, privacy: .public)
                """
            )
            artifacts = []
        }
        let artifactStaleAt = artifacts
            .filter { $0.approvalState == .draft }
            .map { $0.createdAt.addingTimeInterval(Self.staleArtifactAge) }
            .filter { $0 <= now }
            .max()
        let approvalPendingTooLongAt = await approvalRegistry
            .latestPendingDate(onOrBefore: now.addingTimeInterval(-Self.pendingApprovalTimeout))
            .map { $0.addingTimeInterval(Self.pendingApprovalTimeout) }
        return RoutineEventSignals(
            artifactStaleAt: artifactStaleAt,
            approvalPendingTooLongAt: approvalPendingTooLongAt
        )
    }

    /// Runs every installed routine whose trigger is due. Last-run state comes from durable execution
    /// records; event triggers fire when supplied event signals are active.
    ///
    /// The scan records its own `considered` worklog entry naming every installed routine it weighed
    /// and why each was fired or skipped, under `scanCorrelationID`. Only *runs* leave execution
    /// records, so without this a skipped routine is indistinguishable from one that was never
    /// evaluated — "why didn't my routine run?" had no answer after the fact.
    ///
    /// - Parameter scanCorrelationID: The trace for this scan's deliberation. Defaults to a fresh id
    ///   per scan; each fired routine still gets its own run correlation id.
    public func runDueRoutines(
        now: Date = .now,
        staleSignal: Bool = false,
        approvalPendingSignal: Bool = false,
        scanCorrelationID: String = UUID().uuidString
    ) async {
        await runDueRoutines(
            now: now,
            eventSignals: RoutineEventSignals(
                artifactStaleAt: staleSignal ? now : nil,
                approvalPendingTooLongAt: approvalPendingSignal ? now : nil
            ),
            scanCorrelationID: scanCorrelationID
        )
    }

    public func runDueRoutines(
        now: Date = .now,
        eventSignals: RoutineEventSignals,
        scanCorrelationID: String = UUID().uuidString
    ) async {
        // The scan is a governed entry point like any other, and this is the one the *background*
        // refresh enters through; see the note on ``runRoutine(id:trigger:actor:correlationID:)``.
        await bootstrap()
        let playbooks: [Playbook]
        do {
            playbooks = try await playbookStore.all()
        } catch {
            reportPlaybookPersistenceError(error)
            return
        }
        var candidates: [ConsideredCandidate] = []
        for playbook in playbooks where playbook.installState == .installed {
            let lastRun = await schedulingEngine.latestExecution(forPlaybookID: playbook.id)?.startedAt
            let evaluation = TriggerEvaluator.evaluate(
                playbook.trigger,
                lastRun: lastRun,
                now: now,
                eventSignals: eventSignals
            )
            candidates.append(
                ConsideredCandidate(
                    title: playbook.name,
                    // A playbook can declare several capabilities; the first is the one that
                    // characterises it for the trace. `nil` when it declares none.
                    capability: playbook.authority.capabilities.first,
                    wasSelected: evaluation.isDue,
                    rationale: evaluation.rationale
                )
            )
            let due = evaluation.isDue
            if due {
                // Automated fire: attribute the run to the routine itself (P0.5-602), naming which
                // routine acted rather than leaving a bare `.scheduledRoutine`.
                await runRoutine(
                    id: playbook.id,
                    trigger: triggerSource(for: playbook.trigger),
                    actor: ActorRef(
                        kind: .scheduledRoutine,
                        identifier: playbook.id,
                        displayName: playbook.name
                    )
                )
            }
        }
        // Recorded after the loop so the entry reflects the whole scan, and skipped only when nothing
        // was installed — an empty deliberation would say nothing a reader can use.
        guard !candidates.isEmpty else { return }
        await worklogRecorder.record(
            WorkflowStepLog(
                correlationID: scanCorrelationID,
                toolID: nil,
                event: .considered(candidates),
                // The scan is the runtime's own bookkeeping, not any routine's or the person's.
                actor: ActorRef(kind: .workflow, identifier: "runtime.routineScan")
            )
        )
    }

    /// The mapping now lives in ``PlaybookTriggerMapping``, because it is pure and both this type and
    /// ``RitualCoordinator`` need it — as an instance method here it would have been a reason for the
    /// coordinator to hold a host reference it otherwise does not need.
    private func triggerSource(for trigger: PlaybookTrigger) -> TriggerSource {
        PlaybookTriggerMapping.triggerSource(for: trigger)
    }

    /// Grades a finished workflow against its playbook's declared outcome, once.
    ///
    /// Reads the trace back from ``worklogStore`` rather than accumulating it in memory, so the grade
    /// rests on exactly the evidence that was durably recorded — if a step failed to persist, the eval
    /// must see the same gap a person auditing the trace later would, not a rosier in-memory version.
    ///
    /// Silent no-op when the playbook declares no criteria. Grading an undeclared outcome would mean
    /// inventing expectations on the operator's behalf; an absent spec is a real answer ("nobody said
    /// what success meant here"), and a report card shows it as ungraded rather than as a failure.
    ///
    /// Takes the ``ExecutionRecord`` rather than an id pair because the record is what says *which*
    /// run to grade; see ``trace(ofRun:in:)``.
    private func evaluateCompletedRun(for record: ExecutionRecord) async -> EvalResult? {
        let spec: OutcomeSpec
        do {
            guard let storedSpec = try await playbookStore.playbook(id: record.playbookID)?.outcome else { return nil }
            spec = storedSpec
        } catch {
            reportPlaybookPersistenceError(error)
            return nil
        }
        let trace = Self.trace(
            ofRun: record,
            in: await worklogStore.steps(forCorrelationID: record.correlationID)
        )
        let result = await TraceEvaluator().evaluate(
            spec,
            correlationID: record.correlationID,
            trace: trace,
            playbookID: record.playbookID,
            worklogWasDegraded: await worklogStore.health().isDegraded,
            judge: rubricJudge
        )
        await evalResultStore.record(result)
        return result
    }

    /// The worklog entries belonging to `record` alone, out of every entry filed under its correlation
    /// id.
    ///
    /// A correlation id is not one run, and the grade used to assume it was.
    /// ``RitualCoordinator/runSharedWorkflow(sessionID:playbookID:trigger:actor:)`` files every
    /// playbook a person shares into a session under that session's correlation id, and a
    /// collaborative ritual runs each of its playbooks under one shared id — so from the second run
    /// onward `steps(forCorrelationID:)` returns the earlier runs' trace too. ``TraceEvaluator``
    /// grades every entry it is handed (`playbookID` is only stamped onto the result as a label), so
    /// an unscoped read made each run's grade a function of the ones before it: `research.brief`'s
    /// ``SuccessCriterion/completedWithin(seconds:)`` measures `max(timestamp) - min(timestamp)`
    /// across the trace, so a five-second run shared five minutes after another one failed its
    /// 120-second budget. It masked failures just as readily, because the existential criteria are
    /// satisfied by *any* matching entry: ``SuccessCriterion/producedArtifact`` could be met by an
    /// artifact a different playbook produced, and ``SuccessCriterion/reachedRoutinePhase(_:)`` let a
    /// run that recorded `.failed` inherit a `.completed` it never reached.
    ///
    /// Scoped by the run's own time window, because that is the discriminator these entries actually
    /// carry. The two obvious candidates do not work: ``WorkflowStepLog/workflowRun`` resolves to
    /// `.workflow(id: correlationID, workflowID: nil)` here, which is the correlation id again, and
    /// `toolID` is the *tool* on governed pipeline entries but the *playbook* on routine phases, so
    /// matching it would discard the check and decision entries
    /// ``SuccessCriterion/allDeterministicChecksPassed`` and
    /// ``SuccessCriterion/judgeDidNotEscalate`` are asked about. Carrying the run id on each entry
    /// would fix this at the root, but that reaches `WorkflowStepLog`, `SchedulingEngine`, and the
    /// durable row format.
    ///
    /// The window is closed and exact rather than padded. `SchedulingEngine.runOnce` writes its
    /// terminal phase entry *before* it computes `durationSeconds`, and every exit path goes through
    /// that same `finish`, so `startedAt ... startedAt + durationSeconds` contains all of this run's
    /// entries and none of a later run's. Padding it would reintroduce the leak in miniature.
    ///
    /// - Note: This relies on runs under one correlation id not *overlapping*, which
    ///   ``CorrelationGate`` now enforces: ``runRoutine(id:trigger:actor:correlationID:)`` holds the
    ///   id for the whole run, grading included, so no sibling run can be writing entries into this
    ///   window. It previously rested on the callers ("sharing a playbook is a single tap"), and
    ///   `MissionControlHomeModel.sharePlaybook` has no in-flight guard — two taps produced two
    ///   overlapping windows under one session id, and each run's grade then absorbed the other's
    ///   entries, which is the very leak this scoping exists to close. Dispatching runs concurrently
    ///   *on purpose* still needs the run id carried on each entry. A window that matches nothing
    ///   grades `.inconclusive` rather than passing vacuously, so the failure direction stays honest.
    static func trace(ofRun record: ExecutionRecord, in steps: [WorkflowStepLog]) -> [WorkflowStepLog] {
        let start = record.startedAt
        let end = start.addingTimeInterval(max(0, record.durationSeconds))
        return steps.filter { $0.timestamp >= start && $0.timestamp <= end }
    }

    /// Regenerates deterministic advisory recommendations without overwriting a person's review.
    public func refreshImprovementRecommendations(from cards: [OperatorReportCard]) async {
        let engine = ImprovementRecommendationEngine()
        let existing = await improvementRecommendationStore.allRecommendations()
        var generatedIDs = Set<String>()
        for card in cards {
            for candidate in engine.recommendations(for: card) {
                generatedIDs.insert(candidate.id)
                if await improvementRecommendationStore.recommendation(id: candidate.id) == nil {
                    await improvementRecommendationStore.upsert(candidate)
                }
            }
        }
        for recommendation in existing
        where recommendation.state == .proposed && !generatedIDs.contains(recommendation.id) {
            await improvementRecommendationStore.upsert(
                recommendation.transitioning(to: .superseded, reviewedBy: "adaptive.engine")
            )
        }
    }

    /// Human review gate. Recommendations are descriptive data and cannot change authority here.
    public func reviewImprovementRecommendation(
        id: String,
        accept: Bool,
        reviewedBy: String
    ) async {
        guard !reviewedBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let recommendation = await improvementRecommendationStore.recommendation(id: id),
              recommendation.state == .proposed else { return }
        let state: ImprovementRecommendationState = accept ? .accepted : .rejected
        let updated = recommendation.transitioning(to: state, reviewedBy: reviewedBy)
        await improvementRecommendationStore.upsert(updated)
        await recordRecommendationDecision(updated, selected: accept, action: state.rawValue)
    }

    /// Marks a previously accepted recommendation as applied after the human-controlled change was
    /// performed. This method does not edit capabilities, policy, operators, or playbooks.
    public func markImprovementRecommendationApplied(id: String, reviewedBy: String) async {
        guard let recommendation = await improvementRecommendationStore.recommendation(id: id),
              recommendation.state == .accepted,
              recommendation.reviewedBy == reviewedBy else { return }
        let updated = recommendation.transitioning(to: .applied, reviewedBy: reviewedBy)
        await improvementRecommendationStore.upsert(updated)
        await recordRecommendationDecision(updated, selected: true, action: "applied")
    }

    private func recordRecommendationDecision(
        _ recommendation: ImprovementRecommendation,
        selected: Bool,
        action: String
    ) async {
        let correlationID = "improvement:\(recommendation.id)"
        await worklogRecorder.record(WorkflowStepLog(
            correlationID: correlationID,
            toolID: "adaptiveImprovement",
            event: .considered([ConsideredCandidate(
                title: recommendation.summary,
                wasSelected: selected,
                rationale: "Human \(recommendation.reviewedBy ?? "reviewer") marked recommendation \(action)."
            )]),
            actor: .human
        ))
        await appendRuntimeReceipt(
            ReceiptDraft(
                category: "improvement",
                kind: "improvement.\(action)",
                correlationID: correlationID,
                payload: ReceiptPayload(values: [
                    "recommendationID": .string(recommendation.id),
                    "operatorID": .string(recommendation.operatorID),
                    "state": .string(action)
                ]),
                actorDetail: ActorRef.human.receiptActorDetail,
                authorityDetail: ReceiptAuthorityDetail(
                    source: "humanApproval",
                    reason: "A person reviewed an advisory improvement recommendation."
                ),
                mode: cryptoMode.receiptMode,
                summary: "Improvement recommendation \(action)",
                provenance: "local",
                isSuccess: true
            ),
            goal: "Review adaptive improvement",
            actor: .human
        )
    }

    /// Runs a routine once on demand (P1-601/602 manual trigger), recording an execution record,
    /// a performance event, and a durable receipt for the run.
    @discardableResult
    public func runRoutine(
        id: String,
        trigger: TriggerSource = .manual,
        actor: ActorRef? = nil,
        correlationID: String? = nil
    ) async -> ExecutionRecord {
        // Bootstrap first, for the same reason every other governed entry point does — and this one
        // was the omission that mattered. The routine path was the only way into the runtime that did
        // not bootstrap, and it is the path the *background* refresh takes: `RuntimeBackgroundScheduler`
        // builds a host and calls `runDueRoutines` directly, with no other entry point having run. So
        // on a background wake the receipt observer was never subscribed, and the capability grants
        // this method mints below — via `grantStandingAuthority` — published their
        // `.capabilityLeaseGranted` events into a bus nobody was auditing. The ledger recorded *that*
        // the routine ran and not *what authorized it*, which is the half `RuntimeReceiptObserver`
        // exists to keep. `pruneCoordinationHistory()` and the system-playbook seed were skipped on
        // that path too.
        //
        // Memoised, so this costs nothing after the first call and is safe from the scan above, which
        // bootstraps and then calls this per due playbook.
        await bootstrap()
        // Serialized against any other run under the same id. This is the path that made the
        // "sequential per correlation id" invariant violable: a shared session's playbooks all run
        // under that session's id, and `sharePlaybook` has no in-flight guard, so two taps raced both
        // the session evidence index and the eval trace window. Caller-supplied ids can collide;
        // `nil` mints one the engine owns, so it never contends. See ``CorrelationGate``.
        //
        // The whole body is inside, not just the engine call: `evaluateCompletedRun` reads the
        // worklog back and scopes it by this run's time window (``trace(ofRun:in:)``), so the grade is
        // only sound while no sibling run is writing entries under the same id.
        return await correlationGate.withLock(correlationID ?? UUID().uuidString) { [self] in
            await performRoutine(id: id, trigger: trigger, actor: actor, correlationID: correlationID)
        }
    }

    /// The body of ``runRoutine(id:trigger:actor:correlationID:)``, split out so the gate above wraps
    /// it as one unit. Must not be called directly: it assumes the correlation id is already held.
    private func performRoutine(
        id: String,
        trigger: TriggerSource,
        actor: ActorRef?,
        correlationID: String?
    ) async -> ExecutionRecord {
        // Refresh standing authority for *this* run's actor first: the engine now fails closed, so a
        // lapsed or never-granted lease turns the run into a `.blocked` record rather than simply
        // running unattributed. The actor is resolved the same way the engine resolves it.
        do {
            if let playbook = try await playbookStore.playbook(id: id) {
                await grantStandingAuthority(
                    for: playbook,
                    to: actor ?? trigger.defaultActor(playbookID: id)
                )
            }
        } catch {
            reportPlaybookPersistenceError(error)
        }
        let record = await schedulingEngine.runOnce(
            playbookID: id,
            trigger: trigger,
            actor: actor,
            correlationID: correlationID
        )
        // The record owns the resolved id, so the receipt and the run's worklog steps are filed under
        // one key rather than each deriving their own.
        let receiptCorrelationID = record.correlationID
        // Grade the run now the trace is complete, and before the two early returns below: a routine
        // that produced no artifact still earns a grade, and it is precisely the one a report card
        // needs to show. The record, not `id` and `receiptCorrelationID`, because grading has to know
        // which run under that correlation id it is looking at — see ``trace(ofRun:in:)``.
        let evaluation = await evaluateCompletedRun(for: record)
        var payloadValues: [String: ReceiptJSONValue] = [
            "playbook": .string(id),
            "runID": .string(record.id.uuidString),
            "trigger": .string(record.triggerSource.rawValue),
            "outcome": .string(record.outcome.rawValue)
        ]
        if let nextAction = evaluation?.nextAction {
            payloadValues["nextAction"] = .string(nextAction.rawValue)
        }
        if let artifactID = record.artifactID {
            payloadValues["artifactID"] = .string(artifactID.uuidString)
        }
        let draft = ReceiptDraft(
            category: "routine",
            kind: "routine.\(record.outcome.rawValue)",
            correlationID: receiptCorrelationID,
            payload: ReceiptPayload(values: payloadValues),
            // The run already resolved who acted (routine, operator, or human) — carry that onto the
            // run's own receipt instead of dropping it for a bare `.system` (P0.5-602).
            actorDetail: record.actor.receiptActorDetail,
            // The run resolved its own authority too — the capability lease when the engine has a
            // registry attached, standing policy otherwise. Carrying it here is what lets routine
            // history answer "what let this run?" and not just "who ran it".
            authorityDetail: record.authority?.receiptAuthorityDetail,
            mode: cryptoMode.receiptMode,
            summary: "Routine \(id) — \(record.outcome.rawValue)",
            provenance: "routine",
            isSuccess: record.outcome == .success
        )
        guard let receipt = await appendRuntimeReceipt(draft, goal: "Routine \(id)", actor: record.actor),
              let artifactID = record.artifactID else {
            return record
        }
        // Logged rather than discarded, and deliberately not escalated to a run failure — the same
        // reasoning ``ReceiptStoreSink/emit(_:)`` applies to the identical backlink. The receipt and
        // the artifact both landed; only the index between them did not, and the receipt carries
        // `artifactID` in its payload, so artifact → receipt stays recoverable from the ledger.
        // Reporting the run as failed over a lost index would misdescribe a routine that worked.
        do {
            try await artifactStore.linkRelatedReceipt(id: receipt.id, toArtifact: artifactID)
        } catch {
            runtimeHostLogger.error(
                """
                Failed to link routine receipt \(receipt.id.uuidString, privacy: .public) to \
                artifact \(artifactID.uuidString, privacy: .public): \
                \(error.localizedDescription, privacy: .public)
                """
            )
        }
        return record
    }

    /// Records that a human stepped in on the run that produced `artifactID` — approving, correcting,
    /// or otherwise manually completing it. Feeds the playbook's intervention rate (P1-603). No-op when
    /// the artifact wasn't produced by a scheduled run (e.g. a hand-authored artifact).
    public func recordIntervention(forArtifactID artifactID: UUID) async {
        let records = await schedulingEngine.executionRecords()
        guard let run = records.first(where: { $0.artifactID == artifactID }) else { return }
        await performanceStore.recordIntervention(runID: run.id)
    }

    /// Attaches a person's terminal approval decision to the performance event for the proposal.
    /// Deferred requests remain unresolved and intentionally do not enter the approval-rate denominator.
    public func recordApprovalDecision(
        runID: UUID,
        decision: PerformanceApprovalDecision
    ) async {
        await performanceStore.recordApprovalDecision(runID: runID, decision: decision)
    }

    /// `internal` because it is the host's witness for ``RuntimeDegradationReporting``: it is how
    /// ``RitualCoordinator`` reports a failed catalog read through this same observable banner rather
    /// than raising a second, independent one.
    func reportPlaybookPersistenceError(_ error: Error) {
        playbookPersistenceError = error.localizedDescription
    }

    /// Builds the governed pipeline wired to this host's registries, event bus, and receipt sink,
    /// using the crypto-scoped ``DomainJudge`` as the default authority.
    ///
    /// The judge is given this host's ``cryptoMode`` explicitly. `DomainJudge()` defaults to
    /// `.observe`, so a mode-blind judge re-blocked every approved crypto action on resume: the policy
    /// stage escalates in Assist, the person approves, and the judge then refused it as if the app were
    /// in Observe — making the approve → resume path unfinishable outside Observe.
    private func makePipeline(executor: any ToolExecuting) -> GovernedToolPipeline {
        GovernedToolPipeline(
            registry: toolRegistry,
            checks: checkRegistry,
            policy: PolicyCoreToolEvaluator(cryptoMode: cryptoMode),
            judge: DomainJudge(cryptoMode: cryptoMode),
            executor: executor,
            eventBus: eventBus,
            worklog: worklogRecorder,
            receiptSink: receiptSink,
            performanceSink: PerformancePipelineSink(store: performanceStore),
            pauseGate: pauseGate,
            leaseRegistry: leaseRegistry,
            sessionStore: sessionStore,
            contextRecorder: contextRecorder,
            approvalRegistry: approvalRegistry
        )
    }

    /// A fresh subscription to the live runtime event stream (Mission Control's timeline feed).
    public func events() async -> AsyncStream<WorkflowEventEnvelope> {
        await eventBus.events()
    }

    public func recentEvents(limit: Int = 100) async -> [WorkflowEventEnvelope] {
        await eventBus.recentEvents(limit: limit)
    }

    /// - Parameter actor: Who to attribute the session to when this call is the one that opens it
    ///   (P0.5-602). Required rather than defaulted: instrumentation runs on paths that have no session
    ///   of their own, so a default would silently file real runtime work under an anonymous identity.
    ///   Shell-driven refreshes pass ``shellContextActor``.
    public func recordContextRefresh(
        key: String,
        dataClass: ContextDataClass? = nil,
        correlationID: String,
        actor: ActorRef
    ) async {
        await contextRecorder.recordContextRefresh(key: key, dataClass: dataClass, correlationID: correlationID)
        await noteRuntimeSession(correlationID: correlationID, goal: "Runtime context refresh", actor: actor) { session in
            session.note(memoryTouch: AgentSessionMemoryTouch(kind: .contextRefresh, key: key, dataClass: dataClass))
        }
        await eventBus.publish(WorkflowEventEnvelope(event: .contextRefreshed(key: key), correlationID: correlationID))
    }

    /// - Parameter actor: Who to attribute the session to when this call is the one that opens it
    ///   (P0.5-602). Required for the same reason as ``recordContextRefresh(key:dataClass:correlationID:actor:)``.
    public func recordMemoryTouch(
        kind: AgentSessionMemoryTouchKind,
        key: String,
        dataClass: ContextDataClass? = nil,
        correlationID: String,
        actor: ActorRef
    ) async {
        await contextRecorder.recordMemoryTouch(kind: kind, key: key, dataClass: dataClass, correlationID: correlationID)
        await noteRuntimeSession(correlationID: correlationID, goal: "Runtime memory access", actor: actor) { session in
            session.note(memoryTouch: AgentSessionMemoryTouch(kind: kind, key: key, dataClass: dataClass))
        }
        await eventBus.publish(WorkflowEventEnvelope(event: .memoryTouched(kind: kind, key: key), correlationID: correlationID))
    }

    @discardableResult
    public func grantCapabilityLease(
        capability: CapabilityID,
        grantedTo: ActorRef,
        reason: String? = nil,
        correlationID: String? = nil,
        duration: TimeInterval = 20 * 60
    ) async -> CapabilityLease {
        let now = Date()
        let lease = CapabilityLease(
            capability: capability,
            reason: reason,
            grantedTo: grantedTo,
            sessionCorrelationID: correlationID,
            grantedAt: now,
            expiresAt: now.addingTimeInterval(duration)
        )
        let granted = await leaseRegistry.grant(lease)
        await eventBus.publish(WorkflowEventEnvelope(event: .capabilityLeaseGranted(granted), correlationID: correlationID))
        return granted
    }

    public func activeCapabilityLeases(at now: Date = .now) async -> [CapabilityLease] {
        await publishExpiredCapabilityLeases(at: now)
        return await leaseRegistry.activeLeases(at: now)
    }

    public func activeCapabilityRestrictions(at now: Date = .now) async -> [CapabilityRestriction] {
        await leaseRegistry.activeRestrictions(at: now)
    }

    @discardableResult
    public func denyCapability(
        _ kind: CapabilityRestrictionKind,
        reason: String,
        appliesTo actor: ActorRef? = nil,
        correlationID: String? = nil,
        duration: TimeInterval? = nil
    ) async -> CapabilityRestriction {
        let now = Date()
        let restriction = CapabilityRestriction(
            kind: kind,
            reason: reason,
            appliesTo: actor,
            sessionCorrelationID: correlationID,
            createdAt: now,
            expiresAt: duration.map { now.addingTimeInterval($0) }
        )
        let denied = await leaseRegistry.deny(restriction)
        await eventBus.publish(
            WorkflowEventEnvelope(
                event: .executionUpdate("\(kind.displayTitle): \(reason)"),
                correlationID: correlationID
            )
        )
        await recordRestrictionDecision(denied, kind: "runtime.capability.denied", verb: "applied")
        return denied
    }

    public func revokeCapabilityRestriction(id: UUID) async {
        let active = await leaseRegistry.activeRestrictions()
        let restriction = active.first { $0.id == id }
        await leaseRegistry.revokeRestriction(id: id)
        if let restriction {
            await eventBus.publish(
                WorkflowEventEnvelope(
                    event: .executionUpdate("Capability restriction revoked: \(restriction.kind.displayTitle)"),
                    correlationID: restriction.sessionCorrelationID
                )
            )
            await recordRestrictionDecision(
                restriction,
                kind: "runtime.capability.restrictionRevoked",
                verb: "lifted"
            )
        }
    }

    /// Writes the durable receipt for a capability restriction being applied or lifted.
    ///
    /// Both paths published only an ``WorkflowEvent/executionUpdate`` — a free-text string the
    /// receipt observer cannot classify, so neither produced a receipt. That left the restriction
    /// surface asymmetric with every other governance decision in the runtime: a *grant* of authority
    /// is receipted by ``RuntimeReceiptObserver``, an expiry and a revocation likewise, but a person
    /// explicitly saying "never this capability" — the strongest and most deliberate governance act
    /// available, and the one `grantingLease` honours ahead of any grant — left nothing in the ledger.
    ///
    /// Attributed to ``ActorRef/human`` under `humanApproval`: restrictions are only ever created and
    /// lifted from Mission Control, so a person is always the one acting.
    private func recordRestrictionDecision(
        _ restriction: CapabilityRestriction,
        kind: String,
        verb: String
    ) async {
        var values: [String: ReceiptJSONValue] = [
            "restrictionID": .string(restriction.id.uuidString),
            "restriction": .string(restriction.kind.displayTitle),
            "reason": .string(restriction.reason)
        ]
        if let appliesTo = restriction.appliesTo {
            values["appliesTo"] = .string(appliesTo.identifier ?? appliesTo.kind.displayTitle)
        }
        if let expiresAt = restriction.expiresAt {
            values["expiresAt"] = .string(timestampFormatter.string(from: expiresAt))
        }
        await appendRuntimeReceipt(
            ReceiptDraft(
                category: "runtime",
                kind: kind,
                // Filed under the restriction's own session when it has one, so the denial sits in
                // the trace of the run that prompted it rather than in a bucket of its own.
                correlationID: restriction.sessionCorrelationID ?? "runtime.capability",
                payload: ReceiptPayload(values: values),
                actorDetail: ActorRef.human.receiptActorDetail,
                authorityDetail: ReceiptAuthorityDetail(
                    source: "humanApproval",
                    reason: "Operator \(verb) a capability restriction from Mission Control."
                ),
                mode: cryptoMode.receiptMode,
                summary: "Capability restriction \(verb): \(restriction.kind.displayTitle)",
                provenance: "operator",
                isSuccess: true
            ),
            goal: "Capability restriction",
            actor: .human
        )
    }

    public func revokeCapabilityLease(id: UUID) async {
        let active = await leaseRegistry.activeLeases()
        let lease = active.first { $0.id == id }
        await leaseRegistry.revoke(id: id)
        if let lease {
            await eventBus.publish(
                WorkflowEventEnvelope(event: .capabilityRevoked(lease.capability), correlationID: lease.sessionCorrelationID)
            )
        }
    }

    private func publishExpiredCapabilityLeases(at now: Date = .now) async {
        let expired = await leaseRegistry.expiredLeases(at: now)
        for lease in expired {
            await eventBus.publish(
                WorkflowEventEnvelope(event: .capabilityLeaseExpired(lease.capability), correlationID: lease.sessionCorrelationID)
            )
        }
    }

    private func startSession(correlationID: String, goal: String) async {
        await noteRuntimeSession(correlationID: correlationID, goal: goal, actor: Self.autopilotActor) { session in
            session.note(goal: goal)
        }
        await eventBus.publish(WorkflowEventEnvelope(event: .sessionStarted(correlationID: correlationID, goal: goal), correlationID: correlationID))
    }

    private func finishSession(correlationID: String, conclusion: AutopilotRunConclusion) async {
        let endedStatus: AgentSessionStatus?
        switch conclusion {
        case .completed:
            await noteRuntimeSession(correlationID: correlationID, goal: "Autopilot goal", actor: Self.autopilotActor) { session in
                session.complete()
            }
            endedStatus = .completed
        case let .failed(reason):
            await noteRuntimeSession(correlationID: correlationID, goal: "Autopilot goal", actor: Self.autopilotActor) { session in
                session.fail(reason: reason)
            }
            endedStatus = .failed
        case let .blocked(reason):
            await noteRuntimeSession(correlationID: correlationID, goal: "Autopilot goal", actor: Self.autopilotActor) { session in
                session.block(reason: reason)
            }
            endedStatus = .blocked
        case .awaitingConfirmation:
            await noteRuntimeSession(correlationID: correlationID, goal: "Autopilot goal", actor: Self.autopilotActor) { session in
                session.markWaitingForApproval()
            }
            // Not terminal — the run is waiting on a person, so no `sessionEnded`.
            endedStatus = nil
        }
        guard let endedStatus else { return }
        await eventBus.publish(
            WorkflowEventEnvelope(
                event: .sessionEnded(correlationID: correlationID, status: endedStatus),
                correlationID: correlationID
            )
        )
    }

    /// - Parameter actor: Who the session is attributed to when this call is the one that creates it
    ///   (P0.5-602). Required rather than defaulted so each runtime touchpoint has to state whether the
    ///   person or the runtime itself is acting — the two are not interchangeable on a trust surface.
    ///
    /// - Important: Read → mutate → upsert with no compare-and-set, across a suspension point. Two
    ///   writers on the *same* `correlationID` would lose one of their notes. What rules that out is
    ///   ``CorrelationGate``, which the four governed entry points hold for the whole of a run: only
    ///   one run per correlation id is in flight, so there is only ever one writer here.
    ///
    ///   This used to rest on the **call graph** instead — autopilot clearing one step at a time,
    ///   `runDueRoutines` and `runRitualReport` running playbooks in order — which was an invariant of
    ///   the callers rather than of the runtime, and `MissionControlHomeModel.sharePlaybook` broke it
    ///   by dispatching two shares into one session concurrently. Dispatching plan steps or routine
    ///   runs concurrently *on purpose* still needs this to become a store-side read-modify-write (or
    ///   a merging upsert) first; see the same note on
    ///   ``ReceiptStoreSink/noteSessionReceipt(_:correlationID:goal:actor:)`` and
    ///   ``AutopilotStepExecutor/noteReceipt(_:actor:)``.
    private func noteRuntimeSession(
        correlationID: String,
        goal: String,
        actor: ActorRef,
        _ update: (inout AgentSession) -> Void
    ) async {
        var session = await sessionStore.session(correlationID: correlationID)
            ?? AgentSession(correlationID: correlationID, goal: goal, actor: actor)
        update(&session)
        await sessionStore.upsert(session)
    }

    /// Appends a runtime-owned receipt and mirrors it into the event bus and correlated session.
    ///
    /// Use this for runtime/Mission Control decisions that are not emitted by `GovernedToolPipeline`
    /// itself but still belong to the central runtime stream.
    /// - Parameter actor: Who acted (P0.5-602). Required, and expected to match the `actorDetail`
    ///   already on `draft` — the draft's copy is the persisted attribution, this one attributes the
    ///   correlated session the receipt is folded into. Passing them separately keeps `RuntimeKit` off
    ///   the business of decoding `ReceiptActorDetail`'s raw strings back into an `ActorRef`.
    @discardableResult
    public func appendRuntimeReceipt(
        _ draft: ReceiptDraft,
        goal: String,
        actor: ActorRef,
        approvalID: UUID? = nil,
        telemetry: InferenceTelemetry? = nil,
        executionUpdate: String? = nil
    ) async -> ReceiptRecord? {
        let receipt: ReceiptRecord
        do {
            // Deliberately does not clear `receiptPersistenceError`; see that property.
            receipt = try await receiptStore.append(draft)
        } catch {
            await noteReceiptPersistenceFailure(
                correlationID: draft.correlationID,
                goal: goal,
                actor: actor
            )
            return nil
        }
        await eventBus.publish(WorkflowEventEnvelope(event: .receiptCreated(id: receipt.id), correlationID: receipt.correlationID))
        if let correlationID = receipt.correlationID {
            await noteRuntimeSession(correlationID: correlationID, goal: goal, actor: actor) { session in
                session.note(receiptID: receipt.id)
                if let approvalID {
                    session.note(approvalID: approvalID)
                }
                if let telemetry {
                    session.note(telemetry: telemetry)
                }
                if let executionUpdate {
                    session.noteExecutionUpdate(executionUpdate)
                }
            }
        }
        if let executionUpdate {
            await eventBus.publish(WorkflowEventEnvelope(event: .executionUpdate(executionUpdate), correlationID: receipt.correlationID))
        }
        return receipt
    }

    /// Publishes the degraded-audit-evidence signal for a receipt that could not be written: the
    /// observable ``receiptPersistenceError`` banner, an execution update on the correlated session,
    /// and the same update on the event bus.
    ///
    /// Non-private so ``AutopilotStepExecutor`` can route its own failed step receipts through the
    /// identical path. Those were previously written with `try?` and dropped in silence, which is the
    /// one thing this runtime is not allowed to do with a receipt: the step went on to report itself
    /// as fully receipted while no evidence of it existed.
    /// - Parameter correlationID: The workflow run the lost receipt belonged to, or `nil` for
    ///   genuinely un-correlated work. The banner, the missing-receipt count, and the event-bus
    ///   signal all fire either way — a receipt that could not be written must never be silent, and
    ///   whether it had a correlation id is not the user's problem. Only the session fold is skipped,
    ///   because with no id there is no session to fold into, and minting one here would open a
    ///   session for a workflow run that never existed.
    func noteReceiptPersistenceFailure(
        correlationID: String?,
        goal: String,
        actor: ActorRef
    ) async {
        let message = "A runtime receipt could not be saved. Audit evidence is incomplete."
        receiptPersistenceError = message
        missingReceiptCount += 1
        if let correlationID {
            await noteRuntimeSession(correlationID: correlationID, goal: goal, actor: actor) { session in
                session.noteExecutionUpdate(message)
            }
        }
        await eventBus.publish(
            WorkflowEventEnvelope(
                event: .executionUpdate(message),
                correlationID: correlationID
            )
        )
    }

    /// Dismisses the degraded-audit-evidence banner after a person has seen it.
    ///
    /// This acknowledges the gap; it does not repair it. The receipts that failed to write are still
    /// missing, and the execution updates recorded on their sessions and the event bus by
    /// ``noteReceiptPersistenceFailure(correlationID:goal:actor:)`` remain as the durable record that
    /// they were. Only the transient banner is cleared, which is why the acknowledgement has to be
    /// explicit rather than implied by the next receipt that happens to succeed.
    public func acknowledgeReceiptPersistenceFailure() {
        receiptPersistenceError = nil
        missingReceiptCount = 0
    }

    private static func planningReceiptPayload(
        planner: String,
        telemetry: InferenceTelemetry
    ) -> ReceiptPayload {
        var values = telemetry.outputFields.reduce(into: [String: ReceiptJSONValue]()) { partial, field in
            partial[field.key] = .string(field.value)
        }
        values["planner"] = .string(planner)
        values["taskKind"] = .string(ModelTaskKind.autopilotPlanning)
        return ReceiptPayload(values: values)
    }

    private func grantRequiredLease(for proposal: ActionProposal, reason: String) async {
        await grantCapabilityLease(
            capability: proposal.capability,
            grantedTo: proposal.actor,
            reason: reason,
            correlationID: proposal.resolvedCorrelationID
        )
        // Resolved, not raw: the lease and the session must be keyed the same way the pipeline keys
        // this proposal's worklog, or an uncorrelated proposal's grant is unretrievable and its
        // session never records the capability at all.
        await noteRuntimeSession(
            correlationID: proposal.resolvedCorrelationID,
            goal: proposal.intent,
            actor: proposal.actor
        ) { session in
            session.note(capability: proposal.capability)
        }
    }

    private func executor(for toolID: String) -> any ToolExecuting {
        if OperatorCatalog.spec(for: toolID) != nil {
            return operatorExecutor
        }
        return policyActionExecutor
    }
}
