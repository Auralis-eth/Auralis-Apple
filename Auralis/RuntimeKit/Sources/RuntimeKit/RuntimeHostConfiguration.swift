import ArtifactCore
import AuralisPrimaryModels
import EvalCore
import Foundation
import OperatorsFeature
import PerformanceCore
import PlaybookCore
import PolicyCore
import ReceiptsCore
import RuntimeCore
import SchedulingCore
import SocialCore

// The grouped composition surface for ``RuntimeHost``.
//
// The initializer took thirty parameters. Every one had a default, so the common call really was
// `RuntimeHost(receiptStore:)` — but the signature itself had stopped communicating anything: there
// was no way to see, from the declaration, that eleven of those parameters were interchangeable
// trace stores, three were human-coordination stores, three were the model stack, and three were
// hooks back into the app shell. `RuntimeHost.persistent(...)` then mirrored fourteen of them by
// hand, which is how a forwarding bug hid there once already: the storage-unavailable path simply
// omitted the coordination stores, silently swapping healthy durable state for empty in-memory
// defaults (see the comment on that path).
//
// Grouping turns thirty parameters into six, each named for a concern rather than a type. Every
// group is defaulted, so `RuntimeHost(receiptStore: store)` is unchanged; a caller that overrides
// one thing names the group it belongs to, which is also the documentation.
//
// These are deliberately plain memberwise-defaulted structs, not builders or protocols. The point is
// to make the composition legible, not to add a layer.

/// The durable stores that hold what the runtime has done: artifacts, traces, grades, and cursors.
///
/// `nil` on ``playbookStore``, ``performanceStore``, and ``capabilityLeaseStore`` means "resolve the
/// default", which is not the same as an in-memory stub — the host substitutes a seeded
/// `InMemoryPlaybookStore`, a real `PerformanceStore`, and an unbacked lease registry respectively.
public struct RuntimeHostStores {
    public var artifactStore: any ArtifactStore
    public var playbookStore: (any PlaybookStore)?
    public var performanceStore: (any PerformanceStoring)?
    public var executionRecordStore: any ExecutionRecordStoring
    public var worklogStore: any WorklogStoring
    public var evalResultStore: any EvalResultStoring
    public var improvementRecommendationStore: any ImprovementRecommendationStoring
    public var sessionStore: any AgentSessionStoring
    public var eventHistoryStore: any RuntimeEventHistoryStoring
    public var eventCheckpointStore: any RuntimeEventCheckpointStoring
    public var capabilityLeaseStore: (any CapabilityLeaseStoring)?
    public var contextRecorder: RuntimeContextRecorder

    public init(
        artifactStore: any ArtifactStore = InMemoryArtifactStore(),
        playbookStore: (any PlaybookStore)? = nil,
        performanceStore: (any PerformanceStoring)? = nil,
        executionRecordStore: any ExecutionRecordStoring = InMemoryExecutionRecordStore(),
        worklogStore: any WorklogStoring = InMemoryWorklog(),
        evalResultStore: any EvalResultStoring = InMemoryEvalResultStore(),
        improvementRecommendationStore: any ImprovementRecommendationStoring = InMemoryImprovementRecommendationStore(),
        sessionStore: any AgentSessionStoring = InMemoryAgentSessionStore(),
        eventHistoryStore: any RuntimeEventHistoryStoring = InMemoryRuntimeEventHistoryStore(),
        eventCheckpointStore: any RuntimeEventCheckpointStoring = InMemoryRuntimeEventCheckpointStore(),
        capabilityLeaseStore: (any CapabilityLeaseStoring)? = nil,
        contextRecorder: RuntimeContextRecorder = RuntimeContextRecorder()
    ) {
        self.artifactStore = artifactStore
        self.playbookStore = playbookStore
        self.performanceStore = performanceStore
        self.executionRecordStore = executionRecordStore
        self.worklogStore = worklogStore
        self.evalResultStore = evalResultStore
        self.improvementRecommendationStore = improvementRecommendationStore
        self.sessionStore = sessionStore
        self.eventHistoryStore = eventHistoryStore
        self.eventCheckpointStore = eventCheckpointStore
        self.capabilityLeaseStore = capabilityLeaseStore
        self.contextRecorder = contextRecorder
    }
}

/// The human-coordination stores (P1-SOCIAL-101/102).
///
/// Grouped separately from ``RuntimeHostStores`` because they are backed by `UserDefaults` rather
/// than the SwiftData container, which is exactly the distinction that got lost once: they sat
/// outside both the app reset and the runtime container, and outside the storage-unavailable
/// forwarding path in `RuntimeHost.persistent(...)`. Naming them as their own group makes "these
/// three travel together" structural instead of something a caller has to remember.
public struct RuntimeCoordinationStores {
    public var sharedSessionStore: SharedSessionStore
    public var ritualStore: RitualStore
    public var socialEventLogStore: SocialEventLogStore
    /// The durable backings of the three stores above, for quarantine health and recovery.
    ///
    /// Separate from the stores because a `SharedSessionStore` does not expose the persistence it
    /// was built with, and the host needs to reach it: a quarantined backing refuses every write
    /// including the empty one the privacy reset issues. See ``SocialPersistenceQuarantining``.
    ///
    /// Empty by default, and deliberately so. The default stores above are `UserDefaults`-free
    /// (`EphemeralSharedSessionPersistence` and friends), so there is nothing that *can* quarantine;
    /// registering a probe for them would have the host report health for a backing it is not using.
    /// `RuntimeHost.persistent(...)` populates this for the stores it builds itself.
    public var quarantinablePersistence: [any SocialPersistenceQuarantining]

    public init(
        sharedSessionStore: SharedSessionStore = SharedSessionStore(),
        ritualStore: RitualStore = RitualStore(),
        socialEventLogStore: SocialEventLogStore = SocialEventLogStore(),
        quarantinablePersistence: [any SocialPersistenceQuarantining] = []
    ) {
        self.sharedSessionStore = sharedSessionStore
        self.ritualStore = ritualStore
        self.socialEventLogStore = socialEventLogStore
        self.quarantinablePersistence = quarantinablePersistence
    }
}

/// Model routing, inference, and the advisory rubric judge.
///
/// ``rubricJudge`` belongs here rather than with the stores: it is model-backed opinion, and
/// ``NoRubricJudge`` is the default precisely so nothing in the shipping path depends on inference.
public struct RuntimeModelStack {
    public var modelRouter: any ModelRouting
    public var modelInferenceClient: any ModelInferring
    public var rubricJudge: any RubricJudging

    public init(
        modelRouter: any ModelRouting = TaskKindModelRouter.localFirstDefault,
        modelInferenceClient: any ModelInferring = UnsupportedModelInferenceClient(),
        rubricJudge: any RubricJudging = NoRubricJudge()
    ) {
        self.modelRouter = modelRouter
        self.modelInferenceClient = modelInferenceClient
        self.rubricJudge = rubricJudge
    }
}

/// What actually performs work: the operator data source, the routine operators, the executor for
/// cleared policy actions, and the ritual notifier.
///
/// ``policyActionExecutor`` defaults to the fail-closed ``UnconfiguredPolicyActionExecutor``, which
/// throws rather than fabricate a success. The shipping app injects a real wallet-backed executor.
public struct RuntimeOperatorStack {
    public var operatorDataSource: any OperatorDataSource
    public var routineOperators: [String: any RoutineOperator]
    public var routineOperatorFallback: any RoutineOperator
    public var policyActionExecutor: any ToolExecuting
    public var ritualRunNotifier: any RitualRunNotifying

    public init(
        operatorDataSource: any OperatorDataSource = EmptyOperatorDataSource(),
        routineOperators: [String: any RoutineOperator] = [:],
        routineOperatorFallback: any RoutineOperator = DefaultRoutineOperator(),
        policyActionExecutor: any ToolExecuting = UnconfiguredPolicyActionExecutor(),
        ritualRunNotifier: any RitualRunNotifying = NoOpRitualRunNotifier()
    ) {
        self.operatorDataSource = operatorDataSource
        self.routineOperators = routineOperators
        self.routineOperatorFallback = routineOperatorFallback
        self.policyActionExecutor = policyActionExecutor
        self.ritualRunNotifier = ritualRunNotifier
    }
}

/// Governance policy applied at construction: the launch pause, the deterministic-check scope, and
/// durable-store preparation that must finish before standing authority is seeded.
public struct RuntimeGovernanceOptions {
    /// Non-`nil` starts the host paused, with this as the reason on screen.
    public var initialPauseReason: String?
    /// Chain scope and context-freshness window for the standard checks. Injectable because these are
    /// governance policy, not implementation detail: they were once fixed inside
    /// `registerStandardChecks()`, so no composition root could tighten either one.
    public var standardCheckConfiguration: StandardCheckConfiguration
    /// Where the global kill switch is stored so it outlives the host that set it.
    ///
    /// `nil` — the default — keeps the pause process-local, which is right for tests and previews
    /// that compose a host per case and must not read or write a shared `UserDefaults` key.
    /// `RuntimeHost.persistent(...)` supplies ``UserDefaultsRuntimePauseStateStore``, so the shipping
    /// app's pause survives relaunch and applies to every host in the process. See
    /// ``RuntimePauseStateStoring`` for what this fixes.
    public var pauseStateStore: (any RuntimePauseStateStoring)?
    /// Awaited inside ``RuntimeHost/bootstrap()`` *before* standing authority is seeded, rather than
    /// run as a detached task — the seed reads the playbook catalog, so a detached preparation raced
    /// it and could grant authority for an empty catalog.
    ///
    /// Declared last so the closure reads as a trailing block at composition roots.
    public var playbookPreparation: (@Sendable () async throws -> Void)?

    public init(
        initialPauseReason: String? = nil,
        standardCheckConfiguration: StandardCheckConfiguration = .default,
        pauseStateStore: (any RuntimePauseStateStoring)? = nil,
        playbookPreparation: (@Sendable () async throws -> Void)? = nil
    ) {
        self.initialPauseReason = initialPauseReason
        self.standardCheckConfiguration = standardCheckConfiguration
        self.pauseStateStore = pauseStateStore
        self.playbookPreparation = playbookPreparation
    }
}

/// The host's read/write hooks into app-shell state it does not own: the active identity and the
/// crypto posture.
///
/// Providers rather than values because all three are live state that changes while the host is
/// alive — a person switches account or flips Observe → Assist mid-run — and a snapshot taken at
/// construction would report a posture the app was no longer in.
public struct RuntimeIdentityHooks {
    public var activeIdentityProvider: @MainActor () -> String?
    public var cryptoModeProvider: @MainActor @Sendable () -> CryptoMode
    public var cryptoModeSetter: @MainActor @Sendable (CryptoMode) -> Void

    public init(
        activeIdentityProvider: @escaping @MainActor () -> String? = { nil },
        cryptoModeProvider: @escaping @MainActor @Sendable () -> CryptoMode = { .observe },
        cryptoModeSetter: @escaping @MainActor @Sendable (CryptoMode) -> Void = { _ in }
    ) {
        self.activeIdentityProvider = activeIdentityProvider
        self.cryptoModeProvider = cryptoModeProvider
        self.cryptoModeSetter = cryptoModeSetter
    }
}
