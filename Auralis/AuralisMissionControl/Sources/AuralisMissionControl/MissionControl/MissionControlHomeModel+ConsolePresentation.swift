import AuralisReceipts
import AuralisCrypto
import AuralisFoundation
import AuralisRuntime
import Foundation
import Observation
import AuralisOperators
import AuralisPolicy
import AuralisAppShell

extension MissionControlHomeModel {
    // MARK: - Governed context freshness (P1-AGENT-102)

    /// How the console's governed operating context should be presented.
    ///
    /// A source that has never been read and one that has aged out both leave the contract
    /// unsatisfied, but they are different problems: the first resolves itself once loading finishes,
    /// the second needs attention. Collapsing them into one orange warning made a console that simply
    /// had not loaded yet look broken.
    public enum ContextFreshnessState: Equatable, Sendable {
        /// Every required field came from its authoritative source within the contract's age bound.
        case fresh
        /// At least one required source has not been read yet, so nothing can be asserted about it.
        case notLoadedYet
        /// Everything has been read, but the bundle violates the contract — stale, wrong source, or
        /// wrong data class.
        case needsAttention

        public var label: String {
            switch self {
            case .fresh: return "Governed context is fresh and complete"
            case .notLoadedYet: return "Governed context not loaded yet"
            case .needsAttention: return "Context needs attention"
            }
        }

        public var systemImage: String {
            switch self {
            case .fresh: return "checkmark.seal"
            case .notLoadedYet: return "hourglass"
            case .needsAttention: return "exclamationmark.triangle"
            }
        }
    }

    /// The governed context bundle, its contract validation, and the display state — derived together.
    ///
    /// Building the bundle walks and sorts the whole receipt ledger, so the surfaces that show it read
    /// this *once* per body pass. Reading `inspectedContextBundle`, `inspectedContextValidation`, and a
    /// separate freshness accessor meant one screen paid for the same build three times over.
    public struct ContextInspection: Sendable {
        public let bundle: ContextBundle
        public let validation: ContextContractValidation
        public let freshness: ContextFreshnessState
    }

    public var contextInspection: ContextInspection {
        let bundle = inspectedContextBundle
        let validation = inspectedContextContract.validate(bundle, now: referenceDate)
        let freshness: ContextFreshnessState
        if validation.isSatisfied {
            freshness = .fresh
        } else if bundle.fields.contains(where: { $0.lastRefreshed == nil }) {
            // Unread beats stale: a field whose source was never read says nothing about age.
            freshness = .notLoadedYet
        } else {
            freshness = .needsAttention
        }
        return ContextInspection(bundle: bundle, validation: validation, freshness: freshness)
    }

    // MARK: - Policy summary (P1-203)

    public struct PolicySummary: Equatable, Sendable {
        public var allowed = 0
        public var blocked = 0
        public var escalated = 0
    }

    /// A quick allowed/blocked/escalated tally from recent runtime receipts. (P1-203)
    public var policySummary: PolicySummary {
        var summary = PolicySummary()
        for receipt in recentReceipts {
            switch policyDisposition(for: receipt)?.status {
            case .allowed: summary.allowed += 1
            case .blocked: summary.blocked += 1
            case .escalated: summary.escalated += 1
            case nil: break
            }
        }
        return summary
    }

    /// Canonical policy disposition of a governed runtime receipt, derived from the shared receipt
    /// taxonomy so the summary can never silently drift from the emitter's `kind` strings. The `switch`
    /// is exhaustive over ``GovernedOutcomeKind``: adding or renaming an outcome forces this classifier
    /// to be updated rather than dropping the receipt on the floor. Returns `nil` for receipts that are
    /// not governed tool outcomes. (P1-203)
    func policyDisposition(
        for receipt: ReceiptRecord
    ) -> (status: PolicyOutcomeStatus, kind: PolicyKind)? {
        guard receipt.scope == GovernedReceiptTaxonomy.category,
              let outcome = GovernedReceiptTaxonomy.outcome(fromToolKind: receipt.trigger) else {
            return nil
        }
        switch outcome {
        case .executed:
            // Allowed steps are counted but not carded; kind is unused for the allowed bucket.
            return (.allowed, .hard)
        case .blocked:
            return (.blocked, .hard)
        case .needsApproval, .needsRevision:
            return (.escalated, .semantic)
        case .failed:
            // A runtime failure is an execution error, not a policy decision — deliberately excluded
            // from the allowed/blocked/escalated policy tally.
            return nil
        }
    }

    /// Whether a policy outcome came from a deterministic/hard gate or a semantic authority. (P1-203)
    ///
    /// Blocks are produced by hard gates (deterministic checks, the Observe wallet boundary, the
    /// pause gate); escalations are the crypto-scoped semantic `DomainJudge` deferring to a human.
    public enum PolicyKind: String, Sendable {
        case hard = "Hard policy"
        case semantic = "Semantic policy"
    }

    public enum PolicyOutcomeStatus: String, Sendable {
        case allowed = "Allowed"
        case blocked = "Blocked"
        case escalated = "Approval-gated"

        public var systemImage: String {
            switch self {
            case .allowed: return "checkmark.seal"
            case .blocked: return "hand.raised"
            case .escalated: return "exclamationmark.bubble"
            }
        }
    }

    /// A single plain-language policy outcome card for a recent workflow. (P1-203)
    public struct PolicyOutcomeCard: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let title: String
        public let status: PolicyOutcomeStatus
        public let kind: PolicyKind
        public let explanation: String
    }

    /// Plain-language cards for recent blocked or approval-gated runtime outcomes, tagged with
    /// whether a hard or semantic policy produced them. (P1-203)
    public var policyOutcomeCards: [PolicyOutcomeCard] {
        recentReceipts.compactMap { receipt -> PolicyOutcomeCard? in
            guard let disposition = policyDisposition(for: receipt) else { return nil }
            let reason: String?
            if case let .string(value) = receipt.details.values["reason"] { reason = value } else { reason = nil }
            let explanation: String
            switch disposition.status {
            case .allowed:
                // Allowed steps show in the tally only, not as a "why it was blocked or gated" card.
                return nil
            case .blocked:
                explanation = reason ?? "A hard policy gate stopped this step before it could run."
            case .escalated:
                explanation = reason ?? "The semantic judge escalated this step for your approval before it can run."
            }
            return PolicyOutcomeCard(
                id: receipt.id,
                title: receipt.summary,
                status: disposition.status,
                kind: disposition.kind,
                explanation: explanation
            )
        }
    }

    public struct ConsoleCounts: Equatable, Sendable {
        public var queued = 0
        public var running = 0
        public var waiting = 0
        public var blocked = 0
        public var completed = 0
        public var failed = 0
        public var approvals = 0
        public var artifacts = 0
    }

    public var consoleCounts: ConsoleCounts {
        var counts = ConsoleCounts(
            approvals: pendingApprovals.count,
            artifacts: artifacts.count
        )
        for summary in workflowSummaries {
            switch summary.state {
            case .queued:
                counts.queued += 1
            case .running:
                counts.running += 1
            case .waiting:
                counts.waiting += 1
            case .blocked:
                counts.blocked += 1
            case .completed:
                counts.completed += 1
            case .failed:
                counts.failed += 1
            }
        }
        return counts
    }

    public var filteredWorkflowSummaries: [WorkflowSummary] {
        let query = workflowSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return workflowSummaries.filter { summary in
            workflowStatusFilter.includes(summary.state) &&
            (workflowAccountFilter == nil || summary.account == workflowAccountFilter) &&
            (workflowPlaybookFilter == nil || summary.playbook == workflowPlaybookFilter) &&
            (query.isEmpty || summary.id.lowercased().contains(query))
        }
    }

    /// A high-signal event is "linkable" when it correlates to a durable receipt the operator can open.
    /// Resolves the specific `receiptCreated` receipt when possible, else the session's latest receipt.
    /// (P1-103 "links out to receipt detail")
    public func receipt(forEvent envelope: WorkflowEventEnvelope) -> ReceiptRecord? {
        if case let .receiptCreated(id) = envelope.event,
           let match = browserReceipts.first(where: { $0.id == id }) {
            return match
        }
        guard let correlationID = envelope.correlationID else { return nil }
        return browserReceipts.first { $0.correlationID == correlationID }
    }

    public var filteredActivityFeed: [WorkflowEventEnvelope] {
        let visibleCorrelationIDs = Set(filteredWorkflowSummaries.map(\.id))
        let hasWorkflowFilter = workflowStatusFilter != .all
            || !workflowSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || workflowAccountFilter != nil
            || workflowPlaybookFilter != nil
        return activityFeed.filter { envelope in
            guard hasWorkflowFilter else { return true }
            return visibleCorrelationIDs.contains(envelope.correlationID ?? "(untracked)")
        }
    }

    static func events(from steps: [WorkflowStepLog]) -> [WorkflowEventEnvelope] {
        steps.map { step in
            WorkflowEventEnvelope(
                id: step.id,
                event: event(from: step.event),
                correlationID: step.correlationID,
                timestamp: step.timestamp
            )
        }
    }

    static func mergeEvents(
        _ historicalEvents: [WorkflowEventEnvelope],
        with derivedEvents: [WorkflowEventEnvelope]
    ) -> [WorkflowEventEnvelope] {
        var seen = Set<UUID>()
        return (historicalEvents + derivedEvents)
            .sorted { $0.timestamp > $1.timestamp }
            .filter { seen.insert($0.id).inserted }
    }

    static func event(from worklogEvent: WorkflowWorklogEvent) -> WorkflowEvent {
        switch worklogEvent {
        case let .considered(candidates):
            let selected = candidates.filter(\.wasSelected).count
            return .executionUpdate("Considered \(candidates.count) option(s): \(selected) selected, \(candidates.count - selected) rejected")
        case .proposed:
            return .workflowStarted
        case let .checksEvaluated(results):
            if let failure = results.first(where: { !$0.passed }) {
                return .checkFailed(id: failure.checkID, reason: failure.detail ?? "failed")
            }
            // Warnings are named here rather than collapsed into "Checks passed". A two-way branch on
            // `passed` reports a non-blocking warning — an address that is well-formed but
            // unchecksummed — as a clean pass, which contradicts the timeline surface for the same
            // entry (`MissionControlSectionViews` renders the three tiers distinctly) and hides the
            // one thing the warning tier exists to surface.
            let warnings = results.warnings
            guard warnings.isEmpty else {
                let detail = warnings
                    .map { $0.detail ?? $0.checkID }
                    .joined(separator: "; ")
                return .executionUpdate("Checks passed with \(warnings.count) warning(s): \(detail)")
            }
            return .executionUpdate("Checks passed")
        case let .decided(decision):
            switch decision {
            case .allow:
                return .executionUpdate("Allowed by policy")
            case let .block(reason):
                return .workflowBlocked(reason: reason)
            case let .revise(instructions):
                return .workflowBlocked(reason: instructions)
            case let .escalate(request):
                return .approvalRequired(request)
            }
        case let .executed(artifactID, _):
            return .artifactCreated(id: artifactID)
        case let .blocked(reason):
            return .workflowBlocked(reason: reason)
        case let .failed(reason):
            return .executionUpdate("Failed: \(reason)")
        case let .routinePhase(phase, detail):
            switch phase {
            case .blocked:
                return .workflowBlocked(reason: detail ?? "Routine blocked")
            case .authorityResolved, .contextGathered, .operatorFinished,
                 .artifactProduced, .artifactRejected, .awaitingApproval, .completed, .failed:
                guard let detail, !detail.isEmpty else { return .executionUpdate(phase.displayTitle) }
                return .executionUpdate("\(phase.displayTitle): \(detail)")
            }
        case let .unknown(caseName, _):
            return .executionUpdate("Unrecognized step “\(caseName)” — recorded by a newer version")
        }
    }

}
