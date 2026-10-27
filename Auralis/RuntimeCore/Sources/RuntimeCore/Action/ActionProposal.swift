import AuralisFoundation
import Foundation

/// A typed, serializable description of a single thing an actor wants to do, *before* any
/// governance runs on it.
///
/// This is the object the Judge/Policy pipeline evaluates and that a receipt can later be linked
/// back to. It deliberately carries no execution machinery — it is a fact of intent, not a command.
public struct ActionProposal: Identifiable, Equatable, Sendable, Codable {
    /// Stable identity for correlating this proposal with its verdict and receipt.
    public let id: UUID

    /// Who is proposing the action. See ``ActorRef`` for the attribution model.
    public let actor: ActorRef

    /// The workflow that owns this proposal. Standalone actions receive a stable explicit run ref.
    public let workflowRun: WorkflowRunRef

    /// Authority is pending while a proposal is being judged; execution must replace it with a
    /// resolved, denied, or explicitly not-applicable state.
    public let authorityState: AuthorityState

    /// Human-readable statement of what the actor is trying to accomplish.
    public let intent: String

    /// The canonical capability the action would exercise.
    public let capability: CapabilityID

    /// The blast radius, used by UI/policy/approvals.
    public let impact: ActionImpactClass

    /// Named approvals that must be satisfied before execution (empty when none required).
    public let requiredApprovals: [String]

    /// Identifiers of deterministic checks that must pass before execution (empty when none).
    public let requiredCheckIDs: [String]

    /// Optional grouping key tying this proposal to a session/workflow run.
    public let correlationID: String?

    /// Typed-but-stringly parameters the action operates on (e.g. `address`, `chain`, `ens`,
    /// `contextRefreshedAt`). Deterministic checks validate these before execution.
    public let parameters: [String: String]

    public init(
        id: UUID = UUID(),
        actor: ActorRef,
        intent: String,
        capability: CapabilityID,
        impact: ActionImpactClass,
        requiredApprovals: [String] = [],
        requiredCheckIDs: [String] = [],
        correlationID: String? = nil,
        workflowRun: WorkflowRunRef? = nil,
        authorityState: AuthorityState = .pending,
        parameters: [String: String] = [:]
    ) {
        self.id = id
        self.actor = actor
        self.workflowRun = workflowRun ?? .resolved(
            correlationID: correlationID,
            fallbackActionID: id
        )
        self.authorityState = authorityState
        self.intent = intent
        self.capability = capability
        self.impact = impact
        self.requiredApprovals = requiredApprovals
        self.requiredCheckIDs = requiredCheckIDs
        self.correlationID = correlationID
        self.parameters = parameters
    }

    /// The grouping key this proposal's session, events, worklog entries, and receipts are all filed
    /// under, falling back to the proposal's own id when the caller supplied none.
    ///
    /// Always use this rather than reading ``correlationID`` directly when writing correlated
    /// records: a proposal with no correlation id would otherwise file its session under the
    /// fallback and its worklog under `nil`, producing a trace that
    /// ``WorklogStoring/steps(forCorrelationID:)`` can never retrieve.
    public var resolvedCorrelationID: String {
        workflowRun.correlationID
    }

    /// Returns a copy carrying the moment freshness was *evaluated*, replacing whatever the proposing
    /// actor supplied for it.
    ///
    /// The two halves of `context.fresh` have different owners. `contextRefreshedAt` is a claim about
    /// when the context was captured and travels with the proposal; `freshnessEvaluatedAt` is "now",
    /// and must be stamped by the governed boundary at the instant it evaluates the check. Letting it
    /// arrive in ``parameters`` from the actor being governed made the check self-attested — an actor
    /// could pair a months-old capture with its own convenient "now" and always read as fresh.
    ///
    /// Only proposals that actually claim a capture time are stamped: without `contextRefreshedAt`
    /// there is nothing to measure against, the check already refuses them, and stamping would add an
    /// undeclared parameter to every proposal a strict input schema sees.
    ///
    /// The stamp is recorded on the proposal rather than held in the checker, so both time inputs
    /// land in the worklog and receipt and the verdict stays reproducible from the record.
    public func stampingFreshnessEvaluation(at instant: Date) -> ActionProposal {
        guard parameters[StandardCheckParameterKey.contextRefreshedAt] != nil else { return self }
        var stamped = parameters
        stamped[StandardCheckParameterKey.freshnessEvaluatedAt] = String(instant.timeIntervalSince1970)
        return replacingParameters(with: stamped)
    }

    /// This proposal with the boundary-owned freshness stamp removed.
    ///
    /// Use this — never `==` — when asking "is this the proposal that was approved?". The stamp is
    /// written by the pipeline at each run, so the same approved proposal re-evaluated at resume time
    /// is not `==` to the one that was escalated, and a raw comparison reads it as a *different*
    /// proposal and escalates it a second time. This deliberately does not weaken approval custody:
    /// ``ApprovalRegistry/consume(_:)`` still demands an exact match against the registered request.
    public var withoutFreshnessEvaluationStamp: ActionProposal {
        guard parameters[StandardCheckParameterKey.freshnessEvaluatedAt] != nil else { return self }
        var stripped = parameters
        stripped[StandardCheckParameterKey.freshnessEvaluatedAt] = nil
        return replacingParameters(with: stripped)
    }

    /// Copies this proposal with different parameters, preserving identity, workflow run, and
    /// authority state — a fresh `init` would mint a new `workflowRun` and split the trace.
    private func replacingParameters(with parameters: [String: String]) -> ActionProposal {
        ActionProposal(
            id: id,
            actor: actor,
            intent: intent,
            capability: capability,
            impact: impact,
            requiredApprovals: requiredApprovals,
            requiredCheckIDs: requiredCheckIDs,
            correlationID: correlationID,
            workflowRun: workflowRun,
            authorityState: authorityState,
            parameters: parameters
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, actor, workflowRun, authorityState, intent, capability, impact
        case requiredApprovals, requiredCheckIDs, correlationID, parameters
    }

    /// Legacy proposals decode into explicit compatibility states instead of losing their trace.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        actor = try container.decode(ActorRef.self, forKey: .actor)
        intent = try container.decode(String.self, forKey: .intent)
        capability = try container.decode(CapabilityID.self, forKey: .capability)
        impact = try container.decode(ActionImpactClass.self, forKey: .impact)
        requiredApprovals = try container.decodeIfPresent([String].self, forKey: .requiredApprovals) ?? []
        requiredCheckIDs = try container.decodeIfPresent([String].self, forKey: .requiredCheckIDs) ?? []
        correlationID = try container.decodeIfPresent(String.self, forKey: .correlationID)
        parameters = try container.decodeIfPresent([String: String].self, forKey: .parameters) ?? [:]
        workflowRun = try container.decodeIfPresent(WorkflowRunRef.self, forKey: .workflowRun)
            ?? .resolved(correlationID: correlationID, fallbackActionID: id)
        authorityState = try container.decodeIfPresent(AuthorityState.self, forKey: .authorityState)
            ?? .legacyUnknown
    }
}
