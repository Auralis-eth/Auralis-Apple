import CapabilitiesCore
import Foundation

/// A single thing that happened inside the runtime, worth surfacing to observers such as Mission
/// Control, receipts, or (later) eval/performance tracking.
///
/// Receipts remain the durable, human-facing log; `WorkflowEvent` is the in-process signal that fans
/// out over the ``RuntimeEventBus`` as things occur.
///
/// Events are also *persisted*, through ``RuntimeEventHistoryStoring``, so this enum decodes with the
/// same forward tolerance as ``WorkflowWorklogEvent``: an unrecognized shape becomes
/// ``unknown(caseName:payload:)`` rather than throwing. See that case for why.
public enum WorkflowEvent: Equatable, Sendable {
    /// A durable agent session began.
    case sessionStarted(correlationID: String, goal: String)

    /// A durable agent session reached a terminal state.
    case sessionEnded(correlationID: String, status: AgentSessionStatus)

    /// Planner activity started for a session.
    case plannerStarted(goal: String)

    /// Planner activity completed with a known option count.
    case plannerCompleted(selectedCount: Int, rejectedCount: Int)

    /// Planner activity failed before producing a usable plan.
    case plannerFailed(reason: String)

    /// A policy/judge decision was reached.
    case policyDecision(String)

    /// A workflow run began.
    case workflowStarted

    /// A workflow run was stopped by governance.
    case workflowBlocked(reason: String)

    /// A proposal is waiting on human approval.
    case approvalRequired(ApprovalRequest)

    /// A receipt was appended to the store.
    case receiptCreated(id: UUID)

    /// An artifact was produced.
    case artifactCreated(id: UUID)

    /// A deterministic check failed.
    case checkFailed(id: String, reason: String)

    /// A previously granted capability was revoked.
    case capabilityRevoked(CapabilityID)

    /// A capability lease became active.
    case capabilityLeaseGranted(CapabilityLease)

    /// A capability lease expired without explicit revocation.
    case capabilityLeaseExpired(CapabilityID)

    /// Runtime context was refreshed for a session.
    case contextRefreshed(key: String)

    /// Memory/context state was read or written by runtime work.
    case memoryTouched(kind: AgentSessionMemoryTouchKind, key: String)

    /// Free-form progress update for surfaces that want a running commentary.
    case executionUpdate(String)

    /// An event whose shape this build cannot interpret, carried verbatim (L-09).
    ///
    /// Reached on a downgrade — an older build reading rows a newer one wrote — where the case name is
    /// unfamiliar, an associated payload gained a required field, or a nested raw-value enum
    /// (``AgentSessionStatus``, `CapabilityID`) is newer than this build. Runtime events are durably
    /// persisted and read back through `compactMap` (`SwiftDataRuntimeEventHistoryStore`), so before
    /// this case existed all three of those threw and the store silently dropped the *entire*
    /// envelope: the timestamp and correlationID that place the event in a trace went with it, and
    /// Mission Control's timeline read as though nothing had happened rather than as though one entry
    /// was unreadable. A dropped row also breaks ``RuntimeEventBus/reliableEvents`` replay — a
    /// checkpoint pointing at a vanished event degrades to a full-history redelivery and an unhealthy
    /// replay gap.
    ///
    /// `payload` holds the original JSON and re-encodes exactly as it arrived, so a downgrade degrades
    /// *rendering* without destroying data. Never write this case — it exists only for decoding.
    case unknown(caseName: String, payload: WorklogRawJSON)
}

/// The event kinds this build understands, mirrored so the compiler keeps generating their wire
/// format.
///
/// Same technique as ``KnownWorklogEvent``, and for the same reason: hand-writing
/// ``WorkflowEvent``'s coding would mean hand-reproducing Swift's synthesized enum representation,
/// where one mismatch silently orphans every row already on disk. Mirroring keeps synthesis. Add
/// cases here and to ``WorkflowEvent`` together; the mapping switches below make omitting one a
/// compile error.
private enum KnownWorkflowEvent: Codable {
    case sessionStarted(correlationID: String, goal: String)
    case sessionEnded(correlationID: String, status: AgentSessionStatus)
    case plannerStarted(goal: String)
    case plannerCompleted(selectedCount: Int, rejectedCount: Int)
    case plannerFailed(reason: String)
    case policyDecision(String)
    case workflowStarted
    case workflowBlocked(reason: String)
    case approvalRequired(ApprovalRequest)
    case receiptCreated(id: UUID)
    case artifactCreated(id: UUID)
    case checkFailed(id: String, reason: String)
    case capabilityRevoked(CapabilityID)
    case capabilityLeaseGranted(CapabilityLease)
    case capabilityLeaseExpired(CapabilityID)
    case contextRefreshed(key: String)
    case memoryTouched(kind: AgentSessionMemoryTouchKind, key: String)
    case executionUpdate(String)

    /// Returns `nil` only for ``WorkflowEvent/unknown(caseName:payload:)``, which by definition has
    /// no mirror.
    init?(_ event: WorkflowEvent) {
        switch event {
        case let .sessionStarted(correlationID, goal):
            self = .sessionStarted(correlationID: correlationID, goal: goal)
        case let .sessionEnded(correlationID, status):
            self = .sessionEnded(correlationID: correlationID, status: status)
        case let .plannerStarted(goal): self = .plannerStarted(goal: goal)
        case let .plannerCompleted(selected, rejected):
            self = .plannerCompleted(selectedCount: selected, rejectedCount: rejected)
        case let .plannerFailed(reason): self = .plannerFailed(reason: reason)
        case let .policyDecision(message): self = .policyDecision(message)
        case .workflowStarted: self = .workflowStarted
        case let .workflowBlocked(reason): self = .workflowBlocked(reason: reason)
        case let .approvalRequired(request): self = .approvalRequired(request)
        case let .receiptCreated(id): self = .receiptCreated(id: id)
        case let .artifactCreated(id): self = .artifactCreated(id: id)
        case let .checkFailed(id, reason): self = .checkFailed(id: id, reason: reason)
        case let .capabilityRevoked(capability): self = .capabilityRevoked(capability)
        case let .capabilityLeaseGranted(lease): self = .capabilityLeaseGranted(lease)
        case let .capabilityLeaseExpired(capability): self = .capabilityLeaseExpired(capability)
        case let .contextRefreshed(key): self = .contextRefreshed(key: key)
        case let .memoryTouched(kind, key): self = .memoryTouched(kind: kind, key: key)
        case let .executionUpdate(message): self = .executionUpdate(message)
        case .unknown: return nil
        }
    }

    var event: WorkflowEvent {
        switch self {
        case let .sessionStarted(correlationID, goal):
            return .sessionStarted(correlationID: correlationID, goal: goal)
        case let .sessionEnded(correlationID, status):
            return .sessionEnded(correlationID: correlationID, status: status)
        case let .plannerStarted(goal): return .plannerStarted(goal: goal)
        case let .plannerCompleted(selected, rejected):
            return .plannerCompleted(selectedCount: selected, rejectedCount: rejected)
        case let .plannerFailed(reason): return .plannerFailed(reason: reason)
        case let .policyDecision(message): return .policyDecision(message)
        case .workflowStarted: return .workflowStarted
        case let .workflowBlocked(reason): return .workflowBlocked(reason: reason)
        case let .approvalRequired(request): return .approvalRequired(request)
        case let .receiptCreated(id): return .receiptCreated(id: id)
        case let .artifactCreated(id): return .artifactCreated(id: id)
        case let .checkFailed(id, reason): return .checkFailed(id: id, reason: reason)
        case let .capabilityRevoked(capability): return .capabilityRevoked(capability)
        case let .capabilityLeaseGranted(lease): return .capabilityLeaseGranted(lease)
        case let .capabilityLeaseExpired(capability): return .capabilityLeaseExpired(capability)
        case let .contextRefreshed(key): return .contextRefreshed(key: key)
        case let .memoryTouched(kind, key): return .memoryTouched(kind: kind, key: key)
        case let .executionUpdate(message): return .executionUpdate(message)
        }
    }
}

extension WorkflowEvent: Codable {
    public init(from decoder: any Decoder) throws {
        if let known = try? KnownWorkflowEvent(from: decoder) {
            self = known.event
            return
        }
        // Not a shape this build can interpret. Any failure lands here, not just an unfamiliar case
        // name, for the reason ``WorkflowWorklogEvent/init(from:)`` documents: telling "newer build"
        // from "corrupt bytes" would need a hardcoded case-name list a future author could forget to
        // extend, and keeping the entry is the better answer either way.
        let container = try decoder.container(keyedBy: SingleKeyEnumCodingKey.self)
        guard container.allKeys.count == 1, let key = container.allKeys.first else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: """
                        Expected a single-key runtime event object, found \
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
        if let known = KnownWorkflowEvent(self) {
            try known.encode(to: encoder)
        } else if case let .unknown(caseName, payload) = self {
            // Re-emitted under its original case name rather than as an `unknown` wrapper, so the
            // round trip is lossless and a newer build reading this history gets the real event back.
            var container = encoder.container(keyedBy: SingleKeyEnumCodingKey.self)
            try container.encode(payload, forKey: SingleKeyEnumCodingKey(caseName))
        }
    }
}

/// A ``WorkflowEvent`` stamped with correlation and timing metadata for delivery over the bus.
public struct WorkflowEventEnvelope: Equatable, Sendable, Identifiable, Codable {
    public let id: UUID
    public let event: WorkflowEvent
    public let correlationID: String?
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        event: WorkflowEvent,
        correlationID: String? = nil,
        timestamp: Date = .now
    ) {
        self.id = id
        self.event = event
        self.correlationID = correlationID
        self.timestamp = timestamp
    }
}
