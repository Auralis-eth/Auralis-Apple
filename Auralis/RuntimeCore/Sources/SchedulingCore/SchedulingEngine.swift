import Foundation
import PerformanceCore
import PlaybookCore
import RuntimeCore

/// Why a run happened. Recorded on every execution record and receipt. (P1-602)
public enum TriggerSource: String, Equatable, Sendable, Codable {
    case manual
    case schedule
    case maintenance
    case artifactStale
    case approvalPendingTooLong
}

public extension TriggerSource {
    /// The actor a run with this trigger is attributed to when the caller doesn't supply one
    /// (P0.5-602). A manual run is the person using the app; every automated trigger — schedule,
    /// maintenance, or an event — is a scheduled routine acting on the user's behalf.
    ///
    /// - Parameter playbookID: Identifies *which* routine, so an automated run is never recorded as an
    ///   anonymous `scheduledRoutine`. Every caller has this in scope, and an unidentified routine is
    ///   indistinguishable from every other one on a trust surface.
    func defaultActor(playbookID: String) -> ActorRef {
        switch self {
        case .manual:
            return .human
        case .schedule, .maintenance, .artifactStale, .approvalPendingTooLong:
            return ActorRef(kind: .scheduledRoutine, identifier: playbookID)
        }
    }
}

/// A scheduling-owned description of a work product an operator wants persisted.
///
/// The durable artifact model belongs to ReceiptsCore. Keeping this request in the runtime domain
/// lets scheduling describe its output without depending outward on a persistence implementation.
public struct RoutineArtifactDraft: Equatable, Sendable {
    public let type: ArtifactOutputType
    public let title: String
    public let creatorPlaybookID: String?
    public let creatorOperatorID: String?
    public let actor: ActorRef
    public let inference: InferenceProvenance?
    public let relatedReceiptIDs: [UUID]
    public let destination: String?
    public let exportFormat: String?
    public let content: String

    public init(
        type: ArtifactOutputType,
        title: String,
        creatorPlaybookID: String? = nil,
        creatorOperatorID: String? = nil,
        actor: ActorRef,
        inference: InferenceProvenance? = nil,
        relatedReceiptIDs: [UUID] = [],
        destination: String? = nil,
        exportFormat: String? = nil,
        content: String
    ) {
        self.type = type
        self.title = title
        self.creatorPlaybookID = creatorPlaybookID
        self.creatorOperatorID = creatorOperatorID
        self.actor = actor
        self.inference = inference
        self.relatedReceiptIDs = relatedReceiptIDs
        self.destination = destination
        self.exportFormat = exportFormat
        self.content = content
    }
}

/// Persists a routine output without exposing the receipts-owned artifact model to scheduling.
public protocol RoutineArtifactPersisting: Sendable {
    func create(_ draft: RoutineArtifactDraft) async throws -> UUID
}

/// The result an operator returns from a run.
public struct RoutineRunResult: Sendable {
    public let outcome: PlaybookRunOutcome
    public let artifact: RoutineArtifactDraft?
    /// A short, stable reason for a `.failed` outcome (e.g. "provider timeout"). Used to group
    /// recurring failures into patterns (P1-603). Ignored for non-failing outcomes.
    public let failureReason: String?
    public let blockCategory: PerformanceBlockCategory?

    public init(
        outcome: PlaybookRunOutcome,
        artifact: RoutineArtifactDraft? = nil,
        failureReason: String? = nil,
        blockCategory: PerformanceBlockCategory? = nil
    ) {
        self.outcome = outcome
        self.artifact = artifact
        self.failureReason = failureReason
        self.blockCategory = blockCategory
    }
}

/// Runs a playbook's actual work (gathering already done). Injected so scheduling stays testable.
public protocol RoutineOperator: Sendable {
    func run(playbook: Playbook, context: GovernedContext) async -> RoutineRunResult
}

/// Dispatches a run to a per-playbook ``RoutineOperator``, falling back to a default operator for any
/// playbook without a specific one registered.
///
/// This is the seam that lets each playbook — and therefore each ritual (P1-SOCIAL-102) — do
/// domain-specific work: a music/listening operator backs a listening flow, a reflection operator
/// backs weekly reflection, while every unmapped playbook still degrades gracefully to the default
/// summary artifact. The registry itself conforms to ``RoutineOperator`` so ``SchedulingEngine`` needs
/// no change — it is injected exactly where a single operator used to be.
public struct RoutineOperatorRegistry: RoutineOperator {
    private let operators: [String: any RoutineOperator]
    private let fallback: any RoutineOperator

    /// - Parameters:
    ///   - operators: Per-playbook operators, keyed by `Playbook.id`.
    ///   - fallback: Runs any playbook without a specific operator registered.
    public init(operators: [String: any RoutineOperator] = [:], fallback: any RoutineOperator) {
        self.operators = operators
        self.fallback = fallback
    }

    /// The operator registered for `playbook.id`, or `nil` when only the fallback would handle it.
    public func hasOperator(forPlaybookID playbookID: String) -> Bool {
        operators[playbookID] != nil
    }

    public func run(playbook: Playbook, context: GovernedContext) async -> RoutineRunResult {
        await (operators[playbook.id] ?? fallback).run(playbook: playbook, context: context)
    }
}

/// Supplies the context a playbook needs before it runs, as a governed ``ContextBundle`` (each field
/// carries a data class, source, and refresh time) rather than a bare string map. This is what lets
/// the engine validate context against a ``ContextBundleContract`` before an operator sees any data.
public protocol ContextProviding: Sendable {
    func gather(for playbook: Playbook) async -> ContextBundle
}

/// Resolves the ``ContextBundleContract`` a playbook is governed by, if any. This is the seam that
/// makes context governance load-bearing: ``SchedulingEngine`` validates the gathered bundle against
/// the resolved contract *before* handing data to an operator, refusing the run on any violation.
public protocol ContextContractResolving: Sendable {
    func contract(for playbook: Playbook) -> ContextBundleContract?
}

/// An explicit workflow-to-contract declaration. Production composition uses these values instead of
/// assembling an unlabelled dictionary, keeping the workflow identity beside its governance contract.
public struct ContextContractDeclaration: Equatable, Sendable {
    public let playbookID: String
    public let contract: ContextBundleContract

    public init(playbookID: String, contract: ContextBundleContract) {
        self.playbookID = playbookID
        self.contract = contract
    }
}

/// A typed registration failure. Invalid declarations never enter the executable registry.
public enum ContextContractRegistrationError: Error, Equatable, Sendable {
    case emptyWorkflowIdentifier
    case duplicateWorkflowIdentifier(String)
    case invalidContract(workflowID: String, violations: [String])
}

/// Associates contracts with playbooks by `Playbook.id`, mirroring ``RoutineOperatorRegistry``.
///
/// Explicit declarations win; anything not declared falls to `derived`, which may build a contract
/// from the playbook itself. That fallback is what lets a playbook authored *at runtime* be governed
/// at all: keying contracts solely by id means only ids known when the registry was constructed can
/// ever run, so a user-created playbook is refused for having no declaration rather than for asking
/// for context it shouldn't see.
public struct ContextContractRegistry: ContextContractResolving {
    private let contracts: [String: ContextBundleContract]
    private let derived: (@Sendable (Playbook) -> ContextBundleContract?)?
    private let rejectedWorkflowIDs: Set<String>
    public let registrationErrors: [ContextContractRegistrationError]

    /// - Parameters:
    ///   - contracts: Explicit per-playbook declarations, keyed by `Playbook.id`.
    ///   - derived: Builds a contract for a playbook with no explicit declaration. `nil` — the
    ///     default — keeps the registry closed: an undeclared playbook resolves to no contract and
    ///     the engine refuses the run.
    public init(
        contracts: [String: ContextBundleContract],
        derived: (@Sendable (Playbook) -> ContextBundleContract?)? = nil
    ) {
        var accepted: [String: ContextBundleContract] = [:]
        var errors: [ContextContractRegistrationError] = []
        for (workflowID, contract) in contracts {
            if workflowID.isEmpty {
                errors.append(.emptyWorkflowIdentifier)
            } else if !contract.configurationViolations().isEmpty {
                errors.append(.invalidContract(
                    workflowID: workflowID,
                    violations: contract.configurationViolations()
                ))
            } else {
                accepted[workflowID] = contract
            }
        }
        self.contracts = accepted
        self.derived = derived
        rejectedWorkflowIDs = Set(errors.compactMap(\.workflowID))
        registrationErrors = errors
    }

    public init(
        declarations: [ContextContractDeclaration],
        derived: (@Sendable (Playbook) -> ContextBundleContract?)? = nil
    ) {
        var accepted: [String: ContextBundleContract] = [:]
        var errors: [ContextContractRegistrationError] = []
        var seen: Set<String> = []
        for declaration in declarations {
            let workflowID = declaration.playbookID
            guard !workflowID.isEmpty else {
                errors.append(.emptyWorkflowIdentifier)
                continue
            }
            guard seen.insert(workflowID).inserted else {
                accepted.removeValue(forKey: workflowID)
                errors.append(.duplicateWorkflowIdentifier(workflowID))
                continue
            }
            let violations = declaration.contract.configurationViolations()
            guard violations.isEmpty else {
                errors.append(.invalidContract(workflowID: workflowID, violations: violations))
                continue
            }
            accepted[workflowID] = declaration.contract
        }
        contracts = accepted
        self.derived = derived
        rejectedWorkflowIDs = Set(errors.compactMap(\.workflowID))
        registrationErrors = errors
    }

    public func contract(for playbook: Playbook) -> ContextBundleContract? {
        guard !rejectedWorkflowIDs.contains(playbook.id) else { return nil }
        if let contract = contracts[playbook.id] { return contract }
        guard let contract = derived?(playbook), contract.configurationViolations().isEmpty else {
            return nil
        }
        return contract
    }
}

private extension ContextContractRegistrationError {
    var workflowID: String? {
        switch self {
        case .emptyWorkflowIdentifier:
            return ""
        case let .duplicateWorkflowIdentifier(workflowID):
            return workflowID
        case let .invalidContract(workflowID, _):
            return workflowID
        }
    }
}

/// A stored record of one run — kept even for no-ops (P1-601 "Stores execution records even for no-op").
public struct ExecutionRecord: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public let playbookID: String
    public let triggerSource: TriggerSource
    /// Who triggered this run (P0.5-602 actor attribution): who acted, under what authority. Scheduled,
    /// maintenance, and event runs are `.scheduledRoutine`; manual runs are the human (or operator) who
    /// asked. Populated by ``SchedulingEngine/runOnce(playbookID:trigger:actor:)``.
    ///
    /// No initializer default: an `= .system` fallback would let a new call site record an anonymous
    /// actor silently. Records written before the field existed are still tolerated on decode.
    public let actor: ActorRef
    /// What permitted this run (P0.5-601/602). `nil` when the engine has no lease registry attached,
    /// or when the run never reached the point of resolving a grant (paused, uninstalled, blocked on
    /// the read-only guard).
    public let authority: AuthorityRef?
    public let authorityState: AuthorityState
    /// The workflow this run belongs to — the "through what workflow" leg (P0.5-602).
    ///
    /// Non-optional and defaulted to the run's own id, because a run is always *some* workflow even
    /// when nothing external correlated it. Holding it on the record is what lets the run's receipt
    /// and its worklog steps be filed under one key instead of each deriving their own.
    public let correlationID: String
    public let workflowRun: WorkflowRunRef
    public let outcome: PlaybookRunOutcome
    public let artifactID: UUID?
    public let startedAt: Date
    public let durationSeconds: Double
    /// Stable terminal detail for blocked or failed runs. Optional for legacy and successful rows.
    public let failureReason: String?
    public let evidenceCompleteness: EvidenceCompleteness

    public init(
        id: UUID = UUID(),
        playbookID: String,
        triggerSource: TriggerSource,
        actor: ActorRef,
        authority: AuthorityRef? = nil,
        authorityState: AuthorityState? = nil,
        correlationID: String? = nil,
        outcome: PlaybookRunOutcome,
        artifactID: UUID?,
        startedAt: Date,
        durationSeconds: Double,
        failureReason: String? = nil,
        evidenceCompleteness: EvidenceCompleteness = .complete
    ) {
        let workflowRun = WorkflowRunRef.resolved(
            correlationID: correlationID,
            workflowID: playbookID,
            fallbackActionID: id
        )
        self.correlationID = workflowRun.correlationID
        self.workflowRun = workflowRun
        self.id = id
        self.playbookID = playbookID
        self.triggerSource = triggerSource
        self.actor = actor
        self.authority = authority
        self.authorityState = authorityState ?? authority.map(AuthorityState.resolved) ?? .pending
        self.outcome = outcome
        self.artifactID = artifactID
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.failureReason = failureReason
        self.evidenceCompleteness = evidenceCompleteness
    }

    private enum CodingKeys: String, CodingKey {
        case id, playbookID, triggerSource, actor, authority, authorityState, correlationID, workflowRun, outcome, artifactID
        case startedAt, durationSeconds, failureReason, evidenceCompleteness
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        playbookID = try container.decode(String.self, forKey: .playbookID)
        triggerSource = try container.decode(TriggerSource.self, forKey: .triggerSource)
        // Backward-compatible: records written before actor attribution decode as `.system`.
        actor = try container.decodeIfPresent(ActorRef.self, forKey: .actor) ?? .system
        authority = AuthorityRef.decodedIfPresent(from: container, forKey: .authority)
        // Records written before the field decode to the run id — exactly the key the receipt for
        // those runs was already filed under, so old history joins the same way new history does.
        correlationID = try container.decodeIfPresent(String.self, forKey: .correlationID) ?? id.uuidString
        workflowRun = try container.decodeIfPresent(WorkflowRunRef.self, forKey: .workflowRun)
            ?? .workflow(id: correlationID, workflowID: playbookID)
        authorityState = try container.decodeIfPresent(AuthorityState.self, forKey: .authorityState)
            ?? authority.map(AuthorityState.resolved)
            ?? .legacyUnknown
        outcome = try container.decode(PlaybookRunOutcome.self, forKey: .outcome)
        artifactID = try container.decodeIfPresent(UUID.self, forKey: .artifactID)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        durationSeconds = try container.decode(Double.self, forKey: .durationSeconds)
        failureReason = try container.decodeIfPresent(String.self, forKey: .failureReason)
        evidenceCompleteness = try container.decodeIfPresent(EvidenceCompleteness.self, forKey: .evidenceCompleteness) ?? .complete
    }
}

/// Persistence surface for execution records. Default is in-memory; a SwiftData implementation makes
/// run history survive relaunch.
public protocol ExecutionRecordStoring: Sendable {
    func store(_ record: ExecutionRecord) async
    func all() async -> [ExecutionRecord]
    func latest(forPlaybookID playbookID: String) async -> ExecutionRecord?
    /// Erases all run history. Required rather than defaulted so a new store cannot silently survive
    /// a privacy reset: every record carries actor, authority, and correlation attribution.
    func resetAll() async
}

public actor InMemoryExecutionRecordStore: ExecutionRecordStoring {
    private var records: [ExecutionRecord] = []
    public init() { }
    public func store(_ record: ExecutionRecord) { records.append(record) }
    public func all() -> [ExecutionRecord] { records }
    public func latest(forPlaybookID playbookID: String) -> ExecutionRecord? {
        // Searched in reverse because `max(by:)` keeps the *first* of equally-ranked elements: among
        // records sharing a `startedAt` — two runs landing in the same instant — that would hand back
        // the earliest-recorded one, whose outcome and trigger are not what "latest" means. Reversing
        // makes the newest of a tie win.
        records
            .reversed()
            .filter { $0.playbookID == playbookID }
            .max { $0.startedAt < $1.startedAt }
    }

    public func resetAll() { records.removeAll() }
}

/// A trigger evaluation: the verdict, plus why it came out that way.
///
/// The rationale exists so a due-scan can record what it weighed on the worklog. "Why didn't my
/// routine run?" is otherwise unanswerable after the fact — a skipped routine writes nothing, since
/// only runs produce execution records.
public struct TriggerEvaluation: Equatable, Sendable {
    public let isDue: Bool
    /// A short, user-facing explanation of the verdict.
    public let rationale: String

    public init(isDue: Bool, rationale: String) {
        self.isDue = isDue
        self.rationale = rationale
    }
}

/// The time an event condition first became actionable. Comparing this with a routine's last run
/// prevents an unchanged stale artifact or pending approval from firing again on every scheduler scan.
public struct RoutineEventSignals: Equatable, Sendable {
    public let artifactStaleAt: Date?
    public let approvalPendingTooLongAt: Date?

    public init(artifactStaleAt: Date? = nil, approvalPendingTooLongAt: Date? = nil) {
        self.artifactStaleAt = artifactStaleAt
        self.approvalPendingTooLongAt = approvalPendingTooLongAt
    }

    public var staleSignal: Bool { artifactStaleAt != nil }
    public var approvalPendingSignal: Bool { approvalPendingTooLongAt != nil }
}

/// Pure trigger-evaluation helper (P1-602): decides whether a trigger should fire.
public enum TriggerEvaluator {
    public static func shouldFire(
        _ trigger: PlaybookTrigger,
        lastRun: Date?,
        now: Date = .now,
        staleSignal: Bool = false,
        approvalPendingSignal: Bool = false
    ) -> Bool {
        evaluate(
            trigger,
            lastRun: lastRun,
            now: now,
            staleSignal: staleSignal,
            approvalPendingSignal: approvalPendingSignal
        ).isDue
    }

    /// The same decision as ``shouldFire(_:lastRun:now:staleSignal:approvalPendingSignal:)``, with the
    /// reason attached. `shouldFire` delegates here so the verdict and its explanation can never
    /// disagree.
    public static func evaluate(
        _ trigger: PlaybookTrigger,
        lastRun: Date?,
        now: Date = .now,
        staleSignal: Bool = false,
        approvalPendingSignal: Bool = false
    ) -> TriggerEvaluation {
        // Normalised rather than trusted as given. This is a public entry point taking a *bare*
        // trigger, so an interval carrying no cadence — zero, negative, or `NaN` — can arrive without
        // having passed through ``Playbook``'s construction/decode guard. Reusing
        // ``PlaybookTrigger/normalized`` keeps one definition of "schedulable" instead of a second
        // opinion here that could drift from the model's.
        switch trigger.normalized {
        case .manual:
            return TriggerEvaluation(isDue: false, rationale: "Manual trigger — only runs when asked.")
        case let .schedule(interval):
            return intervalEvaluation(interval, lastRun: lastRun, now: now, kind: "Scheduled")
        case .event(.artifactStale):
            return TriggerEvaluation(
                isDue: staleSignal,
                rationale: staleSignal
                    ? "A draft artifact has gone stale."
                    : "No stale draft artifact."
            )
        case .event(.approvalPendingTooLong):
            return TriggerEvaluation(
                isDue: approvalPendingSignal,
                rationale: approvalPendingSignal
                    ? "An approval has been pending too long."
                    : "No approval pending past its window."
            )
        case let .maintenance(interval):
            return intervalEvaluation(interval, lastRun: lastRun, now: now, kind: "Maintenance")
        }
    }

    public static func evaluate(
        _ trigger: PlaybookTrigger,
        lastRun: Date?,
        now: Date = .now,
        eventSignals: RoutineEventSignals
    ) -> TriggerEvaluation {
        switch trigger {
        case .event(.artifactStale):
            return eventEvaluation(
                eventSignals.artifactStaleAt,
                lastRun: lastRun,
                now: now,
                dueRationale: "A draft artifact has gone stale.",
                absentRationale: "No new stale draft artifact."
            )
        case .event(.approvalPendingTooLong):
            return eventEvaluation(
                eventSignals.approvalPendingTooLongAt,
                lastRun: lastRun,
                now: now,
                dueRationale: "An approval has been pending too long.",
                absentRationale: "No new approval pending past its window."
            )
        default:
            return evaluate(trigger, lastRun: lastRun, now: now)
        }
    }

    private static func eventEvaluation(
        _ occurredAt: Date?,
        lastRun: Date?,
        now: Date,
        dueRationale: String,
        absentRationale: String
    ) -> TriggerEvaluation {
        guard let occurredAt, occurredAt <= now else {
            return TriggerEvaluation(isDue: false, rationale: absentRationale)
        }
        guard lastRun.map({ occurredAt > $0 }) ?? true else {
            return TriggerEvaluation(isDue: false, rationale: "Event already handled by the latest run.")
        }
        return TriggerEvaluation(isDue: true, rationale: dueRationale)
    }

    private static func intervalEvaluation(
        _ interval: TimeInterval,
        lastRun: Date?,
        now: Date,
        kind: String
    ) -> TriggerEvaluation {
        guard let lastRun else {
            return TriggerEvaluation(isDue: true, rationale: "\(kind) — has never run.")
        }
        let elapsed = now.timeIntervalSince(lastRun)
        // A last-run stamp dated after `now` is a clock anomaly, not a cadence: the device clock was
        // set forward, a run was recorded against it, and the clock was later corrected back.
        // Waiting for wall-clock to catch up would retire the routine for however far the clock had
        // jumped — a stall of years from one mistake — so an untrustworthy stamp fires once and
        // re-anchors the cadence on the corrected clock. (`Date` is absolute, so a DST change or a
        // time-zone move never produces this; only the clock itself moving does.)
        guard elapsed >= 0 else {
            return TriggerEvaluation(
                isDue: true,
                rationale: "\(kind) — last run is dated in the future; re-anchoring."
            )
        }
        guard elapsed >= interval else {
            return TriggerEvaluation(
                isDue: false,
                rationale: "\(kind) — due in \(remainingDescription(interval - elapsed))."
            )
        }
        return TriggerEvaluation(isDue: true, rationale: "\(kind) — interval elapsed.")
    }

    /// Whole seconds for a rationale, without the abort `Int(_:)` carries.
    ///
    /// `Int(_:)` traps on a non-finite or out-of-`Int`-range `Double`. The model layer bounds
    /// intervals below but deliberately *not* above — a long cadence is a playbook's to declare — so
    /// an absurd-but-finite declaration such as `1e30` seconds reaches here and would abort the
    /// background due-scan while merely *formatting* the reason a routine isn't due yet.
    private static func remainingDescription(_ seconds: TimeInterval) -> String {
        guard let whole = Int(exactly: seconds.rounded()) else { return "more than \(Int.max)s" }
        return "\(whole)s"
    }
}

/// The scheduling loop skeleton: gather context → run operator → produce artifact → record
/// performance + an execution record. Time/background triggering is the app's job (BGTaskScheduler);
/// this engine exposes `runOnce` and a pure trigger evaluator so the app just decides *when* to call.
public actor SchedulingEngine {
    private let playbooks: any PlaybookStore
    private let context: any ContextProviding
    private let contracts: any ContextContractResolving
    private let op: any RoutineOperator
    private let artifacts: any RoutineArtifactPersisting
    private let performance: any PerformanceRecording
    private let records: any ExecutionRecordStoring
    /// Resolves *what* permits a routine run, so the execution record can name the grant rather than
    /// just the actor (P0.5-601/602).
    ///
    /// Optional, and `nil` by default: with no registry attached the engine behaves exactly as before
    /// — runs are gated only by the playbook's declared authority envelope and record
    /// `.policyDefault` authority. Attaching a registry turns on lease enforcement for scheduled
    /// work, which is a real behavior change, so it is opt-in at the composition root.
    private let leaseRegistry: CapabilityLeaseRegistry?
    /// Trace sink for routine runs (P0.5-602 "through what workflow").
    ///
    /// Optional so the engine stays usable without one, but when attached every run writes its phases
    /// under the run's `correlationID` — the same key its receipt uses. Without it, a routine receipt
    /// resolves to a session but `steps(forCorrelationID:)` returns empty, because scheduled work
    /// never passes through the governed pipeline that writes the trace for interactive work.
    private let worklog: (any WorklogRecording)?
    private var globallyPaused = false

    public init(
        playbooks: any PlaybookStore,
        context: any ContextProviding,
        contracts: any ContextContractResolving,
        operator op: any RoutineOperator,
        artifacts: any RoutineArtifactPersisting,
        performance: any PerformanceRecording,
        executionRecords: any ExecutionRecordStoring = InMemoryExecutionRecordStore(),
        leaseRegistry: CapabilityLeaseRegistry? = nil,
        worklog: (any WorklogRecording)? = nil,
        initiallyPaused: Bool = false
    ) {
        self.playbooks = playbooks
        self.context = context
        self.contracts = contracts
        self.op = op
        self.artifacts = artifacts
        self.performance = performance
        self.records = executionRecords
        self.leaseRegistry = leaseRegistry
        self.worklog = worklog
        self.globallyPaused = initiallyPaused
    }

    public func setPaused(_ paused: Bool) {
        globallyPaused = paused
    }

    public func executionRecords() async -> [ExecutionRecord] {
        await records.all().sorted { $0.startedAt > $1.startedAt }
    }

    public func latestExecution(forPlaybookID playbookID: String) async -> ExecutionRecord? {
        await records.latest(forPlaybookID: playbookID)
    }

    /// The outcome of a routine run's authority check: the grant that permits it, or why it doesn't.
    private enum AuthorityResolution {
        case granted(AuthorityRef)
        case refused(String)
    }

    /// Resolves which grant permits `playbook` to run as `actor`.
    ///
    /// With no lease registry attached, standing policy is the authority and nothing is refused —
    /// preserving the pre-registry behavior of scheduled work. With one attached, *every* capability
    /// the playbook declares must be covered by an active lease; the run is refused otherwise. Fails
    /// closed: a declared capability with no grant blocks the run rather than proceeding unattributed.
    private func resolveAuthority(
        for playbook: Playbook,
        actor: ActorRef,
        at now: Date
    ) async -> AuthorityResolution {
        let capabilities = playbook.authority.capabilities

        guard let leaseRegistry else {
            return .granted(
                .policyDefault(
                    capability: capabilities.first,
                    // User-facing: this string is rendered as the "Authority reason" on every routine
                    // receipt, so it states the permission in the operator's terms rather than
                    // naming an absent internal component.
                    reason: "Standing policy permits this routine; no capability lease was required."
                )
            )
        }

        // A playbook that declares no capabilities exercises none — standing policy is the honest
        // answer, not a lease that cannot exist.
        guard !capabilities.isEmpty else {
            return .granted(.policyDefault(reason: "Playbook declares no capabilities."))
        }

        var grantingLeases: [CapabilityLease] = []
        for capability in capabilities {
            guard let lease = await leaseRegistry.grantingLease(
                capability,
                to: actor,
                correlationID: nil,
                scope: CapabilityLeaseScope.defaultScope(for: capability),
                at: now
            ) else {
                return .refused("Missing active capability lease for \(capability.rawValue).")
            }
            grantingLeases.append(lease)
        }

        // Record the grant covering the playbook's first declared capability: the declaration order
        // is the playbook's own statement of what it primarily does.
        return .granted(AuthorityRef(lease: grantingLeases[0]))
    }

    /// - Parameter actor: Who triggered the run (P0.5-602). When `nil`, the actor is derived from the
    ///   trigger via ``TriggerSource/defaultActor(playbookID:)`` — the named `.scheduledRoutine` for
    ///   automated triggers, the
    ///   human for manual runs. Callers that know the specific human or operator should pass it.
    /// - Parameter correlationID: The workflow this run belongs to. When `nil`, the run's own id is
    ///   used, so the record, its receipt, and its worklog steps still share one key.
    @discardableResult
    public func runOnce(
        playbookID: String,
        trigger: TriggerSource,
        actor: ActorRef? = nil,
        correlationID: String? = nil
    ) async -> ExecutionRecord {
        let start = Date()
        // Wall-clock for `startedAt`, because run history has to be displayable and orderable across
        // launches — but the *duration* is measured on a monotonic clock. A wall-clock delta spans any
        // NTP correction or manual clock change landing mid-run, reporting a negative or wildly
        // inflated duration into ``PerformanceEvent`` and from there into routine health, where it is
        // indistinguishable from a genuinely slow run.
        let startInstant = ContinuousClock.now
        let resolvedActor = actor ?? trigger.defaultActor(playbookID: playbookID)
        // The run id is minted up front rather than by `ExecutionRecord`'s default, because the
        // worklog steps written *during* the run have to carry the same correlation id the record
        // ends up with. Deriving it at the end would file the trace under a key nothing else uses.
        let runID = UUID()
        let resolvedCorrelationID = correlationID ?? runID.uuidString
        // Set once authority is resolved, so short-circuit outcomes above that point (paused,
        // uninstalled) honestly record no authority rather than inventing one.
        var resolvedAuthority: AuthorityRef?
        // Accumulated through an actor rather than a captured `var` for the same reason `authority`
        // is passed rather than captured below: a nested async function mutating local state across
        // an await is a data race under Swift 6 region isolation.
        let evidence = EvidenceAccumulator()

        // `authority` is passed rather than captured: a nested async function capturing the mutable
        // `resolvedAuthority` is a data race under Swift 6 region isolation.
        func trace(_ phase: RoutinePhase, detail: String? = nil, authority: AuthorityRef?) async {
            guard let worklog else { return }
            let result = await worklog.record(
                WorkflowStepLog(
                    correlationID: resolvedCorrelationID,
                    toolID: playbookID,
                    event: .routinePhase(phase, detail: detail),
                    actor: resolvedActor,
                    authority: authority
                )
            )
            if let failure = result.failure {
                await evidence.append(EvidenceFailure(component: "worklog", message: failure.localizedDescription))
            }
        }

        func finish(
            _ outcome: PlaybookRunOutcome,
            artifactID: UUID?,
            failureReason: String? = nil,
            blockCategory: PerformanceBlockCategory? = nil
        ) async -> ExecutionRecord {
            // The terminal phase mirrors the outcome, so a surface deriving workflow state from the
            // trace reaches the same verdict as the execution record without parsing prose.
            let terminal: RoutinePhase
            switch outcome {
            case .success, .noOp: terminal = .completed
            case .needsApproval: terminal = .awaitingApproval
            case .blocked: terminal = .blocked
            case .failed: terminal = .failed
            }
            await trace(terminal, detail: failureReason ?? outcome.rawValue, authority: resolvedAuthority)
            let evidenceFailures = await evidence.all
            let record = ExecutionRecord(
                id: runID,
                playbookID: playbookID,
                triggerSource: trigger,
                actor: resolvedActor,
                authority: resolvedAuthority,
                correlationID: resolvedCorrelationID,
                outcome: outcome,
                artifactID: artifactID,
                startedAt: start,
                durationSeconds: startInstant.elapsedSeconds(to: .now),
                failureReason: failureReason,
                evidenceCompleteness: evidenceFailures.isEmpty ? .complete : .incomplete(evidenceFailures)
            )
            await records.store(record)
            await performance.record(
                PerformanceEvent(
                    playbookID: playbookID,
                    outcome: outcome,
                    durationSeconds: record.durationSeconds,
                    runID: record.id,
                    triggerSource: trigger.rawValue,
                    failureReason: failureReason,
                    blockCategory: blockCategory
                )
            )
            return record
        }

        // Kill switch / pause short-circuits to a recorded no-op.
        if globallyPaused {
            return await finish(.noOp, artifactID: nil)
        }
        let playbook: Playbook
        do {
            guard let storedPlaybook = try await playbooks.playbook(id: playbookID) else {
                return await finish(.noOp, artifactID: nil)
            }
            playbook = storedPlaybook
        } catch {
            return await finish(
                .failed,
                artifactID: nil,
                failureReason: "Playbook persistence failed: \(error.localizedDescription)"
            )
        }
        guard playbook.installState == .installed else {
            return await finish(.noOp, artifactID: nil)
        }
        guard playbook.supportsV0ReadPrepareOnly else {
            return await finish(.blocked, artifactID: nil, blockCategory: .unsupported)
        }

        // Resolve *what* permits this run before any operator sees data (P0.5-601/602). Resolving and
        // enforcing are the same step: the grant that lets the run through is the one recorded, so
        // history can answer "under what authority" instead of only "who".
        switch await resolveAuthority(for: playbook, actor: resolvedActor, at: start) {
        case let .granted(authority):
            resolvedAuthority = authority
            // Recorded after assignment so the entry — and every entry after it — carries the grant.
            await trace(.authorityResolved, detail: authority.displaySummary, authority: authority)
        case let .refused(reason):
            return await finish(.blocked, artifactID: nil, failureReason: reason, blockCategory: .authority)
        }

        let bundle = await context.gather(for: playbook)

        // Governed operating context (P0.5-402) is fail-closed: every playbook must have a contract,
        // and only the contract-approved projection is handed to the operator.
        guard let contract = contracts.contract(for: playbook) else {
            return await finish(
                .blocked,
                artifactID: nil,
                failureReason: "context contract missing for playbook \(playbook.id)",
                blockCategory: .context
            )
        }
        let validation = ContextGovernanceBoundary().authorize(bundle, against: contract, at: Date())
        guard case let .success(governedContext) = validation else {
            let violations: [String]
            if case let .failure(failure) = validation {
                violations = failure.violations
            } else {
                violations = ["unknown context-governance failure"]
            }
            return await finish(
                .blocked,
                artifactID: nil,
                failureReason: "context contract unsatisfied: " + violations.joined(separator: "; "),
                blockCategory: .context
            )
        }
        await trace(.contextGathered, detail: governedContext.auditSummary, authority: resolvedAuthority)
        let result = await op.run(playbook: playbook, context: governedContext)
        await trace(
            .operatorFinished,
            detail: result.failureReason ?? result.outcome.rawValue,
            authority: resolvedAuthority
        )

        var artifactID: UUID?
        if let draft = result.artifact {
            // The output-type filter is a real governance decision — a rejected artifact is work the
            // playbook's authority envelope refused to persist — so the trace records both branches
            // rather than only the happy one.
            if playbook.authority.allowedOutputs.contains(draft.type) {
                do {
                    artifactID = try await artifacts.create(draft)
                    await trace(.artifactProduced, detail: draft.type.rawValue, authority: resolvedAuthority)
                } catch {
                    return await finish(
                        .failed,
                        artifactID: nil,
                        failureReason: "Artifact persistence failed: \(error.localizedDescription)",
                        blockCategory: .infrastructure
                    )
                }
            } else {
                await trace(
                    .artifactRejected,
                    detail: "\(draft.type.rawValue) is not an allowed output for this playbook",
                    authority: resolvedAuthority
                )
            }
        }
        return await finish(
            result.outcome,
            artifactID: artifactID,
            failureReason: result.failureReason,
            blockCategory: result.blockCategory
        )
    }
}

private extension ContinuousClock.Instant {
    /// Seconds from this instant to `other`, as the `Double` an ``ExecutionRecord`` stores.
    ///
    /// `Duration` has no lossless seconds accessor, so the two components are recombined by hand
    /// rather than going through a formatter.
    func elapsedSeconds(to other: ContinuousClock.Instant) -> Double {
        let components = duration(to: other).components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

/// Collects evidence-emission failures across the awaits of a single playbook run.
///
/// A local `var` mutated by the run's nested async trace helper is a data race under Swift 6 region
/// isolation; an actor keeps the accumulation correct without an unsafe escape.
private actor EvidenceAccumulator {
    private var failures: [EvidenceFailure] = []

    func append(_ failure: EvidenceFailure) {
        failures.append(failure)
    }

    var all: [EvidenceFailure] {
        failures
    }
}
