import AuralisFoundation
import Foundation

public enum AgentSessionStatus: String, Equatable, Sendable, Codable {
    case active
    case waitingForApproval
    case blocked
    case failed
    case completed
}

public struct AgentSessionGoal: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public let text: String
    public let recordedAt: Date

    public init(id: UUID = UUID(), text: String, recordedAt: Date = .now) {
        self.id = id
        self.text = text
        self.recordedAt = recordedAt
    }
}

public enum AgentSessionMemoryTouchKind: String, Equatable, Sendable, Codable {
    case memoryRead
    case memoryWrite
    case contextRefresh
}

public struct AgentSessionMemoryTouch: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public let kind: AgentSessionMemoryTouchKind
    public let key: String
    public let dataClass: ContextDataClass?
    public let recordedAt: Date

    public init(
        id: UUID = UUID(),
        kind: AgentSessionMemoryTouchKind,
        key: String,
        dataClass: ContextDataClass? = nil,
        recordedAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.key = key
        self.dataClass = dataClass
        self.recordedAt = recordedAt
    }
}

public struct AgentSessionExecutionUpdate: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public let message: String
    public let recordedAt: Date

    public init(id: UUID = UUID(), message: String, recordedAt: Date = .now) {
        self.id = id
        self.message = message
        self.recordedAt = recordedAt
    }
}

/// An explicit, long-running unit of agent work.
///
/// Future systems are sessions, not one-shot prompts: they start, accumulate capabilities, receipts,
/// approvals, model hops, and cost, then end. `correlationID` is the key that ties a session's
/// receipts, worklogs, and events together.
public struct AgentSession: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public let correlationID: String
    /// Who this session's work is attributed to (P0.5-602). A session is the other "run" concept
    /// alongside `ExecutionRecord`, so it carries the same non-optional attribution: a long-running
    /// unit of agent work that can't say who is doing it defeats the point of the session model.
    ///
    /// The initializer deliberately has no default. An `= .system` fallback let a new call site omit
    /// attribution and compile clean, recording an anonymous actor indistinguishable from a legacy
    /// row that predates the field — the exact silent misattribution this ticket exists to prevent.
    /// Legacy rows are still tolerated, but only on the decode path below.
    public let actor: ActorRef
    /// What permitted this session's work (P0.5-601/602), recorded the first time the governed
    /// pipeline resolves a grant for it.
    ///
    /// `var`, not `let`, and optional: a session is opened at the *proposal* step, before any
    /// authority has been resolved, so it genuinely has none until the first allowed action. Once
    /// set it is never overwritten — the grant that opened the session is the one worth auditing.
    public private(set) var authority: AuthorityRef?
    public private(set) var goal: String
    public private(set) var goals: [AgentSessionGoal]
    public let startedAt: Date
    public private(set) var endedAt: Date?
    public private(set) var status: AgentSessionStatus
    public private(set) var capabilities: [CapabilityID]
    public private(set) var receiptIDs: [UUID]
    public private(set) var approvalIDs: [UUID]
    public private(set) var artifactIDs: [UUID]
    public private(set) var modelsUsed: [String]
    /// Total model invocations in this session — every handoff to an inference backend, counted once
    /// per call (P1-AI-103 "model hops"). Distinct from `modelsUsed.count`: a chain that calls the same
    /// model three times is one model but three hops. This is the multi-agent observability number.
    public private(set) var modelHops: Int
    public private(set) var promptTokens: Int
    public private(set) var completionTokens: Int
    public private(set) var estimatedCost: Double
    public private(set) var memoryTouched: [AgentSessionMemoryTouch]
    public private(set) var executionUpdates: [AgentSessionExecutionUpdate]

    public init(
        id: UUID = UUID(),
        correlationID: String,
        goal: String,
        actor: ActorRef,
        startedAt: Date = .now
    ) {
        self.id = id
        self.correlationID = correlationID
        self.actor = actor
        self.authority = nil
        self.goal = goal
        self.goals = [AgentSessionGoal(text: goal, recordedAt: startedAt)]
        self.startedAt = startedAt
        self.endedAt = nil
        self.status = .active
        self.capabilities = []
        self.receiptIDs = []
        self.approvalIDs = []
        self.artifactIDs = []
        self.modelsUsed = []
        self.modelHops = 0
        self.promptTokens = 0
        self.completionTokens = 0
        self.estimatedCost = 0
        self.memoryTouched = []
        self.executionUpdates = []
    }

    // Tolerant decoding: sessions persisted before `modelHops` or `actor` existed decode as zero hops
    // and an unattributed system actor rather than failing to load entirely (they are stored as JSON
    // blobs, so a hard decode error would silently drop the whole session on upgrade).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        correlationID = try container.decode(String.self, forKey: .correlationID)
        actor = try container.decodeIfPresent(ActorRef.self, forKey: .actor) ?? .system
        authority = AuthorityRef.decodedIfPresent(from: container, forKey: .authority)
        goal = try container.decode(String.self, forKey: .goal)
        goals = try container.decode([AgentSessionGoal].self, forKey: .goals)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        status = try container.decode(AgentSessionStatus.self, forKey: .status)
        capabilities = try container.decode([CapabilityID].self, forKey: .capabilities)
        receiptIDs = try container.decode([UUID].self, forKey: .receiptIDs)
        approvalIDs = try container.decode([UUID].self, forKey: .approvalIDs)
        artifactIDs = try container.decode([UUID].self, forKey: .artifactIDs)
        modelsUsed = try container.decode([String].self, forKey: .modelsUsed)
        modelHops = try container.decodeIfPresent(Int.self, forKey: .modelHops) ?? 0
        promptTokens = try container.decode(Int.self, forKey: .promptTokens)
        completionTokens = try container.decode(Int.self, forKey: .completionTokens)
        estimatedCost = try container.decode(Double.self, forKey: .estimatedCost)
        memoryTouched = try container.decode([AgentSessionMemoryTouch].self, forKey: .memoryTouched)
        executionUpdates = try container.decode([AgentSessionExecutionUpdate].self, forKey: .executionUpdates)
    }

    public var isActive: Bool { status == .active || status == .waitingForApproval }
    public var totalTokens: Int { promptTokens + completionTokens }

    public mutating func note(goal newGoal: String, at now: Date = .now) {
        guard !newGoal.isEmpty else { return }
        goal = newGoal
        if goals.last?.text != newGoal {
            goals.append(AgentSessionGoal(text: newGoal, recordedAt: now))
        }
    }

    /// Records the grant that permitted this session's work, keeping the first one seen.
    public mutating func note(authority resolved: AuthorityRef) {
        guard authority == nil else { return }
        authority = resolved
    }

    public mutating func note(capability: CapabilityID) {
        if !capabilities.contains(capability) { capabilities.append(capability) }
    }

    public mutating func note(receiptID: UUID) {
        if !receiptIDs.contains(receiptID) { receiptIDs.append(receiptID) }
    }

    /// Records an approval this session raised, and moves it to `waitingForApproval`.
    ///
    /// The status change goes through ``markWaitingForApproval()`` so it honours the same
    /// already-ended guard. Setting `status` directly here could reopen a session that had reached a
    /// terminal state, leaving `status == .waitingForApproval` alongside a non-nil `endedAt` — a
    /// combination `isActive` reports as live and no terminal transition can clear, because
    /// ``end(status:at:)`` returns early once `endedAt` is set. The approval id is still recorded
    /// either way; only the lifecycle transition is guarded.
    public mutating func note(approvalID: UUID) {
        if !approvalIDs.contains(approvalID) { approvalIDs.append(approvalID) }
        markWaitingForApproval()
    }

    public mutating func note(artifactID: UUID) {
        if !artifactIDs.contains(artifactID) { artifactIDs.append(artifactID) }
    }

    public mutating func note(model: String, cost: Double = 0, promptTokens: Int = 0, completionTokens: Int = 0) {
        modelHops += 1
        if !modelsUsed.contains(model) { modelsUsed.append(model) }
        estimatedCost += cost
        self.promptTokens += promptTokens
        self.completionTokens += completionTokens
    }

    public mutating func note(telemetry: InferenceTelemetry) {
        // A deterministic local data read is not a model invocation — don't inflate the model-hop
        // count or the "models used" list with it. (P1-AI-103)
        guard telemetry.usesInference else { return }
        note(
            model: "\(telemetry.route.provider) · \(telemetry.route.modelClass)",
            cost: telemetry.estimatedCost,
            promptTokens: telemetry.promptTokens,
            completionTokens: telemetry.completionTokens
        )
    }

    public mutating func note(memoryTouch: AgentSessionMemoryTouch) {
        memoryTouched.append(memoryTouch)
    }

    public mutating func noteExecutionUpdate(_ message: String, at now: Date = .now) {
        guard !message.isEmpty else { return }
        executionUpdates.append(AgentSessionExecutionUpdate(message: message, recordedAt: now))
    }

    public mutating func markWaitingForApproval() {
        guard endedAt == nil else { return }
        status = .waitingForApproval
    }

    public mutating func block(reason: String? = nil, at now: Date = .now) {
        if let reason { noteExecutionUpdate(reason, at: now) }
        end(status: .blocked, at: now)
    }

    public mutating func fail(reason: String? = nil, at now: Date = .now) {
        if let reason { noteExecutionUpdate(reason, at: now) }
        end(status: .failed, at: now)
    }

    public mutating func complete(at now: Date = .now) {
        end(status: .completed, at: now)
    }

    public mutating func end(at now: Date = .now) {
        end(status: .completed, at: now)
    }

    private mutating func end(status terminalStatus: AgentSessionStatus, at now: Date = .now) {
        guard endedAt == nil else { return }
        status = terminalStatus
        endedAt = now
    }
}

public protocol AgentSessionStoring: Sendable {
    func upsert(_ session: AgentSession) async
    func session(correlationID: String) async -> AgentSession?
    func allSessions() async -> [AgentSession]
    func resetAll() async
}

public actor InMemoryAgentSessionStore: AgentSessionStoring {
    private var sessionsByCorrelationID: [String: AgentSession] = [:]

    public init() { }

    public func upsert(_ session: AgentSession) {
        sessionsByCorrelationID[session.correlationID] = session
    }

    public func session(correlationID: String) -> AgentSession? {
        sessionsByCorrelationID[correlationID]
    }

    public func allSessions() -> [AgentSession] {
        sessionsByCorrelationID.values.sorted { $0.startedAt > $1.startedAt }
    }

    public func resetAll() {
        sessionsByCorrelationID.removeAll()
    }
}
