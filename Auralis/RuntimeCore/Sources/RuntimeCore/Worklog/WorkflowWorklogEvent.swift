import CapabilitiesCore
import Foundation

/// One option a planner weighed while deciding what to do, recorded on the worklog so Mission
/// Control can show *how the system reasoned* — what was considered, and what was rejected and why —
/// not just the action that ultimately ran. Planner-agnostic on purpose: any planner can describe
/// its deliberation this way.
public struct ConsideredCandidate: Equatable, Sendable, Codable {
    /// A short, user-facing label for the option (a template id, a proposed step/tool title, …).
    public let title: String
    /// The capability the option would exercise, when one is known.
    public let capability: CapabilityID?
    /// Whether the option was chosen for the plan.
    public let wasSelected: Bool
    /// Why the option was selected, or — for rejected options — why it was dropped.
    public let rationale: String

    public init(
        title: String,
        capability: CapabilityID? = nil,
        wasSelected: Bool,
        rationale: String
    ) {
        self.title = title
        self.capability = capability
        self.wasSelected = wasSelected
        self.rationale = rationale
    }
}

/// A single entry in the execution trace of a governed action.
///
/// Receipts are the human-facing summary; the worklog is the fine-grained trace — what was proposed,
/// which checks ran, what the Judge decided, and what execution did. This split is what makes
/// debugging, Mission Control, and (later) evals possible.
public enum WorkflowWorklogEvent: Equatable, Sendable {
    /// The options the planner considered before proposing an action — including the ones it
    /// rejected. Recorded ahead of `proposed` so the trace reads "here's what I weighed, here's what
    /// I chose".
    case considered([ConsideredCandidate])
    case proposed(ActionProposal)
    case checksEvaluated([DeterministicCheckResult])
    case decided(JudgeDecision)
    case executed(artifactID: UUID, durationSeconds: Double)
    case blocked(reason: String)
    case failed(reason: String)
    /// A phase of a scheduled routine's run (P0.5-602 "through what workflow").
    ///
    /// Routine runs don't go through the governed proposal pipeline, so none of the cases above
    /// describe them — which is why scheduled work previously wrote no trace at all and
    /// `steps(forCorrelationID:)` on a routine receipt returned empty by construction.
    case routinePhase(RoutinePhase, detail: String?)
    /// An event whose shape this build cannot interpret, carried verbatim (L-09).
    ///
    /// Reached on a downgrade — an older build reading rows a newer one wrote — where the case name
    /// is unfamiliar, an associated payload gained a required field, or a ``RoutinePhase`` is newer
    /// than this enum. Previously all three threw, and because the stores read through
    /// `try?`/`compactMap` the *whole entry* was discarded: the actor, authority, timestamp, and
    /// correlationID that make the surrounding trace legible went with it, so a workflow read as
    /// though it had skipped a step rather than as though one step was unreadable.
    ///
    /// `payload` holds the original JSON and re-encodes exactly as it arrived, so a downgrade
    /// degrades *rendering* without destroying data: exports stay faithful and reinstalling the
    /// newer build recovers the real event. Never write this case — it exists only for decoding.
    case unknown(caseName: String, payload: WorklogRawJSON)
}

public enum WorklogValidationError: Error, Equatable, Sendable, LocalizedError {
    case invalidDuration(Double)

    public var errorDescription: String? {
        switch self {
        case let .invalidDuration(value):
            return "Worklog execution duration must be finite and nonnegative; received \(value)."
        }
    }
}

public struct WorklogFailure: Error, Equatable, Sendable, Codable, LocalizedError {
    public enum Operation: String, Equatable, Sendable, Codable {
        case encode, fetch, save, reset
    }

    public let operation: Operation
    public let message: String

    public init(operation: Operation, message: String) {
        self.operation = operation
        self.message = message
    }

    public var errorDescription: String? { "Worklog \(operation.rawValue) failed: \(message)" }
}

public enum WorklogRecordResult: Equatable, Sendable {
    case recorded
    case failed(WorklogFailure)

    public var failure: WorklogFailure? {
        guard case let .failed(failure) = self else { return nil }
        return failure
    }
}

public struct EvidenceFailure: Equatable, Sendable, Codable {
    public let component: String
    public let message: String

    public init(component: String, message: String) {
        self.component = component
        self.message = message
    }
}

public enum EvidenceCompleteness: Equatable, Sendable, Codable {
    case complete
    case incomplete([EvidenceFailure])

    public var isComplete: Bool {
        if case .complete = self { return true }
        return false
    }
}

public struct WorklogStoreHealth: Equatable, Sendable, Codable {
    public let lastSuccessfulWriteAt: Date?
    public let lastFailureAt: Date?
    public let lastFailure: WorklogFailure?
    public let failedOperationCount: Int

    public init(
        lastSuccessfulWriteAt: Date? = nil,
        lastFailureAt: Date? = nil,
        lastFailure: WorklogFailure? = nil,
        failedOperationCount: Int = 0
    ) {
        self.lastSuccessfulWriteAt = lastSuccessfulWriteAt
        self.lastFailureAt = lastFailureAt
        self.lastFailure = lastFailure
        self.failedOperationCount = failedOperationCount
    }

    public var isDegraded: Bool { lastFailure != nil }
}

/// The event kinds this build understands, mirrored so the compiler keeps generating their wire
/// format.
///
/// ``WorkflowWorklogEvent`` needs hand-written coding to fall back to `.unknown`, and hand-written
/// coding would mean hand-reproducing Swift's synthesized enum representation — the single-key
/// wrapper object, and `_0` for unlabelled payloads — where one mismatch would silently orphan
/// every row already on disk. Mirroring the known cases keeps synthesis instead, so the format is
/// compiler-guaranteed to be byte-identical to what earlier builds wrote. Add cases here and to
/// ``WorkflowWorklogEvent`` together; the mapping switches below make omitting one a compile error.
private enum KnownWorklogEvent: Codable {
    case considered([ConsideredCandidate])
    case proposed(ActionProposal)
    case checksEvaluated([DeterministicCheckResult])
    case decided(JudgeDecision)
    case executed(artifactID: UUID, durationSeconds: Double)
    case blocked(reason: String)
    case failed(reason: String)
    case routinePhase(RoutinePhase, detail: String?)

    /// Returns `nil` only for ``WorkflowWorklogEvent/unknown(caseName:payload:)``, which by
    /// definition has no mirror.
    init?(_ event: WorkflowWorklogEvent) {
        switch event {
        case let .considered(candidates): self = .considered(candidates)
        case let .proposed(proposal): self = .proposed(proposal)
        case let .checksEvaluated(results): self = .checksEvaluated(results)
        case let .decided(decision): self = .decided(decision)
        case let .executed(artifactID, duration):
            self = .executed(artifactID: artifactID, durationSeconds: duration)
        case let .blocked(reason): self = .blocked(reason: reason)
        case let .failed(reason): self = .failed(reason: reason)
        case let .routinePhase(phase, detail): self = .routinePhase(phase, detail: detail)
        case .unknown: return nil
        }
    }

    var event: WorkflowWorklogEvent {
        switch self {
        case let .considered(candidates): return .considered(candidates)
        case let .proposed(proposal): return .proposed(proposal)
        case let .checksEvaluated(results): return .checksEvaluated(results)
        case let .decided(decision): return .decided(decision)
        case let .executed(artifactID, duration):
            return .executed(artifactID: artifactID, durationSeconds: duration)
        case let .blocked(reason): return .blocked(reason: reason)
        case let .failed(reason): return .failed(reason: reason)
        case let .routinePhase(phase, detail): return .routinePhase(phase, detail: detail)
        }
    }
}

extension WorkflowWorklogEvent: Codable {
    public init(from decoder: any Decoder) throws {
        if let known = try? KnownWorklogEvent(from: decoder) {
            self = known.event
            return
        }
        // Not a shape this build can interpret. Any failure lands here, not just an unfamiliar case
        // name, because the alternative — distinguishing "newer build" from "corrupt bytes" — would
        // need a hardcoded list of known case names that a future author could forget to extend,
        // silently degrading a brand-new event on the very build that writes it. Keeping the entry
        // is the right answer either way: corrupt bytes preserved verbatim are still more than a
        // dropped row, and a later build may be able to read them.
        let container = try decoder.container(keyedBy: SingleKeyEnumCodingKey.self)
        guard container.allKeys.count == 1, let key = container.allKeys.first else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: """
                        Expected a single-key worklog event object, found \
                        \(container.allKeys.count) keys.
                        """
                )
            )
        }
        self = .unknown(
            caseName: key.stringValue,
            payload: try container.decode(WorklogRawJSON.self, forKey: key)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        if let known = KnownWorklogEvent(self) {
            try known.encode(to: encoder)
        } else if case let .unknown(caseName, payload) = self {
            // Re-emitted under its original case name rather than as an `unknown` wrapper, so the
            // round trip is lossless: a newer build reading this export gets the real event back,
            // and two exports of the same trace still compare equal.
            var container = encoder.container(keyedBy: SingleKeyEnumCodingKey.self)
            try container.encode(payload, forKey: SingleKeyEnumCodingKey(caseName))
        }
    }
}

/// A verbatim JSON value, used to carry a worklog event this build cannot interpret.
///
/// Exists so forward compatibility is *lossless*. Recording only that an event was unrecognized
/// would make every downgrade a one-way loss the moment the trace was exported; holding the original
/// payload means the bytes survive the round trip and stay diffable for evals.
public enum WorklogRawJSON: Equatable, Sendable, Codable {
    case null
    case bool(Bool)
    /// Whole numbers stay integers so counts and identifiers survive intact; only values `Int`
    /// cannot represent fall through to ``number(_:)``. A `Double` that happens to be whole (`1.0`)
    /// therefore re-encodes as `1` — the same JSON number, not the same spelling.
    case integer(Int)
    case number(Double)
    case string(String)
    case array([WorklogRawJSON])
    case object([String: WorklogRawJSON])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([WorklogRawJSON].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: WorklogRawJSON].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .integer(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }
}

/// The phases a scheduled routine's run passes through, as recorded on the worklog.
///
/// A closed enum rather than a free string so the surfaces that derive workflow state from a trace
/// stay exhaustive: a new phase becomes a compile error at each derivation instead of silently
/// falling into a default branch and mis-reporting the run.
///
/// Deliberately has no `unrecognized` case, which would forfeit that exhaustiveness for every
/// caller in order to serve one decoding path. A phase written by a newer build is handled a level
/// up instead: the `routinePhase` decode fails and the entry becomes
/// ``WorkflowWorklogEvent/unknown(caseName:payload:)``, which keeps the trace *and* the unknown
/// phase's raw name inside its payload.
public enum RoutinePhase: String, Equatable, Sendable, Codable, CaseIterable {
    case authorityResolved
    case contextGathered
    case operatorFinished
    case artifactProduced
    /// The playbook's authority envelope refused to persist the produced artifact — a governance
    /// decision worth tracing, not just an absent output.
    case artifactRejected
    /// The routine prepared work successfully but is paused until a person decides whether it may
    /// proceed. This is deliberately non-terminal: it must not be counted or pruned as completed.
    case awaitingApproval
    case completed
    case blocked
    case failed

    /// A user-facing label for trust surfaces.
    public var displayTitle: String {
        switch self {
        case .authorityResolved: return "Authority resolved"
        case .contextGathered: return "Context gathered"
        case .operatorFinished: return "Operator finished"
        case .artifactProduced: return "Artifact produced"
        case .artifactRejected: return "Artifact rejected"
        case .awaitingApproval: return "Awaiting approval"
        case .completed: return "Completed"
        case .blocked: return "Blocked"
        case .failed: return "Failed"
        }
    }
}

/// A timestamped, correlated worklog entry.
public struct WorkflowStepLog: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public let correlationID: String?
    public let workflowRun: WorkflowRunRef
    public let toolID: String?
    public let event: WorkflowWorklogEvent
    /// Who this trace entry is attributed to. Every event kind carries attribution — not just
    /// `proposed`, whose `ActionProposal` also embeds an actor — so a workflow run's full trace
    /// (`considered`, `decided`, `executed`, `blocked`, …) records who acted, not only the steps
    /// that happened to come from a proposal. Required: an entry with no actor has no meaning.
    public let actor: ActorRef
    /// The authority the entry happened under, when one had been resolved (P0.5-601/602).
    ///
    /// Optional because the early trace entries are genuinely pre-authority: a proposal is recorded,
    /// checks run, and the Judge decides *before* any grant is consulted. Entries from the point of
    /// permission onward carry it, so the trace shows not just who acted but what let them.
    public let authority: AuthorityRef?
    public let authorityState: AuthorityState
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        correlationID: String?,
        toolID: String?,
        event: WorkflowWorklogEvent,
        actor: ActorRef,
        authority: AuthorityRef? = nil,
        workflowRun: WorkflowRunRef? = nil,
        authorityState: AuthorityState? = nil,
        timestamp: Date = .now
    ) {
        self.id = id
        self.correlationID = correlationID
        self.workflowRun = workflowRun ?? .resolved(
            correlationID: correlationID,
            fallbackActionID: id
        )
        self.toolID = toolID
        self.event = event
        self.actor = actor
        self.authority = authority
        self.authorityState = authorityState ?? authority.map(AuthorityState.resolved) ?? .pending
        self.timestamp = timestamp
    }

    public func validated() throws -> WorkflowStepLog {
        if case let .executed(_, durationSeconds) = event,
           !durationSeconds.isFinite || durationSeconds < 0 {
            throw WorklogValidationError.invalidDuration(durationSeconds)
        }
        return self
    }

    /// Tolerant decoding for both attribution columns: worklog entries persisted before `actor` or
    /// `authority` existed — or carrying an authority this build cannot read — decode with a fallback
    /// rather than being dropped entirely by the store's `try?`. A missing actor is worth more as
    /// `.system` than as an erased trace entry — the whole point of the worklog is that history
    /// survives.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        correlationID = try container.decodeIfPresent(String.self, forKey: .correlationID)
        workflowRun = try container.decodeIfPresent(WorkflowRunRef.self, forKey: .workflowRun)
            ?? .resolved(correlationID: correlationID, fallbackActionID: id)
        toolID = try container.decodeIfPresent(String.self, forKey: .toolID)
        event = try container.decode(WorkflowWorklogEvent.self, forKey: .event)
        actor = try container.decodeIfPresent(ActorRef.self, forKey: .actor) ?? .system
        authority = AuthorityRef.decodedIfPresent(from: container, forKey: .authority)
        authorityState = try container.decodeIfPresent(AuthorityState.self, forKey: .authorityState)
            ?? authority.map(AuthorityState.resolved)
            ?? .legacyUnknown
        timestamp = try container.decode(Date.self, forKey: .timestamp)
    }
}

/// Sink for worklog entries.
public protocol WorklogRecording: Sendable {
    @discardableResult
    func record(_ step: WorkflowStepLog) async -> WorklogRecordResult
}

/// Adds a visible runtime signal to every failed worklog write while preserving the typed result for
/// callers that must fail closed or attach evidence status to their own durable record.
public actor EvidenceReportingWorklogRecorder: WorklogRecording {
    private let base: any WorklogRecording
    private let events: any RuntimeEventPublishing

    public init(base: any WorklogRecording, events: any RuntimeEventPublishing) {
        self.base = base
        self.events = events
    }

    @discardableResult
    public func record(_ step: WorkflowStepLog) async -> WorklogRecordResult {
        let result = await base.record(step)
        if let failure = result.failure {
            await events.publish(WorkflowEventEnvelope(
                event: .executionUpdate("Worklog evidence degraded: \(failure.localizedDescription)"),
                correlationID: step.correlationID
            ))
        }
        return result
    }
}

/// Durable read/write worklog surface for Mission Control history.
public protocol WorklogStoring: WorklogRecording {
    func allSteps() async -> [WorkflowStepLog]
    func steps(forCorrelationID correlationID: String) async -> [WorkflowStepLog]
    /// A stable, self-contained JSON snapshot of the whole trace, oldest first.
    ///
    /// Distinct from ``allSteps()`` on purpose: that returns live values to an in-process reader,
    /// whereas evals and operator report cards need a byte-stable artifact they can carry off-device
    /// and diff between runs. Sorted keys and ascending timestamps so two exports of the same trace
    /// compare equal.
    func exportAll() async throws -> Data
    func resetAll() async
    func health() async -> WorklogStoreHealth
}

/// Shared encoder for worklog exports, so every store's snapshot is byte-comparable.
public enum WorklogExport {
    public static func encode(_ steps: [WorkflowStepLog]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // `id` breaks timestamp ties: entries written in the same instant (a routine's phases can
        // share a `.now`) would otherwise export in whatever order the store returned them, making
        // two exports of one trace differ byte-for-byte.
        return try encoder.encode(steps.sorted {
            $0.timestamp == $1.timestamp
                ? $0.id.uuidString < $1.id.uuidString
                : $0.timestamp < $1.timestamp
        })
    }
}

/// An in-memory worklog, primarily for tests and Mission Control's live view.
public actor InMemoryWorklog: WorklogStoring {
    private var steps: [WorkflowStepLog] = []
    private var storeHealth = WorklogStoreHealth()

    public init() { }

    @discardableResult
    public func record(_ step: WorkflowStepLog) -> WorklogRecordResult {
        do {
            steps.append(try step.validated())
            storeHealth = WorklogStoreHealth(lastSuccessfulWriteAt: .now)
            return .recorded
        } catch {
            let failure = WorklogFailure(operation: .encode, message: error.localizedDescription)
            storeHealth = WorklogStoreHealth(
                lastSuccessfulWriteAt: storeHealth.lastSuccessfulWriteAt,
                lastFailureAt: .now,
                lastFailure: failure,
                failedOperationCount: storeHealth.failedOperationCount + 1
            )
            return .failed(failure)
        }
    }

    public func allSteps() -> [WorkflowStepLog] {
        steps
    }

    public func steps(forCorrelationID correlationID: String) -> [WorkflowStepLog] {
        steps.filter { $0.correlationID == correlationID }
    }

    public func exportAll() throws -> Data {
        try WorklogExport.encode(steps)
    }

    public func resetAll() {
        steps.removeAll()
        storeHealth = WorklogStoreHealth()
    }

    public func health() -> WorklogStoreHealth { storeHealth }
}
