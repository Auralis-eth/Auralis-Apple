import ArtifactCore
import AuralisPrimaryModels
import Foundation
import AuralisRuntime
import PolicyCore
import ReceiptsCore
@testable import RuntimeKit
import SocialCore
import Testing

/// Minimal in-memory ReceiptStore for verifying the sink appends.
private actor SpyReceiptStore: ReceiptStore {
    private(set) var drafts: [ReceiptDraft] = []

    func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord {
        drafts.append(receipt)
        return ReceiptRecord(
            id: UUID(), sequenceID: drafts.count, createdAt: receipt.createdAt,
            actor: receipt.actor, actorDetail: receipt.actorDetail, authorityDetail: receipt.authorityDetail, mode: receipt.mode, trigger: receipt.trigger,
            scope: receipt.scope, summary: receipt.summary, provenance: receipt.provenance,
            isSuccess: receipt.isSuccess, correlationID: receipt.correlationID, details: receipt.details
        )
    }
    func latest(limit: Int) async throws -> [ReceiptRecord] { [] }
    func receipts(forCorrelationID correlationID: String, limit: Int) async throws -> [ReceiptRecord] { [] }
    func exportAll() async throws -> Data { Data() }
    func resetAll() async throws { }

    func appendedDrafts() -> [ReceiptDraft] { drafts }
}

private struct FailingReceiptStore: ReceiptStore {
    struct Failure: LocalizedError {
        var errorDescription: String? { "durable receipt append failed" }
    }

    func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord { throw Failure() }
    func latest(limit: Int) async throws -> [ReceiptRecord] { [] }
    func receipts(forCorrelationID correlationID: String, limit: Int) async throws -> [ReceiptRecord] { [] }
    func exportAll() async throws -> Data { Data() }
    func resetAll() async throws { }
}

/// Fails the first `failuresBeforeSuccess` appends, then behaves normally — the shape of a store
/// that was briefly unavailable and recovered.
private actor RecoveringReceiptStore: ReceiptStore {
    struct Failure: LocalizedError {
        var errorDescription: String? { "durable receipt append failed" }
    }

    private var remainingFailures: Int
    private var appended = 0

    init(failuresBeforeSuccess: Int) {
        remainingFailures = failuresBeforeSuccess
    }

    func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord {
        if remainingFailures > 0 {
            remainingFailures -= 1
            throw Failure()
        }
        appended += 1
        return ReceiptRecord(
            id: UUID(), sequenceID: appended, createdAt: receipt.createdAt,
            actor: receipt.actor, actorDetail: receipt.actorDetail,
            authorityDetail: receipt.authorityDetail, mode: receipt.mode, trigger: receipt.trigger,
            scope: receipt.scope, summary: receipt.summary, provenance: receipt.provenance,
            isSuccess: receipt.isSuccess, correlationID: receipt.correlationID, details: receipt.details
        )
    }
    func latest(limit: Int) async throws -> [ReceiptRecord] { [] }
    func receipts(forCorrelationID correlationID: String, limit: Int) async throws -> [ReceiptRecord] { [] }
    func exportAll() async throws -> Data { Data() }
    func resetAll() async throws { }
}

@Suite("ReceiptStoreSink")
struct ReceiptStoreSinkTests {
    @Test("runtime receipt failure is exposed and emits degraded-evidence activity")
    @MainActor
    func runtimeReceiptFailureIsVisible() async {
        let host = RuntimeHost(receiptStore: FailingReceiptStore())
        let correlationID = "receipt-failure-test"
        let receipt = await host.appendRuntimeReceipt(
            ReceiptDraft(
                category: "routine",
                kind: "routine.success",
                correlationID: correlationID,
                payload: ReceiptPayload(values: [:]),
                actorDetail: .system,
                authorityDetail: nil,
                summary: "Routine completed",
                provenance: "routine",
                isSuccess: true
            ),
            goal: "Test receipt failure",
            actor: .system
        )
        let events = await host.recentEvents(limit: 10)

        #expect(receipt == nil)
        #expect(host.receiptPersistenceError == "A runtime receipt could not be saved. Audit evidence is incomplete.")
        #expect(events.contains { envelope in
            guard envelope.correlationID == correlationID,
                  case let .executionUpdate(message) = envelope.event else { return false }
            return message.contains("Audit evidence is incomplete")
        })
    }

    /// The degraded-evidence banner is sticky. A later receipt succeeding does not bring the missing
    /// one back, so it must not clear the signal — it previously did, and the banner disappeared as
    /// soon as any unrelated receipt was written while the gap in the ledger was permanent.
    @Test("a later successful receipt does not clear the degraded-evidence banner")
    @MainActor
    func degradedEvidenceBannerIsSticky() async {
        let host = RuntimeHost(receiptStore: RecoveringReceiptStore(failuresBeforeSuccess: 2))

        for index in 0..<2 {
            _ = await host.appendRuntimeReceipt(
                Self.draft(correlationID: "sticky-\(index)"),
                goal: "Test receipt failure",
                actor: .system
            )
        }
        #expect(host.receiptPersistenceError != nil)
        #expect(host.missingReceiptCount == 2)

        // The store has recovered; this one lands.
        let recovered = await host.appendRuntimeReceipt(
            Self.draft(correlationID: "sticky-recovered"),
            goal: "Test receipt recovery",
            actor: .system
        )
        #expect(recovered != nil)
        #expect(host.receiptPersistenceError != nil, "a success must not erase evidence that is still missing")
        #expect(host.missingReceiptCount == 2)

        // Only an explicit acknowledgement dismisses it.
        host.acknowledgeReceiptPersistenceFailure()
        #expect(host.receiptPersistenceError == nil)
        #expect(host.missingReceiptCount == 0)
    }

    private static func draft(correlationID: String) -> ReceiptDraft {
        ReceiptDraft(
            category: "routine",
            kind: "routine.success",
            correlationID: correlationID,
            payload: ReceiptPayload(values: [:]),
            actorDetail: .system,
            authorityDetail: nil,
            summary: "Routine completed",
            provenance: "routine",
            isSuccess: true
        )
    }

    @Test
    func appendFailurePropagatesToGovernedPipeline() async {
        let sink = ReceiptStoreSink(store: FailingReceiptStore())
        let proposal = ActionProposal(
            actor: .system,
            intent: "organize",
            capability: .playlistManagement,
            impact: .reversibleWrite
        )

        await #expect(throws: FailingReceiptStore.Failure.self) {
            try await sink.emit(GovernedReceipt(
                proposal: proposal,
                toolID: "organize",
                outcome: .executed
            ))
        }
    }

    @Test
    func executedReceiptIsAppendedAsSuccess() async throws {
        let store = SpyReceiptStore()
        let sink = ReceiptStoreSink(store: store)
        let proposal = ActionProposal(actor: .system, intent: "organize", capability: .playlistManagement, impact: .reversibleWrite)

        try await sink.emit(GovernedReceipt(proposal: proposal, toolID: "organize", outcome: .executed, artifactID: UUID()))

        let drafts = await store.appendedDrafts()
        #expect(drafts.count == 1)
        #expect(drafts.first?.isSuccess == true)
        #expect(drafts.first?.trigger == "tool.executed")
        #expect(drafts.first?.provenance == "local")
    }

    @Test
    func executedReceiptPersistsArtifactOutputFields() async throws {
        let store = SpyReceiptStore()
        let sink = ReceiptStoreSink(store: store)
        let proposal = ActionProposal(actor: .system, intent: "research", capability: .runPlugin, impact: .readOnly)

        try await sink.emit(GovernedReceipt(
            proposal: proposal,
            toolID: "operator.research.brief",
            outcome: .executed,
            outputFields: [
                "modelProvider": "Example Cloud",
                "modelClass": "cloud-lm",
                "inferenceLocality": "remote",
                "privacyImpact": InferenceLocality.remote.privacyImpact,
                "promptTokens": "100",
                "completionTokens": "25",
                "estimatedCost": "0.02"
            ]
        ))

        let draft = await store.appendedDrafts().first
        #expect(draft?.details.values["modelProvider"] == .string("Example Cloud"))
        #expect(draft?.details.values["inferenceLocality"] == .string("remote"))
        #expect(draft?.details.values["privacyImpact"] == .string(InferenceLocality.remote.privacyImpact))
        #expect(draft?.details.values["promptTokens"] == .string("100"))
        #expect(draft?.details.values["estimatedCost"] == .string("0.02"))
    }

    @Test
    func governedPayloadCarriesIntentInterpretedPlanAndApprovals() async throws {
        let store = SpyReceiptStore()
        let sink = ReceiptStoreSink(store: store)
        let proposal = ActionProposal(
            actor: .system,
            intent: "Transfer 1 ETH",
            capability: .draftTransaction,
            impact: .highRisk,
            requiredApprovals: ["treasury"],
            requiredCheckIDs: ["addressFormat"],
            parameters: ["address": "0xABC"]
        )

        try await sink.emit(GovernedReceipt(proposal: proposal, toolID: "wallet.transfer", outcome: .needsApproval))

        let draft = await store.appendedDrafts().first
        #expect(draft?.details.values["requestedIntent"] == .string("Transfer 1 ETH"))
        #expect(draft?.details.values["requiredApprovals"] == .array([.string("treasury")]))
        #expect(draft?.details.values["approvalStatus"] == .string("Awaiting human approval"))

        if case .array(let steps)? = draft?.details.values["interpretedPlan"] {
            #expect(steps.contains(.string("Operate on address = 0xABC")))
            #expect(steps.contains(.string("Pass checks: addressFormat")))
        } else {
            Issue.record("interpretedPlan should be recorded as an array of steps")
        }
    }

    /// The readable plan describes what the *person* asked for, so the keys the runtime stamps on
    /// every proposal have to be filtered out of it.
    ///
    /// The regression guard for a gap the existing coverage could not see: the test above builds its
    /// proposal by hand, so it never carries the stamp `RuntimeHost.schemaStamped` adds in production.
    /// `RecordSchemaKey.all` — the only exclusion the filter used — does not contain
    /// `contextRefreshedAt`, so every real governed receipt rendered a raw Unix timestamp as though it
    /// were part of the requested operation.
    @Test("the runtime's own parameter stamp stays out of the readable plan")
    func interpretedPlanExcludesTheGovernanceStamp() async throws {
        let store = SpyReceiptStore()
        let sink = ReceiptStoreSink(store: store)
        let proposal = ActionProposal(
            actor: .system,
            intent: "Transfer 1 ETH",
            capability: .draftTransaction,
            impact: .highRisk,
            parameters: [
                "address": "0xABC",
                RecordSchemaKey.artifactVersion: "1",
                // Stamped by `RuntimeHost.schemaStamped` on every proposal, and by the governed
                // boundary when it evaluates `context.fresh`.
                StandardCheckParameterKey.contextRefreshedAt: "1757894400.123",
                StandardCheckParameterKey.freshnessEvaluatedAt: "1757894401.456"
            ]
        )

        try await sink.emit(GovernedReceipt(proposal: proposal, toolID: "wallet.transfer", outcome: .executed))

        let draft = await store.appendedDrafts().first
        guard case .array(let steps)? = draft?.details.values["interpretedPlan"] else {
            Issue.record("interpretedPlan should be recorded as an array of steps")
            return
        }
        // The operand the person supplied is the whole plan; it is not diluted by the stamp keys.
        #expect(steps == [.string("Operate on address = 0xABC")])
        let rendered = steps.map(String.init(describing:)).joined(separator: " ")
        #expect(rendered.contains("contextRefreshedAt") == false)
        #expect(rendered.contains("freshnessEvaluatedAt") == false)
        #expect(rendered.contains("1757894400") == false)
    }

    /// A proposal carrying nothing but the runtime's stamp has no plan to show, and the section is
    /// documented as appearing only when there is one. It previously appeared containing just the
    /// timestamp.
    @Test("a proposal with only the governance stamp records no interpreted plan")
    func interpretedPlanIsOmittedWhenOnlyTheStampIsPresent() async throws {
        let store = SpyReceiptStore()
        let sink = ReceiptStoreSink(store: store)
        let proposal = ActionProposal(
            actor: .system,
            intent: "Review identity",
            capability: .runPlugin,
            impact: .readOnly,
            parameters: [
                RecordSchemaKey.artifactVersion: "1",
                StandardCheckParameterKey.contextRefreshedAt: "1757894400.123"
            ]
        )

        try await sink.emit(GovernedReceipt(proposal: proposal, toolID: "operator.identity.review", outcome: .executed))

        let draft = await store.appendedDrafts().first
        #expect(draft?.details.values["interpretedPlan"] == nil)
    }

    @Test
    func executedArtifactReceiptIsLinkedBackToArtifact() async throws {
        let receiptStore = SpyReceiptStore()
        let artifactStore = InMemoryArtifactStore()
        let artifact = await artifactStore.create(ArtifactDraft(
            type: .brief,
            title: "Linked brief",
            provenance: ArtifactProvenance(actor: .system),
            content: "body"
        ))
        let sink = ReceiptStoreSink(store: receiptStore, artifactStore: artifactStore)
        let proposal = ActionProposal(actor: .system, intent: "brief", capability: .runPlugin, impact: .readOnly)

        try await sink.emit(GovernedReceipt(
            proposal: proposal,
            toolID: "operator.research.brief",
            outcome: .executed,
            artifactID: artifact.id
        ))

        let receipt = try #require(await receiptStore.appendedDrafts().first)
        let storedArtifact = try #require(await artifactStore.get(id: artifact.id))
        #expect(storedArtifact.relatedReceiptIDs.count == 1)
        #expect(receipt.details.values["artifactID"] == .string(artifact.id.uuidString))
    }

    @Test
    @MainActor
    func routineArtifactReceiptIsStoredOnArtifact() async throws {
        let receiptStore = SpyReceiptStore()
        let artifactStore = InMemoryArtifactStore()
        let host = RuntimeHost(
            receiptStore: receiptStore,
            stores: RuntimeHostStores(artifactStore: artifactStore)
        )

        let record = await host.runRoutine(id: "research.brief")

        let artifactID = try #require(record.artifactID)
        let storedArtifact = try #require(await artifactStore.get(id: artifactID))
        #expect(storedArtifact.relatedReceiptIDs.count == 1)
        // Selected by content rather than position. `runRoutine` bootstraps the host, so the receipt
        // observer is subscribed and the capability grants the run mints for its own actor are
        // receipted ahead of the routine receipt — which is the point of that bootstrap, not a
        // regression. Asserting on `.first` made this test depend on the grants going unrecorded.
        let draft = try #require(
            await receiptStore.appendedDrafts().first { $0.details.values["playbook"] != nil }
        )
        #expect(draft.details.values["artifactID"] == .string(artifactID.uuidString))
    }

    @Test
    func blockedCryptoReceiptIsAppendedAsFailureWithCryptoProvenance() async throws {
        let store = SpyReceiptStore()
        let sink = ReceiptStoreSink(store: store, modeProvider: { .assist })
        let proposal = ActionProposal(actor: .human, intent: "sign", capability: .signMessage, impact: .highRisk)

        try await sink.emit(GovernedReceipt(proposal: proposal, toolID: "sign", outcome: .blocked, reason: "Observe"))

        let drafts = await store.appendedDrafts()
        #expect(drafts.first?.isSuccess == false)
        #expect(drafts.first?.mode == .assist)
        #expect(drafts.first?.provenance == "crypto")
    }

    @Test
    @MainActor
    func eventRoutineRunsWhenStaleArtifactSignalIsSupplied() async throws {
        let receiptStore = SpyReceiptStore()
        let artifactStore = InMemoryArtifactStore()
        let playbookStore = InMemoryPlaybookStore(seed: [
            Playbook(
                id: "user.stale.watch",
                name: "Stale Artifact Watch",
                summary: "Prepares stale artifact follow-up.",
                trigger: .event(.artifactStale),
                authority: PlaybookAuthority(capabilities: [.runPlugin], allowedOutputs: [.brief]),
                completionCondition: "A stale artifact brief is prepared.",
                source: .user,
                contextContract: SystemPlaybookContracts.contract(for: "user.stale.watch", identifier: "user.playbook.user.stale.watch"),
                installState: .installed
            )
        ])
        let host = RuntimeHost(
            receiptStore: receiptStore,
            stores: RuntimeHostStores(
                artifactStore: artifactStore,
                playbookStore: playbookStore
            )
        )

        await host.runDueRoutines(staleSignal: true)

        // The routine receipt, not merely the first one appended; see
        // ``routineArtifactReceiptIsStoredOnArtifact``.
        let draft = try #require(
            await receiptStore.appendedDrafts().first { $0.details.values["playbook"] != nil }
        )
        #expect(draft.details.values["playbook"] == .string("user.stale.watch"))
        #expect(draft.details.values["trigger"] == .string("artifactStale"))
        #expect(draft.isSuccess)
    }

    /// The due-scan records what it weighed, including the routines it *skipped* and why. Only runs
    /// leave execution records, so without this a skipped routine looks identical to one that was
    /// never evaluated — "why didn't my routine run?" is unanswerable after the fact.
    @Test
    @MainActor
    func dueScanRecordsWhatItConsideredIncludingSkippedRoutines() async throws {
        let playbookStore = InMemoryPlaybookStore(seed: [
            Playbook(
                id: "user.cron.due",
                name: "Due Digest",
                summary: "Fires now.",
                trigger: .schedule(intervalSeconds: 60),
                authority: PlaybookAuthority(capabilities: [.runPlugin], allowedOutputs: [.brief]),
                completionCondition: "A digest is prepared.",
                source: .user,
                contextContract: SystemPlaybookContracts.contract(for: "user.cron.due", identifier: "user.playbook.user.cron.due"),
                installState: .installed
            ),
            Playbook(
                id: "user.manual.skipped",
                name: "Manual Only",
                summary: "Never auto-fires.",
                trigger: .manual,
                authority: PlaybookAuthority(capabilities: [.autoOrganization], allowedOutputs: [.brief]),
                completionCondition: "Never automatically.",
                source: .user,
                contextContract: SystemPlaybookContracts.contract(for: "user.manual.skipped", identifier: "user.playbook.user.manual.skipped"),
                installState: .installed
            ),
            // Not installed, so the scan should not weigh it at all.
            Playbook(
                id: "user.available.uninstalled",
                name: "Not Installed",
                summary: "Available but off.",
                trigger: .schedule(intervalSeconds: 60),
                authority: PlaybookAuthority(capabilities: [.runPlugin], allowedOutputs: [.brief]),
                completionCondition: "n/a",
                source: .user,
                contextContract: SystemPlaybookContracts.contract(for: "user.available.uninstalled", identifier: "user.playbook.user.available.uninstalled"),
                installState: .available
            )
        ])
        let host = RuntimeHost(
            receiptStore: SpyReceiptStore(),
            stores: RuntimeHostStores(playbookStore: playbookStore)
        )

        await host.runDueRoutines(scanCorrelationID: "corr-scan")

        let trace = await host.worklogStore.steps(forCorrelationID: "corr-scan")
        let candidates = try #require(trace.compactMap { step -> [ConsideredCandidate]? in
            if case let .considered(candidates) = step.event { return candidates }
            return nil
        }.first)
        #expect(candidates.count == 2)
        let due = try #require(candidates.first { $0.title == "Due Digest" })
        #expect(due.wasSelected)
        #expect(due.rationale.isEmpty == false)
        let skipped = try #require(candidates.first { $0.title == "Manual Only" })
        #expect(skipped.wasSelected == false)
        // The reason has to be specific enough to act on, not just "skipped".
        #expect(skipped.rationale.contains("Manual"))
        #expect(candidates.contains { $0.title == "Not Installed" } == false)
    }

    /// An automated fire names *which* routine acted, so run history can distinguish a cron run from a
    /// tap even though both land in the same store (P0.5-602).
    @Test
    @MainActor
    func automatedRoutineRunIsAttributedToTheRoutineItself() async throws {
        let playbookStore = InMemoryPlaybookStore(seed: [
            Playbook(
                id: "user.cron.digest",
                name: "Morning Digest",
                summary: "Prepares a scheduled digest.",
                trigger: .schedule(intervalSeconds: 60),
                authority: PlaybookAuthority(capabilities: [.runPlugin], allowedOutputs: [.brief]),
                completionCondition: "A digest is prepared.",
                source: .user,
                contextContract: SystemPlaybookContracts.contract(for: "user.cron.digest", identifier: "user.playbook.user.cron.digest"),
                installState: .installed
            )
        ])
        let host = RuntimeHost(
            receiptStore: SpyReceiptStore(),
            stores: RuntimeHostStores(playbookStore: playbookStore)
        )

        await host.runDueRoutines()

        let scheduled = try #require(await host.schedulingEngine.latestExecution(forPlaybookID: "user.cron.digest"))
        #expect(scheduled.triggerSource == .schedule)
        #expect(scheduled.actor.kind == .scheduledRoutine)
        #expect(scheduled.actor.identifier == "user.cron.digest")
        #expect(scheduled.actor.displayName == "Morning Digest")

        // The same playbook run by hand is attributed to the person, not the routine.
        _ = await host.runRoutine(id: "user.cron.digest", trigger: .manual, actor: .human)
        let manual = try #require(await host.schedulingEngine.latestExecution(forPlaybookID: "user.cron.digest"))
        #expect(manual.triggerSource == .manual)
        #expect(manual.actor.kind == .human)
    }

    /// The sink is the governed pipeline's only path onto a receipt, so the structured actor column
    /// has to be populated from the proposal's `ActorRef` — not left `nil` for the coarse
    /// `user`/`system` flag to stand in for (P0.5-602).
    @Test
    func governedReceiptCarriesStructuredActorAttribution() async throws {
        let store = SpyReceiptStore()
        let sink = ReceiptStoreSink(store: store)
        let actor = ActorRef.model(
            identifier: "com.auralis.planner",
            inference: InferenceProvenance(locality: .remote, provider: "anthropic", modelClass: "opus")
        )
        let proposal = ActionProposal(actor: actor, intent: "brief", capability: .runPlugin, impact: .readOnly)

        try await sink.emit(GovernedReceipt(proposal: proposal, toolID: "operator.research.brief", outcome: .executed))

        let draft = try #require(await store.appendedDrafts().first)
        let detail = try #require(draft.actorDetail)
        #expect(detail.kind == "model")
        #expect(detail.identifier == "com.auralis.planner")
        #expect(detail.inferenceLocality == "remote")
        #expect(detail.inferenceProvider == "anthropic")
        #expect(detail.inferenceModelClass == "opus")
        // The coarse column still collapses non-human actors, which is exactly why the detail matters.
        #expect(draft.actor == .system)
    }

    /// The sink must carry the authority the pipeline resolved onto the durable receipt, so a stored
    /// receipt can answer "under what authority?" (P0.5-601/602).
    @Test
    func governedReceiptCarriesAuthorityAttribution() async throws {
        let store = SpyReceiptStore()
        let sink = ReceiptStoreSink(store: store)
        let proposal = ActionProposal(actor: .system, intent: "queue", capability: .playbackQueue, impact: .reversibleWrite)
        let expiry = Date().addingTimeInterval(1200)
        let lease = CapabilityLease(
            capability: .playbackQueue,
            reason: "Planner may queue playback.",
            grantedTo: proposal.actor,
            expiresAt: expiry
        )

        try await sink.emit(GovernedReceipt(
            proposal: proposal,
            toolID: "queue",
            outcome: .executed,
            authority: AuthorityRef(lease: lease)
        ))

        let detail = try #require(await store.appendedDrafts().first?.authorityDetail)
        #expect(detail.source == "lease")
        #expect(detail.leaseID == lease.id.uuidString)
        #expect(detail.capability == "playback_queue")
        #expect(detail.scope == "execution")
        #expect(detail.reason == "Planner may queue playback.")
        #expect(detail.expiresAt == expiry)
    }

    /// A receipt for a run that never got permission must not claim an authority.
    @Test
    func receiptWithoutResolvedAuthorityCarriesNone() async throws {
        let store = SpyReceiptStore()
        let sink = ReceiptStoreSink(store: store)
        let proposal = ActionProposal(actor: .human, intent: "sign", capability: .signMessage, impact: .highRisk)

        try await sink.emit(GovernedReceipt(proposal: proposal, toolID: "sign", outcome: .blocked, reason: "Observe"))

        let draft = try #require(await store.appendedDrafts().first)
        #expect(draft.authorityDetail == nil)
        // Attribution of *who* is still recorded — only the authority is absent.
        #expect(draft.actorDetail?.kind == "human")
    }

    @Test
    func blockedGovernedReceiptStillCarriesActorAttribution() async throws {
        let store = SpyReceiptStore()
        let sink = ReceiptStoreSink(store: store)
        let routine = ActorRef(kind: .scheduledRoutine, identifier: "morning.brief", displayName: "Morning Brief")
        let proposal = ActionProposal(actor: routine, intent: "sign", capability: .signMessage, impact: .highRisk)

        try await sink.emit(GovernedReceipt(proposal: proposal, toolID: "sign", outcome: .blocked, reason: "Observe"))

        let detail = try #require(await store.appendedDrafts().first?.actorDetail)
        #expect(detail.kind == "scheduledRoutine")
        #expect(detail.identifier == "morning.brief")
        #expect(detail.displayName == "Morning Brief")
    }

    /// A routine's own run receipt must carry the run's attribution rather than an anonymous
    /// `.system` — otherwise the receipt can't say which routine produced it (P0.5-602).
    @Test
    @MainActor
    func routineRunReceiptCarriesTheRunsActorAttribution() async throws {
        let receiptStore = SpyReceiptStore()
        let playbookStore = InMemoryPlaybookStore(seed: [
            Playbook(
                id: "user.cron.digest",
                name: "Morning Digest",
                summary: "Prepares a scheduled digest.",
                trigger: .schedule(intervalSeconds: 60),
                authority: PlaybookAuthority(capabilities: [.runPlugin], allowedOutputs: [.brief]),
                completionCondition: "A digest is prepared.",
                source: .user,
                contextContract: SystemPlaybookContracts.contract(for: "user.cron.digest", identifier: "user.playbook.user.cron.digest"),
                installState: .installed
            )
        ])
        let host = RuntimeHost(
            receiptStore: receiptStore,
            stores: RuntimeHostStores(playbookStore: playbookStore)
        )

        await host.runDueRoutines()

        let routineDraft = try #require(
            await receiptStore.appendedDrafts().first { $0.scope == "routine" }
        )
        let detail = try #require(routineDraft.actorDetail)
        #expect(detail.kind == "scheduledRoutine")
        #expect(detail.identifier == "user.cron.digest")
        #expect(detail.displayName == "Morning Digest")

        // A hand-run of the same routine is attributed to the person who tapped it.
        _ = await host.runRoutine(id: "user.cron.digest", trigger: .manual, actor: .human)
        let manualDraft = try #require(
            await receiptStore.appendedDrafts().last { $0.scope == "routine" }
        )
        #expect(manualDraft.actorDetail?.kind == "human")
        #expect(manualDraft.actor == .user)
    }

    /// The receipt must be keyed the same way the pipeline keys the rest of the trace.
    ///
    /// `GovernedToolPipeline` files a proposal's session, worklog, and events under
    /// `resolvedCorrelationID`. Reading the raw optional here filed the receipt under `nil` for an
    /// uncorrelated proposal, so `receipts(forCorrelationID:)` could never retrieve it and the
    /// session-link below was skipped — one half of the trace pointing at the other half's key.
    @Test
    func receiptForUncorrelatedProposalIsFiledUnderTheResolvedCorrelationID() async throws {
        let store = SpyReceiptStore()
        let sessionStore = InMemoryAgentSessionStore()
        let sink = ReceiptStoreSink(store: store, sessionStore: sessionStore)
        let proposal = ActionProposal(
            actor: .human,
            intent: "organize",
            capability: .playlistManagement,
            impact: .reversibleWrite
        )
        #expect(proposal.correlationID == nil)

        try await sink.emit(GovernedReceipt(proposal: proposal, toolID: "organize", outcome: .executed))

        let draft = try #require(await store.appendedDrafts().first)
        #expect(draft.correlationID == proposal.resolvedCorrelationID)
        #expect(draft.correlationID == proposal.id.uuidString)

        // The receipt must also reach the session, which only happens when the id is non-nil.
        let session = try #require(await sessionStore.session(correlationID: proposal.resolvedCorrelationID))
        #expect(session.receiptIDs.count == 1)
    }

    /// An explicit correlation id is still used verbatim — the fallback must not override it.
    @Test
    func receiptForCorrelatedProposalKeepsItsExplicitCorrelationID() async throws {
        let store = SpyReceiptStore()
        let sink = ReceiptStoreSink(store: store)
        let proposal = ActionProposal(
            actor: .human,
            intent: "organize",
            capability: .playlistManagement,
            impact: .reversibleWrite,
            correlationID: "corr-42"
        )

        try await sink.emit(GovernedReceipt(proposal: proposal, toolID: "organize", outcome: .executed))

        #expect(await store.appendedDrafts().first?.correlationID == "corr-42")
    }

    /// The third attribution leg for scheduled work: given a routine receipt, its worklog steps must
    /// be retrievable (P0.5-602 "through what workflow").
    ///
    /// Scheduled runs don't pass through the governed pipeline, so they used to write no trace at
    /// all — `steps(forCorrelationID:)` on a routine receipt returned empty by construction, and the
    /// receipt/record/steps each derived their own key.
    @Test
    @MainActor
    func routineRunWritesAWorklogTraceUnderTheReceiptsCorrelationID() async throws {
        let receiptStore = SpyReceiptStore()
        let worklog = InMemoryWorklog()
        let host = RuntimeHost(
            receiptStore: receiptStore,
            stores: RuntimeHostStores(worklogStore: worklog)
        )
        await host.bootstrap()

        let record = await host.runRoutine(id: "research.brief")

        let draft = try #require(await receiptStore.appendedDrafts().first { $0.scope == "routine" })
        // One key, three surfaces: the record, its receipt, and its steps.
        #expect(draft.correlationID == record.correlationID)

        let steps = await worklog.steps(forCorrelationID: record.correlationID)
        #expect(steps.isEmpty == false)
        let phases = steps.compactMap { step -> RoutinePhase? in
            guard case let .routinePhase(phase, _) = step.event else { return nil }
            return phase
        }
        #expect(phases.contains(.authorityResolved))
        #expect(phases.contains(.operatorFinished))
        #expect(phases.contains(.completed))
        // Every trace entry names the routine that produced it.
        #expect(steps.allSatisfy { $0.actor.identityKey == record.actor.identityKey })
    }

    /// With the lease registry attached and standing leases seeded, a routine run records the actual
    /// grant — lease id and expiry — rather than a bare `.policyDefault`.
    @Test
    @MainActor
    func routineRunRecordsTheResolvedCapabilityLeaseAsItsAuthority() async throws {
        let receiptStore = SpyReceiptStore()
        let host = RuntimeHost(receiptStore: receiptStore)
        await host.bootstrap()

        let record = await host.runRoutine(id: "research.brief")

        let authority = try #require(record.authority)
        #expect(authority.source == .lease)
        #expect(authority.leaseID != nil)
        #expect(authority.expiresAt != nil)
        #expect(authority.capability == .runPlugin)

        let draft = try #require(await receiptStore.appendedDrafts().first { $0.scope == "routine" })
        #expect(draft.authorityDetail?.source == "lease")
        #expect(draft.authorityDetail?.leaseID == authority.leaseID?.uuidString)
    }

    /// A denial is the durable "no": re-seeding standing authority must not restore a capability the
    /// operator has refused, and the run must fail closed rather than proceed unattributed.
    @Test
    @MainActor
    func deniedCapabilityKeepsRefusingTheRoutineDespiteReseeding() async throws {
        let host = RuntimeHost(receiptStore: SpyReceiptStore())
        await host.bootstrap()

        let routineActor = ActorRef(
            kind: .scheduledRoutine,
            identifier: "research.brief",
            displayName: "Research Brief"
        )
        _ = await host.denyCapability(
            .capability(.runPlugin),
            reason: "Operator paused research.",
            appliesTo: routineActor
        )

        // Goes through `runRoutine`, which re-seeds standing authority before running.
        let record = await host.runRoutine(id: "research.brief", trigger: .schedule, actor: routineActor)

        #expect(record.outcome == .blocked)
        #expect(record.authority == nil)
    }

    @Test
    @MainActor
    func persistentHostFailsSafeWhenRuntimeStorageCannotOpen() async throws {
        struct StorageFailure: Error { }

        let receiptStore = SpyReceiptStore()
        let host = RuntimeHost.persistent(
            receiptStore: receiptStore,
            makeStorageContainer: { throw StorageFailure() }
        )

        #expect(host.isPaused)
        #expect(host.pauseReason?.contains("Operator runtime storage is unavailable") == true)

        do {
            _ = try await host.artifactStore.create(ArtifactDraft(
                type: .brief,
                title: "Should not be volatile",
                provenance: ArtifactProvenance(actor: .system),
                content: "This must not land in memory-only storage."
            ))
            Issue.record("Expected artifact creation to fail while persistent runtime storage is unavailable.")
        } catch let error as RuntimePersistenceError {
            #expect(error.localizedDescription.contains("Artifact creation is paused"))
        } catch {
            Issue.record("Expected RuntimePersistenceError, got \(error).")
        }
    }

    /// Only the SwiftData-backed stores may degrade when the runtime container cannot open.
    ///
    /// The three coordination stores are `UserDefaults`-backed and the operator data source reads
    /// the receipt ledger, so none of them live in that container. The failure path used to build
    /// its host by simply omitting those arguments, which silently swapped healthy durable state
    /// for empty in-memory defaults: shared sessions, rituals, and the pending outbound relay queue
    /// all read as empty, and that queue would never be flushed.
    @Test
    @MainActor
    func degradedHostKeepsStoresThatDoNotLiveInTheFailedContainer() async throws {
        struct StorageFailure: Error { }

        let receiptStore = SpyReceiptStore()
        let sharedSessionStore = SharedSessionStore()
        let ritualStore = RitualStore()
        let socialEventLogStore = SocialEventLogStore()

        let session = await sharedSessionStore.create(
            SharedSession(correlationID: "corr-degraded", title: "Weekly review", createdBy: .human)
        )
        let queued = await socialEventLogStore.enqueueOutbound(
            SocialEventEnvelope(
                sessionID: session.id,
                authorParticipantID: "participant-1",
                event: .sessionCreated(title: session.title, correlationID: session.correlationID)
            )
        )
        // Enable a ritual explicitly rather than relying on whatever the built-in catalog defaults
        // to, so the assertion is about the store surviving and not about catalog defaults.
        let rituals = await ritualStore.all()
        let ritualID = try #require(rituals.first).id
        await ritualStore.setEnabled(id: ritualID, true)

        let host = RuntimeHost.persistent(
            receiptStore: receiptStore,
            sharedSessionStore: sharedSessionStore,
            ritualStore: ritualStore,
            socialEventLogStore: socialEventLogStore,
            makeStorageContainer: { throw StorageFailure() }
        )

        #expect(host.isPaused)
        // The state that does not depend on the failed container is still reachable through the host.
        #expect(await host.sharedSessionStore.session(id: session.id)?.title == "Weekly review")
        #expect(await host.socialEventLogStore.pendingOutbound().map(\.id) == [queued.id])
        #expect(await host.ritualStore.enabled().contains { $0.id == ritualID })
    }

    /// A failed artifact *backlink* must not be reported as a missing receipt.
    ///
    /// The sink appends the receipt and then indexes it against the artifact. `linkRelatedReceipt`
    /// was called with `try`, so a link failure threw out of `emit` — and `GovernedToolPipeline`
    /// reads a throwing sink as "the governance receipt is missing" and degrades the outcome to
    /// `.evidenceIncomplete`. That announced the one piece of evidence that *had* persisted as
    /// absent, which is a worse misreport than the gap it was describing.
    @Test("a failed artifact backlink does not report the receipt as missing")
    func artifactLinkFailureDoesNotMasqueradeAsAMissingReceipt() async throws {
        let receiptStore = SpyReceiptStore()
        let sink = ReceiptStoreSink(
            store: receiptStore,
            artifactStore: LinkFailingArtifactStore()
        )
        let artifactID = UUID()

        // Must not throw: the receipt landed, and only the index write failed.
        try await sink.emit(
            GovernedReceipt(
                proposal: ActionProposal(
                    actor: .system,
                    intent: "Research Brief",
                    capability: .runPlugin,
                    impact: .readOnly,
                    correlationID: "corr-link-failure"
                ),
                toolID: "operator.research.brief",
                outcome: .executed,
                artifactID: artifactID
            )
        )

        let draft = try #require(await receiptStore.appendedDrafts().first)
        #expect(draft.correlationID == "corr-link-failure")
        #expect(draft.isSuccess)
        // The artifact id is still on the receipt, so artifact → receipt stays recoverable from the
        // ledger even though the index write failed.
        #expect(draft.details.values["artifactID"] == .string(artifactID.uuidString))
    }
}

/// An artifact store whose only failure is the receipt backlink — the narrow case the sink has to
/// distinguish from a receipt that could not be written at all.
private actor LinkFailingArtifactStore: ArtifactStore {
    struct LinkFailure: LocalizedError {
        var errorDescription: String? { "artifact index write failed" }
    }

    // `InMemoryArtifactStore` satisfies the throwing requirements without throwing, so forwarding to
    // it needs no `try`. The `throws` stays in each signature — it is the protocol's — but marking
    // the calls produced a warning per line for an effect that cannot occur.
    private let base = InMemoryArtifactStore()

    func create(_ draft: ArtifactDraft) async throws -> Artifact { await base.create(draft) }
    func addVersion(toGroup groupID: UUID, _ draft: ArtifactDraft) async throws -> Artifact {
        await base.addVersion(toGroup: groupID, draft)
    }
    func get(id: UUID) async -> Artifact? { await base.get(id: id) }
    func latest(limit: Int) async throws -> [Artifact] { await base.latest(limit: limit) }
    func versions(ofGroup groupID: UUID) async throws -> [Artifact] { await base.versions(ofGroup: groupID) }
    func all(ofType type: ArtifactType, limit: Int) async throws -> [Artifact] {
        await base.all(ofType: type, limit: limit)
    }
    func setApprovalState(id: UUID, to state: ArtifactApprovalState) async throws {
        try await base.setApprovalState(id: id, to: state)
    }
    func linkRelatedReceipt(id receiptID: UUID, toArtifact artifactID: UUID) async throws {
        throw LinkFailure()
    }
    func updateLifecycle(
        id: UUID,
        to state: ArtifactApprovalState,
        destination: String?,
        exportFormat: String?
    ) async throws {
        try await base.updateLifecycle(id: id, to: state, destination: destination, exportFormat: exportFormat)
    }
    // `exportAll` is the one that really can throw — it JSON-encodes — so it keeps its `try`.
    func exportAll() async throws -> Data { try await base.exportAll() }
    func resetAll() async throws { await base.resetAll() }
}
