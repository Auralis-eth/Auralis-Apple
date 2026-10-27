import Foundation

/// The disposition of one playbook/operator run, for performance tracking. (P1-603)
public enum PlaybookRunOutcome: String, Codable, CaseIterable, Sendable {
    case success
    case noOp
    case failed
    case blocked
    case needsApproval
}

/// Why a blocked run was refused. Keeping policy separate from infrastructure and configuration
/// failures prevents the dashboard from presenting every refusal as a policy decision.
public enum PerformanceBlockCategory: String, Codable, Equatable, Sendable {
    case policy
    case authority
    case context
    case unsupported
    case infrastructure
    case other
}

/// A person's terminal decision for an approval-gated run.
public enum PerformanceApprovalDecision: String, Codable, Equatable, Sendable {
    case approved
    case rejected
}

/// One recorded run of a playbook/operator.
public struct PerformanceEvent: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public let playbookID: String
    public let outcome: PlaybookRunOutcome
    public let durationSeconds: Double
    /// Whether a human had to step in (correction, manual completion) for this run.
    public let requiredIntervention: Bool
    public let recordedAt: Date
    /// The ``ExecutionRecord`` this event belongs to, so a later human action (e.g. approving the
    /// run's artifact) can be attributed back to the exact run that produced it. Optional for
    /// back-compat with events recorded before intervention tracking existed.
    public let runID: UUID?
    /// What triggered the run (`TriggerSource` raw value). Kept as a string so AuralisRuntime stays
    /// free of a dependency on AuralisRuntime. Feeds failure-pattern grouping.
    public let triggerSource: String?
    /// A short, stable reason a run failed, supplied by the operator. Nil for non-failing runs. The
    /// primary grouping key for failure patterns (P1-603 "failure patterns").
    public let failureReason: String?
    public let blockCategory: PerformanceBlockCategory?
    public let approvalDecision: PerformanceApprovalDecision?

    public init(
        id: UUID = UUID(),
        playbookID: String,
        outcome: PlaybookRunOutcome,
        durationSeconds: Double,
        requiredIntervention: Bool = false,
        recordedAt: Date = .now,
        runID: UUID? = nil,
        triggerSource: String? = nil,
        failureReason: String? = nil,
        blockCategory: PerformanceBlockCategory? = nil,
        approvalDecision: PerformanceApprovalDecision? = nil
    ) {
        self.id = id
        self.playbookID = playbookID
        self.outcome = outcome
        // A duration is elapsed time, so it cannot be negative or non-finite, and one bad sample is
        // not a local problem: ``PlaybookHealth/averageLatencySeconds`` sums the playbook's whole
        // history, so a single NaN (or a negative interval from a wall-clock step) poisons the mean
        // for every run of that playbook and surfaces as "nan" in Mission Control. Clamping at the
        // boundary keeps the aggregate honest even when a caller's own timing is not — only
        // ``RuntimePerformanceObserver`` clamps upstream today; the tool-call sink forwards raw.
        self.durationSeconds = durationSeconds.isFinite ? max(0, durationSeconds) : 0
        self.requiredIntervention = requiredIntervention
        self.recordedAt = recordedAt
        self.runID = runID
        self.triggerSource = triggerSource
        self.failureReason = failureReason
        self.blockCategory = blockCategory
        self.approvalDecision = approvalDecision
    }

    /// A copy of this event flagged as having required human intervention. Preserves identity so the
    /// aggregate run count is unchanged — intervention is a property *of* a run, not an extra run.
    public func markingIntervention() -> PerformanceEvent {
        PerformanceEvent(
            id: id,
            playbookID: playbookID,
            outcome: outcome,
            durationSeconds: durationSeconds,
            requiredIntervention: true,
            recordedAt: recordedAt,
            runID: runID,
            triggerSource: triggerSource,
            failureReason: failureReason,
            blockCategory: blockCategory,
            approvalDecision: approvalDecision
        )
    }

    /// A copy carrying the person's final approval decision. Identity is preserved because this is
    /// additional evidence about the original run, not a second execution.
    public func recordingApprovalDecision(_ decision: PerformanceApprovalDecision) -> PerformanceEvent {
        PerformanceEvent(
            id: id,
            playbookID: playbookID,
            outcome: outcome,
            durationSeconds: durationSeconds,
            requiredIntervention: requiredIntervention,
            recordedAt: recordedAt,
            runID: runID,
            triggerSource: triggerSource,
            failureReason: failureReason,
            blockCategory: blockCategory,
            approvalDecision: decision
        )
    }

    /// Decodes leniently, because this type *is* the persisted schema: `SwiftDataPerformanceStore`
    /// JSON-encodes a `PerformanceEvent` into each row's blob, and a row whose blob fails to decode is
    /// dropped entirely by the store's decode helper. Strict synthesized decoding therefore turns
    /// "this build does not recognise one field" into "this run never happened" — the run vanishes
    /// from history and from every rate computed over it.
    ///
    /// So the two forward-compatible directions are handled explicitly:
    ///
    /// - An **unrecognised raw value** (a category or decision added by a newer build, read back after
    ///   a downgrade) degrades to `.other`/`nil` rather than throwing. `PerformanceBlockCategory.other`
    ///   exists for exactly this; an unknown *outcome* has no such bucket, so it becomes `.noOp`, the
    ///   only case that keeps `totalRuns` truthful without fabricating a success, a failure or a
    ///   policy block — an unknown outcome must not be able to move `failureRate` and flip a
    ///   playbook's classification.
    /// - A **missing key** written before the field existed defaults instead of throwing.
    ///   ``requiredIntervention`` needs this for the same reason ``runID`` is optional: events
    ///   recorded before intervention tracking existed have neither key.
    ///
    /// Identity and the timing core (`id`, `playbookID`, `durationSeconds`, `recordedAt`) stay
    /// required — an event missing those is not a degraded run, it is not a run.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            playbookID: try container.decode(String.self, forKey: .playbookID),
            outcome: try container.decodeTolerantly(PlaybookRunOutcome.self, forKey: .outcome, unknown: .noOp) ?? .noOp,
            durationSeconds: try container.decode(Double.self, forKey: .durationSeconds),
            requiredIntervention: try container.decodeIfPresent(Bool.self, forKey: .requiredIntervention) ?? false,
            recordedAt: try container.decode(Date.self, forKey: .recordedAt),
            runID: try container.decodeIfPresent(UUID.self, forKey: .runID),
            triggerSource: try container.decodeIfPresent(String.self, forKey: .triggerSource),
            failureReason: try container.decodeIfPresent(String.self, forKey: .failureReason),
            blockCategory: try container.decodeTolerantly(
                PerformanceBlockCategory.self,
                forKey: .blockCategory,
                unknown: .other
            ),
            approvalDecision: try container.decodeTolerantly(PerformanceApprovalDecision.self, forKey: .approvalDecision)
        )
    }
}

private extension KeyedDecodingContainer {
    /// Decodes a string-raw-value enum without throwing on a case this build does not know.
    ///
    /// Decoding the raw `String` first and initialising by raw value is what makes this tolerant: the
    /// enum's own synthesized `init(from:)` throws `DataCorrupted` on an unknown case, and that throw
    /// is what would discard the surrounding event.
    ///
    /// - Parameter unknown: substituted when the key is **present but unrecognised**. Absence stays
    ///   `nil` regardless, because the two are not the same statement: a missing `blockCategory` means
    ///   the run was not blocked, while an unrecognised one means it was blocked for a reason this
    ///   build cannot name — collapsing them would invent a block that never happened.
    func decodeTolerantly<T: RawRepresentable & Decodable>(
        _ type: T.Type,
        forKey key: Key,
        unknown: T? = nil
    ) throws -> T? where T.RawValue == String {
        guard let raw = try decodeIfPresent(String.self, forKey: key) else { return nil }
        return T(rawValue: raw) ?? unknown
    }
}

/// A recurring failure signature for a playbook: how many times a given reason (or, absent a reason,
/// a given trigger) has failed, and when it was last seen. Descriptive only. (P1-603 "failure patterns")
public struct FailurePattern: Equatable, Sendable, Identifiable, Codable {
    public let key: String
    public let occurrences: Int
    public let lastSeen: Date

    public var id: String { key }
    /// A pattern is only "recurring" once it has happened more than once — a single failure is history,
    /// not yet a pattern.
    public var isRecurring: Bool { occurrences > 1 }

    public init(key: String, occurrences: Int, lastSeen: Date) {
        self.key = key
        self.occurrences = occurrences
        self.lastSeen = lastSeen
    }
}

/// A descriptive trust signal derived only from observed runs. It never grants capabilities or
/// changes a playbook's authority.
public enum PlaybookHealthClassification: String, Equatable, Sendable, Codable {
    case insufficientData
    case stable
    case needsAttention
    case flaky
}

/// Aggregate health for a playbook. Metrics are descriptive only — they never auto-escalate authority
/// (P1-603: "No automatic authority escalation based on performance").
public struct PlaybookHealth: Equatable, Sendable {
    public let playbookID: String
    public let totalRuns: Int
    public let successRate: Double
    public let averageLatencySeconds: Double
    public let interventionRate: Double
    public let approvalRate: Double
    public let blockRate: Double
    public let policyBlockRate: Double
    public let resolvedApprovalCount: Int
    public let failureCount: Int
    /// Failures grouped by recurring signature (reason, else trigger), most frequent first. Lets the
    /// dashboard show *why* a routine is flaky, not just that it is. (P1-603 "failure patterns")
    public let failurePatterns: [FailurePattern]
    public let classification: PlaybookHealthClassification

    public init(playbookID: String, events: [PerformanceEvent]) {
        self.playbookID = playbookID
        let total = events.count
        self.totalRuns = total
        let failures = events.filter { $0.outcome == .failed }
        self.failureCount = failures.count
        self.failurePatterns = Self.patterns(from: failures)
        guard total > 0 else {
            successRate = 0; averageLatencySeconds = 0; interventionRate = 0
            approvalRate = 0; blockRate = 0; policyBlockRate = 0; resolvedApprovalCount = 0
            classification = .insufficientData
            return
        }
        let denom = Double(total)
        successRate = Double(events.filter { $0.outcome == .success }.count) / denom
        let resolvedApprovals = events.compactMap(\.approvalDecision)
        resolvedApprovalCount = resolvedApprovals.count
        approvalRate = resolvedApprovals.isEmpty
            ? 0
            : Double(resolvedApprovals.filter { $0 == .approved }.count) / Double(resolvedApprovals.count)
        blockRate = Double(events.filter { $0.outcome == .blocked }.count) / denom
        policyBlockRate = Double(events.filter {
            $0.outcome == .blocked && $0.blockCategory == .policy
        }.count) / denom
        interventionRate = Double(events.filter(\.requiredIntervention).count) / denom
        averageLatencySeconds = events.map(\.durationSeconds).reduce(0, +) / denom
        classification = Self.classification(
            totalRuns: total,
            failureRate: Double(failures.count) / denom,
            blockRate: blockRate,
            interventionRate: interventionRate,
            hasRecurringFailure: failurePatterns.contains(where: \.isRecurring)
        )
    }

    /// Groups failed events by their reason (or, when absent, the trigger that produced them), sorted
    /// by frequency then recency so the most persistent problems surface first.
    private static func patterns(from failures: [PerformanceEvent]) -> [FailurePattern] {
        Dictionary(grouping: failures) { event in
            event.failureReason ?? "\(event.triggerSource ?? "unknown") trigger"
        }
        .map { key, group in
            FailurePattern(
                key: key,
                occurrences: group.count,
                lastSeen: group.map(\.recordedAt).max() ?? .distantPast
            )
        }
        .sorted { lhs, rhs in
            lhs.occurrences != rhs.occurrences ? lhs.occurrences > rhs.occurrences : lhs.lastSeen > rhs.lastSeen
        }
    }

    private static func classification(
        totalRuns: Int,
        failureRate: Double,
        blockRate: Double,
        interventionRate: Double,
        hasRecurringFailure: Bool
    ) -> PlaybookHealthClassification {
        guard totalRuns >= 5 else { return .insufficientData }
        if failureRate + blockRate >= 0.25 { return .flaky }
        // A recurring signature is corroborating evidence, not a verdict on its own. Ungated it was
        // the *dominant* term, because ``FailurePattern/isRecurring`` is only `occurrences > 1` and
        // patterns are computed over the playbook's whole retained history: two identical failures in
        // 1,000 otherwise-clean runs (0.2%) landed in `.flaky` — the same bucket as a playbook failing
        // a quarter of the time — and, since those two failures never age out, stayed there forever.
        // Requiring the recurrence to also clear the `.needsAttention` failure floor keeps what the
        // signal is for (a playbook failing the *same way* is worse than one failing randomly at the
        // same rate) while making volume matter. A sub-floor recurrence is still visible to the
        // dashboard through ``PlaybookHealth/failurePatterns``; it just no longer condemns the run.
        if hasRecurringFailure && failureRate >= 0.10 { return .flaky }
        if failureRate + blockRate >= 0.10 || interventionRate >= 0.10 { return .needsAttention }
        return .stable
    }
}

public protocol PerformanceRecording: Sendable {
    /// Records a run.
    ///
    /// **Idempotent by ``PerformanceEvent/id``:** recording an event whose ID is already present
    /// replaces that run rather than adding a second one. `id` defaults to a fresh `UUID`, so this
    /// only affects a caller that deliberately reuses one — and one does.
    /// ``RuntimePerformanceObserver`` keys planner runs by the runtime event envelope's ID precisely
    /// so that a replayed event cannot double-count: it checkpoints *after* recording, so a crash in
    /// between replays that event on the next launch.
    ///
    /// This is the same reasoning ``PerformanceEvent/markingIntervention()`` already relies on when it
    /// preserves identity — a run's ID is the run, so anything keyed to it is an update to that run
    /// and not an extra one. Stating it here makes the guarantee the observer depends on part of the
    /// contract rather than a property of whichever store happens to be wired up.
    func record(_ event: PerformanceEvent) async
}

/// Read side of a performance store: recording + per-playbook health queries. Lets Mission Control
/// bind to either the in-memory or a persistent implementation.
public protocol PerformanceStoring: PerformanceRecording {
    func events(forPlaybook playbookID: String) async -> [PerformanceEvent]
    func health(forPlaybook playbookID: String) async -> PlaybookHealth
    func allHealth() async -> [PlaybookHealth]
    /// Marks the run identified by `runID` as having required human intervention. No-op if the run
    /// is unknown (e.g. the event predates intervention tracking). Feeds ``PlaybookHealth/interventionRate``.
    func recordIntervention(runID: UUID) async
    /// Records a person's final decision on the approval request produced by `runID`.
    func recordApprovalDecision(runID: UUID, decision: PerformanceApprovalDecision) async
    /// Erases all recorded runs. Required rather than defaulted so a new store cannot silently
    /// survive a privacy reset: run history names what the person's operators did and when.
    func resetAll() async
}

extension PerformanceStore: PerformanceStoring { }

/// In-memory performance store: records runs and computes per-playbook health.
public actor PerformanceStore: PerformanceRecording {
    private var events: [PerformanceEvent] = []
    /// Position of each event in ``events``, so the idempotency check in ``record(_:)`` is a lookup
    /// rather than a scan of the whole history. Kept valid by the two facts that make it cheap: a
    /// replacement writes in place (the ID and its position are unchanged) and the only thing that
    /// ever removes an element is ``trimToCapacity()``, which rebuilds this map wholesale.
    private var indexByID: [UUID: Int] = [:]

    /// Ceiling on retained runs, for the same reason ``RuntimePerformanceObserver`` bounds its own
    /// buffers (1,024 recorded IDs, 256 pending runs): this store is `RuntimeHost`'s *default* when no
    /// durable one is injected, and `PerformancePipelineSink` records one event per governed tool call,
    /// so an uncapped array grows for the entire life of the process with only `resetAll()` to free it.
    ///
    /// 4,096 is chosen to be large enough that the aggregates stay meaningful — several hundred runs
    /// per playbook across a dozen playbooks, far beyond the 5-run floor `classification` needs — while
    /// costing on the order of a megabyte. It is deliberately much larger than the observer's windows:
    /// those only have to cover a replay window, whereas this is the sample the dashboard reasons over.
    private static let eventCapacity = 4_096
    /// How many of the newest runs survive a trim. Trimming in a block rather than one-in/one-out is
    /// what keeps ``record(_:)`` O(1) amortised: the O(n log n) trim is paid once per 1,024 inserts
    /// instead of on every insert past the ceiling, which is the quadratic behaviour a naive cap has.
    private static let retainedAfterTrim = 3_072

    public init() { }

    /// Idempotent by `event.id`; see ``PerformanceRecording/record(_:)``. The replacement keeps the
    /// original position so a re-recorded run does not jump to the end of the history.
    public func record(_ event: PerformanceEvent) {
        let event = merging(event)
        if let index = indexByID[event.id] {
            events[index] = event
        } else {
            events.append(event)
            indexByID[event.id] = events.count - 1
            trimToCapacity()
        }
    }

    /// Folds the human annotations already held for `event.id` into an incoming re-record.
    ///
    /// Replacement is what makes ``record(_:)`` idempotent, but a replayed event is reconstructed from
    /// the runtime envelope and so always carries `requiredIntervention == false` and
    /// `approvalDecision == nil` — it cannot know what a person did *after* it was first recorded.
    /// Overwriting wholesale therefore silently erased that evidence: record run X → the person
    /// approves it → crash before the observer checkpoints → the next launch replays X and the
    /// approval, along with any intervention flag, is gone from `approvalRate`/`interventionRate`.
    /// Annotations are properties of the run, and the run is its ID, so they survive the replay that
    /// the ``PerformanceRecording/record(_:)`` contract exists to permit. An incoming decision still
    /// wins, so this only ever recovers information, never pins a stale one.
    private func merging(_ event: PerformanceEvent) -> PerformanceEvent {
        guard let index = indexByID[event.id] else { return event }
        let existing = events[index]
        var merged = event
        if existing.requiredIntervention {
            merged = merged.markingIntervention()
        }
        if let decision = event.approvalDecision ?? existing.approvalDecision {
            merged = merged.recordingApprovalDecision(decision)
        }
        return merged
    }

    /// Drops the oldest runs by ``PerformanceEvent/recordedAt`` once the ceiling is passed.
    ///
    /// Ranks by `(recordedAt, position)` rather than `recordedAt` alone so that events sharing a
    /// timestamp still have a total order: a date-only cutoff cannot separate ties, and a burst of
    /// events recorded in the same instant — or a caller backdating them all to one `Date` — would
    /// leave nothing droppable and quietly restore the unbounded growth this cap exists to stop.
    /// Relative order among the survivors is preserved, because `recordApprovalDecision(runID:_:)`
    /// resolves by *last* matching position.
    private func trimToCapacity() {
        guard events.count > Self.eventCapacity else { return }
        let doomed = Set(
            events.indices
                .sorted { lhs, rhs in
                    events[lhs].recordedAt == events[rhs].recordedAt
                        ? lhs < rhs
                        : events[lhs].recordedAt < events[rhs].recordedAt
                }
                .prefix(events.count - Self.retainedAfterTrim)
        )
        events = events.enumerated().filter { !doomed.contains($0.offset) }.map(\.element)
        reindex()
    }

    private func reindex() {
        indexByID = Dictionary(
            uniqueKeysWithValues: events.enumerated().map { ($0.element.id, $0.offset) }
        )
    }

    /// Marks **every** event belonging to the run, not just the first.
    ///
    /// One `ExecutionRecord` can produce several performance events — `PerformancePipelineSink`
    /// writes one per governed tool call, all carrying the run's ID — and intervention is a
    /// property of the run, so leaving the rest unmarked understated `interventionRate` by however
    /// many tool calls the run made. The durable ``SwiftDataPerformanceStore`` already marks all of
    /// them; this is the same protocol, so it must not answer differently depending on whether a
    /// device has a SwiftData container.
    public func recordIntervention(runID: UUID) {
        for index in events.indices where events[index].runID == runID {
            events[index] = events[index].markingIntervention()
        }
    }

    /// Marks the run's **last** event, deliberately unlike ``recordIntervention(runID:)`` which marks
    /// every one: a person makes a single decision per run, and ``PlaybookHealth/approvalRate`` averages
    /// over the events that carry one, so annotating all N events of a multi-tool-call run would weight
    /// that one decision N times. This matches ``SwiftDataPerformanceStore``, which also takes the last.
    public func recordApprovalDecision(runID: UUID, decision: PerformanceApprovalDecision) {
        guard let index = events.lastIndex(where: { $0.runID == runID }) else { return }
        events[index] = events[index].recordingApprovalDecision(decision)
    }

    public func events(forPlaybook playbookID: String) -> [PerformanceEvent] {
        events.filter { $0.playbookID == playbookID }.sorted { $0.recordedAt < $1.recordedAt }
    }

    public func health(forPlaybook playbookID: String) -> PlaybookHealth {
        PlaybookHealth(playbookID: playbookID, events: events(forPlaybook: playbookID))
    }

    public func allHealth() -> [PlaybookHealth] {
        Dictionary(grouping: events, by: \.playbookID)
            .map { PlaybookHealth(playbookID: $0.key, events: $0.value) }
            .sorted { $0.playbookID < $1.playbookID }
    }

    public func resetAll() {
        events.removeAll()
        indexByID.removeAll()
    }
}
