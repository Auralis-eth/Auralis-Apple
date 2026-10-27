import ArtifactCore
import AuralisPrimaryModels
import AuralisFoundation
import AuralisRuntime
import Foundation
import Observation
import OperatorsFeature
import PolicyCore
import ReceiptsCore
import RuntimeKit
import SocialCore
import TrustedUIKit

extension MissionControlHomeModel {
    // MARK: - Approvals (P1-201)

    public enum ApprovalDecision: String, Sendable {
        case approved, rejected, deferred

        var receiptSuccess: Bool {
            switch self {
            case .approved, .deferred:
                return true
            case .rejected:
                return false
            }
        }

        var displayTitle: String {
            switch self {
            case .approved:
                return "Recorded approval"
            case .rejected:
                return "Recorded rejection"
            case .deferred:
                return "Deferred"
            }
        }
    }

    /// How risky a pending approval is, so the inbox can distinguish risky proposed steps from
    /// routine asks. (P1-201)
    public enum ApprovalRisk: String, Sendable {
        case routine = "Routine"
        case elevated = "Needs review"
        case high = "High risk"

        public var systemImage: String {
            switch self {
            case .routine: return "checkmark.circle"
            case .elevated: return "exclamationmark.circle"
            case .high: return "exclamationmark.triangle.fill"
            }
        }

        public var isRisky: Bool { self != .routine }
    }

    /// Classifies a pending approval by the blast radius of its proposed action.
    public func risk(for request: ApprovalRequest) -> ApprovalRisk {
        switch request.proposal.impact {
        case .readOnly, .reversibleWrite:
            return .routine
        case .externalImpact:
            return .elevated
        case .highRisk:
            return .high
        }
    }

    /// Plain-language statement of *why* this approval is needed, derived from the proposal's impact
    /// class and any named approvals it declares. (P1-201)
    public func approvalReason(for request: ApprovalRequest) -> String {
        let base: String
        switch request.proposal.impact {
        case .readOnly:
            base = "This step only reads data but was routed for confirmation."
        case .reversibleWrite:
            base = "This step writes local, undoable state and was routed for confirmation."
        case .externalImpact:
            base = "This step reaches outside the device or produces an effect you'd want to see first."
        case .highRisk:
            base = "This step is irreversible or moves funds, so it needs your explicit sign-off."
        }
        guard !request.proposal.requiredApprovals.isEmpty else { return base }
        return "\(base) Required approvals: \(request.proposal.requiredApprovals.joined(separator: ", "))."
    }

    /// Durable receipts already recorded for a pending approval's workflow — the "receipt draft"
    /// an approval item links to. (P1-201)
    public func receipts(forApproval request: ApprovalRequest) -> [ReceiptRecord] {
        // Resolved, not raw: receipts are written under `resolvedCorrelationID`, so matching on the
        // raw optional would find nothing for an uncorrelated proposal.
        let correlationID = request.proposal.resolvedCorrelationID
        return browserReceipts.filter { $0.correlationID == correlationID }
    }

    /// Artifacts affected by a pending approval's workflow, resolved through its receipts. (P1-201)
    public func artifacts(forApproval request: ApprovalRequest) -> [Artifact] {
        var seen = Set<UUID>()
        var result: [Artifact] = []
        for receipt in receipts(forApproval: request) {
            for artifactID in artifactIDs(from: receipt) where seen.insert(artifactID).inserted {
                guard let artifact = artifact(id: artifactID) else { continue }
                result.append(artifact)
            }
        }
        return result
    }

    /// Records the operator's decision as a durable receipt and clears the item from the inbox.
    /// (A `deferred` decision leaves the item pending.)
    public func resolve(_ request: ApprovalRequest, decision: ApprovalDecision) async {
        // The trusted surface latches immediately, and this model-side claim is the second line of
        // defense: stale views or concurrent callers cannot resume the same governed proposal twice.
        //
        // Two claims, because the in-flight latch is handed off to the durable set once the decision
        // reaches the ledger (see `loadRuntimeHistory`). Checking only the latch would let a stale
        // view re-resolve a request whose receipt is already written — appending a second approval
        // receipt and resuming the proposal again. A `deferred` decision is deliberately absent from
        // the durable set, so deferring and later deciding still works.
        guard !durablyResolvedApprovalIDs.contains(request.id.uuidString) else { return }
        guard resolvingApprovalIDs.insert(request.id).inserted else { return }
        defer {
            if decision == .deferred {
                resolvingApprovalIDs.remove(request.id)
            }
        }
        // Re-run the dry-run at the moment of approval so the durable trust record reflects chain
        // state at the decision point, not whenever the proposal was first opened. Only refreshes a
        // dry-run the operator actually saw — it never fabricates one at approval for a proposal that
        // was never simulated (that stays omitted from the receipt). (P1-AGENT-103 trust freshness)
        if decision == .approved, proposalSimulations[request.proposal.id] != nil {
            await simulateProposal(request.proposal, force: true)
        }
        // Persist the exact diff (and on-chain simulation, if one ran) the operator was shown, so
        // "what was I looking at when I approved this?" is reconstructable from the durable audit
        // trail rather than living only in ephemeral view state. (P1-AGENT-103 trust-trail)
        var payloadValues: [String: ReceiptJSONValue] = [
            "approvalID": .string(request.id.uuidString),
            "capability": .string(request.proposal.capability.rawValue),
            "intent": .string(request.proposal.intent),
            "decision": .string(decision.rawValue),
            "reason": .string(approvalReason(for: request)),
            "risk": .string(risk(for: request).rawValue),
            "proposalDiff": approvalDiffSnapshot(for: request.proposal)
        ]
        if let simulation = approvalSimulationSnapshot(for: request.proposal) {
            payloadValues["simulation"] = simulation
        }
        // The person at the keyboard made this call, and their decision *is* the authority the
        // downstream execution proceeds under — so record both legs, not just a coarse `.user`
        // (P0.5-602). Without this, the single most trust-critical receipt in the system degraded to
        // the label "User" with no structured attribution at all.
        let approvalAuthority = AuthorityRef(
            source: .humanApproval,
            capability: request.proposal.capability,
            reason: approvalReason(for: request)
        )
        let draft = ReceiptDraft(
            category: "approval",
            kind: "approval.\(decision.rawValue)",
            // Resolved, not raw: the pipeline files this proposal's worklog and session under
            // `resolvedCorrelationID`, so the raw optional would strand the approval receipt — the
            // most trust-critical row in the system — outside the trace it belongs to.
            correlationID: request.proposal.resolvedCorrelationID,
            payload: ReceiptPayload(values: payloadValues),
            actorDetail: ActorRef.human.receiptActorDetail,
            authorityDetail: approvalAuthority.receiptAuthorityDetail,
            summary: "\(decision.displayTitle): \(request.proposal.intent)",
            provenance: "operator",
            isSuccess: decision.receiptSuccess
        )
        guard await host.appendRuntimeReceipt(
            draft,
            goal: request.proposal.intent,
            actor: .human,
            approvalID: request.id,
            executionUpdate: "\(decision.displayTitle): \(request.proposal.intent)"
        ) != nil else {
            approvalPersistenceError = "The approval decision was not saved, so the action was not executed. Try again after receipt storage is available."
            resolvingApprovalIDs.remove(request.id)
            return
        }
        approvalPersistenceError = nil
        if decision != .deferred {
            pendingApprovals.removeAll { $0.id == request.id }
        }
        if decision == .approved {
            let outcome = await host.resumeApprovedProposal(request)
            operatorOutcomes[request.proposal.actor.identifier ?? request.proposal.id.uuidString] = Self.describe(outcome)
        }
        switch decision {
        case .approved:
            await host.recordApprovalDecision(runID: request.proposal.id, decision: .approved)
        case .rejected:
            await host.recordApprovalDecision(runID: request.proposal.id, decision: .rejected)
        case .deferred:
            break
        }
        await loadReceipts()
        await loadRuntimeHistory()
        await refreshLeases()
    }

    /// Serializes the declared-impact diff shown at approval time into a durable receipt value, so
    /// the exact before/after/risk the operator approved against is preserved in the audit trail.
    /// (P1-AGENT-103 trust-trail)
    func approvalDiffSnapshot(for proposal: ActionProposal) -> ReceiptJSONValue {
        .array(proposalDiffRows(for: proposal).map { row in
            .object([
                "label": .string(row.label),
                "before": .string(row.before),
                "after": .string(row.after),
                "risk": .string(row.risk)
            ])
        })
    }

    /// Serializes the on-chain dry-run the operator saw — when one had run for this proposal — into a
    /// durable receipt value. Returns `nil` when no simulation was performed, so the payload only
    /// carries a simulation record when there was actually one on screen. (P1-AGENT-103 trust-trail)
    func approvalSimulationSnapshot(for proposal: ActionProposal) -> ReceiptJSONValue? {
        guard case let .finished(simulation)? = proposalSimulations[proposal.id] else { return nil }
        var values: [String: ReceiptJSONValue] = [
            "status": .string(Self.simulationStatusLabel(simulation.status))
        ]
        if let simulatedAt = proposalSimulatedAt[proposal.id] {
            values["simulatedAt"] = .string(ISO8601DateFormatter().string(from: simulatedAt))
        }
        if let chainName = simulation.chainName { values["chain"] = .string(chainName) }
        if simulation.chainAssumed { values["chainAssumed"] = .string("true") }
        if let gasUsed = simulation.gasUsed { values["gasUsed"] = .string(gasUsed) }
        if let cost = simulation.estimatedGasCostEth { values["estimatedGasCostEth"] = .string(cost) }
        if !simulation.assetChanges.isEmpty {
            values["assetChanges"] = .array(simulation.assetChanges.map { change in
                .object([
                    "direction": .string(Self.assetChangeDirectionLabel(change.direction)),
                    "amount": .string(change.amount),
                    "symbol": .string(change.symbol),
                    "counterparty": .string(change.counterparty ?? "unknown")
                ])
            })
        }
        return .object(values)
    }

    static func simulationStatusLabel(_ status: ProposalSimulation.Status) -> String {
        switch status {
        case .success: return "success"
        case let .reverted(reason): return reason.isEmpty ? "reverted" : "reverted: \(reason)"
        case .notApplicable: return "notApplicable"
        case let .unavailable(reason): return reason.isEmpty ? "unavailable" : "unavailable: \(reason)"
        }
    }

    static func assetChangeDirectionLabel(_ direction: ProposalAssetChange.Direction) -> String {
        switch direction {
        case .incoming: return "incoming"
        case .outgoing: return "outgoing"
        case .unknown: return "unknown"
        }
    }

    // MARK: - Trusted UI adoption (P0.5-502)

    /// A governed `TrustedUIComponentRegistry` wired to the current console data, so trusted surfaces
    /// (approval, receipt, capability, context) render through the single sanctioned factory rather
    /// than in parallel with it. Rebuilt per access over value snapshots so its resolvers stay
    /// `Sendable` (they never capture the `@MainActor` model).
    public var trustedUIRegistry: TrustedUIComponentRegistry {
        // Indexed by ID rather than scanned: the receipts list resolves one request per visible row, so a
        // linear scan per resolve made rendering the browser quadratic in the receipt count. Indexes the
        // records (not the summaries) so only the rows actually asked for build a summary.
        let receiptsByID = Dictionary(
            browserReceipts.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let leases = activeLeases
        return TrustedUIComponentRegistry(
            receiptResolver: { id in
                receiptsByID[id].map(MissionControlHomeModel.trustedReceiptSummary(from:))
            },
            leaseResolver: { capability in
                leases.first { $0.capability == capability && $0.isActive() }
            }
        )
    }

    /// Pure bridge from a durable `ReceiptRecord` to the trusted, display-ready summary the
    /// `ReceiptCard` consumes. `nonisolated` + value-only so it is safe to call from a `Sendable`
    /// resolver off the main actor.
    nonisolated static func trustedReceiptSummary(from receipt: ReceiptRecord) -> TrustedUIReceiptSummary {
        TrustedUIReceiptSummary(
            id: receipt.id,
            title: receipt.summary,
            subtitle: "\(receipt.scope) • \(receipt.isSuccess ? "Success" : "Denied")",
            actorLabel: ReceiptAttributionDisplay.actorLabel(for: receipt),
            timestamp: receipt.createdAt,
            fields: [
                .init(key: "Trigger", value: receipt.trigger),
                .init(key: "Mode", value: receipt.mode.rawValue)
            ]
        )
    }

    /// Instance convenience for the receipts list row.
    public func trustedReceiptSummary(for receipt: ReceiptRecord) -> TrustedUIReceiptSummary {
        Self.trustedReceiptSummary(from: receipt)
    }

    /// Resolve a pending approval from a trusted `ApprovalSheet` outcome, mapping onto the console's
    /// three-way `ApprovalDecision` (deferred keeps the item pending).
    public func resolve(_ request: ApprovalRequest, outcome: TrustedUIApprovalOutcome) async {
        let decision: ApprovalDecision
        switch outcome {
        case .approved: decision = .approved
        case .denied: decision = .rejected
        case .deferred: decision = .deferred
        }
        await resolve(request, decision: decision)
    }

    /// Approval decisions are append-only facts. Approved and rejected receipts make a pending request
    /// resolved across reloads; deferred receipts intentionally do not clear the inbox.
    ///
    /// - Parameter reusingLoadedHistory: when `true` *and* ``browserReceipts`` holds the complete
    ///   exported history, resolve against that instead of exporting and decoding the whole store a
    ///   second time. Opt-in rather than automatic: a stale browsed set would let an approval this
    ///   model has already resolved rehydrate as pending, so only a caller that has just loaded the
    ///   complete history in the same pass may ask for reuse.
    func resolvedApprovalIDs(reusingLoadedHistory: Bool = false) async -> Set<String> {
        let receipts: [ReceiptRecord]
        if reusingLoadedHistory, receiptHistoryScope == .complete {
            receipts = browserReceipts
            approvalHistoryDataIssue = nil
        } else {
            do {
                // A read, not an export. Resolving which approvals are already decided needs the
                // rows; it does not need a signed archive, and paying for one here meant an approval
                // the person had already answered rehydrated as pending whenever the integrity gate
                // tripped for an unrelated reason.
                receipts = try await receiptStore.allRecords()
                approvalHistoryDataIssue = nil
            } catch {
                approvalHistoryDataIssue = "Full approval history could not be loaded. Pending approvals are shown conservatively until receipt storage recovers."
                return []
            }
        }
        return Set(receipts.compactMap { receipt in
            guard receipt.scope == "approval",
                  receipt.trigger == "approval.approved" || receipt.trigger == "approval.rejected",
                  case let .string(approvalID) = receipt.details.values["approvalID"] else {
                return nil
            }
            return approvalID
        })
    }

    // MARK: - Capability leases (P1-202)

    /// The four authority scopes the Capability Inspector distinguishes. (P1-202)
    public enum CapabilityScope: String, CaseIterable, Sendable {
        case account = "Account scope"
        case data = "Data scope"
        case execution = "Execution scope"
        case artifact = "Artifact scope"

        public var systemImage: String {
            switch self {
            case .account: return "person.crop.circle"
            case .data: return "externaldrive"
            case .execution: return "gearshape.2"
            case .artifact: return "doc.badge.gearshape"
            }
        }

        public var explanation: String {
            switch self {
            case .account: return "Access to your wallet/account and what it can authorize."
            case .data: return "Read or write access to your library and its metadata."
            case .execution: return "Permission to run tools, plugins, or playback on your behalf."
            case .artifact: return "Permission to produce or export durable artifacts."
            }
        }
    }

    /// Classifies a capability into one of the four inspectable scopes. (P1-202)
    public func scope(for capability: CapabilityID) -> CapabilityScope {
        scope(for: CapabilityLeaseScope.defaultScope(for: capability))
    }

    /// Classifies a lease by the explicit scope recorded when it was granted. (P1-202)
    public func scope(for lease: CapabilityLease) -> CapabilityScope {
        scope(for: lease.scope)
    }

    private func scope(for leaseScope: CapabilityLeaseScope) -> CapabilityScope {
        switch leaseScope {
        case .account:
            return .account
        case .data:
            return .data
        case .execution:
            return .execution
        case .artifact:
            return .artifact
        }
    }

    /// Active leases grouped by scope, in the fixed scope order, for the inspector. (P1-202)
    public func leases(inScope scope: CapabilityScope) -> [CapabilityLease] {
        activeLeases.filter { self.scope(for: $0) == scope }
    }

    /// Human-readable title for a capability, from the capability registry. (P1-202)
    public func capabilityTitle(_ capability: CapabilityID) -> String {
        CapabilityRegistry.descriptor(for: capability).title
    }

    /// The reason a capability was granted — what powers it confers — from the registry. (P1-202)
    public func grantReason(for lease: CapabilityLease) -> String {
        lease.reason
    }

    /// Plain-language duration of a lease's grant window. (P1-202)
    public func durationText(for lease: CapabilityLease) -> String {
        let seconds = lease.expiresAt.timeIntervalSince(lease.grantedAt)
        let minutes = max(1, Int((seconds / 60).rounded()))
        return "granted for \(minutes) min • expires \(relativeText(lease.expiresAt))"
    }

    public func refreshLeases() async {
        activeLeases = await host.activeCapabilityLeases()
        activeRestrictions = await host.activeCapabilityRestrictions()
        markLoaded(.capabilityLeaseRegistry)
    }

    public func revokeLease(id: UUID) async {
        await host.revokeCapabilityLease(id: id)
        await refreshLeases()
    }

    public func revokeRestriction(id: UUID) async {
        await host.revokeCapabilityRestriction(id: id)
        await refreshLeases()
    }

    @discardableResult
    public func grantLease(
        capability: CapabilityID,
        actorKind: ActorKind,
        actorIdentifier: String,
        reason: String,
        durationMinutes: Int
    ) async -> CapabilityLease {
        let normalizedIdentifier = actorIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let actor = ActorRef(
            kind: actorKind,
            identifier: normalizedIdentifier.isEmpty ? nil : normalizedIdentifier
        )
        let lease = await host.grantCapabilityLease(
            capability: capability,
            grantedTo: actor,
            reason: normalizedReason.isEmpty ? nil : normalizedReason,
            duration: TimeInterval(max(1, durationMinutes) * 60)
        )
        await refreshLeases()
        return lease
    }

    @discardableResult
    public func denyCapability(
        _ kind: CapabilityRestrictionKind,
        actorKind: ActorKind?,
        actorIdentifier: String,
        reason: String,
        durationMinutes: Int?
    ) async -> CapabilityRestriction {
        let normalizedIdentifier = actorIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let actor = actorKind.map {
            ActorRef(
                kind: $0,
                identifier: normalizedIdentifier.isEmpty ? nil : normalizedIdentifier
            )
        }
        let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let restriction = await host.denyCapability(
            kind,
            reason: normalizedReason.isEmpty ? "Restricted from Mission Control." : normalizedReason,
            appliesTo: actor,
            duration: durationMinutes.map { TimeInterval(max(1, $0) * 60) }
        )
        await refreshLeases()
        return restriction
    }

    public func loadAgentSessions() async {
        agentSessions = await host.sessionStore.allSessions()
    }

    // MARK: - Workflow stop controls (P1-101)

    public func canStopWorkflow(_ summary: WorkflowSummary) -> Bool {
        switch summary.state {
        case .queued, .running, .waiting:
            return true
        case .blocked, .completed, .failed:
            return false
        }
    }

    public func stopWorkflow(id correlationID: String) async {
        await host.stopWorkflow(correlationID: correlationID)
        // Resolved, not raw: `id` is a ``WorkflowSummary`` id, which comes from the event envelope —
        // and the pipeline publishes those under `resolvedCorrelationID`. Matching the raw optional
        // stranded every proposal that carried no explicit correlation id, because its resolved id is
        // the proposal's own UUID while the raw one is `nil`. The approval then survived the stop and
        // sat in the inbox still live, where approving it resumes work the operator just stopped.
        pendingApprovals.removeAll { $0.proposal.resolvedCorrelationID == correlationID }
        await loadReceipts()
        await loadRuntimeHistory()
    }

}
