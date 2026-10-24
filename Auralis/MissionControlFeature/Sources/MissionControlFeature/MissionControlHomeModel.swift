import ArtifactCore
import AuralisPrimaryModels
import CapabilitiesCore
import EvalCore
import Foundation
import Observation
import OperatorsFeature
import PerformanceCore
import PlaybookCore
import PolicyCore
import ReceiptsCore
import RuntimeCore
import RuntimeKit
import SchedulingCore
import SocialCore
import TrustedUIKit

/// View model for the Mission Control Home console. (P1-101)
///
/// Reads durable history from the `ReceiptStore` and the live activity feed from the runtime event
/// bus. Read-only over the runtime — the only control it drives is the global pause (kill switch).
@MainActor
@Observable
public final class MissionControlHomeModel {
    public let host: RuntimeHost
    /// Internal rather than private so the governance extension can read durable approval history.
    let receiptStore: any ReceiptStore
    /// Optional on-chain dry-run backend for the Proposal Diff Viewer (P1-AGENT-103). `nil` in tests
    /// and previews, where the diff falls back to declared-impact metadata only.
    private let proposalSimulator: (any ProposalSimulating)?
    private let operatorWatchlistStore: any OperatorWatchlistStoring
    public let activeIdentityID: String?

    public private(set) var recentReceipts: [ReceiptRecord] = []
    /// Degraded-evidence messages, tracked per source rather than in one shared slot.
    ///
    /// One slot let a recovering read clear an unrelated source's warning: after a *hard* history
    /// read failure, the next successful `loadReceipts()` cleared the banner while the receipt
    /// browser, artifact provenance, and approval resolution were all still working from empty
    /// history. Separately, `resolvedApprovalIDs()` could only ever *set* its message — nothing
    /// cleared it on recovery.
    private var recentReceiptsDataIssue: String?
    private var receiptHistoryDataIssue: String?
    /// Internal rather than private: the governance extension owns approval resolution.
    var approvalHistoryDataIssue: String?
    private var artifactBrowserDataIssue: String?
    private var artifactVersionDataIssue: String?

    /// The most severe outstanding receipt-evidence problem: a broken full history outranks an
    /// unverifiable approval history, which outranks a stale recent window.
    public var receiptDataIssue: String? {
        receiptHistoryDataIssue ?? approvalHistoryDataIssue ?? recentReceiptsDataIssue
    }

    /// How much of the durable receipt history ``browserReceipts`` currently holds.
    ///
    /// One value rather than a pair of Bools: "complete", "truncated", and "could not be read" are
    /// three states, and encoding them in two independent flags admitted a fourth, impossible
    /// combination — and left one of the flags unread.
    public enum ReceiptHistoryScope: String, Sendable {
        /// Nothing has been read yet. Distinct from ``unavailable``: no read has failed.
        case notLoaded
        /// The complete exported history.
        case complete
        /// A truncated newest-N window, because the full export could not be read.
        case truncated
        /// Neither the export nor the window could be read; previously loaded receipts remain shown.
        case unavailable
    }

    /// Derivations that must see *every* receipt (approval resolution) require
    /// ``ReceiptHistoryScope/complete`` before reusing ``browserReceipts``, rather than exporting and
    /// decoding the whole store again.
    public private(set) var receiptHistoryScope: ReceiptHistoryScope = .notLoaded

    /// What this device can vouch for about the loaded ledger, or `nil` when it has not been
    /// established (not read yet, the verifier failed, or the window is truncated).
    ///
    /// A **separate axis** from ``receiptHistoryScope`` rather than another case on it: "how much of
    /// the history do we have" and "can we attest to what we have" are independent questions, and a
    /// complete history can be untrustworthy exactly as easily as a truncated one can be sound.
    public private(set) var receiptLedgerAttestation: ReceiptLedgerAttestation?

    /// What to tell a person about the trustworthiness of the receipts on screen, or `nil` when every
    /// row is attestable and nothing suggests removal.
    ///
    /// `nil` is reserved for ``ReceiptLedgerAttestation/Status/verified`` with no advisory. An absent
    /// verdict is *not* silence — it reports that the device cannot vouch — because a verifier that
    /// failed to run must never be indistinguishable from one that passed.
    public var receiptAttestationNotice: String? {
        guard receiptHistoryScope == .complete || receiptLedgerAttestation != nil else { return nil }
        guard let attestation = receiptLedgerAttestation else {
            return "This device could not verify the receipt history. The receipts below are shown as "
                + "stored, but their integrity has not been confirmed."
        }
        var notice: String?
        switch attestation.status {
        case .verified:
            notice = nil
        case .unattested:
            // Ordinary and expected after an upgrade or a device restore — the signing key and the
            // integrity anchors are both `ThisDeviceOnly` and do not survive a transfer. Worded as a
            // limit on what can be *proved*, never as evidence of alteration.
            notice = "These receipts are intact but cannot be proved from this device — usually "
                + "because they predate signing or were restored from another device."
        case .tampered:
            notice = "Receipt history integrity check failed. Some receipts may have been altered or "
                + "removed, and this history should not be relied on as an audit trail."
        }
        // The advisory rides alongside the status rather than replacing it, per its own contract: it
        // is a suggestion to investigate possible removal, not a verdict in either direction.
        if let advisory = attestation.completenessAdvisory {
            notice = [notice, advisory].compactMap { $0 }.joined(separator: " ")
        }
        return notice
    }

    public var artifactDataIssue: String? {
        artifactVersionDataIssue ?? artifactBrowserDataIssue
    }
    public internal(set) var approvalPersistenceError: String?
    public private(set) var operatorWatchlistDataIssue: String?
    public private(set) var liveEvents: [WorkflowEventEnvelope] = [] {
        didSet { invalidateWorkflowSummaries() }
    }
    public private(set) var runtimeEventSubscriberHealth: [RuntimeEventSubscriberHealth] = []
    // Governance state stays owned here, but the setters are module-internal so the
    // approval/capability/session behavior can live in `MissionControlHomeModel+Governance`.
    public internal(set) var pendingApprovals: [ApprovalRequest] = [] {
        didSet { invalidateAgentSessionSummaries() }
    }
    /// Requests this model has claimed but whose decision is not yet known to be durable.
    ///
    /// Handed off to ``durablyResolvedApprovalIDs`` on the next history load, so it stays bounded by
    /// what is genuinely in flight rather than accumulating every decision the session ever made.
    var resolvingApprovalIDs: Set<UUID> = []
    /// Approval ids the *durable* receipt history says are already decided.
    ///
    /// The live event stream can replay an `.approvalRequired` envelope for a request that was
    /// resolved earlier (or in a previous session), and ``observeEvents(from:)`` inserts straight into
    /// the inbox without consulting storage — so it checks this instead. It is also the second half of
    /// the double-resolve guard: `resolvingApprovalIDs` covers a decision still in flight, this covers
    /// one already on the ledger, and between them a governed proposal cannot be resumed twice.
    ///
    /// Internal rather than private so the governance extension can consult it. `@ObservationIgnored`
    /// because no surface renders it.
    @ObservationIgnored var durablyResolvedApprovalIDs: Set<String> = []
    /// Workflows the durable worklog says are terminal, as of the last history load. Consulted by the
    /// live-stream insert so a late `.approvalRequired` envelope cannot re-add an ask for a workflow
    /// that has already been stopped, blocked, completed, or failed.
    ///
    /// `@ObservationIgnored` because no surface renders it.
    @ObservationIgnored var terminalWorkflowCorrelationIDs: Set<String> = []
    public internal(set) var activeLeases: [CapabilityLease] = []
    public internal(set) var activeRestrictions: [CapabilityRestriction] = []
    public internal(set) var agentSessions: [AgentSession] = [] {
        didSet { invalidateAgentSessionSummaries() }
    }
    public var workflowStatusFilter: WorkflowStateFilter = .all
    public var workflowSearchText: String = ""
    /// Timeline account filter — `nil` means all accounts. (P1-102)
    public var workflowAccountFilter: String?
    /// Timeline operator/playbook filter — `nil` means all. (P1-102)
    public var workflowPlaybookFilter: String?

    /// Reference "now" for relative date rendering and context-freshness validation.
    ///
    /// Reads the wall clock through ``clock`` on every access, so relative labels ("expires in 5
    /// min", "Simulated 2 minutes ago") and the freshness bound stay correct however long the console
    /// stays open. A value frozen at construction drifted by the model's entire lifetime — and since
    /// nothing ever reassigned it, every relative label was measured against app launch.
    ///
    /// Assigning *pins* it, which is how snapshot tests and previews render deterministically.
    public var referenceDate: Date {
        get { pinnedReferenceDate ?? clock() }
        set { pinnedReferenceDate = newValue }
    }

    private var pinnedReferenceDate: Date?
    private let clock: @MainActor () -> Date

    /// The pinned reference date, or `nil` when this model is on the live clock.
    ///
    /// Views forward this to trusted components that do their own clock reads (``ContextBundleCard``
    /// renders ages with SwiftUI's self-updating `.relative` style). Forwarding ``referenceDate``
    /// instead would hand them a wall-clock value on every body pass and silently freeze those labels
    /// between invalidations; `nil` is what keeps the live console ticking.
    public var pinnedRenderingDate: Date? { pinnedReferenceDate }

    /// When each authoritative source was last read successfully.
    ///
    /// ``inspectedContextBundle`` stamps each field's `lastRefreshed` from this map so the contract's
    /// `maxAge` bound is evaluated against when the *data* was read. Stamping every field with the
    /// render clock and then validating against that same clock made every field exactly zero seconds
    /// old, so the freshness leg of the contract could never fail — the "governed context is fresh"
    /// surface asserted a guarantee nothing checked. A source absent from this map has never been
    /// read, which the contract correctly reports as not fresh rather than silently passing.
    /// (P1-AGENT-102 freshness)
    public private(set) var sourceLoadedAt: [GovernedContextSource: Date] = [:]

    public init(
        host: RuntimeHost,
        receiptStore: any ReceiptStore,
        proposalSimulator: (any ProposalSimulating)? = nil,
        activeIdentityID: String? = nil,
        operatorWatchlistStore: (any OperatorWatchlistStoring)? = nil,
        clock: @escaping @MainActor () -> Date = { .now }
    ) {
        self.host = host
        self.receiptStore = receiptStore
        self.clock = clock
        self.proposalSimulator = proposalSimulator
        let normalizedIdentity = activeIdentityID?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.activeIdentityID = normalizedIdentity?.isEmpty == false ? normalizedIdentity : nil
        self.operatorWatchlistStore = operatorWatchlistStore ?? InMemoryOperatorWatchlistStore()
        do {
            self.operatorWatchlist = try self.operatorWatchlistStore.load(identityID: self.activeIdentityID)
        } catch {
            self.operatorWatchlistDataIssue = error.localizedDescription
        }
    }

    /// A deterministic relative-time string for `date`, measured against ``referenceDate``. Used in
    /// place of SwiftUI's `Text(_:style:.relative)` where the wall clock would make snapshots flaky.
    func relativeText(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: referenceDate)
    }

    /// Bound directly by the pause toggle. A SwiftUI `Binding` setter cannot await, so the flip is
    /// handed to a task — but correctness no longer rests on the caller awaiting it: ``RuntimeHost``
    /// closes the pause gate and the scheduling engine *before* it publishes `isPaused`, so this
    /// getter can never report paused while governed work is still able to start.
    /// ``setPaused(_:reason:)`` is there for callers that can await the whole transition.
    public var isPaused: Bool {
        get { host.isPaused }
        set { Task { await host.setPaused(newValue) } }
    }

    /// Plain-language reason the kill switch is engaged, shown wherever the paused state appears. (P1-204)
    public var pauseReason: String? { host.pauseReason }

    /// Flips the kill switch and waits for it to take hold, for callers in an async context.
    public func setPaused(_ paused: Bool, reason: String? = nil) async {
        await host.setPaused(paused, reason: reason)
    }

    /// Lifts the global pause — the "resume path" the paused-state surfaces link to. (P1-204)
    public func resumeOperator() async {
        await host.setPaused(false)
    }

    public var cryptoModeLabel: String { host.cryptoModeLabel }

    public var cryptoMode: CryptoMode {
        get { host.cryptoMode }
        set { host.setCryptoMode(newValue) }
    }

    /// Records that `source` was read successfully, as of the current reference clock.
    ///
    /// Stamped from ``referenceDate`` rather than the raw clock so a pinned reference date keeps both
    /// legs of the freshness comparison on one clock — otherwise a test that pins the date and then
    /// loads would produce a load stamp in the validator's future.
    func markLoaded(_ source: GovernedContextSource) {
        sourceLoadedAt[source] = referenceDate
    }

    public func loadReceipts() async {
        do {
            recentReceipts = try await receiptStore.latest(limit: 25)
            recentReceiptsDataIssue = nil
            markLoaded(.receiptStore)
        } catch {
            recentReceiptsDataIssue = "Recent receipts could not be loaded. Previously loaded audit data remains visible."
        }
    }

    public func loadRuntimeHistory() async {
        await loadRuntimeHistory(reusingLoadedReceiptHistory: false)
    }

    /// - Parameter reusingLoadedReceiptHistory: see ``resolvedApprovalIDs(reusingLoadedHistory:)``
    ///   for why reuse is opt-in rather than automatic.
    func loadRuntimeHistory(reusingLoadedReceiptHistory: Bool) async {
        let steps = await host.worklogStore.allSteps()
        worklogStoreHealth = await host.worklogStore.health()
        let resolvedApprovalIDs = await resolvedApprovalIDs(
            reusingLoadedHistory: reusingLoadedReceiptHistory
        )
        workflowStepLogs = steps
        liveEvents = Self.mergeEvents(await host.recentEvents(limit: 100), with: Self.events(from: steps))
        terminalWorkflowCorrelationIDs = Self.terminalCorrelationIDs(in: steps)
        pendingApprovals = Self.pendingApprovals(
            in: liveEvents,
            excluding: resolvedApprovalIDs,
            terminalCorrelationIDs: terminalWorkflowCorrelationIDs
        )
        // Approval decisions are append-only facts, so a resolved id never becomes unresolved —
        // union, never replace. That makes a failed history read (which returns an empty set) a
        // no-op here rather than an amnesia event.
        durablyResolvedApprovalIDs.formUnion(resolvedApprovalIDs)
        // `resolvingApprovalIDs` only has to hold the line until the decision is durable: from here
        // on, ``observeEvents(from:)`` rejects a late envelope against the durable set above. Keeping
        // the id in both would grow the in-flight set for the model's entire lifetime to re-state
        // something the durable record already says.
        resolvingApprovalIDs.subtract(
            resolvingApprovalIDs.filter { durablyResolvedApprovalIDs.contains($0.uuidString) }
        )
        markLoaded(.worklogStore)
        markLoaded(.runtimeEventBus)
        await loadAgentSessions()
    }

    /// Collapses `.approvalRequired` envelopes into the inbox's pending set, one entry per request.
    ///
    /// One escalation is deliberately recorded twice: `GovernedToolPipeline.escalate` writes a
    /// `.decided(.escalate)` worklog entry *and* publishes an `.approvalRequired` event. The two carry
    /// different envelope ids, so ``mergeEvents(_:with:)`` — which de-duplicates by envelope — is right
    /// to keep both. The inbox is keyed by the *request*, not the envelope, so it has to collapse them
    /// here: two rows for one ask doubled the approval count on Home and the contract-validated
    /// `approvals.pending.count` in the governed context bundle, and handed `ForEach` duplicate
    /// `Identifiable` ids.
    ///
    /// `envelopes` is expected newest-first (as `mergeEvents` returns), so the surviving entry is the
    /// most recent record of the ask.
    /// - Parameter terminalCorrelationIDs: workflows the durable worklog says have already reached a
    ///   terminal state (blocked / completed / failed). A terminal workflow cannot have a live ask, so
    ///   its escalation must not be re-derived as pending. This is what makes stopping a workflow stick:
    ///   `stopWorkflow` clears the inbox optimistically, but it then reloads history, and this
    ///   derivation rebuilds `pendingApprovals` from the worklog — which still holds the
    ///   `.decided(.escalate)` entry. Without this the approval came straight back, and approving it
    ///   resumed work the operator had explicitly stopped. Keyed off the worklog rather than a new
    ///   receipt kind so it survives reloads and relaunches without inventing an approval decision the
    ///   operator never made.
    static func pendingApprovals(
        in envelopes: [WorkflowEventEnvelope],
        excluding resolvedApprovalIDs: Set<String>,
        terminalCorrelationIDs: Set<String> = []
    ) -> [ApprovalRequest] {
        var seen = Set<UUID>()
        return envelopes.compactMap { envelope in
            guard case let .approvalRequired(request) = envelope.event else { return nil }
            guard !resolvedApprovalIDs.contains(request.id.uuidString) else { return nil }
            guard !terminalCorrelationIDs.contains(request.proposal.resolvedCorrelationID) else {
                return nil
            }
            guard seen.insert(request.id).inserted else { return nil }
            return request
        }
    }

    /// Correlation ids whose durable worklog trace has reached a terminal state.
    static func terminalCorrelationIDs(in steps: [WorkflowStepLog]) -> Set<String> {
        let grouped = Dictionary(grouping: steps) { $0.correlationID }
        var terminal = Set<String>()
        for (correlationID, steps) in grouped {
            guard let correlationID else { continue }
            let ordered = steps.sorted { $0.timestamp < $1.timestamp }
            switch state(forWorklog: ordered.map(\.event)) {
            case .blocked, .completed, .failed:
                terminal.insert(correlationID)
            case .queued, .running, .waiting:
                break
            }
        }
        return terminal
    }

    public func loadConsole() async {
        await loadReceipts()
        await loadBrowserReceipts()
        // The complete history was just decoded, so approval resolution reuses it instead of
        // exporting and decoding the entire receipt store a second time in the same pass.
        await loadRuntimeHistory(reusingLoadedReceiptHistory: true)
        // `loadPerformance()` loads playbooks itself; a separate `loadPlaybooks()` here was a second
        // round-trip for data the next line re-reads anyway.
        await loadPerformance()
        await loadArtifacts()
        await refreshLeases()
        await loadCoordination()
        await loadRuntimeEventSubscriberHealth()
    }

    public func loadRuntimeEventSubscriberHealth() async {
        runtimeEventSubscriberHealth = await host.eventBus.subscriberHealth()
    }

    public var hasUnhealthyRuntimeEventSubscribers: Bool {
        runtimeEventSubscriberHealth.contains { !$0.isHealthy }
    }

    /// `receiptAttestationNotice` is listed first and separately from `receiptDataIssue`: the latter
    /// is about whether the history could be *read*, this is about whether it can be *believed*, and
    /// a readable history that fails its integrity check is the more serious of the two. Keeping them
    /// as distinct entries is what stops a tamper verdict being masked by an availability message.
    public var dataQualityIssues: [String] {
        [receiptAttestationNotice, receiptDataIssue, artifactDataIssue, operatorWatchlistDataIssue]
            .compactMap { $0 }
    }

    public func dismissApprovalPersistenceError() {
        approvalPersistenceError = nil
    }

    /// Registers live observation before loading the initial snapshot, then drains anything that
    /// arrived during hydration. This closes the history-to-live handoff race while retaining the
    /// event-ID de-duplication needed when an event appears in both sources.
    public func loadConsoleAndObserveEvents() async {
        let stream = await host.events()
        await loadConsole()
        await observeEvents(from: stream)
    }

    /// Subscribes to the live event stream; each event is prepended to the feed. Runs until the
    /// hosting task is cancelled. Prefer ``loadConsoleAndObserveEvents()`` when starting a screen.
    public func observeEvents() async {
        await observeEvents(from: await host.events())
    }

    private func observeEvents(from stream: AsyncStream<WorkflowEventEnvelope>) async {
        for await envelope in stream {
            guard !liveEvents.contains(where: { $0.id == envelope.id }) else { continue }
            liveEvents.insert(envelope, at: 0)
            if liveEvents.count > 100 { liveEvents.removeLast() }
            // Keyed by the request, not the envelope: the same ask can arrive on the stream after it
            // already came in from history (see `pendingApprovals(in:excluding:)`), and a request
            // already resolved must not reappear as pending on a late envelope — whether this model
            // resolved it moments ago (`resolvingApprovalIDs`) or the durable history already carries
            // the decision (`durablyResolvedApprovalIDs`).
            if case let .approvalRequired(request) = envelope.event,
               !resolvingApprovalIDs.contains(request.id),
               !durablyResolvedApprovalIDs.contains(request.id.uuidString),
               // A workflow the worklog already calls terminal has no live ask — see
               // `pendingApprovals(in:excluding:terminalCorrelationIDs:)`.
               !terminalWorkflowCorrelationIDs.contains(request.proposal.resolvedCorrelationID),
               !pendingApprovals.contains(where: { $0.id == request.id }) {
                pendingApprovals.insert(request, at: 0)
            }
            await loadRuntimeEventSubscriberHealth()
        }
    }

    #if DEBUG
    public func seedUITestFixtures() async throws {
        let correlationID = "ui-test-mission-control-receipt-route"
        let request = ApprovalRequest(
            proposal: ActionProposal(
                actor: .system,
                intent: "Review seeded receipt route",
                capability: .runPlugin,
                impact: .externalImpact,
                correlationID: correlationID
            ),
            prompt: "Review seeded receipt route?"
        )

        await host.worklogStore.record(
            WorkflowStepLog(
                correlationID: correlationID,
                toolID: "ui-test.operator",
                event: .proposed(request.proposal),
                actor: request.proposal.actor
            )
        )
        await host.worklogStore.record(
            WorkflowStepLog(
                correlationID: correlationID,
                toolID: "ui-test.operator",
                event: .decided(.escalate(approvalRequest: request)),
                actor: request.proposal.actor
            )
        )

        let approvalReceipt = try await receiptStore.append(
            ReceiptDraft(
                category: "approval",
                kind: "approval.requested",
                correlationID: correlationID,
                payload: ReceiptPayload(values: [
                    "requestedIntent": .string(request.proposal.intent),
                    "approvalID": .string(request.id.uuidString),
                    "policyReason": .string("UI test fixture requires approval context routing."),
                    "capability": .string(request.proposal.capability.rawValue)
                ]),
                actorDetail: ActorRef.system.receiptActorDetail,
                authorityDetail: ReceiptAuthorityDetail(source: "policyDefault", reason: "UI-test fixture creation is enabled by the test environment."),
                mode: host.cryptoMode.receiptMode,
                summary: "Seeded Mission Control approval receipt",
                provenance: "ui-tests",
                isSuccess: true
            )
        )
        let artifact = try await host.artifactStore.create(
            ArtifactDraft(
                type: .report,
                title: "Seeded Mission Control Artifact",
                creatorOperatorID: "ui-test.operator",
                provenance: ArtifactProvenance(actor: .system),
                relatedReceiptIDs: [approvalReceipt.id],
                content: "Deterministic artifact for Mission Control receipt route UI tests."
            )
        )
        _ = try await receiptStore.append(
            ReceiptDraft(
                category: "runtime",
                kind: "tool.executed",
                correlationID: correlationID,
                payload: ReceiptPayload(values: [
                    "requestedIntent": .string("Create a seeded route artifact"),
                    "interpretedPlan": .array([
                        .string("Create artifact"),
                        .string("Link receipt from artifact detail")
                    ]),
                    "approvalID": .string(request.id.uuidString),
                    "actionName": .string("ui-test.operator"),
                    "output": .object(["summary": .string("Seeded artifact created")]),
                    "policyReason": .string("UI test fixture uses isolated in-memory runtime state."),
                    "artifactIDs": .array([.string(artifact.id.uuidString)]),
                    "relatedArtifacts": .array([
                        .object(["id": .string(artifact.id.uuidString)])
                    ]),
                    "changeSummary": .string("Created a deterministic Mission Control artifact.")
                ]),
                actorDetail: ActorRef.system.receiptActorDetail,
                authorityDetail: ReceiptAuthorityDetail(source: "policyDefault", reason: "UI-test fixture execution is enabled by the test environment."),
                mode: host.cryptoMode.receiptMode,
                summary: "Seeded Mission Control artifact receipt",
                provenance: "ui-tests",
                isSuccess: true
            )
        )
        await loadConsole()
    }
    #endif

    // MARK: - Receipt browser (P1-301/302/303)

    public private(set) var browserReceipts: [ReceiptRecord] = [] {
        didSet {
            receiptArtifactIndexCache = nil
            invalidateAgentSessionSummaries()
        }
    }
    public var receiptSearchText: String = ""
    public var receiptScopeFilter: String?
    public var receiptOutcomeFilter: ReceiptOutcomeFilter = .all

    /// Memoized `presentation(for:)` results, keyed by receipt ID.
    ///
    /// Safe to key by ID alone because receipts are immutable, append-only, hash-chained records and a
    /// presentation is a pure function of one receipt — an entry can never go stale for a given ID. This
    /// matters because `filteredReceipts` builds a presentation per receipt to evaluate the outcome
    /// filter and search text, and `.searchable` re-runs that on every keystroke.
    ///
    /// `@ObservationIgnored` so filling the cache during a view body pass cannot invalidate that body.
    @ObservationIgnored private var presentationCache: [UUID: ReceiptPresentation] = [:]

    /// Which receipts mention which artifact, built in one pass over ``browserReceipts``.
    ///
    /// `receipts(for:)` is called per artifact by the Artifact Browser's provenance labels, and each
    /// call used to rescan every receipt and re-parse its details for artifact references — so
    /// listing N artifacts against M receipts cost N×M payload parses on every body pass. Same
    /// safety argument as `presentationCache`: receipts are immutable and append-only, so an entry
    /// can only be invalidated by the browsed set being *replaced* (see `setBrowserReceipts`).
    @ObservationIgnored private var receiptArtifactIndexCache: ReceiptArtifactIndex?

    /// A forward index from artifact ID to the receipts referencing it, plus the by-ID lookup and
    /// stable ordering needed to answer `receipts(for:)` in `browserReceipts` order.
    private struct ReceiptArtifactIndex {
        var receiptsByArtifactID: [UUID: [ReceiptRecord]] = [:]
        var receiptsByID: [UUID: ReceiptRecord] = [:]
        var positionByReceiptID: [UUID: Int] = [:]
    }

    /// Memoized ``workflowSummaries``.
    ///
    /// A pure derivation of `liveEvents` + `workflowStepLogs` that groups and sorts both in full, and
    /// the artifact provenance labels consult it per artifact. Both inputs invalidate it via `didSet`,
    /// so the cache cannot outlive the data it was derived from.
    @ObservationIgnored var workflowSummariesCache: [WorkflowSummary]?
    @ObservationIgnored var workflowSummariesByIDCache: [String: WorkflowSummary]?

    /// Memoized ``agentSessionSummaries`` and its by-ID index.
    ///
    /// The build joins every workflow summary against the whole receipt ledger, so it is quadratic in
    /// (workflows × receipts) — and the Timeline, the proposal detail, and the artifact detail all
    /// resolve *one* session out of it. The artifact detail resolves one per source workflow inside a
    /// `ForEach`, and SwiftUI builds `NavigationLink` destinations eagerly, so an uncached property
    /// rebuilt the entire set once per row.
    ///
    /// Every input is invalidated by a `didSet` on the property itself — `liveEvents` and
    /// `workflowStepLogs` (through ``invalidateWorkflowSummaries()``, since session summaries are
    /// built on top of workflow summaries), `browserReceipts`, `agentSessions`, and
    /// `pendingApprovals` — so no future writer of any of them can forget to invalidate.
    @ObservationIgnored private var agentSessionSummariesCache: [AgentSessionSummary]?
    @ObservationIgnored private var agentSessionSummariesByIDCache: [String: AgentSessionSummary]?

    private func invalidateWorkflowSummaries() {
        workflowSummariesCache = nil
        workflowSummariesByIDCache = nil
        // Session summaries are derived from `workflowSummaries`, so whatever invalidates those
        // invalidates these too.
        invalidateAgentSessionSummaries()
    }

    private func invalidateAgentSessionSummaries() {
        agentSessionSummariesCache = nil
        agentSessionSummariesByIDCache = nil
    }

    public enum ReceiptOutcomeFilter: String, CaseIterable, Identifiable, Sendable {
        case all = "All outcomes"
        case success = "Success"
        case denied = "Denied"
        case blocked = "Blocked"
        case draftOnly = "Draft only"
        case artifactProducing = "Produced artifact"
        case noOp = "No change"

        public var id: String { rawValue }

        fileprivate func includes(_ receipt: ReceiptRecord, postflight: PostflightOutcome) -> Bool {
            switch self {
            case .all:
                return true
            case .success:
                return receipt.isSuccess
            case .denied:
                return !receipt.isSuccess
            case .blocked:
                return postflight == .blocked
            case .draftOnly:
                return postflight == .draftOnly
            case .artifactProducing:
                return postflight == .artifactProducing
            case .noOp:
                return postflight == .noOp
            }
        }
    }

    public struct ReceiptDetailRow: Identifiable, Equatable, Sendable {
        public let label: String
        public let value: String

        public var id: String { "\(label)\u{1F}\(value)" }
    }

    public struct ReceiptDetailSection: Identifiable, Equatable, Sendable {
        public let title: String
        public let rows: [ReceiptDetailRow]

        public var id: String { title }
    }

    public struct ReceiptPresentation: Equatable, Sendable {
        public let outcome: PostflightOutcome
        public let searchableText: String
        /// ``searchableText`` pre-lowercased. `filteredReceipts` runs a case-insensitive `contains`
        /// over every loaded receipt on every keystroke, and `.searchable` re-runs it per character —
        /// lowercasing each receipt's full text per keystroke was the browser's dominant typing cost.
        /// Derived here so it is memoized with the rest of the presentation.
        public let searchableTextLowercased: String
        public let intentRows: [ReceiptDetailRow]
        public let planRows: [ReceiptDetailRow]
        public let approvalRows: [ReceiptDetailRow]
        public let actionRows: [ReceiptDetailRow]
        public let inferenceRows: [ReceiptDetailRow]
        public let outputRows: [ReceiptDetailRow]
        public let policyRows: [ReceiptDetailRow]
        public let failureRows: [ReceiptDetailRow]
        public let changeRows: [ReceiptDetailRow]
        public let capabilityRows: [ReceiptDetailRow]
        public let additionalRows: [ReceiptDetailRow]

        /// Non-empty categorized sections in the canonical order and titles shared with the
        /// Receipts tab (both surfaces source this from `ReceiptsCore`).
        public var sections: [ReceiptDetailSection] {
            ReceiptContentCategory.presentationOrder.compactMap { category in
                let rows = rows(for: category)
                guard !rows.isEmpty else { return nil }
                return ReceiptDetailSection(title: category.displayTitle, rows: rows)
            }
        }

        private func rows(for category: ReceiptContentCategory) -> [ReceiptDetailRow] {
            switch category {
            case .intent: return intentRows
            case .plan: return planRows
            case .approval: return approvalRows
            case .action: return actionRows
            case .inference: return inferenceRows
            case .output: return outputRows
            case .policy: return policyRows
            case .capability: return capabilityRows
            case .failure: return failureRows
            case .additional: return additionalRows
            }
        }
    }

    /// Reads through ``ReceiptStore/allRecords()`` rather than ``ReceiptStore/exportAll()``.
    ///
    /// This used to export. That meant every Mission Control open — and this runs from a bare
    /// `.task` in four views — built a signed provenance archive of the entire ledger just to list
    /// it: a payload decode, two canonical encodes, two SHA-256s and a P-256 signature verification
    /// per row, then a JSON decode of the result. At a few thousand receipts that is most of a second
    /// of blocking work on the store's executor, twice per load, to render a table.
    ///
    /// It also inherited the export's all-or-nothing integrity gate, so one unreadable row anywhere
    /// in history collapsed the whole view to the truncated 500-row fallback and told the person
    /// their history was unavailable. Listing receipts is a read; provenance is read separately,
    /// through ``ReceiptStore/ledgerAttestation()``.
    ///
    /// Dropping the export did remove the only tamper signal this surface had, and for a while
    /// nothing replaced it: the rows were listed with no attestation check while
    /// `receiptHistoryDataIssue` was set to `nil`, so the view affirmatively asserted a complete,
    /// sound history and a rewritten row rendered identically to a verified one. The attestation read
    /// below restores the signal without restoring the cost — it is one pass, not a signed archive,
    /// and crucially it does not *refuse*: a non-verified verdict annotates the history instead of
    /// hiding it.
    public func loadBrowserReceipts() async {
        do {
            setBrowserReceipts(try await receiptStore.allRecords())
            receiptHistoryScope = .complete
            receiptHistoryDataIssue = nil
            await refreshLedgerAttestation()
            markLoaded(.receiptStore)
        } catch {
            do {
                setBrowserReceipts(try await receiptStore.latest(limit: 500))
                receiptHistoryScope = .truncated
                receiptHistoryDataIssue = "Complete receipt history is unavailable. Mission Control is showing only the latest 500 receipts."
                // Deliberately not attempted on a truncated window: the verdict covers the whole
                // ledger, and the rows on screen are a subset, so a `.verified` answer here would
                // vouch for more than is being shown. Cleared rather than left stale.
                receiptLedgerAttestation = nil
                markLoaded(.receiptStore)
            } catch {
                receiptHistoryScope = .unavailable
                receiptHistoryDataIssue = "Receipt history could not be loaded. Previously loaded audit data remains visible."
                receiptLedgerAttestation = nil
            }
        }
    }

    /// Reads this device's attestation verdict for the ledger and records it for the trust surface.
    ///
    /// A failure here is *not* a receipt-history failure — the rows loaded fine. It leaves the verdict
    /// `nil`, which ``receiptAttestationNotice`` renders as "cannot vouch" rather than as a clean
    /// bill of health, so an unavailable verifier can never read as a verified ledger.
    private func refreshLedgerAttestation() async {
        receiptLedgerAttestation = try? await receiptStore.ledgerAttestation()
    }

    /// Replaces the browsed set and drops the memoized presentations with it, so the cache stays bounded
    /// by what is currently loaded instead of accumulating across reloads. Entries are never *invalid*
    /// (see `presentationCache`) — this is purely a memory bound.
    ///
    /// The artifact index, by contrast, describes the set as a whole, so a replaced set makes it
    /// *wrong* rather than merely oversized — it is invalidated from `browserReceipts`' own `didSet`
    /// so no future writer of that property can forget to.
    private func setBrowserReceipts(_ receipts: [ReceiptRecord]) {
        browserReceipts = receipts
        presentationCache.removeAll(keepingCapacity: true)
    }

    /// Distinct scopes present in the loaded receipts, for the scope filter.
    public var receiptScopes: [String] {
        Array(Set(browserReceipts.map(\.scope))).sorted()
    }

    /// Receipts after applying the search text and scope filter. (P1-301)
    public var filteredReceipts: [ReceiptRecord] {
        // The filter inputs are hoisted out of the predicate: the query was re-trimmed and
        // re-lowercased once per receipt, and the two filters were re-read through the observation
        // machinery on every element.
        let scopeFilter = receiptScopeFilter
        let outcomeFilter = receiptOutcomeFilter
        let query = receiptSearchText.trimmingCharacters(in: .whitespaces).lowercased()
        return browserReceipts.filter { receipt in
            guard scopeFilter == nil || receipt.scope == scopeFilter else { return false }
            let presentation = presentation(for: receipt)
            guard outcomeFilter.includes(receipt, postflight: presentation.outcome) else { return false }
            guard !query.isEmpty else { return true }
            return presentation.searchableTextLowercased.contains(query)
        }
    }

    /// Live events correlated to a receipt, for its detail timeline. (P1-302)
    public func events(forReceipt receipt: ReceiptRecord) -> [WorkflowEventEnvelope] {
        guard let correlationID = receipt.correlationID else { return [] }
        return liveEvents.filter { $0.correlationID == correlationID }
    }

    /// Compact postflight classification of a completed receipt. (P1-303)
    public enum PostflightOutcome: String, Sendable {
        case noOp = "No change"
        case draftOnly = "Draft only"
        case artifactProducing = "Produced artifact"
        case blocked = "Blocked"

        init(_ kind: ReceiptOutcomeKind) {
            switch kind {
            case .noOp: self = .noOp
            case .draftOnly: self = .draftOnly
            case .artifactProducing: self = .artifactProducing
            case .blocked: self = .blocked
            }
        }
    }

    public func postflight(for receipt: ReceiptRecord) -> PostflightOutcome {
        PostflightOutcome(
            ReceiptContentPresenter.outcome(
                trigger: receipt.trigger,
                isSuccess: receipt.isSuccess,
                details: receipt.details.values
            )
        )
    }

    public func presentation(for receipt: ReceiptRecord) -> ReceiptPresentation {
        if let cached = presentationCache[receipt.id] { return cached }
        let built = Self.buildPresentation(for: receipt)
        presentationCache[receipt.id] = built
        return built
    }

    /// The pure derivation behind `presentation(for:)`. Kept `static` so it cannot accidentally depend
    /// on model state that the ID-keyed cache would not notice changing.
    private static func buildPresentation(for receipt: ReceiptRecord) -> ReceiptPresentation {
        let details = receipt.details.values
        let categorized = ReceiptContentPresenter.categorizedRows(details: details)
        // Sections, ordering, outcome, change rows, and searchable text all come from the one
        // canonical `ReceiptsCore.ReceiptPresentation` the Receipts tab uses, so the two surfaces
        // stay in lockstep. Mission Control keeps its own per-category row accessors on top of it.
        let core = ReceiptsCore.ReceiptPresentation(
            summary: receipt.summary,
            trigger: receipt.trigger,
            scope: receipt.scope,
            actor: ReceiptAttributionDisplay.actorLabel(for: receipt),
            mode: receipt.mode.rawValue,
            provenance: receipt.provenance,
            correlationID: receipt.correlationID,
            isSuccess: receipt.isSuccess,
            details: details
        )

        func rows(_ category: ReceiptContentCategory) -> [ReceiptDetailRow] {
            (categorized[category] ?? []).map(Self.detailRow)
        }

        return ReceiptPresentation(
            outcome: PostflightOutcome(core.outcome),
            searchableText: core.searchableText,
            searchableTextLowercased: core.searchableText.lowercased(),
            intentRows: rows(.intent),
            planRows: rows(.plan),
            approvalRows: rows(.approval),
            actionRows: rows(.action),
            inferenceRows: rows(.inference),
            outputRows: rows(.output),
            policyRows: rows(.policy),
            failureRows: rows(.failure),
            changeRows: core.changeRows.map(Self.detailRow),
            capabilityRows: rows(.capability),
            additionalRows: rows(.additional)
        )
    }

    private static func detailRow(_ row: ReceiptContentRow) -> ReceiptDetailRow {
        ReceiptDetailRow(label: row.label, value: row.value)
    }

    // MARK: - Playbooks & routines (P1-501..504)

    public private(set) var playbooks: [Playbook] = []
    public var playbookPersistenceError: String?

    public func loadPlaybooks() async {
        do {
            playbooks = try await host.playbookStore.all()
            playbookPersistenceError = nil
        } catch {
            playbookPersistenceError = error.localizedDescription
        }
    }

    public func playbooks(inState state: PlaybookInstallState) -> [Playbook] {
        playbooks.filter { $0.installState == state }
    }

    /// Installed or paused playbooks visible in the Routine Manager, including manual playbooks that
    /// can be run on demand after install/configure. (P1-503/P1-504)
    public var routines: [Playbook] {
        playbooks.filter { playbook in
            playbook.installState == .installed || playbook.installState == .paused
        }
    }

    /// Playbook definitions exposed as first-class objects in the Artifact Browser. (P1-501)
    public var artifactBrowserPlaybooks: [Playbook] {
        playbooks
    }

    @discardableResult
    public func setPlaybookState(id: String, to state: PlaybookInstallState) async -> Bool {
        if state == .installed {
            guard await canInstallPlaybook(id: id) else {
                await loadPlaybooks()
                return false
            }
        }
        do {
            try await host.playbookStore.setInstallState(id: id, to: state)
            await loadPlaybooks()
            return playbookPersistenceError == nil
        } catch {
            playbookPersistenceError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    public func saveUserPlaybook(_ playbook: Playbook) async -> Bool {
        do {
            try await host.playbookStore.upsert(playbook)
            await loadPlaybooks()
            return playbookPersistenceError == nil
        } catch {
            playbookPersistenceError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    public func installPlaybook(id: String) async -> Bool {
        await setPlaybookState(id: id, to: .installed)
    }

    private func canInstallPlaybook(id: String) async -> Bool {
        do {
            guard let playbook = try await host.playbookStore.playbook(id: id) else { return false }
            return playbook.supportsV0ReadPrepareOnly
        } catch {
            playbookPersistenceError = error.localizedDescription
            return false
        }
    }

    // MARK: - Scheduling & performance (P1-601..604)

    public private(set) var performanceHealth: [PlaybookHealth] = []
    public private(set) var recentExecutions: [ExecutionRecord] = []

    public func loadPerformance() async {
        let recordedHealth = await host.performanceStore.allHealth()
        await loadPlaybooks()
        let installedIDs = playbooks
            .filter { $0.installState == .installed }
            .map(\.id)
        let healthByID = Dictionary(uniqueKeysWithValues: recordedHealth.map { ($0.playbookID, $0) })
        performanceHealth = Set(recordedHealth.map(\.playbookID) + installedIDs)
            .map { healthByID[$0] ?? PlaybookHealth(playbookID: $0, events: []) }
            .sorted { lhs, rhs in
                if lhs.classification != rhs.classification {
                    return Self.healthSortPriority(lhs.classification) < Self.healthSortPriority(rhs.classification)
                }
                return lhs.playbookID < rhs.playbookID
            }
        recentExecutions = await host.schedulingEngine.executionRecords()
        // The dashboard links each run to its receipt; make sure the receipt browser is populated
        // when the Performance tab is opened directly (not only via the full console load). (P1-604)
        if browserReceipts.isEmpty {
            await loadBrowserReceipts()
        }
    }

    /// Per-operator report cards (P2-EVAL): run health joined with graded runs.
    public private(set) var reportCards: [OperatorReportCard] = []
    public private(set) var improvementRecommendations: [ImprovementRecommendation] = []

    /// Builds a card per playbook that has either run history or a graded run.
    ///
    /// Grades are grouped by the playbook their workflow belongs to, resolved through the execution
    /// records rather than stored on the result itself — a grade is *about a workflow*, and which
    /// operator owned that workflow is already recorded. Duplicating the playbook id onto the result
    /// would create a second source of truth free to disagree with the run history.
    public func loadReportCards() async {
        let health = await host.performanceStore.allHealth()
        let results = await host.evalResultStore.allResults()
        let records = await host.schedulingEngine.executionRecords()

        var playbookByCorrelation: [String: String] = [:]
        for record in records {
            playbookByCorrelation[record.correlationID] = record.playbookID
        }
        let resultsByPlaybook = Dictionary(grouping: results) {
            $0.playbookID ?? playbookByCorrelation[$0.correlationID] ?? ""
        }

        // Union, not intersection: an operator with runs but no declared criteria still deserves a
        // card (showing it as ungraded), and a graded run whose execution record has aged out of the
        // window must not silently drop its grades.
        let ids = Set(health.map(\.playbookID))
            .union(resultsByPlaybook.keys.filter { !$0.isEmpty })

        reportCards = ids.map { id in
            OperatorReportCard(
                playbookID: id,
                health: health.first { $0.playbookID == id }
                    ?? PlaybookHealth(playbookID: id, events: []),
                evalResults: resultsByPlaybook[id] ?? []
            )
        }
        .sorted { $0.playbookID < $1.playbookID }

        await host.refreshImprovementRecommendations(from: reportCards)
        improvementRecommendations = await host.improvementRecommendationStore.allRecommendations()
    }

    public func reviewRecommendation(_ recommendation: ImprovementRecommendation, accept: Bool) async {
        await host.reviewImprovementRecommendation(
            id: recommendation.id,
            accept: accept,
            reviewedBy: "missionControl.human"
        )
        improvementRecommendations = await host.improvementRecommendationStore.allRecommendations()
    }

    public func markRecommendationApplied(_ recommendation: ImprovementRecommendation) async {
        await host.markImprovementRecommendationApplied(
            id: recommendation.id,
            reviewedBy: "missionControl.human"
        )
        improvementRecommendations = await host.improvementRecommendationStore.allRecommendations()
    }

    /// Unsuccessful runs, newest first — the dashboard's failure history surface (P1-604).
    ///
    /// Blocked runs belong here alongside execution failures because they contribute to the health
    /// classification and policy-block rate. Omitting them made a flaky routine's summary disagree
    /// with the history a person could inspect.
    public var unsuccessfulExecutions: [ExecutionRecord] {
        recentExecutions.filter { $0.outcome == .failed || $0.outcome == .blocked }
    }

    /// The receipt written for a run, if any (``RuntimeHost/runRoutine`` correlates them by the run's id).
    /// Lets the dashboard deep-link a run straight to its full receipt. (P1-604)
    public func receipt(forExecution record: ExecutionRecord) -> ReceiptRecord? {
        browserReceipts.first { $0.correlationID == record.correlationID }
    }

    private static func healthSortPriority(_ classification: PlaybookHealthClassification) -> Int {
        switch classification {
        case .flaky: 0
        case .needsAttention: 1
        case .insufficientData: 2
        case .stable: 3
        }
    }

    /// Runs a routine on demand and refreshes the surfaces its run affects. A tap here is the person
    /// using the app, so the run is attributed to `.human` rather than the scheduling routine (P0.5-602).
    public func runRoutine(id: String) async {
        _ = await host.runRoutine(id: id, trigger: .manual, actor: .human)
        await loadPerformance()
        await loadReceipts()
    }

    public func latestExecution(for playbookID: String) -> ExecutionRecord? {
        recentExecutions
            .filter { $0.playbookID == playbookID }
            .max { $0.startedAt < $1.startedAt }
    }

    public func lastRunText(for playbook: Playbook) -> String {
        guard let record = latestExecution(for: playbook.id) else { return "Last run: not yet run" }
        return "Last run: \(record.startedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    public func nextRunText(for playbook: Playbook) -> String {
        switch playbook.trigger {
        case .manual:
            return "Next run: manual only"
        case let .schedule(interval):
            guard let record = latestExecution(for: playbook.id) else { return "Next run: when background refresh is due" }
            let date = record.startedAt.addingTimeInterval(interval)
            return "Next run: \(date.formatted(date: .abbreviated, time: .shortened))"
        case .event(.artifactStale):
            return "Next run: when an artifact stale signal is available"
        case .event(.approvalPendingTooLong):
            return "Next run: when an approval age signal is available"
        case let .maintenance(interval):
            guard let record = latestExecution(for: playbook.id) else { return "Next run: during the next maintenance refresh" }
            let date = record.startedAt.addingTimeInterval(interval)
            return "Next run: \(date.formatted(date: .abbreviated, time: .shortened))"
        }
    }

    // MARK: - Operators (P1-701..703) and artifacts (P1-402)

    public private(set) var operatorTools: [ToolDefinition] = []
    public internal(set) var operatorOutcomes: [String: String] = [:]
    /// Operator inputs bound to the operators surface: a research/watch query, the watched account,
    /// and the identity to scope a review to. (P1-701..703)
    public var operatorQueryInput: String = ""
    public var operatorWatchChainInput: String = "eth-mainnet"
    public var operatorWatchAddressInput: String = ""
    public private(set) var operatorWatchlist: [WatchTarget] = []

    public func addOperatorWatchTarget() {
        let address = operatorWatchAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return }
        let target = WatchTarget(chain: operatorWatchChainInput, address: address)
        guard !operatorWatchlist.contains(where: {
            $0.chain.caseInsensitiveCompare(target.chain) == .orderedSame
                && $0.address.caseInsensitiveCompare(target.address) == .orderedSame
        }) else { return }
        let previousWatchlist = operatorWatchlist
        operatorWatchlist.append(target)
        do {
            try operatorWatchlistStore.save(operatorWatchlist, identityID: activeIdentityID)
            operatorWatchlistDataIssue = nil
            operatorWatchAddressInput = ""
        } catch {
            operatorWatchlist = previousWatchlist
            operatorWatchlistDataIssue = error.localizedDescription
        }
    }

    public func removeOperatorWatchTargets(at offsets: IndexSet) {
        let previousWatchlist = operatorWatchlist
        for index in offsets.sorted(by: >) {
            operatorWatchlist.remove(at: index)
        }
        do {
            try operatorWatchlistStore.save(operatorWatchlist, identityID: activeIdentityID)
            operatorWatchlistDataIssue = nil
        } catch {
            operatorWatchlist = previousWatchlist
            operatorWatchlistDataIssue = error.localizedDescription
        }
    }
    public private(set) var artifacts: [Artifact] = []
    private var artifactLookupByID: [UUID: Artifact] = [:]
    public private(set) var artifactVersionsByGroup: [UUID: [Artifact]] = [:]
    public private(set) var artifactExportPreviews: [UUID: String] = [:]
    public private(set) var artifactBrowserLoadedFullHistory = false
    public var artifactTypeFilter: ArtifactType?
    public var artifactRecencyFilter: ArtifactRecencyFilter = .all
    public var artifactWorkflowFilter: String?
    public var artifactAccountFilter: String?
    public private(set) var workflowStepLogs: [WorkflowStepLog] = [] {
        didSet { invalidateWorkflowSummaries() }
    }
    public private(set) var worklogStoreHealth = WorklogStoreHealth()
    public private(set) var sharedSessions: [SharedSession] = []
    public private(set) var rituals: [RitualDefinition] = []
    public private(set) var ritualLastRuns: [String: Date] = [:]
    public private(set) var ritualRunReports: [String: RuntimeHost.RitualRunReport] = [:]
    public private(set) var ritualAvailability: [String: RuntimeHost.RitualAvailability] = [:]

    public func loadOperators() async {
        operatorTools = await host.registeredTools().sorted { $0.title < $1.title }
    }

    public func canRunOperator(toolID: String) -> Bool {
        switch OperatorCatalog.spec(for: toolID)?.kind {
        case .research:
            return !operatorQueryInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .identityReview:
            return activeIdentityID != nil
        case .onChainWatch:
            return !operatorWatchlist.isEmpty
                || !operatorWatchAddressInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return true
        }
    }

    public func runOperator(toolID: String) async {
        let outcome = await host.runOperator(toolID: toolID, request: operatorRequest(for: toolID))
        operatorOutcomes[toolID] = Self.describe(outcome)
        // Escalation requires an explicit positive count. `!= "0"` also passed when the field was
        // absent or unparseable, so a run that reported no prepared actions — or reported nothing at
        // all — could still put a prepared action in the Approval Inbox. For a governance escalation
        // the absence of evidence has to mean "don't", not "do".
        if toolID == OperatorCatalog.onChainWatchID,
           case let .executed(artifact) = outcome,
           let preparedActionCount = artifact.outputFields["preparedActionCount"].flatMap(Int.init),
           preparedActionCount > 0 {
            // The target comes from the artifact that prepared it, not from this model's inputs.
            // Only the *count* used to cross the boundary, so this escalated against
            // `operatorWatchlist.first` — with a quiet account listed first and an active one
            // second, the Approval Inbox showed a high-risk prepared action for an address the
            // report had found nothing for, while the artifact a human would open to check named a
            // different one. An approval and its evidence must not disagree about the account.
            await escalateWatchFindingFromRun(
                chain: artifact.outputFields["preparedActionChain"],
                address: artifact.outputFields["preparedActionAddress"]
            )
        }
        await refreshAfterOperatorRun()
    }

    /// Manual escalation from the operator surface — the user pressing the button, with no run
    /// behind it. Falls back to the configured watchlist or the draft input, and doing nothing when
    /// neither names a target is the correct answer here: there is nothing to escalate.
    public func escalateFirstWatchFinding() async {
        let draftAddress = operatorWatchAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = operatorWatchlist.first ?? (draftAddress.isEmpty
            ? nil
            : WatchTarget(chain: operatorWatchChainInput, address: draftAddress))
        guard let target else { return }
        await escalate(chain: target.chain, address: target.address)
    }

    /// Run-driven escalation: the account comes from the artifact that prepared the action, and
    /// **there is no fallback to UI state**.
    ///
    /// Separated from the manual path because the two want opposite behaviour on a missing target.
    /// A watch run that reported `preparedActionCount > 0` and then named no account is an
    /// inconsistency between what the run *counted* and what it can *act on* — the third such
    /// mismatch found in this path — and guessing from `operatorWatchlist.first` is exactly the
    /// substitution that put a high-risk prepared action in front of the user for an address the
    /// report had found nothing for. Surfacing it as a failed outcome keeps the count and the act
    /// answerable to each other; silence would let them drift again.
    private func escalateWatchFindingFromRun(chain: String?, address: String?) async {
        guard let chain, !chain.isEmpty, let address, !address.isEmpty else {
            operatorOutcomes[OperatorCatalog.preparedActionID] =
                "Not escalated: the run reported a prepared action but named no account."
            return
        }
        await escalate(chain: chain, address: address)
    }

    private func escalate(chain: String, address: String) async {
        let rationale = operatorQueryInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let outcome = await host.runPreparedAction(
            chain: chain,
            address: address,
            rationale: rationale.isEmpty ? "Review activity found by On-Chain Watch" : rationale
        )
        operatorOutcomes[OperatorCatalog.preparedActionID] = Self.describe(outcome)
    }

    /// P1-702 — Escalate a prepared, confirm-first action to the Approval Inbox. Blocked in Observe,
    /// escalated for human approval in Assist; never executes autonomously.
    public func escalatePreparedAction(chain: String, address: String, rationale: String) async {
        let outcome = await host.runPreparedAction(chain: chain, address: address, rationale: rationale)
        operatorOutcomes[OperatorCatalog.preparedActionID] = Self.describe(outcome)
        await refreshAfterOperatorRun()
    }

    /// Builds the scoped request for an operator from the current, identity-scoped inputs.
    private func operatorRequest(for toolID: String) -> OperatorRequest {
        let query = operatorQueryInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = operatorWatchAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        switch OperatorCatalog.spec(for: toolID)?.kind {
        case .research:
            return OperatorRequest(query: query.isEmpty ? nil : query, playbookID: "research.brief")
        case .onChainWatch:
            let draftTarget = address.isEmpty ? [] : [WatchTarget(chain: operatorWatchChainInput, address: address)]
            let watchlist = operatorWatchlist.isEmpty ? draftTarget : operatorWatchlist
            return OperatorRequest(
                query: query.isEmpty ? nil : query,
                watchlist: watchlist,
                playbookID: "onchain.watch"
            )
        case .identityReview:
            return OperatorRequest(identityID: activeIdentityID)
        default:
            return OperatorRequest()
        }
    }

    private func refreshAfterOperatorRun() async {
        await loadArtifacts()
        await loadReceipts()
        await loadBrowserReceipts()
        // Complete history just loaded — reuse it rather than re-exporting the store.
        await loadRuntimeHistory(reusingLoadedReceiptHistory: true)
    }

    public func loadArtifacts() async {
        do {
            let exportedArtifacts = try await decodeAllArtifacts()
            artifacts = Self.latestArtifacts(from: exportedArtifacts)
            artifactLookupByID = Self.artifactLookup(from: exportedArtifacts)
            artifactBrowserLoadedFullHistory = true
            artifactBrowserDataIssue = nil
            markLoaded(.artifactStore)
            return
        } catch {
            do {
                artifacts = try await host.artifactStore.latest(limit: 100)
                artifactLookupByID = Self.artifactLookup(from: artifacts)
                artifactBrowserLoadedFullHistory = false
                artifactBrowserDataIssue = "Complete artifact history is unavailable. Mission Control is showing only the latest 100 artifacts."
                markLoaded(.artifactStore)
            } catch {
                artifactBrowserLoadedFullHistory = false
                artifactBrowserDataIssue = "Artifacts could not be loaded. Previously loaded artifact data remains visible."
            }
        }
    }

    public func loadArtifactVersions(for artifact: Artifact) async {
        do {
            let versions = try await host.artifactStore.versions(ofGroup: artifact.groupID)
            artifactVersionsByGroup[artifact.groupID] = versions
            for version in versions {
                artifactLookupByID[version.id] = version
            }
            artifactVersionDataIssue = nil
        } catch {
            artifactVersionDataIssue = "Artifact version history could not be loaded. Previously loaded versions remain visible."
        }
    }

    /// Decodes the full artifact export off the main actor.
    ///
    /// The model is `@MainActor`, so decoding an entire export inline blocked the main thread for the
    /// duration — and the console re-decodes it on every load, on every artifact/receipt detail
    /// entry, and after every artifact lifecycle change. The decode is a pure function of `Data`, so
    /// it belongs off the main thread. Receipts no longer need the equivalent: they are read through
    /// `allRecords()`, which returns rows directly rather than an archive to be parsed.
    private func decodeAllArtifacts() async throws -> [Artifact] {
        let data = try await host.artifactStore.exportAll()
        return try await Task.detached(priority: .userInitiated) {
            try JSONDecoder().decode([Artifact].self, from: data)
        }.value
    }

    private static func latestArtifacts(from artifacts: [Artifact]) -> [Artifact] {
        Dictionary(grouping: artifacts, by: \.groupID)
            .compactMap { $0.value.max { lhs, rhs in
                if lhs.version == rhs.version {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.version < rhs.version
            } }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.version > rhs.version
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    private static func artifactLookup(from artifacts: [Artifact]) -> [UUID: Artifact] {
        Dictionary(uniqueKeysWithValues: artifacts.map { ($0.id, $0) })
    }

    public func prepareExportPreview(for artifact: Artifact) {
        artifactExportPreviews[artifact.id] = exportPayload(for: artifact)
    }

    public func exportPreview(for artifact: Artifact) -> String {
        artifactExportPreviews[artifact.id] ?? exportPayload(for: artifact)
    }

    public func approveArtifact(_ artifact: Artifact) async throws -> Artifact {
        try await updateArtifactLifecycle(
            artifact,
            state: .approved,
            destination: artifact.destination,
            exportFormat: artifact.exportFormat,
            receiptKind: "artifact.approved",
            receiptSummary: "Approved artifact: \(artifact.title)",
            countsAsIntervention: true
        )
    }

    public func markArtifactExported(_ artifact: Artifact, destination: String = "Share sheet") async throws -> Artifact {
        try await updateArtifactLifecycle(
            artifact,
            state: .exported,
            destination: destination,
            exportFormat: exportFormatLabel(for: artifact),
            receiptKind: "artifact.exported",
            receiptSummary: "Exported artifact: \(artifact.title)"
        )
    }

    public func markArtifactSuperseded(_ artifact: Artifact) async throws -> Artifact {
        try await updateArtifactLifecycle(
            artifact,
            state: .superseded,
            destination: artifact.destination,
            exportFormat: artifact.exportFormat,
            receiptKind: "artifact.superseded",
            receiptSummary: "Superseded artifact: \(artifact.title)",
            countsAsIntervention: true
        )
    }

    @discardableResult
    private func updateArtifactLifecycle(
        _ artifact: Artifact,
        state: ArtifactApprovalState,
        destination: String?,
        exportFormat: String?,
        receiptKind: String,
        receiptSummary: String,
        countsAsIntervention: Bool = false
    ) async throws -> Artifact {
        let updatedArtifact = artifact.with(
            approvalState: state,
            destination: destination,
            exportFormat: exportFormat
        )
        try await host.artifactStore.updateLifecycle(
            id: artifact.id,
            to: state,
            destination: destination,
            exportFormat: exportFormat
        )
        let draft = ReceiptDraft(
            category: "artifact",
            kind: receiptKind,
            // Every lifecycle decision on one artifact lineage — approved, exported, superseded —
            // is filed under the lineage's own key, so the sequence of interventions on an artifact
            // is retrievable as one workflow (P0.5-602) instead of as unrelated receipts.
            correlationID: "artifact.\(artifact.groupID.uuidString)",
            payload: ReceiptPayload(values: [
                "artifactID": .string(artifact.id.uuidString),
                "artifactGroupID": .string(artifact.groupID.uuidString),
                "artifactTitle": .string(artifact.title),
                "artifactType": .string(artifact.type.rawValue),
                "artifactVersion": .number(Double(artifact.version)),
                "approvalState": .string(state.rawValue),
                "destination": .string(destination ?? "Not exported"),
                "exportFormat": .string(exportFormat ?? exportFormatLabel(for: artifact)),
                "origin": .string("auralis://mission-control/artifacts/\(artifact.id.uuidString)")
            ]),
            actorDetail: ActorRef.human.receiptActorDetail,
            authorityDetail: ReceiptAuthorityDetail(source: "humanApproval", reason: "The person explicitly approved or corrected this artifact."),
            summary: receiptSummary,
            provenance: "mission-control",
            isSuccess: true
        )
        _ = try await receiptStore.append(draft)
        // A human approving or correcting a routine's output is an intervention on the run that
        // produced it — attribute it so the playbook's intervention rate reflects reality (P1-603).
        if countsAsIntervention, let playbookID = artifact.creatorPlaybookID, !playbookID.isEmpty {
            await host.recordIntervention(forArtifactID: artifact.id)
        }
        await loadArtifacts()
        await loadArtifactVersions(for: artifact)
        await loadReceipts()
        await loadBrowserReceipts()
        await loadPerformance()
        prepareExportPreview(for: updatedArtifact)
        return updatedArtifact
    }

    public func versions(for artifact: Artifact) -> [Artifact] {
        artifactVersionsByGroup[artifact.groupID] ?? []
    }

    public func artifact(id: UUID) -> Artifact? {
        artifactLookupByID[id] ?? artifacts.first { $0.id == id }
    }

    public func artifactIDs(from receipt: ReceiptRecord) -> [UUID] {
        ReceiptContentPresenter.artifactIDs(in: receipt.details.values)
    }

    public func artifactID(from receipt: ReceiptRecord) -> UUID? {
        artifactIDs(from: receipt).first
    }

    public func receipts(for artifact: Artifact) -> [ReceiptRecord] {
        let index = receiptArtifactIndex()
        // Two legs, same as the original scan: receipts that *name* this artifact in their payload,
        // and receipts the artifact itself points back at. Merged, de-duplicated, and returned in
        // `browserReceipts` order so callers that take `.first` still see the newest receipt first.
        var seen = Set<UUID>()
        var merged: [ReceiptRecord] = []
        for receipt in index.receiptsByArtifactID[artifact.id] ?? [] where seen.insert(receipt.id).inserted {
            merged.append(receipt)
        }
        for receiptID in artifact.relatedReceiptIDs {
            guard let receipt = index.receiptsByID[receiptID], seen.insert(receiptID).inserted else { continue }
            merged.append(receipt)
        }
        guard merged.count > 1 else { return merged }
        return merged.sorted { lhs, rhs in
            (index.positionByReceiptID[lhs.id] ?? .max) < (index.positionByReceiptID[rhs.id] ?? .max)
        }
    }

    private func receiptArtifactIndex() -> ReceiptArtifactIndex {
        if let cached = receiptArtifactIndexCache { return cached }
        var index = ReceiptArtifactIndex()
        index.receiptsByID.reserveCapacity(browserReceipts.count)
        index.positionByReceiptID.reserveCapacity(browserReceipts.count)
        for (position, receipt) in browserReceipts.enumerated() {
            index.receiptsByID[receipt.id] = receipt
            index.positionByReceiptID[receipt.id] = position
            for artifactID in artifactIDs(from: receipt) {
                index.receiptsByArtifactID[artifactID, default: []].append(receipt)
            }
        }
        receiptArtifactIndexCache = index
        return index
    }

    public enum ArtifactRecencyFilter: String, CaseIterable, Identifiable, Sendable {
        case all = "Any time"
        case today = "Today"
        case last7Days = "Last 7 days"
        case last30Days = "Last 30 days"

        public var id: String { rawValue }

        func includes(_ date: Date, referenceDate: Date) -> Bool {
            switch self {
            case .all:
                return true
            case .today:
                return Calendar.current.isDate(date, inSameDayAs: referenceDate)
            case .last7Days:
                return date >= referenceDate.addingTimeInterval(-7 * 24 * 60 * 60)
            case .last30Days:
                return date >= referenceDate.addingTimeInterval(-30 * 24 * 60 * 60)
            }
        }
    }

    public struct ArtifactCardPresentation: Equatable, Sendable {
        public let title: String
        public let metadata: String
        public let provenance: String
        public let status: String
    }

    public var artifactWorkflows: [String] {
        Array(Set(artifacts.map(artifactWorkflowLabel))).sorted()
    }

    public var artifactAccounts: [String] {
        Array(Set(artifacts.map(artifactAccountLabel))).sorted()
    }

    public var filteredArtifacts: [Artifact] {
        artifacts.filter { artifact in
            let matchesType = artifactTypeFilter == nil || artifact.type == artifactTypeFilter
            let matchesRecency = artifactRecencyFilter.includes(artifact.createdAt, referenceDate: referenceDate)
            let matchesWorkflow = artifactWorkflowFilter == nil || artifactWorkflowLabel(for: artifact) == artifactWorkflowFilter
            let matchesAccount = artifactAccountFilter == nil || artifactAccountLabel(for: artifact) == artifactAccountFilter
            return matchesType && matchesRecency && matchesWorkflow && matchesAccount
        }
        .sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.version > rhs.version
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    public func cardPresentation(for artifact: Artifact) -> ArtifactCardPresentation {
        ArtifactCardPresentation(
            title: artifact.title,
            metadata: "\(artifact.type.rawValue) • v\(artifact.version) • \(relativeText(artifact.createdAt))",
            provenance: "By \(artifactCreatorLabel(for: artifact)) • \(artifactWorkflowLabel(for: artifact))",
            status: artifact.approvalState.rawValue
        )
    }

    public func artifactCreatorLabel(for artifact: Artifact) -> String {
        if let displayName = artifact.provenance.actor.displayName, !displayName.isEmpty {
            return displayName
        }
        if let operatorID = artifact.creatorOperatorID, !operatorID.isEmpty {
            return operatorID
        }
        if let playbookID = artifact.creatorPlaybookID, !playbookID.isEmpty {
            return playbookID
        }
        if let identifier = artifact.provenance.actor.identifier, !identifier.isEmpty {
            return identifier
        }
        return artifact.provenance.actor.kind.displayTitle
    }

    public func artifactWorkflowLabel(for artifact: Artifact) -> String {
        if let playbookID = artifact.creatorPlaybookID, !playbookID.isEmpty {
            return playbooks.first { $0.id == playbookID }?.name ?? playbookID
        }
        if let correlationID = artifactSourceCorrelationIDs(for: artifact).first,
           let summary = workflowSummariesByID[correlationID] {
            return summary.playbook
        }
        if let operatorID = artifact.creatorOperatorID, !operatorID.isEmpty {
            return operatorID
        }
        return MissionControlFacets.adHocPlaybook
    }

    public func artifactAccountLabel(for artifact: Artifact) -> String {
        let summariesByID = workflowSummariesByID
        for correlationID in artifactSourceCorrelationIDs(for: artifact) {
            if let summary = summariesByID[correlationID],
               summary.account != MissionControlFacets.noAccount {
                return summary.account
            }
        }
        for receipt in receipts(for: artifact) {
            if let account = Self.accountLabel(in: receipt.details.values) {
                return account
            }
        }
        return MissionControlFacets.noAccount
    }

    public func artifactSourceCorrelationIDs(for artifact: Artifact) -> [String] {
        let values = receipts(for: artifact).compactMap(\.correlationID)
        return Self.unique(values)
    }

    public func approvalReceipts(for artifact: Artifact) -> [ReceiptRecord] {
        receipts(for: artifact).filter { receipt in
            receipt.scope.lowercased().contains("approval") ||
            receipt.trigger.lowercased().contains("approval") ||
            receipt.details.values.keys.contains { $0.lowercased().contains("approval") }
        }
    }

    public func playbook(for artifact: Artifact) -> Playbook? {
        guard let playbookID = artifact.creatorPlaybookID else { return nil }
        return playbooks.first { $0.id == playbookID }
    }

    /// The live playbook for `id` from the last load. Detail surfaces re-read through this rather than
    /// rendering the value they were constructed with, so an install-state change made *on* the detail
    /// (pause/resume/enable) is reflected there immediately instead of only after navigating back.
    public func playbook(id: String) -> Playbook? {
        playbooks.first { $0.id == id }
    }

    public func exportPayload(for artifact: Artifact) -> String {
        let origin = "auralis://mission-control/artifacts/\(artifact.id.uuidString)"
        let provenance = exportProvenanceLines(for: artifact, origin: origin).joined(separator: "\n")
        switch artifact.type {
        case .doc, .brief, .report, .planChecklist:
            return """
            \(artifact.content)

            ---
            Auralis Artifact Provenance
            \(provenance)
            """
        case .jsonExport:
            let envelope = ArtifactExportEnvelope(
                origin: origin,
                artifact: artifact,
                relatedReceiptIDs: artifact.relatedReceiptIDs
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(envelope),
                  let text = String(data: data, encoding: .utf8) else {
                return provenance
            }
            return text
        case .codeFile:
            return """
            /*
            Auralis Artifact Provenance
            \(provenance)
            */

            \(artifact.content)
            """
        }
    }

    public func exportFormatLabel(for artifact: Artifact) -> String {
        artifact.exportFormat ?? defaultExportFormat(for: artifact.type)
    }

    private func defaultExportFormat(for type: ArtifactType) -> String {
        switch type {
        case .doc, .brief, .report, .planChecklist:
            return "markdown"
        case .jsonExport:
            return "json"
        case .codeFile:
            return "source"
        }
    }

    private func exportProvenanceLines(for artifact: Artifact, origin: String) -> [String] {
        var lines = [
            "Origin: \(origin)",
            "Artifact ID: \(artifact.id.uuidString)",
            "Group ID: \(artifact.groupID.uuidString)",
            "Version: \(artifact.version)",
            "Type: \(artifact.type.rawValue)",
            "State: \(artifact.approvalState.rawValue)",
            "Created: \(artifact.createdAt.formatted())",
            "Creator: \(artifactCreatorLabel(for: artifact))",
            "Workflow: \(artifactWorkflowLabel(for: artifact))",
            "Account: \(artifactAccountLabel(for: artifact))"
        ]
        if let destination = artifact.destination {
            lines.append("Destination: \(destination)")
        }
        lines.append("Export format: \(exportFormatLabel(for: artifact))")
        if !artifact.relatedReceiptIDs.isEmpty {
            lines.append("Related receipts: \(artifact.relatedReceiptIDs.map(\.uuidString).joined(separator: ", "))")
        }
        if let inference = artifact.provenance.inference ?? artifact.provenance.actor.inference {
            lines.append("Inference: \(inference.locality.rawValue)")
            if let provider = inference.provider { lines.append("Provider: \(provider)") }
            if let modelClass = inference.modelClass { lines.append("Model class: \(modelClass)") }
        }
        return lines
    }

    private struct ArtifactExportEnvelope: Codable {
        let origin: String
        let artifact: Artifact
        let relatedReceiptIDs: [UUID]
    }

    private static func accountLabel(in values: [String: ReceiptJSONValue]) -> String? {
        let keys = ["account", "ens", "address", "accountAddress", "wallet", "walletAddress"]
        for key in keys {
            if case let .string(value)? = values[key], !value.isEmpty {
                return value
            }
        }
        for (key, value) in values {
            guard key.lowercased().contains("account") || key.lowercased().contains("wallet") else { continue }
            if case let .string(label) = value, !label.isEmpty {
                return label
            }
        }
        return nil
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }

    static func describe(_ outcome: ToolCallOutcome) -> String {
        switch outcome {
        case .executed: return "Executed — artifact produced"
        case let .blocked(reason): return "Blocked: \(reason)"
        case let .needsApproval(request): return "Needs approval: \(request.prompt)"
        case let .needsRevision(instructions): return "Revise: \(instructions)"
        case let .failed(reason): return "Failed: \(reason)"
        case let .evidenceIncomplete(_, failures): return "Governance evidence incomplete: \(failures.joined(separator: "; "))"
        }
    }

    // MARK: - Context, sessions, and rituals

    public struct AgentSessionSummary: Identifiable, Equatable, Sendable {
        public let id: String
        public let goal: String
        public let state: WorkflowState
        public let capabilities: [String]
        public let receiptCount: Int
        public let approvalCount: Int
        public let artifactCount: Int
        public let modelCount: Int
        public let estimatedCost: Double
        public let startedAt: Date?
        public let endedAt: Date?
        /// Model/token/runtime attribution for the session, aggregated from its receipts. (P1-101)
        public let inference: InferenceSnapshot
        public let memoryTouched: [String]
        public let executionUpdates: [String]

        /// The estimated cost, or "Not recorded" when no model telemetry was captured for the session.
        /// A raw "$0.0000" would read as a fact ("this was free") on the simulator-fallback path where
        /// inference didn't run; this matches the "Not recorded" wording of the token/model fields so an
        /// absent cost never masquerades as a confirmed zero. (P1-AGENT-101 trust surface)
        public var estimatedCostLabel: String {
            inference.isEmpty ? "Not recorded" : String(format: "$%.4f", estimatedCost)
        }
    }

    /// The model, inference locality, and token usage attributed to a set of receipts. Derived from
    /// the telemetry `OperatorExecutor` stamps onto receipt details, so it reflects what actually ran
    /// rather than a declared intent. Powers the timeline's "local vs remote / token / model" surface
    /// (P1-101) and the Context Bundle Inspector's model fields (P1-102).
    public struct InferenceSnapshot: Equatable, Sendable {
        public var provider: String?
        public var modelClass: String?
        public var locality: String?
        public var promptTokens: Int
        public var completionTokens: Int
        public var durationSeconds: Double
        /// Number of model invocations behind this snapshot (P1-AI-103 "model hops"). Counts every
        /// handoff to an inference backend across the session's receipts, so a multi-agent chain reads
        /// as N hops rather than a single opaque "ran a model".
        public var modelHops: Int
        public var privacyImpact: String?
        /// True when any receipt in scope reported its token counts as approximated (e.g. on-device
        /// runs that estimate from content length). Drives the "(estimated)" label. (P1-AGENT-101)
        public var tokensEstimated: Bool
        public var lastRecordedAt: Date?

        public init(
            provider: String? = nil,
            modelClass: String? = nil,
            locality: String? = nil,
            promptTokens: Int = 0,
            completionTokens: Int = 0,
            durationSeconds: Double = 0,
            modelHops: Int = 0,
            privacyImpact: String? = nil,
            tokensEstimated: Bool = false,
            lastRecordedAt: Date? = nil
        ) {
            self.provider = provider
            self.modelClass = modelClass
            self.locality = locality
            self.promptTokens = promptTokens
            self.completionTokens = completionTokens
            self.durationSeconds = durationSeconds
            self.modelHops = modelHops
            self.privacyImpact = privacyImpact
            self.tokensEstimated = tokensEstimated
            self.lastRecordedAt = lastRecordedAt
        }

        public var totalTokens: Int { promptTokens + completionTokens }

        /// True when no receipt in scope carried model telemetry — the fields should read "Not recorded".
        public var isEmpty: Bool {
            provider == nil && modelClass == nil && locality == nil && totalTokens == 0
        }

        /// "Provider · model-class", falling back to whichever half is present.
        public var modelLabel: String {
            switch (provider, modelClass) {
            case let (provider?, modelClass?): return "\(provider) · \(modelClass)"
            case let (provider?, nil): return provider
            case let (nil, modelClass?): return modelClass
            case (nil, nil): return "Not recorded"
            }
        }

        /// Plain-language locality: on-device vs cloud, the privacy/sovereignty signal. (P1-101/102)
        public var localityLabel: String {
            switch locality {
            case InferenceLocality.local.rawValue: return "On-device (local)"
            case InferenceLocality.remote.rawValue: return "Cloud (remote)"
            case let value?: return value
            case nil: return "Not recorded"
            }
        }

        public var privacyImpactLabel: String {
            if let privacyImpact, !privacyImpact.isEmpty { return privacyImpact }
            switch locality {
            case InferenceLocality.local.rawValue: return InferenceLocality.local.privacyImpact
            case InferenceLocality.remote.rawValue: return InferenceLocality.remote.privacyImpact
            default: return "Not recorded"
            }
        }

        public var durationLabel: String {
            guard durationSeconds > 0 else { return "Not recorded" }
            return String(format: "%.2fs", durationSeconds)
        }

        public var tokensLabel: String {
            guard totalTokens > 0 else { return "Not recorded" }
            let base = "\(totalTokens) total • \(promptTokens) prompt / \(completionTokens) completion"
            return tokensEstimated ? "~\(base) (estimated)" : base
        }

        /// Model invocations for the session, pluralized. Reads "Not recorded" when nothing ran so it
        /// matches the rest of the snapshot's absent-telemetry wording rather than asserting "0 hops".
        public var modelHopsLabel: String {
            guard modelHops > 0 else { return "Not recorded" }
            return modelHops == 1 ? "1 hop" : "\(modelHops) hops"
        }
    }

    /// Aggregates model telemetry across `receipts`: the most recent non-empty provider/class/locality
    /// wins, token counts sum. Reused by session summaries and the global context bundle.
    static func inferenceSnapshot(from receipts: [ReceiptRecord], session: AgentSession? = nil) -> InferenceSnapshot {
        var snapshot = InferenceSnapshot()
        if let session {
            snapshot.modelClass = session.modelsUsed.last
            snapshot.promptTokens = session.promptTokens
            snapshot.completionTokens = session.completionTokens
            snapshot.lastRecordedAt = session.executionUpdates.last?.recordedAt
        }
        // Callers may combine overlapping windows of the same store (e.g. the newest-N window plus the
        // full export), so the same receipt can arrive twice. Every field below either sums or counts a
        // hop, and an inflated token count misstates a measurement just as badly as showing "0" for one
        // that never happened — so aggregate each receipt ID exactly once.
        var seenReceiptIDs = Set<UUID>()
        let distinctReceipts = receipts
            .filter { seenReceiptIDs.insert($0.id).inserted }
            .sorted(by: { $0.createdAt < $1.createdAt })

        var receiptHops = 0
        for receipt in distinctReceipts {
            let values = receipt.details.values
            // A deterministic local data read (e.g. the on-chain ledger indexer) carries a route for
            // provenance but is not a model inference — never count it as a model hop or fold it into
            // the AI telemetry aggregate. Legacy receipts omit the flag and keep their prior behavior.
            if case let .string(usesInference) = values["usesInference"], usesInference == "false" {
                continue
            }
            var carriedTelemetry = false
            if case let .string(provider) = values["modelProvider"], !provider.isEmpty {
                snapshot.provider = provider
                carriedTelemetry = true
            }
            if case let .string(modelClass) = values["modelClass"], !modelClass.isEmpty {
                snapshot.modelClass = modelClass
                carriedTelemetry = true
            }
            if case let .string(locality) = values["inferenceLocality"], !locality.isEmpty {
                snapshot.locality = locality
                carriedTelemetry = true
            }
            if case let .string(privacyImpact) = values["privacyImpact"], !privacyImpact.isEmpty {
                snapshot.privacyImpact = privacyImpact
                carriedTelemetry = true
            }
            if case let .string(duration) = values["durationSeconds"], let seconds = Double(duration) {
                snapshot.durationSeconds += seconds
                carriedTelemetry = carriedTelemetry || seconds > 0
            }
            if case let .string(prompt) = values["promptTokens"], let count = Int(prompt) {
                snapshot.promptTokens += count
                carriedTelemetry = carriedTelemetry || count > 0
            }
            if case let .string(completion) = values["completionTokens"], let count = Int(completion) {
                snapshot.completionTokens += count
                carriedTelemetry = carriedTelemetry || count > 0
            }
            if case let .string(estimated) = values["tokensEstimated"], estimated == "true" {
                snapshot.tokensEstimated = true
            }
            if carriedTelemetry {
                snapshot.lastRecordedAt = receipt.createdAt
                receiptHops += 1
            }
        }
        // Each telemetry-bearing receipt is one model invocation, and the session counts hops directly.
        // Take the larger so neither source undercounts: operator runs stamp telemetry on receipts
        // without touching the session's hop counter, while autopilot increments the session directly.
        snapshot.modelHops = max(session?.modelHops ?? 0, receiptHops)
        return snapshot
    }

    static func workflowState(for session: AgentSession) -> WorkflowState {
        switch session.status {
        case .active:
            return .running
        case .waitingForApproval:
            return .waiting
        case .blocked:
            return .blocked
        case .failed:
            return .failed
        case .completed:
            return .completed
        }
    }

    public struct ProposalDiffRow: Identifiable, Equatable, Sendable {
        public let id = UUID()
        public let label: String
        public let before: String
        public let after: String
        public let risk: String
    }

    /// Loading state for a proposal's on-chain simulation, keyed per proposal so the detail view can
    /// render running/finished independently. (P1-AGENT-103)
    public enum ProposalSimulationState: Equatable, Sendable {
        case running
        case finished(ProposalSimulation)
    }

    /// Per-proposal simulation results, populated by ``simulateProposal(_:)``.
    public private(set) var proposalSimulations: [UUID: ProposalSimulationState] = [:]

    /// Wall-clock time each proposal's dry-run last ran, so the diff viewer can show how fresh the
    /// predicted movements are — a dry-run reflects chain state at the moment it ran, not at the
    /// moment of approval. (P1-AGENT-103 trust freshness)
    public private(set) var proposalSimulatedAt: [UUID: Date] = [:]

    public func proposalSimulationState(for proposal: ActionProposal) -> ProposalSimulationState? {
        proposalSimulations[proposal.id]
    }

    /// A short "Simulated <relative>" freshness note for a proposal's dry-run, or `nil` when it hasn't
    /// been simulated. Measured against ``referenceDate`` so it renders deterministically. (P1-AGENT-103)
    public func proposalSimulationFreshness(for proposal: ActionProposal) -> String? {
        guard let simulatedAt = proposalSimulatedAt[proposal.id] else { return nil }
        return "Simulated \(relativeText(simulatedAt))"
    }

    /// Runs (or re-runs) the on-chain dry-run for a proposal and stores the result for the UI.
    ///
    /// Resolves to `.notApplicable` for proposals that carry no concrete transaction, and to
    /// `.unavailable` when no simulator is wired (tests/previews) — so the diff viewer always has a
    /// definite state to show rather than silently degrading to metadata only.
    public func simulateProposal(_ proposal: ActionProposal, force: Bool = false) async {
        // Reuse a completed dry-run rather than hitting the RPC again every time the proposal detail
        // reopens. A `.running` state is not reused (it may be a leftover from a cancelled task), and
        // `force` allows an explicit re-simulation against fresh chain state.
        if !force, case .finished = proposalSimulations[proposal.id] { return }
        guard EVMTransactionIntent.from(proposal: proposal) != nil else {
            proposalSimulations[proposal.id] = .finished(ProposalSimulation(status: .notApplicable))
            return
        }
        guard let proposalSimulator else {
            proposalSimulations[proposal.id] = .finished(
                ProposalSimulation(status: .unavailable("Transaction simulation isn't configured in this build."))
            )
            return
        }
        proposalSimulations[proposal.id] = .running
        let result = await proposalSimulator.simulate(proposal)
        proposalSimulations[proposal.id] = .finished(result)
        // Recorded on the same clock `proposalSimulationFreshness(for:)` measures against. Recording
        // `.now` while rendering relative to `referenceDate` mixed two clocks in one label.
        proposalSimulatedAt[proposal.id] = referenceDate
    }

    /// A playbook that can be shared into a session ("shared workflows"). (P1-SOCIAL-101)
    public struct CoordinationPlaybook: Identifiable, Equatable, Sendable {
        public let id: String
        public let name: String
    }

    public struct CoordinationSessionSyncSummary: Equatable, Sendable {
        public let phase: SocialConnectionPhase
        public let pendingOutboundCount: Int
        public let queueItemCount: Int
        public let queueProposalCount: Int
        public let ritualRuns: [SocialRitualRun]

        public var syncLabel: String {
            switch phase {
            case .offline:
                "Offline"
            case .connecting:
                "Syncing"
            case .connected:
                "Synced"
            case .degraded:
                "Degraded"
            case .blocked:
                "Blocked"
            }
        }
    }

    public private(set) var coordinationPlaybooks: [CoordinationPlaybook] = []
    public private(set) var coordinationSyncSummaries: [UUID: CoordinationSessionSyncSummary] = [:]

    public func loadCoordination() async {
        sharedSessions = await host.sharedSessionStore.allSessions()
        rituals = await host.ritualStore.all()
        // One pass over the rituals for both reads. Two passes walked the same list twice for two
        // facts about each element, doubling the trips to the host for no ordering benefit.
        var availability: [String: RuntimeHost.RitualAvailability] = [:]
        var lastRuns: [String: Date] = [:]
        for ritual in rituals {
            availability[ritual.id] = await host.ritualAvailability(id: ritual.id)
            lastRuns[ritual.id] = await host.ritualStore.lastRun(id: ritual.id)
        }
        ritualAvailability = availability
        ritualLastRuns = lastRuns
        do {
            coordinationPlaybooks = try await host.playbookStore.all()
                .filter { $0.installState == .installed }
                .map { CoordinationPlaybook(id: $0.id, name: $0.name) }
                .sorted { $0.name < $1.name }
        } catch {
            playbookPersistenceError = error.localizedDescription
        }
        var summaries: [UUID: CoordinationSessionSyncSummary] = [:]
        let snapshot = await host.socialEventLogStore.currentSnapshot()
        // `uniquingKeysWith:`, not `uniqueKeysWithValues:` — the latter *traps* on a duplicate id.
        // `SocialEventLogStore.pendingOutbound()` avoids exactly this construct, with a comment
        // recording why: it was safe only by the invariant that every write path runs `normalized()`
        // first, and a future setter that forgot would turn a duplicate relay delivery into a crash.
        // Reading the same envelope array in the UI layer re-introduced that hazard one level up,
        // where a trap is a launch-path crash rather than a dropped row.
        let eventByID = Dictionary(
            snapshot.envelopes.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        for session in sharedSessions {
            // Through the snapshot so the log's own provenance comes with it: the bare-array form of
            // `reduce` trusts no `.local` identity, which would hide every locally-authored ritual.
            let projection = snapshot.projection(sessionID: session.id)
            let pendingCount = snapshot.pendingOutboundEventIDs
                .compactMap { eventByID[$0] }
                .filter { $0.sessionID == session.id }
                .count
            let syncState = snapshot.syncStates[session.id] ?? SocialSyncState(
                phase: session.isActive ? .offline : .blocked,
                pendingOutboundCount: pendingCount
            )
            summaries[session.id] = CoordinationSessionSyncSummary(
                phase: syncState.phase,
                pendingOutboundCount: syncState.pendingOutboundCount,
                queueItemCount: projection.queueItems.count,
                queueProposalCount: projection.queueProposals.count,
                ritualRuns: projection.ritualRunDetails.values.sorted { $0.ritualID < $1.ritualID }
            )
        }
        coordinationSyncSummaries = summaries
    }

    public func openSharedSession() async {
        let session = SharedSession(
            correlationID: UUID().uuidString,
            title: "Shared operator session",
            createdBy: .human
        )
        _ = await host.sharedSessionStore.create(session)
        await loadCoordination()
    }

    /// The live session for `id` from the last coordination load — the source of truth the detail
    /// surface renders, so mutations reflect immediately after `loadCoordination()`.
    public func sharedSession(id: UUID) -> SharedSession? {
        sharedSessions.first { $0.id == id }
    }

    public func coordinationSyncSummary(sessionID: UUID) -> CoordinationSessionSyncSummary? {
        coordinationSyncSummaries[sessionID]
    }

    /// Adds a named human participant to a shared session (P1-SOCIAL-101). The name doubles as the
    /// stable participant key, so distinct names are distinct participants and re-adding is idempotent.
    public func addParticipant(toSession sessionID: UUID, name: String, role: SharedRole) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let actor = ActorRef(kind: .human, identifier: trimmed, displayName: trimmed)
        await host.sharedSessionStore.mutate(id: sessionID) { $0.addParticipant(actor, role: role) }
        await loadCoordination()
    }

    /// Files a receipt into a shared session's shared context ("shared receipts"). (P1-SOCIAL-101)
    public func shareReceipt(_ receiptID: UUID, toSession sessionID: UUID) async {
        await host.sharedSessionStore.mutate(id: sessionID) { $0.share(receiptID: receiptID) }
        await loadCoordination()
    }

    /// Files an artifact into a shared session ("shared agent context"). (P1-SOCIAL-101)
    public func shareArtifact(_ artifactID: UUID, toSession sessionID: UUID) async {
        await host.sharedSessionStore.mutate(id: sessionID) { $0.share(artifactID: artifactID) }
        await loadCoordination()
    }

    public func shareAgentContext(
        title: String,
        summary: String,
        toSession sessionID: UUID
    ) async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTitle.isEmpty == false, trimmedSummary.isEmpty == false else { return }
        _ = await host.shareAgentContext(
            SharedAgentContext(
                title: trimmedTitle,
                summary: trimmedSummary,
                provenance: "mission-control.human-summary",
                dataClassNames: ["user-authored"]
            ),
            sessionID: sessionID,
            authorParticipantID: ActorRef.human.participantKey
        )
        await loadCoordination()
    }

    /// Files a playbook into a shared session ("shared workflows"). (P1-SOCIAL-101)
    public func sharePlaybook(_ playbookID: String, toSession sessionID: UUID) async {
        _ = await host.runSharedWorkflow(
            sessionID: sessionID,
            playbookID: playbookID,
            trigger: .manual,
            actor: .human
        )
        await loadPerformance()
        await loadReceipts()
        await loadRuntimeHistory()
        await loadCoordination()
    }

    /// Ends a shared session. Terminal and idempotent.
    public func endSharedSession(_ sessionID: UUID) async {
        await host.sharedSessionStore.mutate(id: sessionID) { $0.end() }
        await loadCoordination()
    }

    /// Opens a collaborative approval on a shared session, standing in for a pending runtime
    /// `ApprovalRequest` that needs multi-participant sign-off. (P1-SOCIAL-101)
    public func openCollaborativeApproval(
        sessionID: UUID,
        request: ApprovalRequest,
        requiredApprovals: Int
    ) async {
        await host.openCollaborativeApproval(
            sessionID: sessionID,
            approvalRequest: request,
            prompt: request.prompt,
            requiredApprovals: requiredApprovals
        )
        await loadCoordination()
    }

    /// Casts a participant's vote on a collaborative approval. When the collaborative vote resolves,
    /// this drives the *same* single-actor runtime approval flow the Approval Inbox uses — approving
    /// resumes the proposal through the governed pipeline; rejecting records the refusal — so
    /// collaborative sign-off is wired end-to-end, not a parallel bookkeeping surface. (P1-SOCIAL-101)
    public func voteOnCollaborativeApproval(
        sessionID: UUID,
        approvalID: UUID,
        participant: ActorRef,
        approved: Bool
    ) async {
        let (_, resolution) = await host.recordCollaborativeVote(
            sessionID: sessionID,
            approvalID: approvalID,
            actor: participant,
            approved: approved
        )
        await loadCoordination()
        guard let resolution, resolution != .pending else { return }
        guard let session = sharedSession(id: sessionID),
              let collaborative = session.approvals.first(where: { $0.id == approvalID }),
              let request = collaborative.approvalRequest ?? pendingApprovals.first(where: { $0.id == collaborative.approvalRequestID }) else {
            return
        }
        await resolve(request, decision: resolution == .approved ? .approved : .rejected)
        await loadCoordination()
    }

    public func setRitualEnabled(id: String, enabled: Bool) async {
        await host.ritualStore.setEnabled(id: id, enabled)
        await loadCoordination()
    }

    public func runRitual(id: String) async {
        ritualRunReports[id] = await host.runRitualReport(id: id, trigger: .manual, actor: .human)
        await loadPerformance()
        await loadReceipts()
        await loadRuntimeHistory()
        await loadCoordination()
    }

    /// Wallet accounts the visible workflows operate on, derived from their proposals. (P1-102)
    public var contextAccountsInScope: [String] {
        workflowAccounts.filter { $0 != MissionControlFacets.noAccount }
    }

    /// Chains referenced by the visible workflows and recent receipts. (P1-102)
    public var contextChainsInScope: [String] {
        var chains = Set<String>()
        for step in workflowStepLogs {
            if case let .proposed(proposal) = step.event,
               let chain = EVMTransactionIntent.chainKey(from: proposal), !chain.isEmpty {
                chains.insert(chain)
            }
        }
        for receipt in recentReceipts {
            if case let .string(chain) = receipt.details.values["chain"], !chain.isEmpty {
                chains.insert(chain)
            }
        }
        return chains.sorted()
    }

    /// Capabilities currently granted (active leases), named. Distinct from the raw lease count so the
    /// inspector shows *what* authority is in scope, not just how many. (P1-102)
    public var grantedPermissionLabels: [String] {
        Array(Set(activeLeases.map { $0.capability.rawValue })).sorted()
    }

    /// The model attribution in scope for the console, aggregated across durable and browsed receipts.
    ///
    /// `recentReceipts` is the newest window of the same store `browserReceipts` exports in full, so the
    /// two deliberately overlap — whichever has loaded is the one that carries the telemetry. Summing is
    /// safe because `inferenceSnapshot(from:)` aggregates each receipt ID once.
    public var contextInferenceSnapshot: InferenceSnapshot {
        Self.inferenceSnapshot(from: recentReceipts + browserReceipts)
    }

    /// What the session's working memory actually contains — not just a count, but the distinct
    /// workflows and the goals held in scope, so the inspector shows the substance of the context.
    /// (P1-AGENT-102 "memory included")
    public var contextMemorySummary: String {
        guard !workflowStepLogs.isEmpty else { return "Empty — no session steps in memory" }
        let workflowCount = Set(workflowStepLogs.map { $0.correlationID ?? "(untracked)" }).count
        let goals = Self.unique(workflowStepLogs.compactMap { step -> String? in
            guard case let .proposed(proposal) = step.event, !proposal.intent.isEmpty else { return nil }
            return proposal.intent
        })
        var summary = "\(workflowStepLogs.count) step(s) across \(workflowCount) workflow(s)"
        if !goals.isEmpty {
            let shown = goals.prefix(3).joined(separator: "; ")
            let overflow = goals.count > 3 ? " +\(goals.count - 3) more" : ""
            summary += " • goals: \(shown)\(overflow)"
        }
        return summary
    }

    /// The authoritative sources actually feeding the current context — its data lineage, so
    /// provenance reads as "where this came from" rather than a single opaque label. Derived from data
    /// presence (not from the bundle itself, to avoid a cycle). (P1-AGENT-102 "data provenance")
    public var contextProvenanceSummary: String {
        contextProvenanceSummary(inference: contextInferenceSnapshot)
    }

    /// - Parameter inference: an already-aggregated telemetry snapshot. Taken as a parameter rather
    ///   than recomputed because aggregating it dedupes and sorts the entire receipt ledger, and
    ///   ``inspectedContextBundle`` has already done that for its own fields — recomputing it here
    ///   doubled the cost of every bundle build just to test `isEmpty`.
    func contextProvenanceSummary(inference: InferenceSnapshot) -> String {
        var sources = ["RuntimeHost (mode)"]
        if !workflowStepLogs.isEmpty { sources.append("WorklogStore (\(workflowStepLogs.count) steps)") }
        if !(recentReceipts.isEmpty && browserReceipts.isEmpty) {
            sources.append("ReceiptStore (\(max(recentReceipts.count, browserReceipts.count)) receipts)")
        }
        if !activeLeases.isEmpty { sources.append("CapabilityLeaseRegistry (\(activeLeases.count) leases)") }
        if !artifacts.isEmpty { sources.append("ArtifactStore (\(artifacts.count) artifacts)") }
        if !inference.isEmpty { sources.append("OperatorExecutor (model telemetry)") }
        return sources.joined(separator: ", ")
    }

    /// The `lastRefreshed` stamp for a bundle field: when the data behind it was actually read.
    ///
    /// `nil` until every contributing source has been read at least once — the contract then reports
    /// the field as not fresh, which is the honest answer for data the console has never loaded. When
    /// a field draws on more than one source the *oldest* read wins, so a composite field can never
    /// report itself fresher than its stalest input.
    private func lastRefreshed(for sources: GovernedContextSource...) -> Date? {
        var oldest: Date?
        for source in sources {
            guard let loaded = loadedAt(source) else { return nil }
            oldest = min(oldest ?? loaded, loaded)
        }
        return oldest
    }

    private func loadedAt(_ source: GovernedContextSource) -> Date? {
        switch source {
        // Read live off `RuntimeHost` on every access, so it is current by construction.
        case .runtimeHost:
            return referenceDate
        // Model telemetry is stamped onto receipt details, so its freshness is the receipt read's.
        case .operatorExecutor:
            return sourceLoadedAt[.receiptStore]
        default:
            return sourceLoadedAt[source]
        }
    }

    public var inspectedContextBundle: ContextBundle {
        let inference = contextInferenceSnapshot
        let accounts = contextAccountsInScope
        let chains = contextChainsInScope
        let permissions = grantedPermissionLabels
        return ContextBundle(fields: [
            ContextField(
                key: "operator.mode",
                stringValue: cryptoModeLabel,
                dataClass: .derived,
                source: .runtimeHost,
                lastRefreshed: lastRefreshed(for: .runtimeHost)
            ),
            ContextField(
                key: "accounts.inScope",
                stringValue: accounts.isEmpty ? "None in scope" : accounts.joined(separator: ", "),
                dataClass: .publicIdentifier,
                source: .worklogStore,
                lastRefreshed: lastRefreshed(for: .worklogStore)
            ),
            ContextField(
                key: "chains.inScope",
                // Drawn from the worklog's proposals *and* the recent receipt window, so it is only
                // as fresh as whichever of the two was read longer ago.
                stringValue: chains.isEmpty ? "None in scope" : chains.joined(separator: ", "),
                dataClass: .publicIdentifier,
                source: .worklogStore,
                lastRefreshed: lastRefreshed(for: .worklogStore, .receiptStore)
            ),
            ContextField(
                key: "memory.session",
                stringValue: contextMemorySummary,
                dataClass: .derived,
                source: .worklogStore,
                lastRefreshed: lastRefreshed(for: .worklogStore)
            ),
            ContextField(
                key: "data.provenance",
                // Lineage, not payload: a list of which sources are feeding the bundle, recomputed
                // from currently-loaded state on every access. Reuses the snapshot above.
                stringValue: contextProvenanceSummary(inference: inference),
                dataClass: .derived,
                source: .runtimeHost,
                lastRefreshed: lastRefreshed(for: .runtimeHost)
            ),
            ContextField(
                key: "permissions.granted",
                stringValue: permissions.isEmpty ? "None granted" : permissions.joined(separator: ", "),
                dataClass: .derived,
                source: .capabilityLeaseRegistry,
                lastRefreshed: lastRefreshed(for: .capabilityLeaseRegistry)
            ),
            ContextField(
                key: "model.used",
                stringValue: inference.isEmpty ? "Not recorded" : inference.modelLabel,
                dataClass: .derived,
                source: .operatorExecutor,
                lastRefreshed: lastRefreshed(for: .operatorExecutor)
            ),
            ContextField(
                key: "inference.locality",
                stringValue: inference.localityLabel,
                dataClass: .derived,
                source: .operatorExecutor,
                lastRefreshed: lastRefreshed(for: .operatorExecutor)
            ),
            ContextField(
                key: "inference.privacyImpact",
                stringValue: inference.privacyImpactLabel,
                dataClass: .derived,
                source: .operatorExecutor,
                lastRefreshed: lastRefreshed(for: .operatorExecutor)
            ),
            ContextField(
                key: "inference.executionTime",
                stringValue: inference.durationLabel,
                dataClass: .derived,
                source: .operatorExecutor,
                lastRefreshed: lastRefreshed(for: .operatorExecutor)
            ),
            ContextField(
                key: "receipts.recent.count",
                stringValue: "\(recentReceipts.count)",
                dataClass: .derived,
                source: .receiptStore,
                lastRefreshed: lastRefreshed(for: .receiptStore)
            ),
            ContextField(
                key: "approvals.pending.count",
                stringValue: "\(pendingApprovals.count)",
                dataClass: .derived,
                source: .runtimeEventBus,
                lastRefreshed: lastRefreshed(for: .runtimeEventBus)
            ),
            ContextField(
                key: "artifacts.visible.count",
                stringValue: "\(artifacts.count)",
                dataClass: .derived,
                source: .artifactStore,
                lastRefreshed: lastRefreshed(for: .artifactStore)
            ),
            ContextField(
                key: "capabilities.active.count",
                stringValue: "\(activeLeases.count)",
                dataClass: .derived,
                source: .capabilityLeaseRegistry,
                lastRefreshed: lastRefreshed(for: .capabilityLeaseRegistry)
            )
        ])
    }

    public var inspectedContextContract: ContextBundleContract {
        ContextBundleContract(
            identifier: "mission-control.inspected-context",
            requirements: [
                ContextFieldRequirement(
                    key: "operator.mode",
                    allowedDataClasses: [.derived],
                    maxAge: 300,
                    authoritativeSource: .runtimeHost,
                    missingFieldBehavior: .fail
                ),
                ContextFieldRequirement(
                    key: "accounts.inScope",
                    allowedDataClasses: [.publicIdentifier],
                    maxAge: 300,
                    authoritativeSource: .worklogStore,
                    missingFieldBehavior: .fail
                ),
                ContextFieldRequirement(
                    key: "chains.inScope",
                    allowedDataClasses: [.publicIdentifier],
                    maxAge: 300,
                    authoritativeSource: .worklogStore,
                    missingFieldBehavior: .fail
                ),
                ContextFieldRequirement(
                    key: "memory.session",
                    allowedDataClasses: [.derived],
                    maxAge: 300,
                    authoritativeSource: .worklogStore,
                    missingFieldBehavior: .fail
                ),
                ContextFieldRequirement(
                    key: "data.provenance",
                    allowedDataClasses: [.derived],
                    maxAge: 300,
                    authoritativeSource: .runtimeHost,
                    missingFieldBehavior: .fail
                ),
                ContextFieldRequirement(
                    key: "receipts.recent.count",
                    allowedDataClasses: [.derived],
                    maxAge: 300,
                    authoritativeSource: .receiptStore,
                    missingFieldBehavior: .fail
                ),
                ContextFieldRequirement(
                    key: "approvals.pending.count",
                    allowedDataClasses: [.derived],
                    maxAge: 300,
                    authoritativeSource: .runtimeEventBus,
                    missingFieldBehavior: .fail
                ),
                ContextFieldRequirement(
                    key: "artifacts.visible.count",
                    allowedDataClasses: [.derived],
                    maxAge: 300,
                    authoritativeSource: .artifactStore,
                    missingFieldBehavior: .fail
                ),
                // Trust-critical provenance: the model, inference locality, and granted permissions
                // must come from their authoritative source and carry the derived data class. This
                // catches a spoofed or misattributed value on the sovereignty surface, while still
                // permitting the legitimate "Not recorded" / "None granted" states (those fields are
                // always emitted, so presence passes and only a wrong source/class fails). (P1-AGENT-102)
                ContextFieldRequirement(
                    key: "model.used",
                    allowedDataClasses: [.derived],
                    maxAge: 300,
                    authoritativeSource: .operatorExecutor,
                    missingFieldBehavior: .fail
                ),
                ContextFieldRequirement(
                    key: "inference.locality",
                    allowedDataClasses: [.derived],
                    maxAge: 300,
                    authoritativeSource: .operatorExecutor,
                    missingFieldBehavior: .fail
                ),
                ContextFieldRequirement(
                    key: "inference.privacyImpact",
                    allowedDataClasses: [.derived],
                    maxAge: 300,
                    authoritativeSource: .operatorExecutor,
                    missingFieldBehavior: .fail
                ),
                ContextFieldRequirement(
                    key: "inference.executionTime",
                    allowedDataClasses: [.derived],
                    maxAge: 300,
                    authoritativeSource: .operatorExecutor,
                    missingFieldBehavior: .fail
                ),
                ContextFieldRequirement(
                    key: "permissions.granted",
                    allowedDataClasses: [.derived],
                    maxAge: 300,
                    authoritativeSource: .capabilityLeaseRegistry,
                    missingFieldBehavior: .fail
                ),
                ContextFieldRequirement(
                    key: "capabilities.active.count",
                    allowedDataClasses: [.derived],
                    maxAge: 300,
                    authoritativeSource: .capabilityLeaseRegistry,
                    missingFieldBehavior: .fail
                )
            ],
            missingFieldBehavior: .fail
        )
    }

    public var inspectedContextValidation: ContextContractValidation {
        inspectedContextContract.validate(inspectedContextBundle, now: referenceDate)
    }

    public var agentSessionSummaries: [AgentSessionSummary] {
        if let cached = agentSessionSummariesCache { return cached }
        let built = buildAgentSessionSummaries()
        agentSessionSummariesCache = built
        return built
    }

    /// ``agentSessionSummaries`` indexed by correlation ID, for the surfaces that need exactly one
    /// session. Prefer ``agentSessionSummary(id:)`` over `agentSessionSummaries.first(where:)`, which
    /// builds the whole set to answer a single lookup.
    public var agentSessionSummariesByID: [String: AgentSessionSummary] {
        if let cached = agentSessionSummariesByIDCache { return cached }
        let built = Dictionary(
            agentSessionSummaries.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        agentSessionSummariesByIDCache = built
        return built
    }

    /// The session summary for one correlation ID, or `nil` when no workflow or session carries it.
    public func agentSessionSummary(id correlationID: String) -> AgentSessionSummary? {
        agentSessionSummariesByID[correlationID]
    }

    private func buildAgentSessionSummaries() -> [AgentSessionSummary] {
        let sessionsByCorrelation = Dictionary(uniqueKeysWithValues: agentSessions.map { ($0.correlationID, $0) })
        var emitted = Set<String>()
        var summaries = workflowSummaries.map { summary in
            emitted.insert(summary.id)
            let steps = workflowStepLogs.filter { $0.correlationID == summary.id }
            let proposals = steps.compactMap { step -> ActionProposal? in
                guard case let .proposed(proposal) = step.event else { return nil }
                return proposal
            }
            let session = sessionsByCorrelation[summary.id]
            let capabilities = Array(
                Set((session?.capabilities.map(\.rawValue) ?? []) + proposals.map { $0.capability.rawValue })
            ).sorted()
            let receipts = browserReceipts.filter { $0.correlationID == summary.id }
            let artifactCount = Set((session?.artifactIDs ?? []) + receipts.flatMap { artifactIDs(from: $0) }).count
            let modelCount = receipts.filter { receipt in
                if case .string = receipt.details.values["modelProvider"] { return true }
                if case .string = receipt.details.values["inferenceLocality"] { return true }
                return false
            }.count + (session?.modelsUsed.count ?? 0)
            let estimatedCost = receipts.reduce(0) { partial, receipt in
                guard case let .string(value) = receipt.details.values["estimatedCost"],
                      let cost = Double(value) else { return partial }
                return partial + cost
            } + (session?.estimatedCost ?? 0)
            return AgentSessionSummary(
                id: summary.id,
                goal: session?.goal ?? proposals.first?.intent ?? summary.nextStep,
                state: session.map(Self.workflowState(for:)) ?? summary.state,
                capabilities: capabilities,
                receiptCount: Set((session?.receiptIDs ?? []) + receipts.map(\.id)).count,
                approvalCount: Set((session?.approvalIDs ?? []) + pendingApprovals.filter { $0.proposal.correlationID == summary.id }.map(\.id)).count,
                artifactCount: artifactCount,
                modelCount: modelCount,
                estimatedCost: estimatedCost,
                startedAt: session?.startedAt ?? steps.map(\.timestamp).min(),
                endedAt: session?.endedAt ?? ([.completed, .blocked, .failed].contains(summary.state) ? steps.map(\.timestamp).max() : nil),
                inference: Self.inferenceSnapshot(from: receipts, session: session),
                memoryTouched: session?.memoryTouched.map { "\($0.kind.rawValue): \($0.key)" } ?? [],
                executionUpdates: session?.executionUpdates.map(\.message) ?? []
            )
        }
        summaries.append(contentsOf: agentSessions.filter { !emitted.contains($0.correlationID) }.map { session in
            let receipts = browserReceipts.filter { $0.correlationID == session.correlationID }
            return AgentSessionSummary(
                id: session.correlationID,
                goal: session.goal,
                state: Self.workflowState(for: session),
                capabilities: session.capabilities.map(\.rawValue).sorted(),
                receiptCount: Set(session.receiptIDs + receipts.map(\.id)).count,
                approvalCount: session.approvalIDs.count,
                artifactCount: session.artifactIDs.count,
                modelCount: session.modelsUsed.count,
                estimatedCost: session.estimatedCost,
                startedAt: session.startedAt,
                endedAt: session.endedAt,
                inference: Self.inferenceSnapshot(from: receipts, session: session),
                memoryTouched: session.memoryTouched.map { "\($0.kind.rawValue): \($0.key)" },
                executionUpdates: session.executionUpdates.map(\.message)
            )
        })
        return summaries.sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }
    }

    /// A compact, at-a-glance reasoning summary for a workflow — the deliberation counts, last
    /// execution duration, and model/inference attribution — so the Timeline list surfaces *how the
    /// system reasoned* on the row itself, not only after drilling in. (P1-AGENT-101)
    public struct TimelineReasoning: Equatable, Sendable {
        public let consideredCount: Int
        public let selectedCount: Int
        public let rejectedCount: Int
        public let lastDurationSeconds: Double?
        public let modelLabel: String?
        public let localityLabel: String?

        public var isEmpty: Bool {
            consideredCount == 0 && lastDurationSeconds == nil && modelLabel == nil && localityLabel == nil
        }

        /// One-line reasoning summary, or `nil` when nothing meaningful has been recorded yet.
        public var summaryLine: String? {
            var parts: [String] = []
            if consideredCount > 0 {
                parts.append("Considered \(consideredCount): \(selectedCount) selected / \(rejectedCount) rejected")
            }
            if let lastDurationSeconds {
                parts.append(String(format: "%.2fs", lastDurationSeconds))
            }
            if let modelLabel {
                parts.append(modelLabel)
            }
            if let localityLabel {
                parts.append(localityLabel)
            }
            return parts.isEmpty ? nil : parts.joined(separator: " • ")
        }
    }

    public func timelineReasoning(for correlationID: String) -> TimelineReasoning {
        var considered = 0
        var selected = 0
        var lastDuration: Double?
        for step in worklogSteps(for: correlationID) {
            switch step.event {
            case let .considered(candidates):
                considered += candidates.count
                selected += candidates.filter(\.wasSelected).count
            case let .executed(_, duration):
                lastDuration = duration
            default:
                break
            }
        }
        let inference = Self.inferenceSnapshot(from: browserReceipts.filter { $0.correlationID == correlationID })
        return TimelineReasoning(
            consideredCount: considered,
            selectedCount: selected,
            rejectedCount: considered - selected,
            lastDurationSeconds: lastDuration,
            modelLabel: inference.isEmpty ? nil : inference.modelLabel,
            localityLabel: inference.isEmpty ? nil : inference.localityLabel
        )
    }

    public func proposalDiffRows(for proposal: ActionProposal) -> [ProposalDiffRow] {
        [
            ProposalDiffRow(
                label: "Capability",
                before: "No capability exercised",
                after: proposal.capability.rawValue,
                risk: proposal.impact.rawValue
            ),
            ProposalDiffRow(
                label: "Action boundary",
                before: "No state change",
                after: proposal.impact.requiresConfirmation ? "Approval or block required" : "May run inside current authority",
                risk: proposal.impact.requiresConfirmation ? "approval-gated" : "routine"
            ),
            ProposalDiffRow(
                label: "Receipt",
                before: "No receipt",
                after: proposal.impact.requiresReceipt ? "Required" : "Optional for read-only",
                risk: proposal.requiredApprovals.isEmpty ? "none declared" : proposal.requiredApprovals.joined(separator: ", ")
            ),
            ProposalDiffRow(
                label: "Deterministic checks",
                before: "Not evaluated",
                after: proposal.requiredCheckIDs.isEmpty ? "No proposal-specific checks" : proposal.requiredCheckIDs.joined(separator: ", "),
                risk: proposal.requiredCheckIDs.isEmpty ? "none declared" : "\(proposal.requiredCheckIDs.count) check(s)"
            ),
            // P1-103 — what data the action would read/touch, named from its declared parameters.
            ProposalDiffRow(
                label: "Data accessed",
                before: "No data accessed",
                after: proposal.parameters.isEmpty ? "No declared inputs" : proposal.parameters.keys.sorted().joined(separator: ", "),
                risk: proposal.parameters.isEmpty ? "none declared" : "\(proposal.parameters.count) field(s)"
            )
        ]
    }

    public func worklogSteps(for correlationID: String) -> [WorkflowStepLog] {
        workflowStepLogs
            .filter { $0.correlationID == correlationID }
            .sorted { $0.timestamp < $1.timestamp }
    }

    public func comparisonRows(for versions: [Artifact]) -> [ProposalDiffRow] {
        guard let previous = versions.dropLast().last, let current = versions.last else { return [] }
        var rows = [
            ProposalDiffRow(
                label: "Version",
                before: "v\(previous.version)",
                after: "v\(current.version)",
                risk: current.approvalState.rawValue
            ),
            ProposalDiffRow(
                label: "Content length",
                before: "\(previous.content.count) characters",
                after: "\(current.content.count) characters",
                risk: current.content == previous.content ? "unchanged" : "changed"
            ),
            ProposalDiffRow(
                label: "Provenance",
                before: previous.provenance.inference?.locality.rawValue ?? "not recorded",
                after: current.provenance.inference?.locality.rawValue ?? "not recorded",
                risk: current.provenance.inference?.provider ?? "unknown provider"
            )
        ]
        rows.append(contentsOf: contentDiffRows(previous: previous, current: current))
        return rows
    }

    private func contentDiffRows(previous: Artifact, current: Artifact) -> [ProposalDiffRow] {
        let previousLines = previous.content.components(separatedBy: .newlines)
        let currentLines = current.content.components(separatedBy: .newlines)
        let maxCount = max(previousLines.count, currentLines.count)
        var added = 0
        var removed = 0
        var changed = 0
        var firstChangedLine: Int?
        var firstBefore = "No differing line"
        var firstAfter = "No differing line"

        for index in 0..<maxCount {
            let before = index < previousLines.count ? previousLines[index] : nil
            let after = index < currentLines.count ? currentLines[index] : nil
            if before == after { continue }
            if firstChangedLine == nil {
                firstChangedLine = index + 1
                firstBefore = Self.diffExcerpt(before)
                firstAfter = Self.diffExcerpt(after)
            }
            switch (before, after) {
            case (nil, .some):
                added += 1
            case (.some, nil):
                removed += 1
            case (.some, .some):
                changed += 1
            case (nil, nil):
                break
            }
        }

        let risk = added == 0 && removed == 0 && changed == 0
            ? "unchanged"
            : "+\(added) / -\(removed) / changed \(changed)"

        return [
            ProposalDiffRow(
                label: "Content line diff",
                before: "\(previousLines.count) lines",
                after: "\(currentLines.count) lines",
                risk: risk
            ),
            ProposalDiffRow(
                label: "First content change",
                before: firstBefore,
                after: firstAfter,
                risk: firstChangedLine.map { "line \($0)" } ?? "unchanged"
            )
        ]
    }

    private static func diffExcerpt(_ line: String?) -> String {
        guard let line else { return "No line" }
        guard !line.isEmpty else { return "Empty line" }
        if line.count <= 160 { return line }
        return String(line.prefix(157)) + "..."
    }

    #if DEBUG
    /// Test/preview seam: injects deterministic display state so snapshot baselines can render
    /// *populated* sections without a live runtime. Setting ``referenceDate`` here also fixes the
    /// relative/freshness rendering. Not used in production (compiled out of release builds).
    func seedForSnapshot(
        referenceDate: Date,
        recentReceipts: [ReceiptRecord] = [],
        browserReceipts: [ReceiptRecord] = [],
        activeLeases: [CapabilityLease] = [],
        performanceHealth: [PlaybookHealth] = [],
        recentExecutions: [ExecutionRecord] = [],
        artifacts: [Artifact] = [],
        playbooks: [Playbook] = [],
        workflowStepLogs: [WorkflowStepLog] = []
    ) {
        self.referenceDate = referenceDate
        // The seam stands in for the real loads, so it records their timestamps too. Without this the
        // context bundle would report every source as never-read and a fully seeded console would
        // (correctly, but uselessly) render as unverified.
        for source in [
            GovernedContextSource.receiptStore,
            .worklogStore,
            .runtimeEventBus,
            .capabilityLeaseRegistry,
            .artifactStore
        ] {
            sourceLoadedAt[source] = referenceDate
        }
        self.recentReceipts = recentReceipts
        self.browserReceipts = browserReceipts
        self.activeLeases = activeLeases
        self.performanceHealth = performanceHealth
        self.recentExecutions = recentExecutions
        self.artifacts = artifacts
        self.artifactLookupByID = Self.artifactLookup(from: artifacts)
        self.playbooks = playbooks
        self.workflowStepLogs = workflowStepLogs
        self.liveEvents = Self.events(from: workflowStepLogs)
        self.pendingApprovals = Self.pendingApprovals(in: liveEvents, excluding: [])
    }
    #endif
}
