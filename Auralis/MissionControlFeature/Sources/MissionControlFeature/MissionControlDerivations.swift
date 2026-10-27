import Foundation
import AuralisRuntime

/// A workflow's coarse lifecycle state, derived from its stream of events. (P1-102)
public enum WorkflowState: String, Sendable, CaseIterable {
    case queued
    case running
    case waiting
    case blocked
    case completed
    case failed

    public var label: String {
        switch self {
        case .queued: return "Queued"
        case .running: return "Running"
        case .waiting: return "Waiting"
        case .blocked: return "Blocked"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }

    public var systemImage: String {
        switch self {
        case .queued: return "tray.and.arrow.down"
        case .running: return "arrow.triangle.2.circlepath"
        case .waiting: return "hourglass"
        case .blocked: return "hand.raised"
        case .completed: return "checkmark.circle"
        case .failed: return "xmark.octagon"
        }
    }
}

public enum WorkflowStateFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case queued = "Queued"
    case running = "Running"
    case waiting = "Waiting"
    case blocked = "Blocked"
    case completed = "Completed"
    case failed = "Failed"

    public var id: String { rawValue }

    func includes(_ state: WorkflowState) -> Bool {
        switch self {
        case .all: return true
        case .queued: return state == .queued
        case .running: return state == .running
        case .waiting: return state == .waiting
        case .blocked: return state == .blocked
        case .completed: return state == .completed
        case .failed: return state == .failed
        }
    }
}

/// A grouped view of one workflow's activity, keyed by correlation id. (P1-102)
public struct WorkflowSummary: Identifiable, Sendable {
    public let id: String
    public let state: WorkflowState
    public let eventCount: Int
    public let lastUpdated: Date
    public let nextStep: String
    /// The account the workflow operates on, derived from its proposal parameters. (P1-102 filter)
    public let account: String
    /// The operator/playbook that produced the workflow, derived from its proposal. (P1-102 filter)
    public let playbook: String

    public init(
        id: String,
        state: WorkflowState,
        eventCount: Int,
        lastUpdated: Date,
        nextStep: String,
        account: String = MissionControlFacets.noAccount,
        playbook: String = MissionControlFacets.adHocPlaybook
    ) {
        self.id = id
        self.state = state
        self.eventCount = eventCount
        self.lastUpdated = lastUpdated
        self.nextStep = nextStep
        self.account = account
        self.playbook = playbook
    }
}

/// Sentinel labels for workflows with no derivable account / operator.
public enum MissionControlFacets {
    public static let noAccount = "No account"
    public static let adHocPlaybook = "Ad-hoc"
}

/// The four high-signal categories the Activity Feed distinguishes. (P1-103)
public enum ActivityCategory: String, Sendable, CaseIterable, Identifiable {
    case observation = "Observation"
    case preparation = "Preparation"
    case approvalNeeded = "Approval needed"
    case completed = "Completed"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .observation: return "eye"
        case .preparation: return "gearshape"
        case .approvalNeeded: return "hand.raised"
        case .completed: return "checkmark.seal"
        }
    }
}

/// One session's worth of high-signal activity, for the grouped Activity Feed. (P1-103)
public struct ActivityGroup: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let events: [WorkflowEventEnvelope]
    public let lastUpdated: Date
}

public extension MissionControlHomeModel {
    var timelineStateFilterBindingDefault: WorkflowStateFilter { .all }

    /// One row per correlated workflow, newest activity first. State and facets come from the durable
    /// worklog when available (distinct queued/failed/…); live-only workflows fall back to the event
    /// stream. (P1-102 Workflow Timeline)
    var workflowSummaries: [WorkflowSummary] {
        if let cached = workflowSummariesCache { return cached }
        let built = buildWorkflowSummaries()
        workflowSummariesCache = built
        return built
    }

    /// `workflowSummaries` indexed by correlation ID. The artifact provenance labels resolve one
    /// workflow per artifact, so a linear `first(where:)` per artifact made the Artifact Browser
    /// quadratic in the artifact count on top of rebuilding the summaries themselves.
    var workflowSummariesByID: [String: WorkflowSummary] {
        if let cached = workflowSummariesByIDCache { return cached }
        let built = Dictionary(
            workflowSummaries.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        workflowSummariesByIDCache = built
        return built
    }

    private func buildWorkflowSummaries() -> [WorkflowSummary] {
        let groupedEvents = Dictionary(grouping: liveEvents) { $0.correlationID ?? "(untracked)" }
        let stepsByCorrelation = Dictionary(grouping: workflowStepLogs) { $0.correlationID ?? "(untracked)" }
        return groupedEvents
            .map { key, envelopes in
                let ascending = envelopes.sorted { $0.timestamp < $1.timestamp }
                let steps = (stepsByCorrelation[key] ?? []).sorted { $0.timestamp < $1.timestamp }
                let state = steps.isEmpty
                    ? Self.state(for: ascending)
                    : Self.state(forWorklog: steps.map(\.event))
                return WorkflowSummary(
                    id: key,
                    state: state,
                    eventCount: envelopes.count,
                    lastUpdated: ascending.last?.timestamp ?? .distantPast,
                    nextStep: Self.nextStep(for: state),
                    account: Self.accountLabel(for: steps),
                    playbook: Self.playbookLabel(for: steps)
                )
            }
            .sorted { $0.lastUpdated > $1.lastUpdated }
    }

    /// Distinct accounts across visible workflows, for the timeline account filter. (P1-102)
    var workflowAccounts: [String] {
        Array(Set(workflowSummaries.map(\.account))).sorted()
    }

    /// Distinct operators/playbooks across visible workflows, for the timeline playbook filter. (P1-102)
    var workflowPlaybooks: [String] {
        Array(Set(workflowSummaries.map(\.playbook))).sorted()
    }

    /// High-signal events only — the meaningful state changes, dropping routine progress noise.
    /// (P1-103 Activity Feed)
    var activityFeed: [WorkflowEventEnvelope] {
        liveEvents.filter { Self.isHighSignal($0.event) }
    }

    /// Related high-signal events grouped by session (correlation id), newest session first.
    /// (P1-103 "Feed groups related events")
    var groupedActivityFeed: [ActivityGroup] {
        let grouped = Dictionary(grouping: filteredActivityFeed) { $0.correlationID ?? "(untracked)" }
        return grouped
            .map { key, envelopes in
                let ordered = envelopes.sorted { $0.timestamp > $1.timestamp }
                return ActivityGroup(
                    id: key,
                    title: key,
                    events: ordered,
                    lastUpdated: ordered.first?.timestamp ?? .distantPast
                )
            }
            .sorted { $0.lastUpdated > $1.lastUpdated }
    }

    /// How each wallet action is treated under the *currently selected* crypto mode. All three modes
    /// are fully live: Observe keeps wallet execution read-only, Assist prepares drafts and escalates
    /// for approval, Operate proceeds once signing evidence and receipt controls pass. Mirrors the
    /// `DomainJudge` decision for these capabilities. (P1-104)
    struct CryptoActionDisposition: Identifiable, Sendable {
        public let id: String
        public let availability: String
        public let isAvailable: Bool
        public let systemImage: String
    }

    var cryptoActionDispositions: [CryptoActionDisposition] {
        ["Sign message", "Approve spending", "Draft transaction"].map { action in
            switch cryptoMode {
            case .observe:
                return CryptoActionDisposition(
                    id: action,
                    availability: "Read-only in Observe — nothing is signed or sent",
                    isAvailable: false,
                    systemImage: "lock"
                )
            case .assist:
                return CryptoActionDisposition(
                    id: action,
                    availability: "Prepared and escalated for approval",
                    isAvailable: true,
                    systemImage: "hand.raised"
                )
            case .operate:
                return CryptoActionDisposition(
                    id: action,
                    availability: "Runs once signing evidence and receipts pass",
                    isAvailable: true,
                    systemImage: "bolt"
                )
            }
        }
    }

    // MARK: - Derivation helpers

    /// Coarse state from the *durable worklog* — the accurate source that distinguishes queued
    /// (proposed only), running, waiting (approval), blocked, completed, and failed. (P1-102)
    static func state(forWorklog events: [WorkflowWorklogEvent]) -> WorkflowState {
        var state: WorkflowState = .queued
        for event in events {
            switch event {
            case .considered:
                // Deliberation precedes the proposal; it doesn't advance the workflow's coarse state.
                break
            case .proposed:
                // A recorded proposal is what *makes* a workflow queued, which is the initial state
                // — so it has nothing to advance, and it must not walk back a later state either.
                break
            case .checksEvaluated:
                if state == .queued { state = .running }
            case let .decided(decision):
                switch decision {
                case .allow: state = .running
                case .block, .revise: state = .blocked
                case .escalate: state = .waiting
                }
            case .executed:
                state = .completed
            case .blocked:
                state = .blocked
            case .failed:
                state = .failed
            case let .routinePhase(phase, _):
                // Scheduled runs report their own lifecycle: the terminal phase mirrors the
                // execution record's outcome, so the trace and the record agree.
                switch phase {
                case .authorityResolved, .contextGathered, .operatorFinished,
                     .artifactProduced, .artifactRejected:
                    state = .running
                case .awaitingApproval:
                    state = .waiting
                case .completed:
                    state = .completed
                case .blocked:
                    state = .blocked
                case .failed:
                    state = .failed
                }
            case .unknown:
                // A step this build cannot interpret says nothing about the run, so it must neither
                // advance the state nor walk it back: reporting `queued` for a workflow that had
                // already finished would be worse than reporting nothing at all.
                break
            }
        }
        return state
    }

    /// Fallback state from the lossy live event stream (used only for workflows with no worklog yet).
    static func state(for ascendingEvents: [WorkflowEventEnvelope]) -> WorkflowState {
        var state: WorkflowState = .running
        for envelope in ascendingEvents {
            switch envelope.event {
            case .sessionStarted, .plannerStarted, .plannerCompleted, .policyDecision,
                 .capabilityLeaseGranted, .contextRefreshed, .memoryTouched:
                if state != .completed { state = .running }
            case let .sessionEnded(_, status):
                switch status {
                case .completed: state = .completed
                case .blocked: state = .blocked
                case .failed: state = .failed
                case .waitingForApproval: state = .waiting
                case .active: state = .running
                }
            case .plannerFailed:
                state = .failed
            case .workflowStarted:
                if state != .completed { state = .running }
            case let .executionUpdate(message):
                if message.localizedCaseInsensitiveContains("failed") {
                    state = .failed
                } else if state != .completed {
                    state = .running
                }
            case .workflowBlocked, .checkFailed:
                state = .blocked
            case .approvalRequired:
                state = .waiting
            case .artifactCreated, .receiptCreated:
                state = .completed
            case .capabilityRevoked, .capabilityLeaseExpired:
                break
            case .unknown:
                // An event this build cannot interpret says nothing about the run's state, so it
                // must not move it. Deriving anything from a case name we don't understand would be
                // a guess presented as fact on the surface whose whole job is to say what happened.
                break
            }
        }
        return state
    }

    static func nextStep(for state: WorkflowState) -> String {
        switch state {
        case .queued: return "Awaiting checks and policy decision"
        case .running: return "Awaiting execution result"
        case .waiting: return "Record approval decision"
        case .blocked: return "Blocked — revise inputs or abandon"
        case .completed: return "No planned next step"
        case .failed: return "Failed — inspect worklog and retry"
        }
    }

    /// The account a workflow operates on, taken from the first proposal parameter that names one.
    static func accountLabel(for steps: [WorkflowStepLog]) -> String {
        for step in steps {
            guard case let .proposed(proposal) = step.event else { continue }
            // Prefer a human-readable alias (account name / ENS) over the raw hex address.
            if let account = proposal.parameters["account"]
                ?? proposal.parameters["ens"]
                ?? proposal.parameters["address"],
               !account.isEmpty {
                return account
            }
        }
        return MissionControlFacets.noAccount
    }

    /// The operator/playbook that produced a workflow — the proposal intent (tool title), else toolID.
    static func playbookLabel(for steps: [WorkflowStepLog]) -> String {
        for step in steps {
            guard case let .proposed(proposal) = step.event else { continue }
            if !proposal.intent.isEmpty { return proposal.intent }
        }
        if let toolID = steps.compactMap(\.toolID).first, !toolID.isEmpty { return toolID }
        return MissionControlFacets.adHocPlaybook
    }

    static func isHighSignal(_ event: WorkflowEvent) -> Bool {
        switch event {
        case .sessionStarted, .sessionEnded, .plannerStarted, .plannerCompleted, .plannerFailed,
             .policyDecision, .workflowStarted, .workflowBlocked, .approvalRequired,
             .artifactCreated, .receiptCreated, .checkFailed, .capabilityRevoked,
             .capabilityLeaseGranted, .capabilityLeaseExpired, .contextRefreshed, .memoryTouched:
            return true
        case let .executionUpdate(message):
            return message.localizedCaseInsensitiveContains("failed")
        case .unknown:
            // Kept in the timeline and in exports, but not promoted into the activity feed: the only
            // thing this build could render is a raw case name, and a feed row that reads
            // "quorumReached" is less honest than no row. A newer build recovers the real event —
            // the payload is preserved verbatim.
            return false
        }
    }

    /// Buckets a high-signal event into one of the four feed categories. (P1-103)
    static func category(for event: WorkflowEvent) -> ActivityCategory {
        switch event {
        case .sessionStarted, .plannerStarted, .plannerCompleted, .policyDecision,
             .capabilityLeaseGranted, .contextRefreshed, .memoryTouched:
            return .observation
        case let .sessionEnded(_, status):
            return status == .completed ? .completed : .preparation
        case .plannerFailed:
            return .preparation
        case .workflowStarted:
            return .observation
        case .checkFailed, .capabilityRevoked, .capabilityLeaseExpired:
            return .preparation
        case .workflowBlocked:
            // A block is never a completion, whatever its reason says. The reason text is not a
            // signal here: the most common block in the system is the deterministic-check gate,
            // whose reason reads "Check failed (<id>)" — so keying off the word "failed" filed
            // exactly those steps under "Completed" with a checkmark, telling the operator the
            // opposite of what happened on the surface that exists to say what happened.
            return .preparation
        case .approvalRequired:
            return .approvalNeeded
        case .artifactCreated, .receiptCreated:
            return .completed
        case let .executionUpdate(message):
            return message.localizedCaseInsensitiveContains("failed") ? .preparation : .observation
        case .unknown:
            // Unreachable in practice — `isHighSignal` filters these out before bucketing — but
            // categorizing an uninterpretable event as anything other than a neutral observation
            // would assert something about it. Exhaustive so a real new case can't default in here.
            return .observation
        }
    }
}
