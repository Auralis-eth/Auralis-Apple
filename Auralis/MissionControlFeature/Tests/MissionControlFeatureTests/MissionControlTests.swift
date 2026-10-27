import AuralisReceipts
import AuralisPrimaryModels
import AuralisFoundation
import Foundation
@testable import MissionControlFeature
import OperatorsFeature
import AuralisRuntime
import AuralisPolicy
import RuntimeKit
import SocialCore
import Testing

private extension RuntimeHost {
    convenience init(receiptStore: any ReceiptStore, worklogStore: any WorklogStoring) {
        self.init(receiptStore: receiptStore, stores: RuntimeHostStores(worklogStore: worklogStore))
    }

    convenience init(receiptStore: any ReceiptStore, artifactStore: any ArtifactStore) {
        self.init(receiptStore: receiptStore, stores: RuntimeHostStores(artifactStore: artifactStore))
    }

    convenience init(receiptStore: any ReceiptStore, playbookStore: any PlaybookStore) {
        self.init(receiptStore: receiptStore, stores: RuntimeHostStores(playbookStore: playbookStore))
    }

    convenience init(
        receiptStore: any ReceiptStore,
        playbookStore: any PlaybookStore,
        executionRecordStore: any ExecutionRecordStoring
    ) {
        self.init(
            receiptStore: receiptStore,
            stores: RuntimeHostStores(
                playbookStore: playbookStore,
                executionRecordStore: executionRecordStore
            )
        )
    }

    convenience init(receiptStore: any ReceiptStore, socialEventLogStore: SocialEventLogStore) {
        self.init(
            receiptStore: receiptStore,
            coordination: RuntimeCoordinationStores(socialEventLogStore: socialEventLogStore)
        )
    }

    convenience init(
        receiptStore: any ReceiptStore,
        cryptoModeProvider: @escaping @MainActor @Sendable () -> CryptoMode,
        cryptoModeSetter: @escaping @MainActor @Sendable (CryptoMode) -> Void
    ) {
        self.init(
            receiptStore: receiptStore,
            identity: RuntimeIdentityHooks(
                cryptoModeProvider: cryptoModeProvider,
                cryptoModeSetter: cryptoModeSetter
            )
        )
    }
}

private actor NoopReceiptStore: ReceiptStore {
    private var records: [ReceiptRecord] = []

    func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord {
        let record = ReceiptRecord(
            id: UUID(), sequenceID: records.count + 1, createdAt: receipt.createdAt, actor: receipt.actor, actorDetail: receipt.actorDetail, authorityDetail: receipt.authorityDetail, mode: receipt.mode,
            trigger: receipt.trigger, scope: receipt.scope, summary: receipt.summary,
            provenance: receipt.provenance, isSuccess: receipt.isSuccess,
            correlationID: receipt.correlationID, details: receipt.details
        )
        records.insert(record, at: 0)
        return record
    }

    func latest(limit: Int) async throws -> [ReceiptRecord] {
        Array(records.prefix(limit))
    }

    func receipts(forCorrelationID correlationID: String, limit: Int) async throws -> [ReceiptRecord] {
        Array(records.filter { $0.correlationID == correlationID }.prefix(limit))
    }

    /// Emits the same `ReceiptProvenanceExport` envelope the real store does. A bare `[ReceiptRecord]`
    /// array here failed to decode in `loadBrowserReceipts`, which silently fell back to
    /// `latest(limit: 500)` — so the "loads full exported history" test was measuring the fallback,
    /// not the export path. The manifest/signature fields are placeholders: the browser reads only
    /// `records`, and integrity verification is `SwiftDataReceiptStore`'s own test surface.
    func exportAll() async throws -> Data {
        let ordered = Array(records.reversed())
        return try JSONEncoder().encode(
            ReceiptProvenanceExport(
                records: ordered,
                manifest: ReceiptProvenanceManifest(
                    recordCount: ordered.count,
                    recordsHash: "test-records-hash",
                    chainHeads: []
                ),
                manifestHash: "test-manifest-hash",
                manifestSignature: "test-manifest-signature",
                trustAnchor: ReceiptProvenanceTrustAnchor(
                    algorithm: "test",
                    publicKey: "test-public-key",
                    fingerprint: "test-fingerprint"
                )
            )
        )
    }
    func resetAll() async throws { records.removeAll() }

    func appendedRecords() -> [ReceiptRecord] { records }
}

/// A readable ledger whose integrity verdict is whatever the test says it is.
///
/// Reads always succeed — that is the point. The defect this covers was a *readable* history being
/// presented as sound, so a double that fails its reads would prove nothing.
private actor AttestingReceiptStore: ReceiptStore {
    enum Verdict {
        case value(ReceiptLedgerAttestation)
        /// The verifier itself threw. Must read as "cannot vouch", never as verified.
        case failure
        /// The conformer does not implement verification at all (the protocol default).
        case unsupported
    }

    struct VerifierFailure: Error {}

    private let verdict: Verdict
    private var records: [ReceiptRecord]

    init(verdict: Verdict, recordCount: Int = 3) {
        self.verdict = verdict
        records = (0..<recordCount).map { index in
            ReceiptRecord(
                id: UUID(),
                sequenceID: index + 1,
                createdAt: Date(timeIntervalSince1970: TimeInterval(1_000 + index)),
                actor: .system,
                actorDetail: nil,
                authorityDetail: nil,
                mode: .observe,
                trigger: "test",
                scope: "test",
                summary: "receipt \(index)",
                provenance: "test",
                isSuccess: true,
                correlationID: nil,
                details: ReceiptPayload(values: [:])
            )
        }
    }

    func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord {
        throw VerifierFailure()
    }

    func latest(limit: Int) async throws -> [ReceiptRecord] { Array(records.prefix(limit)) }

    func receipts(forCorrelationID correlationID: String, limit: Int) async throws -> [ReceiptRecord] { [] }

    func allRecords() async throws -> [ReceiptRecord] { records }

    func ledgerAttestation() async throws -> ReceiptLedgerAttestation? {
        switch verdict {
        case let .value(attestation): return attestation
        case .failure: throw VerifierFailure()
        case .unsupported: return nil
        }
    }

    func exportAll() async throws -> Data { Data() }

    func resetAll() async throws { records.removeAll() }
}

private struct FailingAppendReceiptStore: ReceiptStore {
    struct Failure: Error {}

    func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord { throw Failure() }
    func latest(limit: Int) async throws -> [ReceiptRecord] { [] }
    func receipts(forCorrelationID correlationID: String, limit: Int) async throws -> [ReceiptRecord] { [] }
    func exportAll() async throws -> Data {
        try JSONEncoder().encode(
            ReceiptProvenanceExport(
                records: [],
                manifest: ReceiptProvenanceManifest(recordCount: 0, recordsHash: "", chainHeads: []),
                manifestHash: "",
                manifestSignature: "",
                trustAnchor: ReceiptProvenanceTrustAnchor(algorithm: "test", publicKey: "", fingerprint: "")
            )
        )
    }
    func resetAll() async throws {}
}

private struct FailingReadReceiptStore: ReceiptStore {
    struct Failure: Error {}

    func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord { throw Failure() }
    func latest(limit: Int) async throws -> [ReceiptRecord] { throw Failure() }
    func receipts(forCorrelationID correlationID: String, limit: Int) async throws -> [ReceiptRecord] { throw Failure() }
    func exportAll() async throws -> Data { throw Failure() }
    func resetAll() async throws {}
}

/// A receipt store whose reads can be failed and recovered, for the intermittent-storage case: the
/// full-history read fails, then the store comes back before the next recent-window read.
private actor ControllableReadReceiptStore: ReceiptStore {
    struct Failure: Error {}

    private var readsFail: Bool

    init(readsFail: Bool) {
        self.readsFail = readsFail
    }

    func setReadsFail(_ shouldFail: Bool) {
        readsFail = shouldFail
    }

    func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord { throw Failure() }

    func latest(limit: Int) async throws -> [ReceiptRecord] {
        if readsFail { throw Failure() }
        return []
    }

    func receipts(forCorrelationID correlationID: String, limit: Int) async throws -> [ReceiptRecord] {
        if readsFail { throw Failure() }
        return []
    }

    func exportAll() async throws -> Data {
        if readsFail { throw Failure() }
        return try JSONEncoder().encode(
            ReceiptProvenanceExport(
                records: [],
                manifest: ReceiptProvenanceManifest(recordCount: 0, recordsHash: "", chainHeads: []),
                manifestHash: "",
                manifestSignature: "",
                trustAnchor: ReceiptProvenanceTrustAnchor(algorithm: "test", publicKey: "", fingerprint: "")
            )
        )
    }

    func resetAll() async throws {}
}

private struct FailingArtifactStore: ArtifactStore {
    struct Failure: Error {}

    func create(_ draft: ArtifactDraft) async throws -> Artifact { throw Failure() }
    func addVersion(toGroup groupID: UUID, _ draft: ArtifactDraft) async throws -> Artifact { throw Failure() }
    func get(id: UUID) async throws -> Artifact? { throw Failure() }
    func latest(limit: Int) async throws -> [Artifact] { throw Failure() }
    func versions(ofGroup groupID: UUID) async throws -> [Artifact] { throw Failure() }
    func all(ofType type: ArtifactType, limit: Int) async throws -> [Artifact] { throw Failure() }
    func setApprovalState(id: UUID, to state: ArtifactApprovalState) async throws { throw Failure() }
    func linkRelatedReceipt(id receiptID: UUID, toArtifact artifactID: UUID) async throws { throw Failure() }
    func updateLifecycle(id: UUID, to state: ArtifactApprovalState, destination: String?, exportFormat: String?) async throws { throw Failure() }
    func exportAll() async throws -> Data { throw Failure() }
    func resetAll() async throws { throw Failure() }
}

private actor ControllableArtifactVersionStore: ArtifactStore {
    struct Failure: Error {}

    private var storedVersions: [Artifact]
    private var versionReadsFail = false

    init(versions: [Artifact]) {
        storedVersions = versions
    }

    func setVersions(_ versions: [Artifact]) {
        storedVersions = versions
    }

    func setVersionReadsFail(_ shouldFail: Bool) {
        versionReadsFail = shouldFail
    }

    func create(_ draft: ArtifactDraft) async throws -> Artifact { throw Failure() }
    func addVersion(toGroup groupID: UUID, _ draft: ArtifactDraft) async throws -> Artifact { throw Failure() }
    func get(id: UUID) async throws -> Artifact? { throw Failure() }
    func latest(limit: Int) async throws -> [Artifact] { throw Failure() }

    func versions(ofGroup groupID: UUID) async throws -> [Artifact] {
        guard !versionReadsFail else { throw Failure() }
        return storedVersions.filter { $0.groupID == groupID }
    }

    func all(ofType type: ArtifactType, limit: Int) async throws -> [Artifact] { throw Failure() }
    func setApprovalState(id: UUID, to state: ArtifactApprovalState) async throws { throw Failure() }
    func linkRelatedReceipt(id receiptID: UUID, toArtifact artifactID: UUID) async throws { throw Failure() }
    func updateLifecycle(id: UUID, to state: ArtifactApprovalState, destination: String?, exportFormat: String?) async throws { throw Failure() }
    func exportAll() async throws -> Data { throw Failure() }
    func resetAll() async throws { throw Failure() }
}

/// Returns a canned simulation so the model's simulate flow can be tested without a network. (P1-AGENT-103)
private struct StubProposalSimulator: ProposalSimulating {
    let result: ProposalSimulation
    func simulate(_ proposal: ActionProposal) async -> ProposalSimulation { result }
}

@Suite("MissionControlFeature")
@MainActor
struct MissionControlTests {
    @Test
    func describesEvents() {
        #expect(MissionControlHomeView.describe(.workflowStarted) == "Workflow started")
        #expect(MissionControlHomeView.describe(.workflowBlocked(reason: "no")) == "Blocked: no")
        #expect(MissionControlHomeView.describe(.executionUpdate("hi")) == "hi")
    }

    // MARK: - Receipt ledger attestation

    /// A verified ledger says nothing — silence is reserved for "every row is attestable".
    @Test("a verified ledger raises no attestation notice")
    func verifiedLedgerRaisesNoNotice() async {
        let store = AttestingReceiptStore(verdict: .value(ReceiptLedgerAttestation(status: .verified)))
        let model = MissionControlHomeModel(host: RuntimeHost(receiptStore: store), receiptStore: store)

        await model.loadBrowserReceipts()

        #expect(model.receiptHistoryScope == .complete)
        #expect(model.receiptLedgerAttestation?.status == .verified)
        #expect(model.receiptAttestationNotice == nil)
        #expect(model.dataQualityIssues.isEmpty)
    }

    /// The defect this exists for: before the attestation read, a tampered row was fetched and
    /// rendered identically to a verified one while `receiptHistoryDataIssue` was set to `nil`, so the
    /// view affirmatively asserted a complete, sound history. The rows must still load — refusing
    /// them is what the export gate used to do wrong — but the surface must say so.
    @Test("a tampered ledger still loads but is reported as untrustworthy")
    func tamperedLedgerIsReported() async throws {
        let store = AttestingReceiptStore(
            verdict: .value(
                ReceiptLedgerAttestation(status: .tampered, failureReason: "chain head mismatch at 2")
            )
        )
        let model = MissionControlHomeModel(host: RuntimeHost(receiptStore: store), receiptStore: store)

        await model.loadBrowserReceipts()

        #expect(model.browserReceipts.count == 3, "a tamper verdict must annotate history, not hide it")
        #expect(model.receiptLedgerAttestation?.status == .tampered)
        let notice = try #require(model.receiptAttestationNotice)
        #expect(notice.contains("integrity check failed"))
        #expect(model.dataQualityIssues.contains { $0.contains("integrity check failed") })
    }

    /// `.unattested` is an ordinary upgrade/restore state and must never be worded as alteration —
    /// the storage type's documentation is emphatic that conflating the two marks honest ledgers
    /// invalid.
    @Test("an unattested ledger is reported as unprovable, not as altered")
    func unattestedLedgerIsNotCalledAltered() async throws {
        let store = AttestingReceiptStore(
            verdict: .value(ReceiptLedgerAttestation(status: .unattested, failureReason: "unsigned prefix"))
        )
        let model = MissionControlHomeModel(host: RuntimeHost(receiptStore: store), receiptStore: store)

        await model.loadBrowserReceipts()

        let notice = try #require(model.receiptAttestationNotice)
        #expect(notice.contains("cannot be proved"))
        #expect(notice.contains("altered") == false)
        #expect(notice.contains("integrity check failed") == false)
    }

    /// A verifier that throws must not be indistinguishable from one that passed.
    @Test("a failed attestation read reports that the device cannot vouch")
    func failedAttestationReadIsNotSilence() async {
        let store = AttestingReceiptStore(verdict: .failure)
        let model = MissionControlHomeModel(host: RuntimeHost(receiptStore: store), receiptStore: store)

        await model.loadBrowserReceipts()

        #expect(model.receiptHistoryScope == .complete, "the rows read fine; only verification failed")
        #expect(model.receiptLedgerAttestation == nil)
        #expect(model.receiptAttestationNotice?.contains("could not verify") == true)
    }

    /// Same for a conformer that does not implement verification: the protocol default returns `nil`,
    /// which must render as "cannot vouch" rather than as a clean bill of health.
    @Test("a store without verification support reports that it cannot vouch")
    func unsupportedAttestationIsNotSilence() async {
        let store = AttestingReceiptStore(verdict: .unsupported)
        let model = MissionControlHomeModel(host: RuntimeHost(receiptStore: store), receiptStore: store)

        await model.loadBrowserReceipts()

        #expect(model.receiptAttestationNotice?.contains("could not verify") == true)
    }

    /// The advisory rides *alongside* the status, never instead of it.
    @Test("a completeness advisory is surfaced alongside an otherwise verified verdict")
    func completenessAdvisoryIsSurfaced() async {
        let store = AttestingReceiptStore(
            verdict: .value(
                ReceiptLedgerAttestation(
                    status: .verified,
                    completenessAdvisory: "The ledger mark suggests 2 receipts may have been removed."
                )
            )
        )
        let model = MissionControlHomeModel(host: RuntimeHost(receiptStore: store), receiptStore: store)

        await model.loadBrowserReceipts()

        #expect(model.receiptLedgerAttestation?.status == .verified)
        #expect(model.receiptAttestationNotice?.contains("may have been removed") == true)
    }

    @Test
    func pauseTogglesHost() async {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(host: host, receiptStore: store)
        #expect(model.isPaused == false)
        await model.setPaused(true)
        #expect(host.isPaused == true)
    }

    @Test
    func modeSelectionUpdatesHostMode() {
        let store = NoopReceiptStore()
        var selectedMode = CryptoMode.observe
        let host = RuntimeHost(
            receiptStore: store,
            cryptoModeProvider: { selectedMode },
            cryptoModeSetter: { selectedMode = $0 }
        )
        let model = MissionControlHomeModel(host: host, receiptStore: store)

        model.cryptoMode = .assist

        #expect(model.cryptoMode == .assist)
        #expect(model.cryptoModeLabel == "Assist")
    }

    @Test
    func initialConsoleLoadSubscribesBeforeHydratingHistory() async {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(host: host, receiptStore: store)
        let observation = Task { await model.loadConsoleAndObserveEvents() }

        for _ in 0..<100 {
            if await host.eventBus.subscriberCount > 0 { break }
            await Task.yield()
        }
        let envelope = WorkflowEventEnvelope(event: .executionUpdate("during hydration"))
        await host.eventBus.publish(envelope)
        for _ in 0..<100 {
            if model.liveEvents.contains(where: { $0.id == envelope.id }) { break }
            await Task.yield()
        }

        #expect(model.liveEvents.filter { $0.id == envelope.id }.count == 1)
        observation.cancel()
        await observation.value
    }

    @Test
    func approvalDecisionRecordsReceiptWithoutExecuting() async throws {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(host: host, receiptStore: store)
        let request = ApprovalRequest(
            proposal: ActionProposal(
                actor: .human,
                intent: "Open external effect",
                capability: .runPlugin,
                impact: .externalImpact,
                correlationID: "approval-correlation"
            ),
            prompt: "Review external effect"
        )
        await host.performanceStore.record(PerformanceEvent(
            playbookID: "external",
            outcome: .needsApproval,
            durationSeconds: 0.1,
            runID: request.proposal.id
        ))

        await model.resolve(request, decision: .approved)
        await model.resolve(request, decision: .approved)

        let approvalRecords = await store.appendedRecords().filter { $0.trigger == "approval.approved" }
        let record = try #require(approvalRecords.first)
        #expect(approvalRecords.count == 1)
        #expect(record.trigger == "approval.approved")
        #expect(record.summary.contains("Recorded approval"))
        #expect(record.scope == "approval")
        #expect(record.details.values["approvalID"] == .string(request.id.uuidString))
        let health = await host.performanceStore.health(forPlaybook: "external")
        #expect(health.resolvedApprovalCount == 1)
        #expect(health.approvalRate == 1)

        let session = try #require(await host.sessionStore.session(correlationID: "approval-correlation"))
        #expect(session.receiptIDs.contains(record.id))
        #expect(session.approvalIDs == [request.id])
        #expect(session.executionUpdates.map(\.message).contains("Recorded approval: Open external effect"))

        let events = await host.recentEvents(limit: 100)
        #expect(events.contains { envelope in
            if case .receiptCreated(record.id) = envelope.event {
                return envelope.correlationID == "approval-correlation"
            }
            return false
        })
        #expect(events.contains { envelope in
            if case .executionUpdate("Recorded approval: Open external effect") = envelope.event {
                return envelope.correlationID == "approval-correlation"
            }
            return false
        })
    }

    /// The in-flight latch (`resolvingApprovalIDs`) is handed off to the durable set once a history
    /// load confirms the decision reached the ledger, so it stays bounded by what is genuinely in
    /// flight. This is the half of that handoff that has to keep holding: after the reload, a stale
    /// view re-submitting the same decision must not append a second approval receipt or resume the
    /// governed proposal again.
    @Test("a resolved approval cannot be re-resolved after the decision becomes durable")
    func approvalCannotBeResolvedTwiceAcrossAHistoryReload() async throws {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(host: host, receiptStore: store)
        let request = ApprovalRequest(
            proposal: ActionProposal(
                actor: .human,
                intent: "Open external effect",
                capability: .runPlugin,
                impact: .externalImpact,
                correlationID: "approval-reresolve"
            ),
            prompt: "Review external effect"
        )

        await model.resolve(request, decision: .approved)
        #expect(await store.appendedRecords().filter { $0.trigger == "approval.approved" }.count == 1)

        // `resolve` already reloads history, which is what prunes the in-flight latch. Reload again
        // to make the handoff unambiguous rather than incidental to the first call.
        await model.loadRuntimeHistory()
        #expect(model.resolvingApprovalIDs.contains(request.id) == false)
        #expect(model.durablyResolvedApprovalIDs.contains(request.id.uuidString))

        await model.resolve(request, decision: .approved)

        #expect(await store.appendedRecords().filter { $0.trigger == "approval.approved" }.count == 1)
        #expect(model.pendingApprovals.contains { $0.id == request.id } == false)
    }

    @Test("approval fails closed when its durable receipt cannot be saved")
    func approvalReceiptFailureDoesNotResolveOrResumeProposal() async {
        let store = FailingAppendReceiptStore()
        let worklog = InMemoryWorklog()
        let request = ApprovalRequest(
            proposal: ActionProposal(
                actor: .human,
                intent: "Open external effect",
                capability: .runPlugin,
                impact: .externalImpact,
                correlationID: "approval-fail-closed"
            ),
            prompt: "Review external effect"
        )
        await worklog.record(WorkflowStepLog(
            correlationID: request.proposal.resolvedCorrelationID,
            toolID: "tool",
            event: .decided(.escalate(approvalRequest: request)),
            actor: request.proposal.actor
        ))
        let host = RuntimeHost(receiptStore: store, worklogStore: worklog)
        let model = MissionControlHomeModel(host: host, receiptStore: store)
        await model.loadRuntimeHistory()

        await model.resolve(request, decision: .approved)

        #expect(model.pendingApprovals.map(\.id) == [request.id])
        #expect(model.approvalPersistenceError != nil)
        #expect(model.operatorOutcomes.isEmpty)
        #expect(model.activeLeases.isEmpty)
    }

    /// One escalation reaches the console through *both* sources the pipeline writes it to — the
    /// worklog's `.decided(.escalate)` entry and the bus's `.approvalRequired` event — and the two
    /// envelopes carry different ids, so envelope-level de-duplication cannot collapse them. The inbox
    /// is keyed by the request, so it must: two rows for one ask double the approval count on Home and
    /// the contract-validated `approvals.pending.count` on the governed context surface.
    @Test
    func escalationRecordedInBothSourcesYieldsOnePendingApproval() async {
        let store = NoopReceiptStore()
        let worklog = InMemoryWorklog()
        let request = ApprovalRequest(
            proposal: ActionProposal(
                actor: .human,
                intent: "Prepare treasury transfer",
                capability: .draftTransaction,
                impact: .highRisk,
                correlationID: "dual-source-escalation"
            ),
            prompt: "Approve treasury transfer draft?"
        )
        await worklog.record(WorkflowStepLog(
            correlationID: request.proposal.resolvedCorrelationID,
            toolID: "tool",
            event: .decided(.escalate(approvalRequest: request)),
            actor: request.proposal.actor
        ))
        let host = RuntimeHost(receiptStore: store, worklogStore: worklog)
        await host.eventBus.publish(WorkflowEventEnvelope(
            event: .approvalRequired(request),
            correlationID: request.proposal.resolvedCorrelationID
        ))
        let model = MissionControlHomeModel(host: host, receiptStore: store)

        await model.loadRuntimeHistory()

        // Both records of the ask are still in the feed — only the inbox collapses them.
        #expect(model.liveEvents.filter { envelope in
            if case .approvalRequired = envelope.event { return true }
            return false
        }.count == 2)
        #expect(model.pendingApprovals.map(\.id) == [request.id])
        #expect(model.consoleCounts.approvals == 1)
        #expect(
            model.inspectedContextBundle.fields
                .first { $0.key == "approvals.pending.count" }?.stringValue == "1"
        )
    }

    /// The live stream carries the same guarantee: an ask already hydrated from history must not be
    /// added a second time when its bus envelope arrives, and one this model has already resolved must
    /// not reappear as pending on a late envelope.
    @Test
    func liveStreamDoesNotReAddHydratedOrResolvedApprovals() async {
        let store = NoopReceiptStore()
        let worklog = InMemoryWorklog()
        let request = ApprovalRequest(
            proposal: ActionProposal(
                actor: .human,
                intent: "Open external effect",
                capability: .runPlugin,
                impact: .externalImpact,
                correlationID: "live-stream-dedupe"
            ),
            prompt: "Review external effect"
        )
        await worklog.record(WorkflowStepLog(
            correlationID: request.proposal.resolvedCorrelationID,
            toolID: "tool",
            event: .decided(.escalate(approvalRequest: request)),
            actor: request.proposal.actor
        ))
        let host = RuntimeHost(receiptStore: store, worklogStore: worklog)
        let model = MissionControlHomeModel(host: host, receiptStore: store)
        let observation = Task { await model.loadConsoleAndObserveEvents() }
        for _ in 0..<100 {
            if await host.eventBus.subscriberCount > 0, !model.pendingApprovals.isEmpty { break }
            await Task.yield()
        }

        // The bus record of the ask the console already hydrated from the worklog.
        let duplicate = WorkflowEventEnvelope(
            event: .approvalRequired(request),
            correlationID: request.proposal.resolvedCorrelationID
        )
        await host.eventBus.publish(duplicate)
        for _ in 0..<100 {
            if model.liveEvents.contains(where: { $0.id == duplicate.id }) { break }
            await Task.yield()
        }
        #expect(model.pendingApprovals.map(\.id) == [request.id])

        // Once resolved, a late envelope for the same request must not resurrect it.
        await model.resolve(request, decision: .approved)
        #expect(model.pendingApprovals.isEmpty)
        let late = WorkflowEventEnvelope(
            event: .approvalRequired(request),
            correlationID: request.proposal.resolvedCorrelationID
        )
        await host.eventBus.publish(late)
        for _ in 0..<100 {
            if model.liveEvents.contains(where: { $0.id == late.id }) { break }
            await Task.yield()
        }
        #expect(model.pendingApprovals.isEmpty)

        observation.cancel()
        await observation.value
    }

    /// P1-AGENT-103 trust-trail — the approval receipt persists the exact diff (and the on-chain
    /// simulation the operator saw) so "what was I shown when I approved?" is reconstructable from the
    /// durable audit trail, not just ephemeral view state.
    @Test
    func approvalReceiptPersistsDiffAndSimulationSnapshot() async throws {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(
            host: host,
            receiptStore: store,
            proposalSimulator: StubProposalSimulator(
                result: ProposalSimulation(
                    status: .success,
                    chainName: "Ethereum",
                    gasUsed: "21000",
                    estimatedGasCostEth: "0.00042",
                    assetChanges: [
                        ProposalAssetChange(direction: .outgoing, amount: "0.25", symbol: "ETH", counterparty: "0xrecipient")
                    ]
                )
            )
        )
        let proposal = ActionProposal(
            actor: .system,
            intent: "Send 0.25 ETH",
            capability: .draftTransaction,
            impact: .highRisk,
            correlationID: "approval-sim",
            parameters: ["to": "0xabc", "value": "0x1", "chain": "ethereum"]
        )
        let request = ApprovalRequest(proposal: proposal, prompt: "Approve transfer?")

        // The operator dry-runs the proposal, then approves — both must land in the receipt.
        await model.simulateProposal(proposal)
        await model.resolve(request, decision: .approved)

        let record = try #require(await store.appendedRecords().first { $0.trigger == "approval.approved" })

        // The declared-impact diff is preserved row-for-row.
        guard case let .array(diffRows) = record.details.values["proposalDiff"] else {
            Issue.record("expected a persisted proposalDiff array")
            return
        }
        #expect(!diffRows.isEmpty)

        // The on-chain simulation the operator saw is preserved with its outcome and deltas.
        guard case let .object(simulation) = record.details.values["simulation"] else {
            Issue.record("expected a persisted simulation object")
            return
        }
        #expect(simulation["status"] == .string("success"))
        #expect(simulation["gasUsed"] == .string("21000"))
        #expect(simulation["chain"] == .string("Ethereum"))
        guard case let .array(assetChanges) = simulation["assetChanges"] else {
            Issue.record("expected persisted asset changes")
            return
        }
        #expect(assetChanges.count == 1)
    }

    /// A proposal with no dry-run on screen persists the diff but omits the simulation key entirely,
    /// rather than recording an empty or misleading simulation record. (P1-AGENT-103 trust-trail)
    @Test
    func approvalReceiptOmitsSimulationWhenNoneRan() async throws {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(host: host, receiptStore: store)
        let request = ApprovalRequest(
            proposal: ActionProposal(
                actor: .human,
                intent: "Open external effect",
                capability: .runPlugin,
                impact: .externalImpact
            ),
            prompt: "Review external effect"
        )

        await model.resolve(request, decision: .approved)

        let record = try #require(await store.appendedRecords().first { $0.trigger == "approval.approved" })
        #expect(record.details.values["proposalDiff"] != nil)
        #expect(record.details.values["simulation"] == nil)
    }

    @Test
    func durableWorklogHydratesTimeline() async {
        let store = NoopReceiptStore()
        let worklog = InMemoryWorklog()
        await worklog.record(
            WorkflowStepLog(
                correlationID: "corr-1",
                toolID: "tool",
                event: .proposed(ActionProposal(actor: .system, intent: "Read", capability: .audioPlayback, impact: .readOnly)),
                actor: .system
            )
        )
        let host = RuntimeHost(receiptStore: store, worklogStore: worklog)
        let model = MissionControlHomeModel(host: host, receiptStore: store)

        await model.loadRuntimeHistory()

        #expect(model.workflowSummaries.map(\.id) == ["corr-1"])
        // A proposal with nothing evaluated yet is queued, not running. (P1-102 distinct states)
        #expect(model.workflowSummaries.first?.state == .queued)
        #expect(model.workflowSummaries.first?.playbook == "Read")
    }

    @Test
    func stoppingWorkflowRecordsTerminalBlockedState() async throws {
        let store = NoopReceiptStore()
        let worklog = InMemoryWorklog()
        await worklog.record(
            WorkflowStepLog(
                correlationID: "corr-stop",
                toolID: "tool",
                event: .proposed(ActionProposal(actor: .system, intent: "Read", capability: .audioPlayback, impact: .readOnly)),
                actor: .system
            )
        )
        let host = RuntimeHost(receiptStore: store, worklogStore: worklog)
        let model = MissionControlHomeModel(host: host, receiptStore: store)
        await model.loadRuntimeHistory()
        let queued = try #require(model.workflowSummaries.first)
        #expect(model.canStopWorkflow(queued))

        await model.stopWorkflow(id: "corr-stop")

        let stopped = try #require(model.workflowSummaries.first)
        #expect(stopped.state == .blocked)
        #expect(!model.canStopWorkflow(stopped))
        let receipt = try #require(await store.appendedRecords().first { $0.trigger == "workflow.stopped" })
        #expect(receipt.trigger == "workflow.stopped")
        #expect(receipt.correlationID == "corr-stop")
    }

    /// Stopping a workflow must clear its pending approval even when the proposal carried no explicit
    /// correlation id.
    ///
    /// The inbox was filtered on the *raw* optional `proposal.correlationID`, but `stopWorkflow(id:)`
    /// is always called with a ``WorkflowSummary`` id — which the pipeline publishes as
    /// `resolvedCorrelationID`. For a proposal with no explicit id those two disagree (resolved falls
    /// back to the proposal's own UUID, raw is `nil`), so the approval survived the stop and stayed
    /// live in the inbox, where approving it resumes work the operator just stopped.
    @Test
    func stoppingWorkflowClearsPendingApprovalWithoutExplicitCorrelationID() async throws {
        let store = NoopReceiptStore()
        let worklog = InMemoryWorklog()
        // Deliberately no `correlationID:` — this is the case the raw-optional match missed.
        let request = ApprovalRequest(
            proposal: ActionProposal(
                actor: .system,
                intent: "Prepare treasury transfer",
                capability: .draftTransaction,
                impact: .highRisk
            ),
            prompt: "Approve treasury transfer draft?"
        )
        #expect(request.proposal.correlationID == nil)
        let resolvedID = request.proposal.resolvedCorrelationID

        await worklog.record(WorkflowStepLog(
            correlationID: resolvedID,
            toolID: "tool",
            event: .decided(.escalate(approvalRequest: request)),
            actor: request.proposal.actor
        ))
        let host = RuntimeHost(receiptStore: store, worklogStore: worklog)
        let model = MissionControlHomeModel(host: host, receiptStore: store)
        await model.loadRuntimeHistory()

        let waiting = try #require(model.workflowSummaries.first)
        #expect(waiting.id == resolvedID)
        #expect(waiting.state == .waiting)
        #expect(model.pendingApprovals.map(\.id) == [request.id])

        await model.stopWorkflow(id: resolvedID)

        #expect(model.pendingApprovals.isEmpty)
        // `stopWorkflow` reloads history on its way out, and that reload re-derives the inbox from the
        // worklog — which still holds the `.decided(.escalate)` entry. The optimistic `removeAll` alone
        // was undone two lines later, so assert the workflow reads terminal and the ask stays gone.
        #expect(try #require(model.workflowSummaries.first).state == .blocked)

        // And it must stay gone across an independent reload, not just the one inside `stopWorkflow`.
        await model.loadRuntimeHistory()
        #expect(model.pendingApprovals.isEmpty)
    }

    /// The same stop, but for a workflow that *does* carry an explicit correlation id — the reload
    /// rehydration this guards against was never specific to the nil-id case.
    @Test
    func stoppingWorkflowClearsPendingApprovalAcrossReload() async throws {
        let store = NoopReceiptStore()
        let worklog = InMemoryWorklog()
        let request = ApprovalRequest(
            proposal: ActionProposal(
                actor: .system,
                intent: "Prepare treasury transfer",
                capability: .draftTransaction,
                impact: .highRisk,
                correlationID: "corr-stop-approval"
            ),
            prompt: "Approve treasury transfer draft?"
        )
        await worklog.record(WorkflowStepLog(
            correlationID: request.proposal.resolvedCorrelationID,
            toolID: "tool",
            event: .decided(.escalate(approvalRequest: request)),
            actor: request.proposal.actor
        ))
        let host = RuntimeHost(receiptStore: store, worklogStore: worklog)
        let model = MissionControlHomeModel(host: host, receiptStore: store)
        await model.loadRuntimeHistory()
        #expect(model.pendingApprovals.map(\.id) == [request.id])

        await model.stopWorkflow(id: "corr-stop-approval")
        #expect(model.pendingApprovals.isEmpty)

        await model.loadRuntimeHistory()
        #expect(model.pendingApprovals.isEmpty)
        #expect(model.consoleCounts.approvals == 0)
    }

    @Test
    func worklogDerivesDistinctFailedAndWaitingStates() {
        // Failed is now distinct from blocked. (P1-102)
        let failed = MissionControlHomeModel.state(forWorklog: [
            .proposed(ActionProposal(actor: .system, intent: "x", capability: .audioPlayback, impact: .readOnly)),
            .checksEvaluated([]),
            .failed(reason: "boom")
        ])
        #expect(failed == .failed)

        // Escalation surfaces as waiting-for-approval.
        let waiting = MissionControlHomeModel.state(forWorklog: [
            .proposed(ActionProposal(actor: .system, intent: "x", capability: .draftTransaction, impact: .highRisk)),
            .decided(.escalate(approvalRequest: ApprovalRequest(
                proposal: ActionProposal(actor: .system, intent: "x", capability: .draftTransaction, impact: .highRisk),
                prompt: "approve?"
            )))
        ])
        #expect(waiting == .waiting)
    }

    @Test
    func timelineFiltersByAccountAndPlaybook() async {
        let store = NoopReceiptStore()
        let worklog = InMemoryWorklog()
        await worklog.record(WorkflowStepLog(
            correlationID: "wf-a", toolID: "operator.onchain.watch",
            event: .proposed(ActionProposal(
                actor: .system, intent: "On-Chain Watch", capability: .draftTransaction,
                impact: .highRisk, correlationID: "wf-a", parameters: ["address": "0xABC"]
            )),
            actor: .system
        ))
        await worklog.record(WorkflowStepLog(
            correlationID: "wf-b", toolID: "operator.research.brief",
            event: .proposed(ActionProposal(
                actor: .system, intent: "Research Brief", capability: .runPlugin,
                impact: .readOnly, correlationID: "wf-b"
            )),
            actor: .system
        ))
        let host = RuntimeHost(receiptStore: store, worklogStore: worklog)
        let model = MissionControlHomeModel(host: host, receiptStore: store)
        await model.loadRuntimeHistory()

        #expect(Set(model.workflowAccounts) == ["0xABC", "No account"])
        #expect(Set(model.workflowPlaybooks) == ["On-Chain Watch", "Research Brief"])

        model.workflowAccountFilter = "0xABC"
        #expect(model.filteredWorkflowSummaries.map(\.id) == ["wf-a"])
        #expect(model.groupedActivityFeed.map(\.id) == ["wf-a"])

        model.workflowAccountFilter = nil
        model.workflowPlaybookFilter = "Research Brief"
        #expect(model.filteredWorkflowSummaries.map(\.id) == ["wf-b"])
        #expect(model.groupedActivityFeed.map(\.id) == ["wf-b"])
    }

    // MARK: - P1-101/102/103 Agent visibility

    /// P1-101 — the session view surfaces token/model/runtime metadata and local vs remote inference,
    /// aggregated from the telemetry `OperatorExecutor` stamps onto receipts.
    @Test
    func sessionSummaryAggregatesInferenceTelemetry() async throws {
        let store = NoopReceiptStore()
        let worklog = InMemoryWorklog()
        await worklog.record(WorkflowStepLog(
            correlationID: "corr-inf", toolID: "operator.research",
            event: .proposed(ActionProposal(
                actor: .system, intent: "Research", capability: .runPlugin,
                impact: .readOnly, correlationID: "corr-inf"
            )),
            actor: .system
        ))
        let host = RuntimeHost(receiptStore: store, worklogStore: worklog)
        let model = MissionControlHomeModel(host: host, receiptStore: store)
        _ = try await store.append(ReceiptDraft(
            category: "runtime", kind: "tool.executed", correlationID: "corr-inf",
            payload: ReceiptPayload(values: [
                "modelProvider": .string("Apple"),
                "modelClass": .string("on-device-foundation"),
                "inferenceLocality": .string("local"),
                "privacyImpact": .string(InferenceLocality.local.privacyImpact),
                "promptTokens": .string("120"),
                "completionTokens": .string("30"),
                "durationSeconds": .string("0.42")
            ]),
            actorDetail: .system, authorityDetail: nil, summary: "ran", provenance: "operator", isSuccess: true
        ))
        await model.loadRuntimeHistory()
        await model.loadBrowserReceipts()

        let summary = try #require(model.agentSessionSummaries.first { $0.id == "corr-inf" })
        #expect(summary.inference.modelLabel == "Apple · on-device-foundation")
        #expect(summary.inference.localityLabel == "On-device (local)")
        #expect(summary.inference.privacyImpactLabel == InferenceLocality.local.privacyImpact)
        #expect(summary.inference.durationLabel == "0.42s")
        #expect(summary.inference.totalTokens == 150)
        #expect(summary.inference.tokensLabel == "150 total • 120 prompt / 30 completion")
    }

    /// P1-102 — the Context Bundle Inspector exposes accounts, chains, session memory, granted
    /// permissions, and the model/locality actually used — without breaking the declared contract.
    @Test
    func contextBundleSurfacesAccountsChainsMemoryAndModel() async throws {
        let store = NoopReceiptStore()
        let worklog = InMemoryWorklog()
        await worklog.record(WorkflowStepLog(
            correlationID: "corr-ctx", toolID: "operator.watch",
            event: .proposed(ActionProposal(
                actor: .system, intent: "Watch", capability: .runPlugin, impact: .readOnly,
                correlationID: "corr-ctx", parameters: ["account": "vitalik.eth", "chain": "ethereum"]
            )),
            actor: .system
        ))
        let host = RuntimeHost(receiptStore: store, worklogStore: worklog)
        let model = MissionControlHomeModel(host: host, receiptStore: store)
        _ = try await store.append(ReceiptDraft(
            category: "runtime", kind: "tool.executed", correlationID: "corr-ctx",
            payload: ReceiptPayload(values: [
                "modelProvider": .string("Apple"),
                "inferenceLocality": .string("remote"),
                "privacyImpact": .string(InferenceLocality.remote.privacyImpact),
                "durationSeconds": .string("1.5")
            ]),
            actorDetail: .system, authorityDetail: nil, summary: "ran", provenance: "operator", isSuccess: true
        ))
        // Every source the contract declares has to be read, not just the two this bundle's content
        // comes from: a field whose store was never opened is not fresh, and the contract says so.
        await model.loadConsole()

        let bundle = model.inspectedContextBundle
        #expect(bundle.field("accounts.inScope")?.stringValue == "vitalik.eth")
        #expect(bundle.field("chains.inScope")?.stringValue == "ethereum")
        // Memory surfaces its contents (workflows + goals), not just a step count. (P1-AGENT-102)
        #expect(bundle.field("memory.session")?.stringValue == "1 step(s) across 1 workflow(s) • goals: Watch")
        // Provenance names the data lineage feeding the bundle. (P1-AGENT-102)
        #expect(bundle.field("data.provenance")?.stringValue?.contains("WorklogStore") == true)
        #expect(bundle.field("model.used")?.stringValue == "Apple")
        #expect(bundle.field("inference.locality")?.stringValue == "Cloud (remote)")
        #expect(bundle.field("inference.privacyImpact")?.stringValue == InferenceLocality.remote.privacyImpact)
        #expect(bundle.field("inference.executionTime")?.stringValue == "1.50s")
        // Model/locality/privacy/time/permissions are contract requirements; they come from their
        // authoritative source with the derived class, so validation is satisfied.
        #expect(model.inspectedContextValidation.violations.isEmpty)
        #expect(model.inspectedContextValidation.isSatisfied)
    }

    /// The freshness leg of the governed-context contract has to be able to *fail*.
    ///
    /// Every field used to be stamped with the same render clock the validator measured against, so
    /// each one was exactly zero seconds old and `maxAge` was unreachable — the "context is fresh"
    /// surface asserted a guarantee nothing checked. Fields now carry the timestamp of the read that
    /// produced them.
    @Test("context freshness is measured against when each source was actually read")
    func contextFreshnessReflectsRealSourceAges() async throws {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let loadedAt = Date(timeIntervalSince1970: 1_800_000)
        var clockReading = loadedAt
        let model = MissionControlHomeModel(host: host, receiptStore: store, clock: { clockReading })

        // Before any load, no source has been read: nothing can claim to be fresh.
        #expect(model.inspectedContextBundle.field("receipts.recent.count")?.lastRefreshed == nil)
        #expect(!model.inspectedContextValidation.isSatisfied)

        await model.loadConsole()
        #expect(model.inspectedContextBundle.field("receipts.recent.count")?.lastRefreshed == loadedAt)
        #expect(model.inspectedContextValidation.isSatisfied)

        // The data is untouched; only the clock moves. Past the contract's 300s bound every
        // store-backed field is stale, and the surface now says so instead of reporting "fresh".
        clockReading = loadedAt.addingTimeInterval(301)
        let validation = model.inspectedContextValidation
        #expect(!validation.isSatisfied)
        #expect(validation.violations.contains { $0.contains("receipts.recent.count") && $0.contains("stale") })

        // Re-reading the sources makes it fresh again — staleness tracks the read, not the clock.
        await model.loadConsole()
        #expect(model.inspectedContextValidation.isSatisfied)
    }

    /// "Not read yet" and "read but aged out" both leave the contract unsatisfied, and the surface
    /// has to tell them apart — one resolves itself when hydration finishes, the other is a finding.
    @Test("context freshness separates a console that has not loaded from one that has gone stale")
    func contextFreshnessDistinguishesUnloadedFromStale() async {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let loadedAt = Date(timeIntervalSince1970: 1_800_000)
        var clockReading = loadedAt
        let model = MissionControlHomeModel(host: host, receiptStore: store, clock: { clockReading })

        #expect(model.contextInspection.freshness == .notLoadedYet)

        await model.loadConsole()
        #expect(model.contextInspection.freshness == .fresh)

        clockReading = loadedAt.addingTimeInterval(301)
        #expect(model.contextInspection.freshness == .needsAttention)
    }

    /// The three context accessors a screen needs come from one derivation, so a surface cannot
    /// accidentally pay for the bundle build — which walks and sorts the whole receipt ledger — once
    /// per accessor. Guards the invariant that they agree with each other.
    @Test("one context inspection carries the bundle, its validation, and the display state")
    func contextInspectionIsInternallyConsistent() async {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(host: host, receiptStore: store)

        await model.loadConsole()
        let inspection = model.contextInspection

        #expect(inspection.freshness == .fresh)
        #expect(inspection.validation.isSatisfied)
        #expect(inspection.validation.violations.isEmpty)
        #expect(inspection.bundle.fields.map(\.key) == model.inspectedContextBundle.fields.map(\.key))
        #expect(inspection.validation.isSatisfied == model.inspectedContextValidation.isSatisfied)
    }

    /// Receipt-history completeness is one value with three reachable states, not two Bools with an
    /// impossible fourth combination.
    @Test("receipt history scope reports not-loaded, complete, and unavailable distinctly")
    func receiptHistoryScopeTracksWhatWasActuallyRead() async {
        let store = ControllableReadReceiptStore(readsFail: true)
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(host: host, receiptStore: store)

        #expect(model.receiptHistoryScope == .notLoaded)

        await model.loadBrowserReceipts()
        #expect(model.receiptHistoryScope == .unavailable)

        await store.setReadsFail(false)
        await model.loadBrowserReceipts()
        #expect(model.receiptHistoryScope == .complete)
    }

    /// Relative labels are measured against a live clock, so they stay correct however long the
    /// console stays open. `referenceDate` was frozen at construction and never reassigned, so every
    /// relative label drifted by the model's whole lifetime.
    @Test("reference date advances with the clock unless a test pins it")
    func referenceDateFollowsTheClockUntilPinned() async {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let start = Date(timeIntervalSince1970: 1_800_000)
        var clockReading = start
        let model = MissionControlHomeModel(host: host, receiptStore: store, clock: { clockReading })

        #expect(model.referenceDate == start)
        clockReading = start.addingTimeInterval(3_600)
        #expect(model.referenceDate == start.addingTimeInterval(3_600))

        // Assigning pins it, which is what keeps snapshot baselines deterministic.
        model.referenceDate = start
        clockReading = start.addingTimeInterval(7_200)
        #expect(model.referenceDate == start)
    }

    /// P1-103 — the Proposal Diff Viewer names what data the action would touch, from its parameters.
    @Test
    func proposalDiffIncludesDataAccessed() throws {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(host: host, receiptStore: store)
        let proposal = ActionProposal(
            actor: .system, intent: "Draft", capability: .draftTransaction, impact: .highRisk,
            parameters: ["address": "0xabc", "chain": "ethereum"]
        )

        let rows = model.proposalDiffRows(for: proposal)
        let dataRow = try #require(rows.first { $0.label == "Data accessed" })
        #expect(dataRow.after == "address, chain")
        #expect(dataRow.risk == "2 field(s)")
    }

    /// P1-AGENT-103 — a proposal with no on-chain transaction (no destination) resolves to
    /// `notApplicable` without ever invoking the simulator.
    @Test
    func simulateProposalWithoutTransactionIsNotApplicable() async {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(
            host: host, receiptStore: store,
            proposalSimulator: StubProposalSimulator(result: ProposalSimulation(status: .success))
        )
        let proposal = ActionProposal(actor: .system, intent: "Read", capability: .audioPlayback, impact: .readOnly)

        await model.simulateProposal(proposal)

        #expect(model.proposalSimulationState(for: proposal) == .finished(ProposalSimulation(status: .notApplicable)))
    }

    /// P1-AGENT-103 — a real transaction with no simulator wired degrades to `unavailable` rather
    /// than silently showing nothing.
    @Test
    func simulateProposalWithoutSimulatorIsUnavailable() async {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(host: host, receiptStore: store)
        let proposal = ActionProposal(
            actor: .system, intent: "Send", capability: .draftTransaction, impact: .highRisk,
            parameters: ["to": "0xabc", "value": "0x1", "chain": "ethereum"]
        )

        await model.simulateProposal(proposal)

        guard case let .finished(simulation)? = model.proposalSimulationState(for: proposal),
              case .unavailable = simulation.status else {
            Issue.record("expected an unavailable simulation result")
            return
        }
    }

    /// P1-AGENT-103 — a real transaction runs through the injected simulator and its result is stored
    /// verbatim for the diff viewer.
    @Test
    func simulateProposalStoresInjectedResult() async {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let expected = ProposalSimulation(
            status: .success,
            chainName: "Ethereum Mainnet",
            gasUsed: "21000",
            assetChanges: [ProposalAssetChange(direction: .outgoing, amount: "0.1", symbol: "ETH", counterparty: "0xdef")]
        )
        let model = MissionControlHomeModel(
            host: host, receiptStore: store,
            proposalSimulator: StubProposalSimulator(result: expected)
        )
        let proposal = ActionProposal(
            actor: .system, intent: "Send", capability: .draftTransaction, impact: .highRisk,
            parameters: ["to": "0xabc", "value": "100", "chain": "base"]
        )

        await model.simulateProposal(proposal)

        #expect(model.proposalSimulationState(for: proposal) == .finished(expected))
    }

    /// P1-AGENT-103 — the EVM intent extractor recovers a transaction and normalizes a decimal value
    /// to a hex quantity and bare calldata to a 0x-prefixed string.
    @Test
    func evmIntentExtractsTransactionAndNormalizesValue() throws {
        let proposal = ActionProposal(
            actor: .system, intent: "Send", capability: .draftTransaction, impact: .highRisk,
            parameters: ["to": "0xabc", "value": "256", "data": "deadbeef", "chain": "base"]
        )

        let intent = try #require(EVMTransactionIntent.from(proposal: proposal))
        #expect(intent.to == "0xabc")
        #expect(intent.valueHex == "0x100")
        #expect(intent.dataHex == "0xdeadbeef")
        #expect(intent.chainKey == "base")
    }

    /// P1-AGENT-103 — a wei value above the 64-bit ceiling must convert faithfully rather than
    /// silently failing to `0x0`, which would dry-run a large transfer as a safe zero-value tx.
    @Test
    func evmIntentPreservesValuesAboveUInt64() throws {
        // 2^64 = 18446744073709551616 (one past UInt64.max) → 0x1 followed by sixteen zeros.
        let proposal = ActionProposal(
            actor: .system, intent: "Send", capability: .draftTransaction, impact: .highRisk,
            parameters: ["to": "0xabc", "value": "18446744073709551616"]
        )
        let intent = try #require(EVMTransactionIntent.from(proposal: proposal))
        #expect(intent.valueHex == "0x10000000000000000")

        #expect(EVMTransactionIntent.normalizeHexQuantity("0") == "0x0")
        #expect(EVMTransactionIntent.normalizeHexQuantity("255") == "0xff")
        #expect(EVMTransactionIntent.normalizeHexQuantity("0x1a2b") == "0x1a2b")
        #expect(EVMTransactionIntent.normalizeHexQuantity("12.5") == nil)
    }

    /// P1-AGENT-102/103 — the Context Bundle Inspector and the simulator must agree on a proposal's
    /// network, so the chain key is recovered across every accepted alias.
    @Test
    func chainKeyResolvesAcrossAliases() {
        for key in ["chain", "chainId", "network"] {
            let proposal = ActionProposal(
                actor: .system, intent: "Send", capability: .draftTransaction, impact: .highRisk,
                parameters: [key: "base"]
            )
            #expect(EVMTransactionIntent.chainKey(from: proposal) == "base")
        }
        let none = ActionProposal(
            actor: .system, intent: "Send", capability: .draftTransaction, impact: .highRisk,
            parameters: ["to": "0xabc"]
        )
        #expect(EVMTransactionIntent.chainKey(from: none) == nil)
    }

    /// P1-101 — a `considered` worklog entry (what the planner weighed and rejected) hydrates into
    /// the session trace ahead of the proposal, without disturbing the derived workflow state.
    @Test
    func worklogSurfacesConsideredCandidates() async {
        let store = NoopReceiptStore()
        let worklog = InMemoryWorklog()
        await worklog.record(WorkflowStepLog(
            correlationID: "corr-consider", toolID: "planner.deterministic",
            event: .considered([
                ConsideredCandidate(title: "make-playlist", capability: .playlistManagement, wasSelected: true, rationale: "Goal keywords matched this template."),
                ConsideredCandidate(title: "send-value", capability: .draftTransaction, wasSelected: false, rationale: "Goal did not mention any of: tip, send, pay.")
            ]),
            actor: .system
        ))
        await worklog.record(WorkflowStepLog(
            correlationID: "corr-consider", toolID: "planner.deterministic",
            event: .proposed(ActionProposal(
                actor: .system, intent: "Draft the playlist", capability: .playlistManagement,
                impact: .readOnly, correlationID: "corr-consider"
            )),
            actor: .system
        ))
        let host = RuntimeHost(receiptStore: store, worklogStore: worklog)
        let model = MissionControlHomeModel(host: host, receiptStore: store)
        await model.loadRuntimeHistory()

        let steps = model.worklogSteps(for: "corr-consider")
        #expect(steps.count == 2)
        let candidates: [ConsideredCandidate] = {
            if case let .considered(candidates) = steps.first?.event { return candidates }
            return []
        }()
        #expect(candidates.filter(\.wasSelected).count == 1)
        #expect(candidates.filter { !$0.wasSelected }.count == 1)
        // Deliberation precedes the proposal and leaves the coarse state at queued.
        #expect(model.workflowSummaries.first { $0.id == "corr-consider" }?.state == .queued)
    }

    /// P1-AGENT-101 — the Timeline row itself surfaces the reasoning (considered/rejected + duration),
    /// not only the drill-in session detail.
    @Test
    func timelineReasoningSummarizesDeliberationAndDuration() async throws {
        let store = NoopReceiptStore()
        let worklog = InMemoryWorklog()
        await worklog.record(WorkflowStepLog(
            correlationID: "corr-reason", toolID: "planner.deterministic",
            event: .considered([
                ConsideredCandidate(title: "make-playlist", capability: .playlistManagement, wasSelected: true, rationale: "matched"),
                ConsideredCandidate(title: "send-value", capability: .draftTransaction, wasSelected: false, rationale: "no match"),
                ConsideredCandidate(title: "watch", capability: .runPlugin, wasSelected: false, rationale: "no match")
            ]),
            actor: .system
        ))
        await worklog.record(WorkflowStepLog(
            correlationID: "corr-reason", toolID: "planner.deterministic",
            event: .executed(artifactID: UUID(), durationSeconds: 0.42),
            actor: .system
        ))
        let host = RuntimeHost(receiptStore: store, worklogStore: worklog)
        let model = MissionControlHomeModel(host: host, receiptStore: store)
        await model.loadRuntimeHistory()

        let reasoning = model.timelineReasoning(for: "corr-reason")
        #expect(reasoning.consideredCount == 3)
        #expect(reasoning.selectedCount == 1)
        #expect(reasoning.rejectedCount == 2)
        #expect(reasoning.lastDurationSeconds == 0.42)
        let line = try #require(reasoning.summaryLine)
        #expect(line.contains("Considered 3: 1 selected / 2 rejected"))
        #expect(line.contains("0.42s"))
    }

    /// P1-AGENT-101 — on-device token counts are labelled as estimates so they aren't read as exact.
    @Test
    func tokenLabelMarksEstimatedCounts() async throws {
        let store = NoopReceiptStore()
        let worklog = InMemoryWorklog()
        await worklog.record(WorkflowStepLog(
            correlationID: "corr-est", toolID: "operator.research",
            event: .proposed(ActionProposal(
                actor: .system, intent: "Research", capability: .runPlugin, impact: .readOnly,
                correlationID: "corr-est"
            )),
            actor: .system
        ))
        let host = RuntimeHost(receiptStore: store, worklogStore: worklog)
        let model = MissionControlHomeModel(host: host, receiptStore: store)
        _ = try await store.append(ReceiptDraft(
            category: "runtime", kind: "tool.executed", correlationID: "corr-est",
            payload: ReceiptPayload(values: [
                "promptTokens": .string("120"),
                "completionTokens": .string("30"),
                "tokensEstimated": .string("true")
            ]),
            actorDetail: .system, authorityDetail: nil, summary: "ran", provenance: "operator", isSuccess: true
        ))
        await model.loadRuntimeHistory()
        await model.loadBrowserReceipts()

        let summary = try #require(model.agentSessionSummaries.first { $0.id == "corr-est" })
        #expect(summary.inference.tokensEstimated)
        #expect(summary.inference.tokensLabel == "~150 total • 120 prompt / 30 completion (estimated)")
    }

    // MARK: - P1-201 Approval Inbox

    @Test
    func resolvedApprovalDoesNotRehydrateFromDurableWorklog() async throws {
        let store = NoopReceiptStore()
        let worklog = InMemoryWorklog()
        let request = ApprovalRequest(
            proposal: ActionProposal(
                actor: .system,
                intent: "Prepare transfer",
                capability: .draftTransaction,
                impact: .highRisk,
                correlationID: "approval-reload"
            ),
            prompt: "Approve transfer?"
        )
        await worklog.record(WorkflowStepLog(
            correlationID: "approval-reload",
            toolID: "tool",
            event: .proposed(request.proposal),
            actor: request.proposal.actor
        ))
        await worklog.record(WorkflowStepLog(
            correlationID: "approval-reload",
            toolID: "tool",
            event: .decided(.escalate(approvalRequest: request)),
            actor: request.proposal.actor
        ))
        let host = RuntimeHost(receiptStore: store, worklogStore: worklog)
        let model = MissionControlHomeModel(host: host, receiptStore: store)

        await model.loadRuntimeHistory()
        #expect(model.pendingApprovals.map(\.id) == [request.id])

        await model.resolve(request, decision: .approved)
        await model.loadRuntimeHistory()

        #expect(model.pendingApprovals.isEmpty)
        let receipt = try #require(
            await store.appendedRecords().first { $0.trigger == "approval.approved" }
        )
        #expect(receipt.details.values["approvalID"] == .string(request.id.uuidString))
    }

    @Test("resolved approvals use complete history beyond the latest receipt window")
    func oldResolvedApprovalDoesNotRehydrateAfterFiveHundredNewerReceipts() async throws {
        let store = NoopReceiptStore()
        let worklog = InMemoryWorklog()
        let request = ApprovalRequest(
            proposal: ActionProposal(
                actor: .system,
                intent: "Prepare transfer",
                capability: .draftTransaction,
                impact: .highRisk,
                correlationID: "approval-old"
            ),
            prompt: "Approve transfer?"
        )
        await worklog.record(WorkflowStepLog(
            correlationID: request.proposal.resolvedCorrelationID,
            toolID: "tool",
            event: .decided(.escalate(approvalRequest: request)),
            actor: request.proposal.actor
        ))
        _ = try await store.append(ReceiptDraft(
            category: "approval",
            kind: "approval.approved",
            correlationID: request.proposal.resolvedCorrelationID,
            payload: ReceiptPayload(values: ["approvalID": .string(request.id.uuidString)]),
            actorDetail: .human,
            authorityDetail: nil,
            summary: "Approved",
            provenance: "test",
            isSuccess: true
        ))
        for index in 0..<501 {
            _ = try await store.append(ReceiptDraft(
                category: "runtime",
                kind: "runtime.event",
                correlationID: "newer-\(index)",
                payload: ReceiptPayload(values: [:]),
                actorDetail: .system,
                authorityDetail: nil,
                summary: "Newer receipt",
                provenance: "test",
                isSuccess: true
            ))
        }
        let host = RuntimeHost(receiptStore: store, worklogStore: worklog)
        let model = MissionControlHomeModel(host: host, receiptStore: store)

        await model.loadRuntimeHistory()

        #expect(model.pendingApprovals.isEmpty)
    }

    @Test("receipt and artifact load failures remain visible as degraded evidence")
    func auditDataFailuresAreVisible() async {
        let receiptStore = FailingReadReceiptStore()
        let host = RuntimeHost(receiptStore: receiptStore, artifactStore: FailingArtifactStore())
        let model = MissionControlHomeModel(host: host, receiptStore: receiptStore)

        await model.loadReceipts()
        await model.loadBrowserReceipts()
        await model.loadArtifacts()

        #expect(model.receiptDataIssue != nil)
        #expect(model.artifactDataIssue != nil)
        #expect(model.dataQualityIssues.count == 2)
    }

    /// Degraded-evidence warnings are tracked per source, so a source that recovers cannot clear a
    /// different source's warning. One shared slot meant a successful recent-window read silently
    /// dismissed a *broken full history* — while the browser, artifact provenance, and approval
    /// resolution were all still working from nothing.
    @Test("a recovering recent-receipt read does not clear a broken receipt history warning")
    func recoveringRecentReadKeepsHistoryWarning() async {
        let store = ControllableReadReceiptStore(readsFail: true)
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(host: host, receiptStore: store)

        await model.loadBrowserReceipts()
        let historyIssue = model.receiptDataIssue
        #expect(historyIssue?.contains("could not be loaded") == true)
        #expect(model.browserReceipts.isEmpty)

        // Storage recovers in time for the cheap recent-window read, but the history is still unread.
        await store.setReadsFail(false)
        await model.loadReceipts()
        #expect(model.receiptDataIssue == historyIssue)

        // Re-reading the history is what clears it.
        await model.loadBrowserReceipts()
        #expect(model.receiptDataIssue == nil)
    }

    /// The approval-history warning used to be write-only: nothing cleared it once set, so an
    /// unreadable-approvals banner outlived the failure that produced it.
    ///
    /// The copy says "loaded" rather than "verified" because resolving which approvals are already
    /// decided is a plain read now — it used to go through `exportAll()`, which verified every
    /// signature in the ledger to answer a question that only needed the rows.
    @Test("an unreadable approval history warning clears once the history can be read again")
    func approvalHistoryWarningClearsOnRecovery() async {
        let store = ControllableReadReceiptStore(readsFail: true)
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(host: host, receiptStore: store)

        await model.loadRuntimeHistory()
        #expect(model.receiptDataIssue?.contains("could not be loaded") == true)

        await store.setReadsFail(false)
        await model.loadRuntimeHistory()
        #expect(model.receiptDataIssue == nil)
    }

    @Test
    func deferredApprovalRehydratesAsPending() async {
        let store = NoopReceiptStore()
        let worklog = InMemoryWorklog()
        let request = ApprovalRequest(
            proposal: ActionProposal(
                actor: .system,
                intent: "Open external effect",
                capability: .runPlugin,
                impact: .externalImpact,
                correlationID: "approval-deferred"
            ),
            prompt: "Review effect?"
        )
        await worklog.record(WorkflowStepLog(
            correlationID: "approval-deferred",
            toolID: "tool",
            event: .decided(.escalate(approvalRequest: request)),
            actor: request.proposal.actor
        ))
        let host = RuntimeHost(receiptStore: store, worklogStore: worklog)
        let model = MissionControlHomeModel(host: host, receiptStore: store)

        await model.resolve(request, decision: .deferred)
        await model.loadRuntimeHistory()

        #expect(model.pendingApprovals.map(\.id) == [request.id])
    }

    @Test
    func collaborativeApprovalResolvesFromStoredRequestWhenPendingApprovalsAreStale() async throws {
        let store = NoopReceiptStore()
        let worklog = InMemoryWorklog()
        let request = ApprovalRequest(
            proposal: ActionProposal(
                actor: .system,
                intent: "Approve shared operator action",
                capability: .runPlugin,
                impact: .externalImpact,
                correlationID: "collab-approval"
            ),
            prompt: "Approve shared operator action?"
        )
        await worklog.record(WorkflowStepLog(
            correlationID: "collab-approval",
            toolID: "tool",
            event: .decided(.escalate(approvalRequest: request)),
            actor: request.proposal.actor
        ))
        let host = RuntimeHost(receiptStore: store, worklogStore: worklog)
        let model = MissionControlHomeModel(host: host, receiptStore: store)

        await model.loadRuntimeHistory()
        await model.openSharedSession()
        let session = try #require(model.sharedSessions.first)
        await model.addParticipant(toSession: session.id, name: "Alice", role: .collaborator)
        await model.openCollaborativeApproval(sessionID: session.id, request: request, requiredApprovals: 1)
        await model.loadRuntimeHistory()
        #expect(model.pendingApprovals.map(\.id) == [request.id])

        await model.resolve(request, decision: .deferred)
        await model.voteOnCollaborativeApproval(
            sessionID: session.id,
            approvalID: try #require(model.sharedSession(id: session.id)?.approvals.first?.id),
            participant: ActorRef(kind: .human, identifier: "Alice", displayName: "Alice"),
            approved: true
        )

        let approvalReceipts = await store.appendedRecords().filter { $0.trigger == "approval.approved" }
        #expect(approvalReceipts.count == 1)
        #expect(approvalReceipts.first?.details.values["approvalID"] == .string(request.id.uuidString))
    }

    @Test
    func sharedWorkflowMutationRunsRoutineAndFilesSessionContext() async throws {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(host: host, receiptStore: store)

        await model.openSharedSession()
        let session = try #require(model.sharedSessions.first)
        await model.sharePlaybook("research.brief", toSession: session.id)
        let updated = try #require(model.sharedSession(id: session.id))

        #expect(updated.sharedPlaybookIDs == ["research.brief"])
        #expect(updated.sharedArtifactIDs.isEmpty == false)
        #expect(updated.sharedReceiptIDs.isEmpty == false)
    }

    @Test
    func approvalRiskDistinguishesRoutineFromRisky() {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(host: host, receiptStore: store)
        func request(_ impact: ActionImpactClass) -> ApprovalRequest {
            ApprovalRequest(
                proposal: ActionProposal(actor: .system, intent: "x", capability: .runPlugin, impact: impact),
                prompt: "?"
            )
        }
        #expect(model.risk(for: request(.readOnly)) == .routine)
        #expect(model.risk(for: request(.reversibleWrite)) == .routine)
        #expect(model.risk(for: request(.externalImpact)) == .elevated)
        #expect(model.risk(for: request(.highRisk)) == .high)
        #expect(model.risk(for: request(.readOnly)).isRisky == false)
        #expect(model.risk(for: request(.highRisk)).isRisky == true)
    }

    @Test
    func approvalReasonMentionsRequiredApprovals() {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(host: host, receiptStore: store)
        let request = ApprovalRequest(
            proposal: ActionProposal(
                actor: .system, intent: "x", capability: .approveSpending, impact: .highRisk,
                requiredApprovals: ["treasury"]
            ),
            prompt: "?"
        )
        let reason = model.approvalReason(for: request)
        #expect(reason.contains("irreversible"))
        #expect(reason.contains("treasury"))
    }

    @Test
    func approvalLinksResolveReceiptAndArtifact() async {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(host: host, receiptStore: store)
        let artifactID = UUID()
        _ = try? await store.append(ReceiptDraft(
            category: "runtime", kind: "tool.executed", correlationID: "corr-link",
            payload: ReceiptPayload(values: ["artifactID": .string(artifactID.uuidString)]),
            actorDetail: .system, authorityDetail: nil, summary: "did a thing", provenance: "operator", isSuccess: true
        ))
        await model.loadBrowserReceipts()
        let request = ApprovalRequest(
            proposal: ActionProposal(actor: .system, intent: "x", capability: .runPlugin, impact: .externalImpact, correlationID: "corr-link"),
            prompt: "?"
        )
        #expect(model.receipts(forApproval: request).count == 1)
        // Artifact resolution requires the artifact to be in the loaded store; absent here it stays empty.
        #expect(model.artifacts(forApproval: request).isEmpty)
    }

    // MARK: - EPIC P1-500 Playbooks & Routines

    /// The degraded-audit-evidence signal is reachable from Mission Control and dismissible there.
    ///
    /// `RuntimeHost.receiptPersistenceError` was raised by the runtime for a long time and read by
    /// *nothing* — Mission Control only ever wired `playbookPersistenceError` — so a run could lose
    /// its receipt and still present itself as fully evidenced. This covers the wiring that was
    /// missing: the surface can see the gap, it is told how much is missing, and only an explicit
    /// acknowledgement clears it.
    @Test
    func degradedAuditEvidenceIsVisibleToMissionControlAndAcknowledgeable() async {
        let receiptStore = FailingAppendReceiptStore()
        let host = RuntimeHost(receiptStore: receiptStore)
        let model = MissionControlHomeModel(host: host, receiptStore: receiptStore)

        for index in 0..<2 {
            _ = await host.appendRuntimeReceipt(
                ReceiptDraft(
                    category: "routine",
                    kind: "routine.success",
                    correlationID: "corr-degraded-\(index)",
                    payload: ReceiptPayload(values: [:]),
                    actorDetail: .system,
                    authorityDetail: nil,
                    summary: "Routine completed",
                    provenance: "routine",
                    isSuccess: true
                ),
                goal: "Surface degraded evidence",
                actor: .system
            )
        }

        // What `MissionControlDegradedEvidenceBanner` renders from.
        #expect(model.host.receiptPersistenceError != nil)
        #expect(model.host.missingReceiptCount == 2)

        // What its Acknowledge button calls.
        model.host.acknowledgeReceiptPersistenceFailure()
        #expect(model.host.receiptPersistenceError == nil)
        #expect(model.host.missingReceiptCount == 0)
    }

    @Test
    func playbookPersistenceFailureIsReportedToTheUIModel() async {
        let receiptStore = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: receiptStore, playbookStore: FailingPlaybookStore())
        let model = MissionControlHomeModel(host: host, receiptStore: receiptStore)

        await model.loadPlaybooks()

        #expect(model.playbookPersistenceError == "The playbook database is unavailable.")
    }

    @Test
    func playbookInstallRejectsExecuteFlowsAtModelBoundary() async {
        let store = NoopReceiptStore()
        let playbookStore = InMemoryPlaybookStore(seed: [
            playbook(id: "execute.flow", installState: .available, supportedFlows: [.read, .execute])
        ])
        let host = RuntimeHost(receiptStore: store, playbookStore: playbookStore)
        let model = MissionControlHomeModel(host: host, receiptStore: store)

        let didInstall = await model.installPlaybook(id: "execute.flow")

        #expect(didInstall == false)
        #expect(await playbookStore.playbook(id: "execute.flow")?.installState == .available)
        await model.loadPlaybooks()
        #expect(model.playbooks(inState: .installed).isEmpty)
    }

    @Test
    func playbookResumeRejectsPausedExecuteFlowsAtModelBoundary() async {
        let store = NoopReceiptStore()
        let playbookStore = InMemoryPlaybookStore(seed: [
            playbook(id: "paused.execute", installState: .paused, supportedFlows: [.execute])
        ])
        let host = RuntimeHost(receiptStore: store, playbookStore: playbookStore)
        let model = MissionControlHomeModel(host: host, receiptStore: store)

        let didResume = await model.setPlaybookState(id: "paused.execute", to: .installed)

        #expect(didResume == false)
        #expect(await playbookStore.playbook(id: "paused.execute")?.installState == .paused)
    }

    @Test
    func routineManagerListsInstalledRoutinesAndRunNowRecordsReceipts() async {
        let store = NoopReceiptStore()
        let executionStore = InMemoryExecutionRecordStore()
        let playbookStore = InMemoryPlaybookStore(seed: [
            playbook(id: "manual.installed", name: "Manual Only", trigger: .manual, installState: .installed),
            playbook(id: "scheduled.active", name: "Scheduled Active", trigger: .schedule(intervalSeconds: 60), installState: .installed),
            playbook(id: "event.paused", name: "Event Paused", trigger: .event(.artifactStale), installState: .paused)
        ])
        let host = RuntimeHost(
            receiptStore: store,
            playbookStore: playbookStore,
            executionRecordStore: executionStore
        )
        let model = MissionControlHomeModel(host: host, receiptStore: store)

        await model.loadPlaybooks()
        #expect(model.routines.map(\.id) == ["event.paused", "manual.installed", "scheduled.active"])
        #expect(model.lastRunText(for: model.routines[2]) == "Last run: not yet run")

        await model.runRoutine(id: "scheduled.active")

        let record = await executionStore.latest(forPlaybookID: "scheduled.active")
        #expect(record?.outcome == .success)
        #expect(record?.triggerSource == .manual)
        #expect(await store.appendedRecords().first?.trigger == "routine.success")
        #expect(model.latestExecution(for: "scheduled.active")?.id == record?.id)
    }

    @Test
    func artifactBrowserExposesPlaybookObjects() async {
        let store = NoopReceiptStore()
        let playbookStore = InMemoryPlaybookStore(seed: [
            playbook(id: "manual.installed", name: "Manual Installed", trigger: .manual, installState: .installed),
            playbook(id: "draft.user", name: "Draft User", trigger: .schedule(intervalSeconds: 60), installState: .draft)
        ])
        let host = RuntimeHost(receiptStore: store, playbookStore: playbookStore)
        let model = MissionControlHomeModel(host: host, receiptStore: store)

        await model.loadPlaybooks()

        #expect(model.artifactBrowserPlaybooks.map(\.id) == ["draft.user", "manual.installed"])
        #expect(model.artifactBrowserPlaybooks.first { $0.id == "manual.installed" }?.trigger.classification == "manual")
    }

    @Test
    func pausedRoutineRunNowRecordsNoOpWithoutProducingReceiptSuccess() async {
        let store = NoopReceiptStore()
        let executionStore = InMemoryExecutionRecordStore()
        let playbookStore = InMemoryPlaybookStore(seed: [
            playbook(id: "scheduled.pause", trigger: .schedule(intervalSeconds: 60), installState: .installed)
        ])
        let host = RuntimeHost(
            receiptStore: store,
            playbookStore: playbookStore,
            executionRecordStore: executionStore
        )
        let model = MissionControlHomeModel(host: host, receiptStore: store)
        await model.loadPlaybooks()

        let didPause = await model.setPlaybookState(id: "scheduled.pause", to: .paused)
        await model.runRoutine(id: "scheduled.pause")

        #expect(didPause)
        #expect(await playbookStore.playbook(id: "scheduled.pause")?.installState == .paused)
        #expect(await executionStore.latest(forPlaybookID: "scheduled.pause")?.outcome == .noOp)
        // Selected by provenance rather than taken positionally. `appendedRecords()` is
        // newest-first, and `RuntimeReceiptObserver` appends its `runtime.capability.granted`
        // receipts (provenance `local`, `isSuccess: true`) off the event bus *asynchronously* — so
        // whether a grant receipt or the routine's own receipt was newest at this line came down to
        // task scheduling, and this assertion failed on roughly two runs in three. The claim under
        // test is about the routine receipt, so name it: `runRoutine` writes it before returning,
        // which makes this deterministic.
        let routineReceipt = await store.appendedRecords().first { $0.provenance == "routine" }
        #expect(routineReceipt?.isSuccess == false)
    }

    @Test
    func playbookStateAndExecutionHistorySurviveModelRecreationWithSharedStores() async {
        let store = NoopReceiptStore()
        let executionStore = InMemoryExecutionRecordStore()
        let playbookStore = InMemoryPlaybookStore(seed: [
            playbook(id: "scheduled.persist", trigger: .schedule(intervalSeconds: 60), installState: .available)
        ])
        let firstHost = RuntimeHost(
            receiptStore: store,
            playbookStore: playbookStore,
            executionRecordStore: executionStore
        )
        let firstModel = MissionControlHomeModel(host: firstHost, receiptStore: store)

        #expect(await firstModel.installPlaybook(id: "scheduled.persist"))
        await firstModel.runRoutine(id: "scheduled.persist")

        let secondHost = RuntimeHost(
            receiptStore: store,
            playbookStore: playbookStore,
            executionRecordStore: executionStore
        )
        let secondModel = MissionControlHomeModel(host: secondHost, receiptStore: store)
        await secondModel.loadPlaybooks()
        await secondModel.loadPerformance()

        #expect(secondModel.playbooks(inState: .installed).map(\.id) == ["scheduled.persist"])
        #expect(secondModel.latestExecution(for: "scheduled.persist")?.outcome == .success)
    }

    @Test
    func performanceIncludesInstalledPlaybooksThatHaveNeverRun() async {
        let store = NoopReceiptStore()
        let playbookStore = InMemoryPlaybookStore(seed: [
            playbook(id: "installed.zero", installState: .installed),
            playbook(id: "available.zero", installState: .available)
        ])
        let host = RuntimeHost(receiptStore: store, playbookStore: playbookStore)
        let model = MissionControlHomeModel(host: host, receiptStore: store)

        await model.loadPerformance()

        #expect(model.performanceHealth.map(\.playbookID).contains("installed.zero"))
        #expect(model.performanceHealth.first { $0.playbookID == "installed.zero" }?.classification == .insufficientData)
        #expect(model.performanceHealth.map(\.playbookID).contains("available.zero") == false)
    }

    @Test
    func performanceFailureHistoryIncludesFailuresAndPolicyBlocks() {
        let store = NoopReceiptStore()
        let model = MissionControlHomeModel(host: RuntimeHost(receiptStore: store), receiptStore: store)
        let startedAt = Date(timeIntervalSince1970: 1_000)
        func execution(id: UUID, outcome: PlaybookRunOutcome) -> ExecutionRecord {
            ExecutionRecord(
                id: id,
                playbookID: "routine.health",
                triggerSource: .schedule,
                actor: ActorRef(kind: .scheduledRoutine, identifier: "routine.health"),
                outcome: outcome,
                artifactID: nil,
                startedAt: startedAt,
                durationSeconds: 0.1
            )
        }
        let failed = execution(id: UUID(), outcome: .failed)
        let blocked = execution(id: UUID(), outcome: .blocked)
        let successful = execution(id: UUID(), outcome: .success)
        model.seedForSnapshot(
            referenceDate: startedAt,
            recentExecutions: [failed, blocked, successful]
        )

        #expect(model.unsuccessfulExecutions.map(\.id) == [failed.id, blocked.id])
    }

    private func playbook(
        id: String,
        name: String? = nil,
        trigger: PlaybookTrigger = .manual,
        installState: PlaybookInstallState,
        supportedFlows: [PlaybookFlowKind] = [.read, .prepare]
    ) -> Playbook {
        Playbook(
            id: id,
            name: name ?? id,
            summary: "Removes routine work for \(id).",
            trigger: trigger,
            authority: PlaybookAuthority(capabilities: [.runPlugin], allowedOutputs: [.brief]),
            completionCondition: "A reviewable artifact is prepared.",
            supportedFlows: supportedFlows,
            source: .user,
            contextContract: SystemPlaybookContracts.contract(for: id, identifier: "user.playbook.\(id)"),
            installState: installState
        )
    }

    // MARK: - P1-202 Capability Inspector

    @Test
    func capabilityScopeMapsEveryCapability() {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(host: host, receiptStore: store)
        #expect(model.scope(for: .signMessage) == .account)
        #expect(model.scope(for: .approveSpending) == .account)
        #expect(model.scope(for: .metadataOverride) == .data)
        #expect(model.scope(for: .playlistManagement) == .data)
        #expect(model.scope(for: .runPlugin) == .execution)
        #expect(model.scope(for: .audioPlayback) == .execution)
        #expect(model.scope(for: .musicExport) == .artifact)
        // Every capability resolves to exactly one scope (no crash / total mapping).
        for capability in CapabilityID.allCases {
            _ = model.scope(for: capability)
        }
    }

    @Test
    func leasesGroupIntoTheirScopes() async {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(host: host, receiptStore: store)
        let now = Date()
        await host.leaseRegistry.grant(CapabilityLease(
            capability: .signMessage, grantedTo: .system, grantedAt: now, expiresAt: now.addingTimeInterval(600)
        ))
        await host.leaseRegistry.grant(CapabilityLease(
            capability: .musicExport,
            reason: "Export approved playlist evidence.",
            scope: .artifact,
            grantedTo: .system,
            grantedAt: now,
            expiresAt: now.addingTimeInterval(600)
        ))
        await model.refreshLeases()
        #expect(model.leases(inScope: .account).count == 1)
        #expect(model.leases(inScope: .artifact).count == 1)
        #expect(model.grantReason(for: model.leases(inScope: .artifact)[0]) == "Export approved playlist evidence.")
        #expect(model.leases(inScope: .data).isEmpty)
    }

    @Test
    func grantLeaseAuthoringCreatesInspectableRuntimeLease() async {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(host: host, receiptStore: store)

        let lease = await model.grantLease(
            capability: .musicLibraryClassification,
            actorKind: .workflow,
            actorIdentifier: "planner",
            reason: "Planner can read local preferences while building a recommendation.",
            durationMinutes: 20
        )

        #expect(model.activeLeases.map(\.id) == [lease.id])
        #expect(model.activeLeases.first?.capability == .musicLibraryClassification)
        #expect(model.activeLeases.first?.grantedTo == ActorRef(kind: .workflow, identifier: "planner"))
        #expect(model.activeLeases.first?.reason == "Planner can read local preferences while building a recommendation.")
    }

    @Test
    func denyCapabilityAuthoringCreatesInspectableRestriction() async {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(host: host, receiptStore: store)

        let restriction = await model.denyCapability(
            .externalNetwork,
            actorKind: .workflow,
            actorIdentifier: "planner",
            reason: "Planner must stay local for this session.",
            durationMinutes: 20
        )

        #expect(model.activeRestrictions.map(\.id) == [restriction.id])
        #expect(model.activeRestrictions.first?.kind.displayTitle == "No external network")
        #expect(model.activeRestrictions.first?.appliesTo == ActorRef(kind: .workflow, identifier: "planner"))
        #expect(model.activeRestrictions.first?.reason == "Planner must stay local for this session.")
    }

    @Test
    func restrictionsAreInspectableAndRevocable() async {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(host: host, receiptStore: store)
        let restriction = await host.denyCapability(
            .walletAccess,
            reason: "Planner can read context but cannot touch wallets."
        )

        await model.refreshLeases()
        #expect(model.activeRestrictions.map(\.id) == [restriction.id])
        #expect(model.activeRestrictions.first?.kind.displayTitle == "No wallet access")

        await model.revokeRestriction(id: restriction.id)
        #expect(model.activeRestrictions.isEmpty)
    }

    // MARK: - P1-300 Receipts & History

    @Test
    func receiptBrowserSearchesStructuredPayloadAndFiltersOutcome() async throws {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(host: host, receiptStore: store)
        let artifactID = UUID()
        _ = try await store.append(ReceiptDraft(
            category: "runtime",
            kind: "tool.executed",
            correlationID: "receipt-search",
            payload: ReceiptPayload(values: [
                "requestedIntent": .string("Prepare playlist export"),
                "interpretedPlan": .array([.string("Collect tracks"), .string("Write artifact")]),
                "policyReason": .string("Semantic policy allowed read-only export."),
                "artifactID": .string(artifactID.uuidString),
                "capability": .string("music.export")
            ]),
            actorDetail: .system,
            authorityDetail: nil,
            summary: "Exported playlist",
            provenance: "runtime",
            isSuccess: true
        ))
        _ = try await store.append(ReceiptDraft(
            category: "account",
            kind: "account.selected",
            correlationID: nil,
            payload: ReceiptPayload(values: ["outcome": .string("no-op")]),
            actorDetail: .system,
            authorityDetail: nil,
            summary: "Selected same account",
            provenance: "accounts",
            isSuccess: true
        ))

        await model.loadBrowserReceipts()
        model.receiptSearchText = "semantic policy"
        #expect(model.filteredReceipts.map(\.summary) == ["Exported playlist"])

        model.receiptSearchText = ""
        model.receiptOutcomeFilter = .artifactProducing
        #expect(model.filteredReceipts.map(\.summary) == ["Exported playlist"])

        model.receiptOutcomeFilter = .noOp
        #expect(model.filteredReceipts.map(\.summary) == ["Selected same account"])
    }

    @Test
    func receiptBrowserLoadsFullExportedHistoryBeyondLatestWindow() async throws {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(host: host, receiptStore: store)

        for index in 1...501 {
            let marker = index == 1 ? "oldest-hidden-receipt" : "receipt-\(index)"
            _ = try await store.append(ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                category: "runtime",
                kind: "tool.executed",
                correlationID: nil,
                payload: ReceiptPayload(values: ["marker": .string(marker)]),
                actorDetail: .system,
                authorityDetail: nil,
                summary: "Receipt \(index)",
                provenance: "test",
                isSuccess: true
            ))
        }

        await model.loadBrowserReceipts()
        model.receiptSearchText = "oldest-hidden-receipt"

        #expect(model.browserReceipts.count == 501)
        #expect(model.filteredReceipts.map(\.summary) == ["Receipt 1"])
    }

    @Test
    func receiptPresentationBuildsHumanReadableAcceptanceSections() {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(host: host, receiptStore: store)
        let receipt = ReceiptRecord(
            id: UUID(),
            sequenceID: 1,
            createdAt: .now,
            actor: .system,
            actorDetail: .system,
            authorityDetail: nil,
            mode: .assist,
            trigger: "tool.needsApproval",
            scope: "runtime",
            summary: "Approval requested",
            provenance: "runtime",
            isSuccess: true,
            correlationID: "receipt-detail",
            details: ReceiptPayload(values: [
                "requestedIntent": .string("Transfer 1 ETH"),
                "interpretedPlan": .array([.string("Draft transfer"), .string("Wait for approval")]),
                "approvalID": .string("approval-1"),
                "actionName": .string("wallet.transfer"),
                "output": .object(["draft": .string("unsigned transaction")]),
                "policyReason": .string("Human approval required for value transfer."),
                "capability": .string("wallet.sign"),
                "changeSummary": .string("Created an unsigned transaction draft.")
            ])
        )

        let presentation = model.presentation(for: receipt)
        #expect(presentation.intentRows.contains { $0.value == "Transfer 1 ETH" })
        #expect(presentation.planRows.contains { $0.value.contains("Draft transfer") })
        #expect(presentation.approvalRows.contains { $0.value == "approval-1" })
        #expect(presentation.actionRows.contains { $0.value == "wallet.transfer" })
        #expect(presentation.outputRows.contains { $0.value.contains("unsigned transaction") })
        #expect(presentation.policyRows.contains { $0.value.contains("Human approval") })
        #expect(presentation.capabilityRows.contains { $0.value == "wallet.sign" })
        #expect(presentation.changeRows.contains { $0.value.contains("unsigned transaction draft") })
        #expect(presentation.searchableText.contains("wallet.sign"))
    }

    @Test
    func postflightDistinguishesNoOpDraftArtifactAndBlockedOutcomes() {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(host: host, receiptStore: store)
        let artifactID = UUID()
        let noOp = receipt(kind: "account.selected", payload: ["outcome": .string("no-op")], success: true)
        let draft = receipt(kind: "tool.draftPrepared", payload: ["receiptDraftID": .string("draft-1")], success: true)
        let artifact = receipt(kind: "tool.executed", payload: ["artifactID": .string(artifactID.uuidString)], success: true)
        let blocked = receipt(kind: "tool.blocked", payload: ["reason": .string("Observe mode")], success: false)

        #expect(model.postflight(for: noOp) == .noOp)
        #expect(model.postflight(for: draft) == .draftOnly)
        #expect(model.postflight(for: artifact) == .artifactProducing)
        #expect(model.postflight(for: blocked) == .blocked)
    }

    @Test
    func artifactRelationshipsResolveMultipleNestedReceiptReferences() async throws {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(host: host, receiptStore: store)
        let primaryID = UUID()
        let secondaryID = UUID()
        let nestedID = UUID()
        let receiptID = UUID()
        let groupID = UUID()
        let receipt = ReceiptRecord(
            id: receiptID,
            sequenceID: 7,
            createdAt: .now,
            actor: .system,
            actorDetail: .system,
            authorityDetail: nil,
            mode: .assist,
            trigger: "tool.executed",
            scope: "runtime",
            summary: "Produced related artifacts",
            provenance: "runtime",
            isSuccess: true,
            correlationID: "artifact-links",
            details: ReceiptPayload(values: [
                "artifactID": .string(primaryID.uuidString),
                "artifactIDs": .array([
                    .string(primaryID.uuidString),
                    .string(secondaryID.uuidString)
                ]),
                "relatedArtifacts": .array([
                    .object(["id": .string(nestedID.uuidString)])
                ])
            ])
        )
        let primary = artifact(id: primaryID, groupID: groupID, title: "Primary Artifact", relatedReceiptIDs: [])
        let secondary = artifact(id: secondaryID, groupID: UUID(), title: "Secondary Artifact", relatedReceiptIDs: [])
        let reverseLinked = artifact(id: UUID(), groupID: UUID(), title: "Reverse Linked Artifact", relatedReceiptIDs: [receiptID])

        model.seedForSnapshot(
            referenceDate: .now,
            browserReceipts: [receipt],
            artifacts: [primary, secondary, reverseLinked]
        )

        #expect(model.artifactIDs(from: receipt) == [primaryID, secondaryID, nestedID])
        #expect(model.artifactID(from: receipt) == primaryID)
        #expect(model.postflight(for: receipt) == .artifactProducing)
        #expect(model.receipts(for: primary).map(\.id) == [receiptID])
        #expect(model.receipts(for: reverseLinked).map(\.id) == [receiptID])
        #expect(model.artifacts(forApproval: ApprovalRequest(
            proposal: ActionProposal(
                actor: .system,
                intent: "Review artifacts",
                capability: .runPlugin,
                impact: .externalImpact,
                correlationID: "artifact-links"
            ),
            prompt: "Review artifacts?"
        )).map(\.title) == ["Primary Artifact", "Secondary Artifact"])
    }

    @Test
    func artifactBrowserFiltersByTypeRecencyWorkflowAndAccount() {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(host: host, receiptStore: store)
        let referenceDate = Date(timeIntervalSince1970: 1_800_000)
        let visibleID = UUID()
        let oldID = UUID()
        let otherAccountID = UUID()
        let visibleReceipt = receipt(
            id: UUID(),
            kind: "tool.executed",
            payload: [
                "artifactID": .string(visibleID.uuidString),
                "account": .string("vault.eth")
            ],
            success: true,
            correlationID: "wf-visible"
        )
        let oldReceipt = receipt(
            id: UUID(),
            kind: "tool.executed",
            payload: [
                "artifactID": .string(oldID.uuidString),
                "account": .string("vault.eth")
            ],
            success: true,
            correlationID: "wf-old"
        )
        let otherAccountReceipt = receipt(
            id: UUID(),
            kind: "tool.executed",
            payload: [
                "artifactID": .string(otherAccountID.uuidString),
                "account": .string("other.eth")
            ],
            success: true,
            correlationID: "wf-other"
        )
        let researchBrief = SystemPlaybooks.all.first { $0.id == "research.brief" }
        let visible = artifact(
            id: visibleID,
            groupID: UUID(),
            type: .report,
            title: "Visible report",
            creatorPlaybookID: "research.brief",
            creatorOperatorID: "operator.research.brief",
            createdAt: referenceDate.addingTimeInterval(-60 * 60),
            relatedReceiptIDs: [visibleReceipt.id],
            approvalState: .approved,
            destination: "Mission Control",
            exportFormat: "markdown"
        )
        let old = artifact(
            id: oldID,
            groupID: UUID(),
            type: .report,
            title: "Old report",
            creatorPlaybookID: "research.brief",
            createdAt: referenceDate.addingTimeInterval(-40 * 24 * 60 * 60),
            relatedReceiptIDs: [oldReceipt.id]
        )
        let otherAccount = artifact(
            id: otherAccountID,
            groupID: UUID(),
            type: .codeFile,
            title: "Other account code",
            creatorOperatorID: "operator.code",
            createdAt: referenceDate.addingTimeInterval(-30 * 60),
            relatedReceiptIDs: [otherAccountReceipt.id]
        )

        model.seedForSnapshot(
            referenceDate: referenceDate,
            browserReceipts: [visibleReceipt, oldReceipt, otherAccountReceipt],
            artifacts: [otherAccount, old, visible],
            playbooks: researchBrief.map { [$0] } ?? [],
            workflowStepLogs: [
                WorkflowStepLog(
                    correlationID: "wf-visible",
                    toolID: "operator.research.brief",
                    event: .proposed(ActionProposal(
                        actor: .system,
                        intent: "Research Brief",
                        capability: .runPlugin,
                        impact: .readOnly,
                        correlationID: "wf-visible",
                        parameters: ["account": "vault.eth"]
                    )),
                    actor: .system
                )
            ]
        )

        #expect(model.artifactWorkflows.contains("Research Brief"))
        #expect(model.artifactAccounts.contains("vault.eth"))
        #expect(model.cardPresentation(for: visible).provenance.contains("Research Brief"))
        #expect(model.cardPresentation(for: visible).status == "approved")

        model.artifactTypeFilter = .report
        model.artifactRecencyFilter = .last7Days
        model.artifactWorkflowFilter = "Research Brief"
        model.artifactAccountFilter = "vault.eth"

        #expect(model.filteredArtifacts.map(\.title) == ["Visible report"])
    }

    @Test
    func artifactDetailMetadataResolvesApprovalsSourceWorkflowAndPlaybook() {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(host: host, receiptStore: store)
        let artifactID = UUID()
        let approvalReceipt = receipt(
            id: UUID(),
            kind: "approval.approved",
            payload: [
                "approvalID": .string("approval-1"),
                "artifactID": .string(artifactID.uuidString)
            ],
            success: true,
            correlationID: "wf-approval"
        )
        let artifact = artifact(
            id: artifactID,
            groupID: UUID(),
            type: .brief,
            title: "Approved brief",
            creatorPlaybookID: "research.brief",
            creatorOperatorID: "operator.research.brief",
            relatedReceiptIDs: [approvalReceipt.id],
            destination: "Shared exports",
            exportFormat: "markdown"
        )
        let playbook = SystemPlaybooks.all.first { $0.id == "research.brief" }

        model.seedForSnapshot(
            referenceDate: .now,
            browserReceipts: [approvalReceipt],
            artifacts: [artifact],
            playbooks: playbook.map { [$0] } ?? []
        )

        #expect(model.approvalReceipts(for: artifact).map(\.summary) == ["approval.approved"])
        #expect(model.artifactSourceCorrelationIDs(for: artifact) == ["wf-approval"])
        #expect(model.playbook(for: artifact)?.id == "research.brief")
        #expect(model.exportFormatLabel(for: artifact) == "markdown")
    }

    @Test
    func artifactExportPayloadsCoverEveryCoreTypeAndPreserveOrigin() {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(host: host, receiptStore: store)

        for type in ArtifactType.allCases {
            let artifact = artifact(
                id: UUID(),
                groupID: UUID(),
                type: type,
                title: "Export \(type.rawValue)",
                creatorOperatorID: "operator.export",
                destination: "Share sheet",
                exportFormat: nil,
                content: "body for \(type.rawValue)"
            )
            let payload = model.exportPayload(for: artifact)

            #expect(payload.contains("auralis://mission-control/artifacts") || payload.contains("auralis:\\/\\/mission-control\\/artifacts"))
            #expect(payload.contains(artifact.id.uuidString))
            #expect(payload.contains(type.rawValue))
            #expect(payload.contains("operator.export"))
            #expect(payload.contains(model.exportFormatLabel(for: artifact)))
        }
    }

    @Test
    func artifactExportFilesCoverEveryCoreTypeAndPreserveOrigin() throws {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(host: host, receiptStore: store)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MissionControlExportTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let expectations: [(ArtifactType, String?, String)] = [
            (.doc, nil, "md"),
            (.brief, nil, "md"),
            (.report, nil, "md"),
            (.jsonExport, nil, "json"),
            (.codeFile, "swift", "swift"),
            (.planChecklist, nil, "md")
        ]

        for (type, exportFormat, pathExtension) in expectations {
            let artifact = artifact(
                id: UUID(),
                groupID: UUID(),
                type: type,
                title: "Export: \(type.rawValue)",
                creatorOperatorID: "operator.export",
                destination: "Share sheet",
                exportFormat: exportFormat,
                content: "body for \(type.rawValue)"
            )

            let file = try model.exportFile(for: artifact, directory: directory)
            let text = try String(contentsOf: file.url, encoding: .utf8)

            #expect(file.url.pathExtension == pathExtension)
            #expect(file.filename.contains("export-\(type.rawValue.lowercased())"))
            #expect(text.contains("auralis://mission-control/artifacts") || text.contains("auralis:\\/\\/mission-control\\/artifacts"))
            #expect(text.contains(artifact.id.uuidString))
            #expect(text.contains(type.rawValue))
            #expect(text.contains("operator.export"))
            #expect(text.contains(model.exportFormatLabel(for: artifact)))
        }
    }

    @Test
    func artifactBrowserLoadsFullHistoryBeyondLatestWindow() async {
        let receiptStore = NoopReceiptStore()
        let artifactStore = InMemoryArtifactStore()
        let host = RuntimeHost(receiptStore: receiptStore, artifactStore: artifactStore)
        let model = MissionControlHomeModel(host: host, receiptStore: receiptStore)

        for index in 0..<105 {
            _ = await artifactStore.create(ArtifactDraft(
                type: .report,
                title: "Artifact \(index)",
                provenance: ArtifactProvenance(actor: .system),
                content: "body \(index)"
            ))
        }

        await model.loadArtifacts()

        #expect(model.artifactBrowserLoadedFullHistory == true)
        #expect(model.artifacts.count == 105)
    }

    @Test("artifact version failures preserve loaded history and surface degraded evidence")
    func artifactVersionFailuresPreserveHistory() async {
        let receiptStore = NoopReceiptStore()
        let groupID = UUID()
        let firstVersion = artifact(groupID: groupID, version: 1, title: "Version 1")
        let secondVersion = artifact(groupID: groupID, version: 2, title: "Version 2")
        let artifactStore = ControllableArtifactVersionStore(versions: [firstVersion])
        let host = RuntimeHost(receiptStore: receiptStore, artifactStore: artifactStore)
        let model = MissionControlHomeModel(host: host, receiptStore: receiptStore)

        await model.loadArtifactVersions(for: firstVersion)
        #expect(model.versions(for: firstVersion) == [firstVersion])
        #expect(model.artifactDataIssue == nil)

        await artifactStore.setVersions([firstVersion, secondVersion])
        await artifactStore.setVersionReadsFail(true)
        await model.loadArtifactVersions(for: firstVersion)

        #expect(model.versions(for: firstVersion) == [firstVersion])
        #expect(model.artifactDataIssue == "Artifact version history could not be loaded. Previously loaded versions remain visible.")

        await artifactStore.setVersionReadsFail(false)
        await model.loadArtifactVersions(for: firstVersion)

        #expect(model.versions(for: firstVersion) == [firstVersion, secondVersion])
        #expect(model.artifactDataIssue == nil)
    }

    @Test
    func coordinationLoadDerivesSyncQueueAndRitualSummaryFromSocialEventLog() async throws {
        let receiptStore = NoopReceiptStore()
        let eventLogStore = SocialEventLogStore()
        let host = RuntimeHost(receiptStore: receiptStore, socialEventLogStore: eventLogStore)
        let model = MissionControlHomeModel(host: host, receiptStore: receiptStore)
        let session = await host.sharedSessionStore.create(
            SharedSession(correlationID: "social-summary", title: "Shared", createdBy: .human)
        )
        let alice = SocialParticipantIdentity(
            participantID: "alice",
            caip10Account: "eip155:1:0xalice",
            displayName: "Alice",
            role: .collaborator,
            verificationState: .verified
        )
        await eventLogStore.saveInvite(SocialInvite(
            sessionID: session.id,
            relayTopic: "topic-a",
            encryptedSessionKey: "ciphertext",
            inviterParticipantID: "alice",
            expiresAt: Date(timeIntervalSince1970: 300),
            nonce: "nonce"
        ))
        // Alice authors her own join, which is what production does
        // (`SocialJoinVerificationService` and `RitualCoordinator` both set
        // `authorParticipantID` to the joining participant). A third-party author such as "system"
        // is rejected as `.mismatchedAuthor` by the Social v1 author-binding gate.
        //
        // These go in through `appendLocal`, not `appendInbound`, and that choice is the whole
        // reason the summary below is non-empty. A relay-delivered `.verified` identity is
        // *downgraded* to `.pending`, and `canAuthorBindingEvents` requires `.local` or
        // `.verified` — so over the wire Alice's queue proposal, snapshot, and ritual run are all
        // refused as `.unverifiedAuthor` and every count here reads zero. This test is about
        // Mission Control deriving a summary from a populated log, so it populates it the way
        // accepted events actually enter it. The withheld-over-the-wire case is SocialCore's to
        // pin, not this suite's.
        await eventLogStore.appendLocal(SocialEventEnvelope(
            sessionID: session.id,
            authorParticipantID: alice.participantID,
            authorCAIP10Account: alice.caip10Account,
            createdAt: Date(timeIntervalSince1970: 1),
            event: .participantJoined(alice)
        ))
        await eventLogStore.appendLocal(SocialEventEnvelope(
            sessionID: session.id,
            authorParticipantID: "alice",
            authorCAIP10Account: alice.caip10Account,
            createdAt: Date(timeIntervalSince1970: 2),
            event: .queueProposalCreated(SocialQueueProposal(
                mediaItemID: "track-1",
                title: "Track 1",
                proposedByParticipantID: "alice"
            ))
        ))
        await eventLogStore.appendLocal(SocialEventEnvelope(
            sessionID: session.id,
            authorParticipantID: "alice",
            authorCAIP10Account: alice.caip10Account,
            createdAt: Date(timeIntervalSince1970: 3),
            event: .queueSnapshotPublished(SocialQueueSnapshot(items: [
                SocialQueueItem(mediaItemID: "track-1", title: "Track 1")
            ]))
        ))
        await eventLogStore.appendLocal(SocialEventEnvelope(
            sessionID: session.id,
            authorParticipantID: "alice",
            authorCAIP10Account: alice.caip10Account,
            createdAt: Date(timeIntervalSince1970: 4),
            event: .ritualRunChanged(
                ritualID: "ritual.collaborative-listening",
                status: .completed,
                artifactIDs: [UUID()],
                receiptIDs: [UUID()]
            )
        ))
        let pending = await eventLogStore.enqueueOutbound(SocialEventEnvelope(
            sessionID: session.id,
            authorParticipantID: "alice",
            authorCAIP10Account: alice.caip10Account,
            createdAt: Date(timeIntervalSince1970: 5),
            event: .playlistShared("playlist-1")
        ))
        await eventLogStore.setSyncState(
            SocialSyncState(phase: .degraded, pendingOutboundCount: 1, lastErrorSummary: "offline"),
            for: session.id
        )

        await model.loadCoordination()

        let summary = try #require(model.coordinationSyncSummary(sessionID: session.id))
        #expect(summary.syncLabel == "Degraded")
        #expect(summary.pendingOutboundCount == 1)
        #expect(summary.queueItemCount == 1)
        #expect(summary.queueProposalCount == 1)
        #expect(summary.ritualRuns.first?.status == .completed)
        #expect((await eventLogStore.pendingOutbound()).map(\.id) == [pending.id])
    }

    @Test
    func artifactLookupResolvesSupersededVersionOriginIDs() async throws {
        let receiptStore = NoopReceiptStore()
        let artifactStore = InMemoryArtifactStore()
        let host = RuntimeHost(receiptStore: receiptStore, artifactStore: artifactStore)
        let model = MissionControlHomeModel(host: host, receiptStore: receiptStore)
        let first = await artifactStore.create(ArtifactDraft(
            type: .planChecklist,
            title: "Launch plan",
            provenance: ArtifactProvenance(actor: .system),
            content: "Draft checklist"
        ))
        _ = await artifactStore.addVersion(toGroup: first.groupID, ArtifactDraft(
            type: .planChecklist,
            title: "Launch plan",
            provenance: ArtifactProvenance(actor: .system),
            content: "Approved checklist"
        ))

        await model.loadArtifacts()

        #expect(model.artifacts.map(\.version) == [2])
        let routedArtifact = try #require(model.artifact(id: first.id))
        #expect(routedArtifact.id == first.id)
        #expect(routedArtifact.approvalState == .superseded)
    }

    @Test
    func preparingArtifactExportFileDoesNotRecordExportLifecycle() throws {
        let receiptStore = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: receiptStore)
        let model = MissionControlHomeModel(host: host, receiptStore: receiptStore)
        let draft = artifact(
            type: .brief,
            title: "Prepared brief",
            approvalState: .approved,
            content: "ready"
        )

        let file = try model.exportFile(for: draft)
        defer { try? FileManager.default.removeItem(at: file.url) }

        #expect(file.artifact.id == draft.id)
        #expect(file.preview.contains("State: approved"))
        #expect(file.preview.contains("Destination:") == false)
    }

    @Test
    func artifactLifecycleActionsPersistStateAndReceipts() async throws {
        let receiptStore = NoopReceiptStore()
        let artifactStore = InMemoryArtifactStore()
        let host = RuntimeHost(receiptStore: receiptStore, artifactStore: artifactStore)
        let model = MissionControlHomeModel(host: host, receiptStore: receiptStore)
        let artifact = await artifactStore.create(ArtifactDraft(
            type: .brief,
            title: "Lifecycle brief",
            provenance: ArtifactProvenance(actor: .system),
            content: "draft"
        ))

        _ = try await model.approveArtifact(artifact)
        #expect(await artifactStore.get(id: artifact.id)?.approvalState == .approved)

        let approved = await artifactStore.get(id: artifact.id) ?? artifact
        _ = try await model.markArtifactExported(approved)
        let exported = await artifactStore.get(id: artifact.id)

        #expect(exported?.approvalState == .exported)
        #expect(exported?.destination == "Share sheet")
        #expect(exported?.exportFormat == "markdown")
        #expect(model.exportPreview(for: artifact).contains("State: exported"))
        #expect(model.exportPreview(for: artifact).contains("Destination: Share sheet"))
        let receiptKinds = (await receiptStore.appendedRecords()).map(\.trigger)
        #expect(receiptKinds.contains("artifact.approved"))
        #expect(receiptKinds.contains("artifact.exported"))
    }

    @Test
    func artifactComparisonShowsActualContentDiff() {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(host: host, receiptStore: store)
        let groupID = UUID()
        let first = artifact(
            groupID: groupID,
            version: 1,
            title: "Plan",
            content: "Keep wallet read-only\nDraft checklist"
        )
        let second = artifact(
            groupID: groupID,
            version: 2,
            title: "Plan",
            content: "Keep wallet read-only\nApprove checklist\nExport summary"
        )

        let rows = model.comparisonRows(for: [first, second])

        #expect(rows.contains { $0.label == "Content line diff" && $0.risk == "+1 / -0 / changed 1" })
        #expect(rows.contains { $0.label == "First content change" && $0.before == "Draft checklist" && $0.after == "Approve checklist" })
    }

    // MARK: - P1-203 Policy Summary Cards

    @Test
    func policyOutcomeCardsTagHardVsSemantic() async {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(host: host, receiptStore: store)
        _ = try? await store.append(ReceiptDraft(
            category: "runtime", kind: "tool.blocked",
            correlationID: nil,
            payload: ReceiptPayload(values: ["reason": .string("Observe mode")]),
            actorDetail: .system, authorityDetail: nil, summary: "Blocked: sign", provenance: "crypto", isSuccess: false
        ))
        _ = try? await store.append(ReceiptDraft(
            category: "runtime", kind: "tool.needsApproval",
            correlationID: nil,
            payload: ReceiptPayload(values: ["reason": .string("Needs human sign-off")]),
            actorDetail: .system, authorityDetail: nil, summary: "Awaiting approval: spend", provenance: "crypto", isSuccess: true
        ))
        await model.loadReceipts()
        let cards = model.policyOutcomeCards
        #expect(cards.contains { $0.status == .blocked && $0.kind == .hard })
        #expect(cards.contains { $0.status == .escalated && $0.kind == .semantic })
    }

    /// The summary classifies every emitted governed outcome via the shared taxonomy, so the tally can't
    /// silently read zero if a `kind` string drifts, and `failed`/`needsRevision` are handled deliberately.
    @Test
    func policySummaryClassifiesEveryGovernedOutcomeViaSharedTaxonomy() async {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(host: host, receiptStore: store)

        func append(_ outcome: GovernedOutcomeKind, success: Bool) async {
            _ = try? await store.append(ReceiptDraft(
                category: GovernedReceiptTaxonomy.category,
                kind: GovernedReceiptTaxonomy.toolKind(outcome),
                correlationID: nil,
                payload: ReceiptPayload(values: ["reason": .string("r")]),
                actorDetail: .system, authorityDetail: nil, summary: outcome.rawValue, provenance: "local", isSuccess: success
            ))
        }
        await append(.executed, success: true)
        await append(.blocked, success: false)
        await append(.needsApproval, success: true)
        await append(.needsRevision, success: true)
        await append(.failed, success: false)
        await model.loadReceipts()

        let summary = model.policySummary
        #expect(summary.allowed == 1)
        #expect(summary.blocked == 1)
        // needsApproval + needsRevision are both semantic escalations.
        #expect(summary.escalated == 2)
        // A runtime failure is not a policy decision, so it lands in no bucket and produces no card.
        #expect(summary.allowed + summary.blocked + summary.escalated == 4)
        #expect(model.policyOutcomeCards.allSatisfy { $0.status != .allowed })
    }

    // MARK: - P1-204 Kill Switch / Pause

    @Test
    func pauseRecordsReasonAndResumeClearsIt() async {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(host: host, receiptStore: store)
        #expect(model.pauseReason == nil)
        await model.setPaused(true)
        #expect(model.pauseReason != nil)
        await model.resumeOperator()
        #expect(model.isPaused == false)
        #expect(model.pauseReason == nil)
    }

    @Test
    func activityFeedGroupsAndCategorizes() {
        #expect(MissionControlHomeModel.category(for: .approvalRequired(ApprovalRequest(
            proposal: ActionProposal(actor: .system, intent: "x", capability: .runPlugin, impact: .readOnly),
            prompt: "?"
        ))) == .approvalNeeded)
        #expect(MissionControlHomeModel.category(for: .artifactCreated(id: UUID())) == .completed)
        #expect(MissionControlHomeModel.category(for: .workflowStarted) == .observation)
        #expect(MissionControlHomeModel.category(for: .checkFailed(id: "c", reason: "r")) == .preparation)
        // executionUpdate is noise, filtered out of the high-signal feed.
        #expect(MissionControlHomeModel.isHighSignal(.executionUpdate("hi")) == false)
        #expect(MissionControlHomeModel.isHighSignal(.workflowStarted) == true)
    }

    /// A blocked step must never be filed under "Completed", whatever its reason text says. The
    /// deterministic-check gate (`AuralisRuntime.Judge`) blocks with the reason "Check failed (<id>)",
    /// so a classifier that keyed off the word "failed" put the system's most common block in the
    /// completed bucket.
    @Test
    func blockedWorkflowsAreNeverCategorizedAsCompleted() {
        let blockReasons = [
            "Check failed (address.format): not checksummed",
            "Check failed (balance.sufficient)",
            "State-changing actions are not available in Observe mode.",
            "“Approve Spending” is not available in Observe mode.",
            "Routine blocked"
        ]
        for reason in blockReasons {
            #expect(
                MissionControlHomeModel.category(for: .workflowBlocked(reason: reason)) == .preparation,
                "block reason \"\(reason)\" should categorize as preparation"
            )
        }
    }

    /// `receipts(for:)` answers from a memoized artifact index rather than rescanning every receipt.
    /// It must stay identical to the linear scan it replaced — same records, same order — across both
    /// legs: receipts that name the artifact in their payload, and receipts the artifact points back at.
    @Test
    func artifactReceiptLookupMatchesLinearScanIncludingOrder() {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(host: host, receiptStore: store)

        let artifactID = UUID()
        let backReferencedID = UUID()
        let payloadReceiptA = receipt(
            kind: "tool.executed",
            payload: ["artifactIDs": .array([.string(artifactID.uuidString)])],
            success: true
        )
        let unrelated = receipt(kind: "tool.executed", payload: ["note": .string("n")], success: true)
        let backReferenced = receipt(
            id: backReferencedID,
            kind: "artifact.approved",
            payload: ["note": .string("n")],
            success: true
        )
        let payloadReceiptB = receipt(
            kind: "tool.executed",
            payload: ["artifactIDs": .array([.string(artifactID.uuidString)])],
            success: true
        )
        // Deliberately interleaved so an ordering regression in the merge is observable.
        let browsed = [payloadReceiptA, unrelated, backReferenced, payloadReceiptB]
        let subject = artifact(id: artifactID, title: "Indexed", relatedReceiptIDs: [backReferencedID])

        model.seedForSnapshot(referenceDate: .now, browserReceipts: browsed, artifacts: [subject])

        let expected = browsed.filter { candidate in
            model.artifactIDs(from: candidate).contains(artifactID)
                || subject.relatedReceiptIDs.contains(candidate.id)
        }
        #expect(model.receipts(for: subject).map(\.id) == expected.map(\.id))
        #expect(model.receipts(for: subject).count == 3)
        // Repeat reads come from the cache and must not drift.
        #expect(model.receipts(for: subject).map(\.id) == expected.map(\.id))
    }

    /// The artifact index describes the browsed set as a whole, so replacing that set must invalidate
    /// it. A stale index would keep reporting provenance from receipts that are no longer loaded.
    @Test
    func artifactReceiptIndexInvalidatesWhenBrowsedSetIsReplaced() {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(host: host, receiptStore: store)

        let artifactID = UUID()
        let subject = artifact(id: artifactID, title: "Reindexed")
        let first = receipt(
            kind: "tool.executed",
            payload: ["artifactIDs": .array([.string(artifactID.uuidString)])],
            success: true
        )

        model.seedForSnapshot(referenceDate: .now, browserReceipts: [first], artifacts: [subject])
        #expect(model.receipts(for: subject).map(\.id) == [first.id])

        let replacement = receipt(
            kind: "tool.executed",
            payload: ["artifactIDs": .array([.string(artifactID.uuidString)])],
            success: true
        )
        model.seedForSnapshot(referenceDate: .now, browserReceipts: [replacement], artifacts: [subject])
        #expect(model.receipts(for: subject).map(\.id) == [replacement.id])

        model.seedForSnapshot(referenceDate: .now, browserReceipts: [], artifacts: [subject])
        #expect(model.receipts(for: subject).isEmpty)
    }

    /// `workflowSummaries` is memoized; the memo must not outlive the worklog it was derived from.
    @Test
    func workflowSummariesMemoInvalidatesWhenTheWorklogChanges() {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(host: host, receiptStore: store)

        func proposedStep(_ correlationID: String, at timestamp: Date) -> WorkflowStepLog {
            WorkflowStepLog(
                correlationID: correlationID,
                toolID: "tool",
                event: .proposed(
                    ActionProposal(actor: .system, intent: correlationID, capability: .audioPlayback, impact: .readOnly)
                ),
                actor: .system,
                timestamp: timestamp
            )
        }

        model.seedForSnapshot(referenceDate: .now, workflowStepLogs: [proposedStep("corr-1", at: .now)])
        #expect(model.workflowSummaries.map(\.id) == ["corr-1"])

        model.seedForSnapshot(
            referenceDate: .now,
            workflowStepLogs: [
                proposedStep("corr-1", at: .now),
                proposedStep("corr-2", at: .now.addingTimeInterval(1))
            ]
        )
        #expect(Set(model.workflowSummaries.map(\.id)) == ["corr-1", "corr-2"])
        #expect(model.workflowSummariesByID.keys.sorted() == ["corr-1", "corr-2"])
    }

    private func receipt(
        id: UUID = UUID(),
        kind: String,
        payload: [String: ReceiptJSONValue],
        success: Bool,
        correlationID: String? = nil
    ) -> ReceiptRecord {
        ReceiptRecord(
            id: id,
            sequenceID: 1,
            createdAt: .now,
            actor: .system,
            actorDetail: .system,
            authorityDetail: nil,
            mode: .observe,
            trigger: kind,
            scope: "runtime",
            summary: kind,
            provenance: "test",
            isSuccess: success,
            correlationID: correlationID,
            details: ReceiptPayload(values: payload)
        )
    }

    private func artifact(
        id: UUID = UUID(),
        groupID: UUID = UUID(),
        version: Int = 1,
        type: ArtifactType = .report,
        title: String,
        creatorPlaybookID: String? = nil,
        creatorOperatorID: String? = "test.operator",
        createdAt: Date = .now,
        provenance: ArtifactProvenance = ArtifactProvenance(actor: .system),
        relatedReceiptIDs: [UUID] = [],
        approvalState: ArtifactApprovalState = .draft,
        destination: String? = nil,
        exportFormat: String? = nil,
        content: String = "Fixture"
    ) -> Artifact {
        Artifact(
            id: id,
            groupID: groupID,
            version: version,
            type: type,
            title: title,
            creatorPlaybookID: creatorPlaybookID,
            creatorOperatorID: creatorOperatorID,
            createdAt: createdAt,
            provenance: provenance,
            relatedReceiptIDs: relatedReceiptIDs,
            approvalState: approvalState,
            destination: destination,
            exportFormat: exportFormat,
            content: content
        )
    }
}

private actor FailingPlaybookStore: PlaybookStore {
    private struct StoreUnavailable: LocalizedError {
        var errorDescription: String? { "The playbook database is unavailable." }
    }

    func all() throws -> [Playbook] { throw StoreUnavailable() }
    func playbook(id: String) throws -> Playbook? { throw StoreUnavailable() }
    func playbooks(inState state: PlaybookInstallState) throws -> [Playbook] { throw StoreUnavailable() }
    func upsert(_ playbook: Playbook) throws { throw StoreUnavailable() }
    func setInstallState(id: String, to state: PlaybookInstallState) throws { throw StoreUnavailable() }
}

@Suite("InferenceSnapshot model hops")
@MainActor
struct InferenceSnapshotModelHopsTests {
    private func telemetryReceipt(correlationID: String, at date: Date) -> ReceiptRecord {
        ReceiptRecord(
            id: UUID(),
            sequenceID: 1,
            createdAt: date,
            actor: .system,
            actorDetail: .system,
            authorityDetail: nil,
            mode: .assist,
            trigger: "autopilot.step.ran",
            scope: "autopilot",
            summary: "Step ran",
            provenance: "autopilot",
            isSuccess: true,
            correlationID: correlationID,
            details: ReceiptPayload(values: [
                "modelProvider": .string("Apple Foundation Models"),
                "inferenceLocality": .string(InferenceLocality.local.rawValue),
                "promptTokens": .string("10"),
                "completionTokens": .string("4")
            ])
        )
    }

    @Test
    func countsOneHopPerTelemetryReceipt() {
        let receipts = [
            telemetryReceipt(correlationID: "c1", at: .now),
            telemetryReceipt(correlationID: "c1", at: .now.addingTimeInterval(1))
        ]
        let snapshot = MissionControlHomeModel.inferenceSnapshot(from: receipts)
        #expect(snapshot.modelHops == 2)
        #expect(snapshot.modelHopsLabel == "2 hops")
    }

    @Test
    func reconcilesSessionAndReceiptsWithoutUndercounting() {
        // Autopilot increments the session's hop counter directly; take the larger so an operator run
        // that only stamped receipts (never touching the session counter) still counts.
        var session = AgentSession(correlationID: "c1", goal: "g", actor: .system)
        session.note(model: "on-device") // 1 session hop, no receipt
        let receipts = [telemetryReceipt(correlationID: "c1", at: .now)] // 1 receipt hop
        let snapshot = MissionControlHomeModel.inferenceSnapshot(from: receipts, session: session)
        #expect(snapshot.modelHops == 1) // max(1, 1), not summed
    }

    @Test
    func noTelemetryReadsAsNotRecorded() {
        let snapshot = MissionControlHomeModel.inferenceSnapshot(from: [])
        #expect(snapshot.modelHops == 0)
        #expect(snapshot.modelHopsLabel == "Not recorded")
    }

    /// A deterministic local data read (usesInference == false) carries a route for provenance but is
    /// not a model invocation, so it must not count as a hop or populate the AI telemetry aggregate.
    private func dataReadReceipt(correlationID: String, at date: Date) -> ReceiptRecord {
        ReceiptRecord(
            id: UUID(),
            sequenceID: 1,
            createdAt: date,
            actor: .system,
            actorDetail: .system,
            authorityDetail: nil,
            mode: .observe,
            trigger: "operator.onChainWatch.ran",
            scope: "operator",
            summary: "Ledger read",
            provenance: "operator",
            isSuccess: true,
            correlationID: correlationID,
            details: ReceiptPayload(values: [
                "modelProvider": .string("Local ledger"),
                "modelClass": .string("on-device-indexer"),
                "inferenceLocality": .string(InferenceLocality.local.rawValue),
                "durationSeconds": .string("0.4"),
                "promptTokens": .string("0"),
                "completionTokens": .string("0"),
                "usesInference": .string("false")
            ])
        )
    }

    @Test
    func dataReadReceiptIsNotCountedAsModelHop() {
        let snapshot = MissionControlHomeModel.inferenceSnapshot(from: [dataReadReceipt(correlationID: "c1", at: .now)])
        #expect(snapshot.modelHops == 0)
        #expect(snapshot.modelHopsLabel == "Not recorded")
        // Provider/locality from a pure data read must not leak into the AI telemetry surface.
        #expect(snapshot.provider == nil)
        #expect(snapshot.locality == nil)
    }

    @Test
    func dataReadDoesNotDiluteRealInferenceHops() {
        // A real inference plus a data read in the same session still reads as one model hop.
        let receipts = [
            telemetryReceipt(correlationID: "c1", at: .now),
            dataReadReceipt(correlationID: "c1", at: .now.addingTimeInterval(1))
        ]
        let snapshot = MissionControlHomeModel.inferenceSnapshot(from: receipts)
        #expect(snapshot.modelHops == 1)
    }

    @Test
    func aReceiptPresentInTwoWindowsIsAggregatedOnce() {
        // Guards the aggregate itself: the same receipt ID handed in twice must not double its sums.
        let receipt = telemetryReceipt(correlationID: "c1", at: .now)
        let snapshot = MissionControlHomeModel.inferenceSnapshot(from: [receipt, receipt])
        #expect(snapshot.modelHops == 1)
        #expect(snapshot.promptTokens == 10)
        #expect(snapshot.completionTokens == 4)
    }

    #if DEBUG
    /// The Context Bundle Inspector reads `contextInferenceSnapshot`, which sums the newest-N window
    /// and the full export of the *same* store. Those overlap by design, so the telemetry it shows must
    /// match what one pass over the distinct receipts reports — an inflated token count misstates a
    /// measurement just as badly as reporting one that never happened.
    @Test
    func contextSnapshotDoesNotDoubleCountOverlappingReceiptWindows() {
        let store = NoopReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        let model = MissionControlHomeModel(host: host, receiptStore: store)

        let newest = telemetryReceipt(correlationID: "c1", at: .now)
        let older = telemetryReceipt(correlationID: "c1", at: .now.addingTimeInterval(-60))
        // `browserReceipts` is the full export; `recentReceipts` is the newest window of the same store.
        model.seedForSnapshot(
            referenceDate: .now,
            recentReceipts: [newest],
            browserReceipts: [newest, older]
        )

        let snapshot = model.contextInferenceSnapshot
        #expect(snapshot.modelHops == 2)
        #expect(snapshot.promptTokens == 20)
        #expect(snapshot.completionTokens == 8)
    }
    #endif
}

/// P0.5-701/702 — the worklog is only useful off-device if the byte-stable snapshot can actually be
/// carried somewhere. These cover the two export call sites Mission Control exposes.
@Suite("Worklog trace export")
@MainActor
struct WorklogTraceExportTests {
    private func step(_ correlationID: String?, intent: String, at timestamp: Date) -> WorkflowStepLog {
        WorkflowStepLog(
            correlationID: correlationID,
            toolID: "tool",
            event: .proposed(
                ActionProposal(actor: .system, intent: intent, capability: .audioPlayback, impact: .readOnly)
            ),
            actor: .system,
            timestamp: timestamp
        )
    }

    private func makeModel(steps: [WorkflowStepLog]) async -> MissionControlHomeModel {
        let store = NoopReceiptStore()
        let worklog = InMemoryWorklog()
        for step in steps {
            await worklog.record(step)
        }
        let host = RuntimeHost(receiptStore: store, worklogStore: worklog)
        return MissionControlHomeModel(host: host, receiptStore: store)
    }

    private func scratchDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("worklog-export-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    @Test
    func fullTraceExportWritesEveryEntryAcrossWorkflows() async throws {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let model = await makeModel(steps: [
            step("corr-1", intent: "Read one", at: base),
            step("corr-1", intent: "Read two", at: base.addingTimeInterval(1)),
            step("corr-2", intent: "Read three", at: base.addingTimeInterval(2))
        ])
        let directory = scratchDirectory()

        let file = try await model.exportWorklogTraceFile(directory: directory)

        #expect(file.stepCount == 3)
        #expect(file.workflowCount == 2)
        #expect(file.byteCount > 0)
        let written = try Data(contentsOf: file.url)
        let decoded = try JSONDecoder().decode([WorkflowStepLog].self, from: written)
        #expect(decoded.count == 3)
        // Oldest first, so a diff between two exports lines up entry for entry.
        #expect(decoded.map(\.timestamp) == decoded.map(\.timestamp).sorted())
    }

    /// The whole point of routing exports through `exportAll()` is that the same trace exports to the
    /// same bytes — otherwise two eval runs can't be diffed.
    @Test
    func repeatedFullTraceExportIsByteStable() async throws {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let model = await makeModel(steps: [
            step("corr-1", intent: "Read one", at: base),
            step("corr-2", intent: "Read two", at: base.addingTimeInterval(1))
        ])

        let first = try await model.exportWorklogTraceFile(directory: scratchDirectory())
        let second = try await model.exportWorklogTraceFile(directory: scratchDirectory())

        #expect(try Data(contentsOf: first.url) == (try Data(contentsOf: second.url)))
    }

    /// Exports are plaintext copies of governed data written where the share sheet can reach them.
    /// They were never removed, so every export a person ever opened accumulated in the temp
    /// directory until the OS chose to reclaim it.
    @Test("abandoned exports are swept, and a just-written one is not")
    func abandonedExportsArePruned() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("MissionControlExportSweepTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        let abandoned = directory.appendingPathComponent("abandoned.json")
        let justShared = directory.appendingPathComponent("just-shared.json")
        try Data("old".utf8).write(to: abandoned)
        try Data("new".utf8).write(to: justShared)
        let now = Date()
        try fileManager.setAttributes(
            [.modificationDate: now.addingTimeInterval(-(MissionControlExportSweep.retentionWindow + 60))],
            ofItemAtPath: abandoned.path
        )

        MissionControlExportSweep.pruneAbandonedExports(in: directory, now: now, fileManager: fileManager)

        #expect(!fileManager.fileExists(atPath: abandoned.path))
        // A file handed to an open share sheet is never pulled out from under it.
        #expect(fileManager.fileExists(atPath: justShared.path))
    }

    @Test
    func workflowScopedExportCarriesOnlyThatWorkflow() async throws {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let model = await makeModel(steps: [
            step("corr-1", intent: "Keep one", at: base),
            step("corr-1", intent: "Keep two", at: base.addingTimeInterval(1)),
            step("corr-2", intent: "Drop me", at: base.addingTimeInterval(2))
        ])

        let file = try await model.exportWorklogTraceFile(
            forCorrelationID: "corr-1",
            directory: scratchDirectory()
        )

        #expect(file.stepCount == 2)
        #expect(file.workflowCount == 1)
        let decoded = try JSONDecoder().decode([WorkflowStepLog].self, from: try Data(contentsOf: file.url))
        #expect(decoded.allSatisfy { $0.correlationID == "corr-1" })
    }

    /// Sharing an empty `[]` file reads as "there is no history" rather than "nothing has run yet".
    @Test
    func emptyTraceRefusesToExport() async throws {
        let model = await makeModel(steps: [])

        await #expect(throws: MissionControlWorklogExportError.emptyTrace) {
            try await model.exportWorklogTraceFile(directory: scratchDirectory())
        }
    }

    @Test
    func unknownWorkflowRefusesToExport() async throws {
        let model = await makeModel(steps: [
            step("corr-1", intent: "Read", at: Date(timeIntervalSince1970: 1_800_000_000))
        ])

        await #expect(throws: MissionControlWorklogExportError.workflowNotFound("corr-missing")) {
            try await model.exportWorklogTraceFile(
                forCorrelationID: "corr-missing",
                directory: scratchDirectory()
            )
        }
    }

    /// Filenames are timestamped from the model's reference date so successive exports don't overwrite
    /// each other and each file names the point in time it captured.
    @Test
    func exportFilenamesAreScopedAndTimestamped() async throws {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let model = await makeModel(steps: [step("corr-1", intent: "Read", at: base)])
        model.referenceDate = base

        let full = try await model.exportWorklogTraceFile(directory: scratchDirectory())
        let scoped = try await model.exportWorklogTraceFile(
            forCorrelationID: "corr-1",
            directory: scratchDirectory()
        )

        let stamp = MissionControlWorklogExportFileBuilder.traceFilename(generatedAt: base)
        #expect(full.filename == stamp)
        #expect(full.filename.hasSuffix(".json"))
        #expect(scoped.filename.hasPrefix("worklog-corr-1-"))
        #expect(scoped.filename.hasSuffix(".json"))
    }
}
@MainActor
@Suite("Operator watchlist persistence")
struct OperatorWatchlistPersistenceTests {
    private final class FailingStore: OperatorWatchlistStoring {
        var savedTargets: [WatchTarget] = []

        func load(identityID: String?) throws -> [WatchTarget] {
            savedTargets
        }

        func save(_ targets: [WatchTarget], identityID: String?) throws {
            throw OperatorWatchlistStoreError.encodingFailed
        }
    }

    @Test
    func watchlistsPersistAndRemainIdentityScoped() throws {
        let suiteName = "OperatorWatchlistPersistenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsOperatorWatchlistStore(defaults: defaults, keyPrefix: "test.watchlist")
        let first = WatchTarget(chain: "ethereum", address: "0x0000000000000000000000000000000000000001")
        let second = WatchTarget(chain: "ethereum", address: "0x0000000000000000000000000000000000000002")

        try store.save([first], identityID: "identity-a")
        try store.save([second], identityID: "identity-b")

        #expect(try store.load(identityID: "IDENTITY-A") == [first])
        #expect(try store.load(identityID: "identity-b") == [second])
        #expect(try store.load(identityID: nil).isEmpty)
    }

    @Test
    func corruptedWatchlistIsReportedInsteadOfReadingAsEmpty() throws {
        let suiteName = "OperatorWatchlistPersistenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("not-json".utf8), forKey: "test.watchlist.identity-a")
        let store = UserDefaultsOperatorWatchlistStore(defaults: defaults, keyPrefix: "test.watchlist")

        #expect(throws: OperatorWatchlistStoreError.corruptedData) {
            try store.load(identityID: "identity-a")
        }
    }

    @Test
    func failedSaveRollsBackTheVisibleWatchlistAndSurfacesDataQuality() {
        let store = FailingStore()
        let receiptStore = NoopReceiptStore()
        let model = MissionControlHomeModel(
            host: RuntimeHost(receiptStore: receiptStore),
            receiptStore: receiptStore,
            operatorWatchlistStore: store
        )
        model.operatorWatchAddressInput = "0x0000000000000000000000000000000000000001"

        model.addOperatorWatchTarget()

        #expect(model.operatorWatchlist.isEmpty)
        #expect(model.operatorWatchAddressInput.isEmpty == false)
        #expect(model.operatorWatchlistDataIssue != nil)
        #expect(model.dataQualityIssues.contains { $0.contains("not saved") })
    }
}
