import AuralisReceipts
import AuralisPrimaryModels
import Foundation
import OSLog
import AuralisPolicy
import AuralisRuntime

/// Bridges the kernel's ``ReceiptEmitting`` seam to the app's real ``ReceiptStore``: every governed
/// tool call — allowed *or* denied — becomes a durable, signed receipt (P0.5-204 + ADR-004 "receipts
/// for both denied and approved decisions").
public struct ReceiptStoreSink: ReceiptEmitting, Sendable {
    private let store: any ReceiptStore
    private let artifactStore: (any ArtifactStore)?
    private let eventBus: (any RuntimeEventPublishing)?
    private let sessionStore: (any AgentSessionStoring)?
    /// `@MainActor @Sendable`, which is what lets this type be checked-`Sendable`. It was previously
    /// a bare `@MainActor` closure, and the only way to hold one in a value that crosses isolation
    /// was to assert `@unchecked Sendable` for the whole sink — suppressing the compiler's check on
    /// every other stored property too. The isolation is unchanged; it is now verified.
    private let modeProvider: @MainActor @Sendable () -> CryptoMode

    public init(
        store: any ReceiptStore,
        artifactStore: (any ArtifactStore)? = nil,
        eventBus: (any RuntimeEventPublishing)? = nil,
        sessionStore: (any AgentSessionStoring)? = nil,
        modeProvider: @escaping @MainActor @Sendable () -> CryptoMode = { .observe }
    ) {
        self.store = store
        self.artifactStore = artifactStore
        self.eventBus = eventBus
        self.sessionStore = sessionStore
        self.modeProvider = modeProvider
    }

    public func emit(_ receipt: GovernedReceipt) async throws {
        let mode = await modeProvider().receiptMode
        let draft = ReceiptDraft(
            category: GovernedReceiptTaxonomy.category,
            kind: GovernedReceiptTaxonomy.toolKind(receipt.outcome),
            // Resolved, not raw: the pipeline files this proposal's session, worklog, and events
            // under `resolvedCorrelationID`. Reading the raw optional here would file the receipt
            // under `nil` for an uncorrelated proposal — unretrievable by
            // `receipts(forCorrelationID:)`, and it would also skip the `noteSessionReceipt` link
            // below, breaking receipt → run → steps in both directions.
            correlationID: receipt.proposal.resolvedCorrelationID,
            payload: payload(for: receipt),
            actorDetail: receipt.proposal.actor.receiptActorDetail,
            authorityDetail: receipt.authority?.receiptAuthorityDetail,
            mode: mode,
            summary: summary(for: receipt),
            provenance: CapabilityDomain.isCrypto(receipt.proposal.capability) ? "crypto" : "local",
            isSuccess: receipt.outcome == .executed
        )
        let record = try await store.append(draft)
        await eventBus?.publish(WorkflowEventEnvelope(event: .receiptCreated(id: record.id), correlationID: record.correlationID))
        if let correlationID = record.correlationID {
            await noteSessionReceipt(
                record.id,
                correlationID: correlationID,
                goal: receipt.proposal.intent,
                actor: receipt.proposal.actor
            )
        }
        if let artifactID = receipt.artifactID {
            // Not `try`: the receipt above already landed, and this sink's thrown error is read by
            // `GovernedToolPipeline` as "the governance receipt is missing" — it degrades the whole
            // outcome to `.evidenceIncomplete`. Propagating a *backlink* failure through that channel
            // reported the one piece of evidence that did persist as absent, which is a worse lie
            // than the gap it was describing. The receipt still carries `artifactID` in its payload,
            // so artifact → receipt is recoverable from the ledger even when this index write fails.
            do {
                try await artifactStore?.linkRelatedReceipt(id: record.id, toArtifact: artifactID)
            } catch {
                Self.logger.error(
                    """
                    Failed to link receipt \(record.id.uuidString, privacy: .public) to artifact \
                    \(artifactID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)
                    """
                )
            }
        }
    }

    private static let logger = Logger(subsystem: "com.auralis.runtime", category: "receipt-sink")

    /// Files this receipt onto the correlated session.
    ///
    /// - Important: Read → mutate → upsert with no compare-and-set, across a suspension point, and —
    ///   unlike the host's copy — reachable from *outside* the main actor, since this sink is a
    ///   `Sendable` value the pipeline calls wherever it happens to be running. Two governed calls
    ///   emitting receipts concurrently under one `correlationID` would lose one `receiptID` from the
    ///   session. What rules that out is ``CorrelationGate``, held by the governed entry points above
    ///   this sink for the whole of a run, so only one pipeline call per correlation id is ever in
    ///   flight. It previously rested on the **call graph** — the pipeline completing one tool call
    ///   before the next, and every caller above it being sequential per correlation id — which was a
    ///   caller invariant, and one `MissionControlHomeModel.sharePlaybook` broke. The receipt itself
    ///   is durable regardless, so the loss would be to the session's evidence index only and is
    ///   recoverable via `receipts(forCorrelationID:)` — but the index is what Mission Control reads.
    ///   Same note as ``RuntimeHost/noteRuntimeSession(correlationID:goal:actor:_:)``.
    private func noteSessionReceipt(
        _ receiptID: UUID,
        correlationID: String,
        goal: String,
        actor: ActorRef
    ) async {
        guard let sessionStore else { return }
        var session = await sessionStore.session(correlationID: correlationID)
            ?? AgentSession(correlationID: correlationID, goal: goal, actor: actor)
        session.note(receiptID: receiptID)
        await sessionStore.upsert(session)
    }

    private func summary(for receipt: GovernedReceipt) -> String {
        switch receipt.outcome {
        case .executed: return receipt.proposal.intent
        case .blocked: return "Blocked: \(receipt.reason ?? receipt.proposal.intent)"
        case .failed: return "Failed: \(receipt.reason ?? receipt.proposal.intent)"
        case .needsRevision: return "Revision requested: \(receipt.proposal.intent)"
        case .needsApproval: return "Awaiting approval: \(receipt.proposal.intent)"
        }
    }

    /// Every parameter key the runtime stamps onto a proposal itself, excluded from the readable
    /// `interpretedPlan` because none of them is part of what the person requested.
    ///
    /// ``RecordSchemaKey/all`` alone was not enough. `RuntimeHost.schemaStamped` also writes
    /// ``StandardCheckParameterKey/contextRefreshedAt`` onto *every* proposal it builds — and
    /// deliberately overrides any caller-supplied value, so it is never the caller's — while the
    /// governed boundary adds ``StandardCheckParameterKey/freshnessEvaluatedAt`` when it evaluates
    /// `context.fresh` (see `ActionProposal.stampingFreshnessEvaluation(at:)`). Neither is a
    /// record-schema key, so both survived the old filter and were rendered to a person as
    /// `Operate on contextRefreshedAt = 1757894400.12` — a raw Unix timestamp presented as the
    /// operation they asked for, on the one surface whose purpose is legibility (P1-301).
    ///
    /// It also made the section appear when there was no plan to show: a proposal carrying no
    /// operands at all still produced an `interpretedPlan` containing nothing but that timestamp,
    /// which the comment in ``payload(for:)`` says it omits.
    private static let governanceStampKeys: Set<String> = RecordSchemaKey.all.union([
        StandardCheckParameterKey.contextRefreshedAt,
        StandardCheckParameterKey.freshnessEvaluatedAt
    ])

    private func payload(for receipt: GovernedReceipt) -> ReceiptPayload {
        let proposal = receipt.proposal
        var values: [String: ReceiptJSONValue] = [
            // The requested intent, so the readable receipt exposes what the actor asked for
            // (P1-301) rather than leaving it only in the receipt summary.
            "requestedIntent": .string(proposal.intent),
            "tool": .string(receipt.toolID),
            "capability": .string(proposal.capability.rawValue),
            "impact": .string(proposal.impact.rawValue),
            "outcome": .string(receipt.outcome.rawValue)
        ]

        // Interpreted plan (P1-301): the concrete operation the pipeline resolved the intent into —
        // the parameters it acts on and the deterministic checks it planned to run. Omitted when the
        // proposal carried neither, so the section only appears when there is a plan to show.
        var planSteps: [ReceiptJSONValue] = []
        // The governance stamp is metadata the runtime adds, not part of the operation the person
        // asked for, so it stays out of the readable plan. It is still on the proposal — and
        // therefore still reproducible from the worklog — where the schema and freshness checks
        // read it. See ``governanceStampKeys``.
        let operationParameters = proposal.parameters
            .filter { !Self.governanceStampKeys.contains($0.key) }
        if !operationParameters.isEmpty {
            let rendered = operationParameters.keys.sorted()
                .map { "\($0) = \(operationParameters[$0] ?? "")" }
                .joined(separator: ", ")
            planSteps.append(.string("Operate on \(rendered)"))
        }
        if !proposal.requiredCheckIDs.isEmpty {
            planSteps.append(.string("Pass checks: \(proposal.requiredCheckIDs.joined(separator: ", "))"))
        }
        if !planSteps.isEmpty {
            values["interpretedPlan"] = .array(planSteps)
        }

        // Approvals (P1-301): the named approvals this proposal requires, plus whether this outcome
        // is still awaiting a human decision.
        if !proposal.requiredApprovals.isEmpty {
            values["requiredApprovals"] = .array(proposal.requiredApprovals.map(ReceiptJSONValue.string))
        }
        if receipt.outcome == .needsApproval {
            values["approvalStatus"] = .string("Awaiting human approval")
        }

        if let artifactID = receipt.artifactID {
            values["artifactID"] = .string(artifactID.uuidString)
        }
        for key in receipt.outputFields.keys.sorted() where values[key] == nil {
            values[key] = .string(receipt.outputFields[key] ?? "")
        }
        if let reason = receipt.reason {
            values["reason"] = .string(reason)
        }
        return ReceiptPayload(values: values)
    }
}
