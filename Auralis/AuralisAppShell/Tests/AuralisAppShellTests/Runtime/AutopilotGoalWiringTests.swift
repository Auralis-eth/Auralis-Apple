import AuralisReceipts
import AuralisPrimaryModels
import AuralisFoundation
import Foundation
import AuralisOperators
import AuralisRuntime
import AuralisPolicy
@testable import AuralisAppShell
import Testing

/// In-memory receipt store whose appended records can be read back.
private actor CapturingReceiptStore: ReceiptStore {
    private var records: [ReceiptRecord] = []
    func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord {
        let record = ReceiptRecord(
            id: UUID(), sequenceID: records.count + 1, createdAt: receipt.createdAt,
            actor: receipt.actor, actorDetail: receipt.actorDetail, authorityDetail: receipt.authorityDetail, mode: receipt.mode, trigger: receipt.trigger,
            scope: receipt.scope, summary: receipt.summary, provenance: receipt.provenance,
            isSuccess: receipt.isSuccess, correlationID: receipt.correlationID, details: receipt.details
        )
        records.insert(record, at: 0)
        return record
    }
    func latest(limit: Int) async throws -> [ReceiptRecord] { Array(records.prefix(limit)) }
    func receipts(forCorrelationID correlationID: String, limit: Int) async throws -> [ReceiptRecord] {
        Array(records.filter { $0.correlationID == correlationID }.prefix(limit))
    }
    func exportAll() async throws -> Data { Data() }
    func resetAll() async throws { records.removeAll() }
}

/// A performer double: no model call, returns fixed output and the telemetry it is handed. Lets the
/// wiring tests be fast and deterministic while still exercising the real telemetry-stamping path.
@MainActor
private struct FakeStepPerformer: AutopilotStepPerforming {
    let telemetry: InferenceTelemetry?
    func perform(_ step: PlanStep, goal: PlanningGoal) async -> AutopilotStepWork {
        AutopilotStepWork(output: "did “\(step.title)” for “\(goal.text)”", telemetry: telemetry)
    }
}

private struct TelemetryPlanner: GoalPlanning {
    let name = "telemetry"

    let telemetry: InferenceTelemetry

    func makePlan(for goal: PlanningGoal) async -> Plan {
        Plan(
            goal: goal,
            steps: [
                PlanStep(
                    capability: .musicLibraryClassification,
                    kind: .observe,
                    title: "Inspect library",
                    rationale: "Gather context first."
                )
            ],
            summary: "Inspect the library.",
            deliberation: PlanDeliberation(
                planner: "model",
                candidates: [
                    PlanCandidate(
                        title: "Inspect library",
                        capability: .musicLibraryClassification,
                        isSelected: true,
                        rationale: "Model selected a safe read-only step."
                    )
                ],
                telemetry: telemetry
            )
        )
    }
}

private func fakeLocalTelemetry(prompt: Int, completion: Int) -> InferenceTelemetry {
    let route = ModelRoute(
        id: "test.foundation-models.local",
        provider: "Apple Foundation Models",
        modelClass: "local-language-model",
        locality: .local
    )
    return InferenceTelemetry(
        route: route,
        promptTokens: prompt,
        completionTokens: completion,
        durationSeconds: 0.05,
        estimatedCost: 0,
        tokensEstimated: false
    )
}

private func string(_ value: ReceiptJSONValue?) -> String? {
    if case let .string(s)? = value { return s }
    return nil
}

@MainActor
@Suite("Autopilot goal wiring")
struct AutopilotGoalWiringTests {
    /// P1-101 — running a goal on autopilot records the planner's deliberation (considered/rejected)
    /// onto the host's shared worklog, each cleared step onto the shared receipt store, and — crucially
    /// — the **real** inference telemetry for steps that ran a model. These are the very stores Mission
    /// Control reads, so this closes the loop planner → worklog → receipts → Agent Activity Timeline.
    @Test
    func autopilotGoalRecordsDeliberationStepReceiptsAndTelemetry() async {
        let store = CapturingReceiptStore()
        let host = RuntimeHost(
            receiptStore: store,
            identity: RuntimeIdentityHooks(cryptoModeProvider: { .observe })
        )
        // Pin planning + inference to deterministic doubles so the test is fast and stable regardless of
        // whether the on-device model is present on the machine running it.
        host.autopilotPlannerOverride = DeterministicGoalPlanner()
        host.autopilotStepPerformerOverride = FakeStepPerformer(telemetry: fakeLocalTelemetry(prompt: 42, completion: 17))
        await host.bootstrap()
        await host.grantCapabilityLease(
            capability: .runPlugin,
            grantedTo: ActorRef(kind: .operatorAgent, identifier: OperatorCatalog.researchBriefID)
        )

        let (plan, _) = await host.runAutopilotGoal(
            "organize my music library",
            correlationID: "corr-autopilot"
        )

        // The planner's deliberation landed on the shared worklog as a `considered` entry.
        let steps = await host.worklogStore.allSteps().filter { $0.correlationID == "corr-autopilot" }
        let considered: [ConsideredCandidate]? = steps.compactMap { step in
            if case let .considered(candidates) = step.event { return candidates }
            return nil
        }.first
        #expect(considered != nil)
        #expect(considered?.contains { $0.wasSelected } == true)
        #expect(considered?.contains { !$0.wasSelected } == true)

        // The plan is the observe → assist → execute ladder.
        #expect(plan.steps.map(\.kind) == [.observe, .assist, .execute])

        // The cleared observe/assist steps ran and left correlated autopilot receipts.
        let receipts = (try? await store.latest(limit: 50)) ?? []
        let ran = receipts.filter { $0.correlationID == "corr-autopilot" && $0.summary.hasPrefix("Autopilot ran") }
        #expect(ran.count >= 2)

        // Those receipts carry REAL inference telemetry in the exact keys Mission Control aggregates.
        let telemetryReceipt = ran.first { string($0.details.values["modelProvider"]) != nil }
        #expect(telemetryReceipt != nil)
        #expect(string(telemetryReceipt?.details.values["modelProvider"]) == "Apple Foundation Models")
        #expect(string(telemetryReceipt?.details.values["inferenceLocality"]) == InferenceLocality.local.rawValue)
        #expect(string(telemetryReceipt?.details.values["privacyImpact"]) == InferenceLocality.local.privacyImpact)
        #expect(string(telemetryReceipt?.details.values["promptTokens"]) == "42")
        #expect(string(telemetryReceipt?.details.values["completionTokens"]) == "17")
        #expect(string(telemetryReceipt?.details.values["durationSeconds"]) == "0.05")
        #expect(string(telemetryReceipt?.details.values["tokensEstimated"]) == "false")
    }

    /// The deliberation that chose a step and the governed trace of that step running must be ONE
    /// workflow. `runOperator` used to mint its own correlation id, so an autopilot goal's
    /// `considered` entry and its steps' `proposed`/`decided`/`executed` entries landed under
    /// different keys — `steps(forCorrelationID:)` could never reassemble the run, and the step
    /// surfaced in Mission Control as a phantom second workflow.
    @Test
    func autopilotDeliberationAndGovernedStepShareOneTrace() async {
        let host = RuntimeHost(
            receiptStore: CapturingReceiptStore(),
            identity: RuntimeIdentityHooks(cryptoModeProvider: { .observe })
        )
        // A `.runPlugin` step is what routes through the governed pipeline; no built-in template
        // emits one, so the template is supplied here rather than relying on the catalog.
        host.autopilotPlannerOverride = DeterministicGoalPlanner(templates: [
            PlanTemplate(
                id: "research-goal",
                keywords: ["research"],
                summary: "Research the subject.",
                steps: [
                    PlanStep(
                        capability: .runPlugin,
                        kind: .observe,
                        title: "Research the subject",
                        rationale: "Gather context before acting."
                    )
                ]
            )
        ])
        host.autopilotStepPerformerOverride = FakeStepPerformer(telemetry: nil)
        await host.bootstrap()
        // The research-brief operator is what `.runPlugin` maps to; without a lease the governed run
        // would be blocked before it wrote an `executed` entry.
        await host.grantCapabilityLease(
            capability: .runPlugin,
            grantedTo: ActorRef(kind: .operatorAgent, identifier: OperatorCatalog.researchBriefID)
        )

        await host.runAutopilotGoal("research vitalik.eth", correlationID: "corr-unified")

        let trace = await host.worklogStore.steps(forCorrelationID: "corr-unified")
        let hasConsidered = trace.contains { if case .considered = $0.event { return true } else { return false } }
        let hasProposed = trace.contains { if case .proposed = $0.event { return true } else { return false } }
        let hasExecuted = trace.contains { if case .executed = $0.event { return true } else { return false } }
        #expect(hasConsidered)
        #expect(hasProposed)
        #expect(hasExecuted)

        // And nothing leaked into a second trace: every entry the run wrote carries this id.
        let orphans = await host.worklogStore.allSteps().filter { $0.correlationID != "corr-unified" }
        #expect(orphans.isEmpty)
    }

    /// A cleared step whose capability maps to a governed operator runs it through the real pipeline
    /// rather than the inference path — "route through existing governed operators where one exists".
    @Test
    func clearedStepWithOperatorRoutesToGovernedOperator() async throws {
        let store = CapturingReceiptStore()
        let recorder = ToolIDRecorder()
        let executor = AutopilotStepExecutor(
            receiptStore: store,
            eventBus: nil,
            sessionStore: nil,
            correlationID: "corr-op",
            modeProvider: { .observe },
            goal: PlanningGoal(text: "look into vitalik.eth"),
            performer: FakeStepPerformer(telemetry: nil),
            operatorRunner: { toolID, _, correlationID in
                await recorder.record(toolID, correlationID: correlationID)
                return .executed(ToolCallArtifact(toolID: toolID, summary: "brief"))
            }
        )

        let step = PlanStep(capability: .runPlugin, kind: .observe, title: "Research", rationale: "gather context")
        _ = try await executor.execute(step)

        #expect(await recorder.toolID == OperatorCatalog.researchBriefID)
        // The step's governed run must inherit the goal's trace, not start a new one.
        #expect(await recorder.correlationID == "corr-op")
        let receipts = (try? await store.latest(limit: 10)) ?? []
        let opReceipt = receipts.first { string($0.details.values["operatorID"]) != nil }
        #expect(string(opReceipt?.details.values["operatorID"]) == OperatorCatalog.researchBriefID)
        #expect(opReceipt?.summary.contains("via") == true)
    }

    /// When no model runs (no operator, no on-device inference), the receipt is still written but carries
    /// NO fabricated telemetry — the timeline honestly reads "Not recorded".
    @Test
    func stepWithoutInferenceStampsNoTelemetry() async throws {
        let store = CapturingReceiptStore()
        let executor = AutopilotStepExecutor(
            receiptStore: store,
            eventBus: nil,
            sessionStore: nil,
            correlationID: "corr-noinf",
            modeProvider: { .observe },
            goal: PlanningGoal(text: "tidy my library"),
            performer: FakeStepPerformer(telemetry: nil),
            operatorRunner: nil
        )

        let step = PlanStep(capability: .musicLibraryClassification, kind: .observe, title: "Classify", rationale: "look first")
        _ = try await executor.execute(step)

        let receipts = (try? await store.latest(limit: 10)) ?? []
        let receipt = receipts.first
        #expect(receipt?.summary.hasPrefix("Autopilot ran") == true)
        #expect(receipt?.details.values["modelProvider"] == nil)
        #expect(receipt?.details.values["promptTokens"] == nil)
    }

    @Test
    func plannerTelemetryIsRecordedAsReceiptAndSessionTelemetry() async throws {
        let store = CapturingReceiptStore()
        let sessionStore = InMemoryAgentSessionStore()
        let telemetry = fakeLocalTelemetry(prompt: 12, completion: 4)
        let host = RuntimeHost(
            receiptStore: store,
            stores: RuntimeHostStores(sessionStore: sessionStore),
            identity: RuntimeIdentityHooks(cryptoModeProvider: { .observe })
        )
        host.autopilotPlannerOverride = TelemetryPlanner(telemetry: telemetry)
        host.autopilotStepPerformerOverride = FakeStepPerformer(telemetry: nil)
        await host.bootstrap()

        _ = await host.runAutopilotGoal("inspect my library", correlationID: "corr-plan-telemetry")

        let receipts = (try? await store.latest(limit: 20)) ?? []
        let planningReceipt = try #require(receipts.first { $0.trigger == "autopilot.planning.model" })
        #expect(string(planningReceipt.details.values["modelProvider"]) == "Apple Foundation Models")
        #expect(string(planningReceipt.details.values["inferenceLocality"]) == InferenceLocality.local.rawValue)
        #expect(string(planningReceipt.details.values["promptTokens"]) == "12")

        let session = try #require(await sessionStore.session(correlationID: "corr-plan-telemetry"))
        #expect(session.promptTokens == 12)
        #expect(session.completionTokens == 4)
        #expect(session.modelsUsed.contains("Apple Foundation Models · local-language-model"))
    }

    /// P0.5-602 — the same inference facts the loose payload keys expose must also land in the
    /// structured actor column, so a step receipt says *a model did this, here* rather than `.system`.
    @Test
    func stepReceiptAttributesWorkToTheModelThatRanIt() async throws {
        let store = CapturingReceiptStore()
        let executor = AutopilotStepExecutor(
            receiptStore: store,
            eventBus: nil,
            sessionStore: nil,
            correlationID: "corr-actor",
            modeProvider: { .observe },
            goal: PlanningGoal(text: "tidy my library"),
            performer: FakeStepPerformer(telemetry: fakeLocalTelemetry(prompt: 9, completion: 3)),
            operatorRunner: nil
        )

        let step = PlanStep(capability: .musicLibraryClassification, kind: .observe, title: "Classify", rationale: "look first")
        _ = try await executor.execute(step)

        let receipt = try #require(((try? await store.latest(limit: 10)) ?? []).first)
        let detail = try #require(receipt.actorDetail)
        #expect(detail.kind == "model")
        #expect(detail.identifier == "local-language-model")
        #expect(detail.inferenceLocality == InferenceLocality.local.rawValue)
        #expect(detail.inferenceProvider == "Apple Foundation Models")
        #expect(detail.inferenceModelClass == "local-language-model")
    }

    /// With no model in the loop the actor is the workflow itself — honest, and still not anonymous.
    @Test
    func stepWithoutInferenceIsAttributedToTheWorkflow() async throws {
        let store = CapturingReceiptStore()
        let executor = AutopilotStepExecutor(
            receiptStore: store,
            eventBus: nil,
            sessionStore: nil,
            correlationID: "corr-actor-noinf",
            modeProvider: { .observe },
            goal: PlanningGoal(text: "tidy my library"),
            performer: FakeStepPerformer(telemetry: nil),
            operatorRunner: nil
        )

        let step = PlanStep(capability: .musicLibraryClassification, kind: .observe, title: "Classify", rationale: "look first")
        _ = try await executor.execute(step)

        let detail = try #require(((try? await store.latest(limit: 10)) ?? []).first?.actorDetail)
        #expect(detail.kind == "workflow")
        #expect(detail.identifier == "autopilot")
        #expect(detail.inferenceLocality == nil)
    }

    /// An operator-routed step is attributed to the operator pack that did the work.
    @Test
    func operatorRoutedStepIsAttributedToTheOperator() async throws {
        let store = CapturingReceiptStore()
        let executor = AutopilotStepExecutor(
            receiptStore: store,
            eventBus: nil,
            sessionStore: nil,
            correlationID: "corr-actor-op",
            modeProvider: { .observe },
            goal: PlanningGoal(text: "look into vitalik.eth"),
            performer: FakeStepPerformer(telemetry: nil),
            operatorRunner: { toolID, _, _ in .executed(ToolCallArtifact(toolID: toolID, summary: "brief")) }
        )

        let step = PlanStep(capability: .runPlugin, kind: .observe, title: "Research", rationale: "gather context")
        _ = try await executor.execute(step)

        let detail = try #require(((try? await store.latest(limit: 10)) ?? []).first?.actorDetail)
        #expect(detail.kind == "operator")
        #expect(detail.identifier == OperatorCatalog.researchBriefID)
    }

    // MARK: - a step that does not complete

    /// A governed operator that refuses the step must not be receipted as work that happened.
    ///
    /// The outcome used to be described into the payload and then discarded: the receipt was
    /// hardcoded `isSuccess: true` and a non-throwing return told `SequentialPlanOrchestrator` the
    /// step `.ran`, so the run continued onto later steps and the session closed `.completed`. The
    /// only trace of the refusal was a string buried in the payload.
    @Test(
        "an operator that does not execute fails the step instead of receipting a success",
        arguments: [
            ToolCallOutcome.blocked(reason: "Crypto actions are read-only in Observe."),
            ToolCallOutcome.failed(reason: "The provider timed out.")
        ]
    )
    func nonExecutedOperatorFailsTheStep(outcome: ToolCallOutcome) async throws {
        let store = CapturingReceiptStore()
        let executor = AutopilotStepExecutor(
            receiptStore: store,
            eventBus: nil,
            sessionStore: nil,
            correlationID: "corr-op-refused",
            modeProvider: { .observe },
            goal: PlanningGoal(text: "look into vitalik.eth"),
            performer: FakeStepPerformer(telemetry: nil),
            operatorRunner: { _, _, _ in outcome }
        )
        let step = PlanStep(capability: .runPlugin, kind: .observe, title: "Research", rationale: "gather context")

        await #expect(throws: AutopilotOperatorStepFailure.self) {
            _ = try await executor.execute(step)
        }

        // The attempt is still evidenced — but as the refusal it was.
        let receipt = try #require(((try? await store.latest(limit: 10)) ?? []).first)
        #expect(receipt.isSuccess == false)
        #expect(receipt.summary.contains("did not complete"))
        #expect(string(receipt.details.values["operatorID"]) == OperatorCatalog.researchBriefID)
    }

    /// An escalated step is waiting on a person, so it has not run either.
    @Test("an operator that escalates for approval does not close the step as done")
    func escalatedOperatorFailsTheStep() async throws {
        let store = CapturingReceiptStore()
        let proposal = ActionProposal(
            actor: ActorRef(kind: .operatorAgent, identifier: OperatorCatalog.researchBriefID),
            intent: "Research",
            capability: .runPlugin,
            impact: .readOnly
        )
        let executor = AutopilotStepExecutor(
            receiptStore: store,
            eventBus: nil,
            sessionStore: nil,
            correlationID: "corr-op-escalated",
            modeProvider: { .assist },
            goal: PlanningGoal(text: "look into vitalik.eth"),
            performer: FakeStepPerformer(telemetry: nil),
            operatorRunner: { _, _, _ in
                .needsApproval(ApprovalRequest(proposal: proposal, prompt: "Approve this?"))
            }
        )
        let step = PlanStep(capability: .runPlugin, kind: .observe, title: "Research", rationale: "gather context")

        await #expect(throws: AutopilotOperatorStepFailure.self) {
            _ = try await executor.execute(step)
        }
        #expect(((try? await store.latest(limit: 10)) ?? []).first?.isSuccess == false)
    }

    // MARK: - a state-changing step with no operator to perform it

    /// A cleared `execute` step whose capability has no registered operator must not be receipted as
    /// work that happened.
    ///
    /// These are reachable, not hypothetical. ``DomainJudge`` is crypto-scoped by design, so a
    /// non-crypto `.reversibleWrite` step is *cleared to run unattended* — see
    /// `JudgeStepAuthorizerTests.nonCryptoExecuteRunsUnattended`. Only `.runPlugin` has a mapped
    /// operator, so both of these `PlanTemplateCatalog` steps fell through to the inference path and
    /// recorded `autopilot.step.ran` with `isSuccess: true` over a paragraph of prose. No playlist was
    /// created; the receipt said the step succeeded.
    @Test(
        "a state-changing step with no operator is refused instead of receipted as a success",
        arguments: [
            (CapabilityID.playlistManagement, "Create the playlist"),
            (CapabilityID.autoOrganization, "Apply the organization")
        ]
    )
    func stateChangingStepWithoutOperatorFailsTheStep(capability: CapabilityID, title: String) async throws {
        let store = CapturingReceiptStore()
        let executor = AutopilotStepExecutor(
            receiptStore: store,
            eventBus: nil,
            sessionStore: nil,
            correlationID: "corr-unperformable",
            modeProvider: { .observe },
            goal: PlanningGoal(text: "make me a playlist"),
            performer: FakeStepPerformer(telemetry: nil),
            operatorRunner: nil
        )
        let step = PlanStep(capability: capability, kind: .execute, title: title, rationale: "once you approve it")

        await #expect(throws: AutopilotUnperformableStepFailure.self) {
            _ = try await executor.execute(step)
        }

        // The attempt is still evidenced — but as the refusal it was, under its own queryable kind.
        let receipt = try #require(((try? await store.latest(limit: 10)) ?? []).first)
        #expect(receipt.isSuccess == false)
        #expect(receipt.trigger == "autopilot.step.unperformable")
        #expect(receipt.summary.contains("could not perform"))
        #expect(string(receipt.details.values["capability"]) == capability.rawValue)
    }

    /// The performer must not run for an unperformable step: prose about a change that cannot happen
    /// is not evidence, and an inference pass would attach real token counts and a model actor to a
    /// step that did nothing.
    @Test("an unperformable step runs no inference and claims no telemetry")
    func unperformableStepRunsNoInference() async throws {
        let store = CapturingReceiptStore()
        let performer = RecordingStepPerformer(telemetry: fakeLocalTelemetry(prompt: 99, completion: 99))
        let executor = AutopilotStepExecutor(
            receiptStore: store,
            eventBus: nil,
            sessionStore: nil,
            correlationID: "corr-unperformable-noinf",
            modeProvider: { .observe },
            goal: PlanningGoal(text: "tidy my library"),
            performer: performer,
            operatorRunner: nil
        )
        let step = PlanStep(capability: .autoOrganization, kind: .execute, title: "Apply", rationale: "r")

        await #expect(throws: AutopilotUnperformableStepFailure.self) {
            _ = try await executor.execute(step)
        }

        #expect(performer.didPerform == false)
        let receipt = try #require(((try? await store.latest(limit: 10)) ?? []).first)
        #expect(receipt.details.values["modelProvider"] == nil)
        #expect(receipt.details.values["promptTokens"] == nil)
        #expect(receipt.details.values["output"] == nil)
        // The workflow itself, not a model that never ran.
        #expect(receipt.actorDetail?.kind == "workflow")
        #expect(receipt.actorDetail?.inferenceLocality == nil)
    }

    /// The guard is keyed on `kind.isStateChanging`, not on the capability: the same capabilities are
    /// still performed by inference at the observe/assist rungs, where the prose *is* the work.
    @Test(
        "a non-state-changing step with the same capability still runs",
        arguments: [PlanStepKind.observe, PlanStepKind.assist]
    )
    func nonStateChangingStepWithSameCapabilityStillRuns(kind: PlanStepKind) async throws {
        let store = CapturingReceiptStore()
        let executor = AutopilotStepExecutor(
            receiptStore: store,
            eventBus: nil,
            sessionStore: nil,
            correlationID: "corr-advisory",
            modeProvider: { .observe },
            goal: PlanningGoal(text: "make me a playlist"),
            performer: FakeStepPerformer(telemetry: nil),
            operatorRunner: nil
        )
        let step = PlanStep(capability: .playlistManagement, kind: kind, title: "Draft the playlist", rationale: "for review")

        let result = try await executor.execute(step)

        #expect(result.summary.hasPrefix("Autopilot ran"))
        #expect(((try? await store.latest(limit: 10)) ?? []).first?.isSuccess == true)
    }

    /// Ordering guard: the operator branch is consulted *before* the state-changing refusal, so an
    /// `execute` step that does have a mapped operator still routes through the governed pipeline
    /// rather than being refused out of hand.
    @Test("a state-changing step with a mapped operator still routes to the operator")
    func stateChangingStepWithOperatorStillRoutes() async throws {
        let store = CapturingReceiptStore()
        let recorder = ToolIDRecorder()
        let executor = AutopilotStepExecutor(
            receiptStore: store,
            eventBus: nil,
            sessionStore: nil,
            correlationID: "corr-exec-op",
            modeProvider: { .observe },
            goal: PlanningGoal(text: "look into vitalik.eth"),
            performer: FakeStepPerformer(telemetry: nil),
            operatorRunner: { toolID, _, correlationID in
                await recorder.record(toolID, correlationID: correlationID)
                return .executed(ToolCallArtifact(toolID: toolID, summary: "brief"))
            }
        )
        let step = PlanStep(capability: .runPlugin, kind: .execute, title: "Run the plugin", rationale: "r")

        let result = try await executor.execute(step)

        #expect(await recorder.toolID == OperatorCatalog.researchBriefID)
        #expect(result.summary.hasPrefix("Autopilot ran"))
        #expect(((try? await store.latest(limit: 10)) ?? []).first?.isSuccess == true)
    }

    /// End to end through the host: the refusal halts the run and surfaces as a planner failure, so
    /// the session does not close `.completed` over a step that did nothing.
    @Test("a goal whose execute step cannot be performed is classified as a planner failure")
    func unperformableStepMakesTheRunFail() async throws {
        let store = CapturingReceiptStore()
        let host = RuntimeHost(
            receiptStore: store,
            identity: RuntimeIdentityHooks(cryptoModeProvider: { .observe })
        )
        host.autopilotPlannerOverride = UnperformableStepPlanner()
        host.autopilotStepPerformerOverride = FakeStepPerformer(telemetry: nil)
        await host.bootstrap()

        let run = await host.runAutopilotGoal("make me a playlist", correlationID: "corr-unperformable-e2e")

        #expect(run.result.isComplete == false)
        #expect(RuntimeHost.conclusion(for: run.result).plannerFailureReason != nil)
        let receipts = (try? await store.latest(limit: 20)) ?? []
        let refusal = try #require(receipts.first { $0.trigger == "autopilot.step.unperformable" })
        #expect(refusal.isSuccess == false)
        // And nothing anywhere claims the step ran.
        #expect(receipts.contains { $0.trigger == "autopilot.step.ran" } == false)
    }

    /// An operator that *does* execute is unaffected — the success path still reports success.
    @Test("an executed operator still reports the step as ran")
    func executedOperatorStillSucceeds() async throws {
        let store = CapturingReceiptStore()
        let executor = AutopilotStepExecutor(
            receiptStore: store,
            eventBus: nil,
            sessionStore: nil,
            correlationID: "corr-op-ok",
            modeProvider: { .observe },
            goal: PlanningGoal(text: "look into vitalik.eth"),
            performer: FakeStepPerformer(telemetry: nil),
            operatorRunner: { toolID, _, _ in .executed(ToolCallArtifact(toolID: toolID, summary: "brief")) }
        )
        let step = PlanStep(capability: .runPlugin, kind: .observe, title: "Research", rationale: "gather context")

        let result = try await executor.execute(step)

        #expect(result.summary.hasPrefix("Autopilot ran"))
        #expect(((try? await store.latest(limit: 10)) ?? []).first?.isSuccess == true)
    }

    // MARK: - planner outcome classification

    /// `runAutopilotGoal` published `.plannerCompleted` unconditionally and nothing published
    /// `.plannerFailed`, so `RuntimePerformanceObserver` recorded `.success` for every planner run
    /// and Mission Control's planner health was pinned at 100%.
    @Test("a run whose step does not complete is classified as a planner failure")
    func conclusionClassifiesEachTerminalShape() {
        let step = PlanStep(capability: .runPlugin, kind: .observe, title: "Research", rationale: "gather context")
        let plan = Plan(goal: PlanningGoal(text: "goal"), steps: [step], summary: "s", deliberation: PlanDeliberation(planner: "test", candidates: []))

        func conclusion(_ status: StepReport.Status, _ authorization: StepAuthorization = .autopilot) -> RuntimeHost.AutopilotRunConclusion {
            RuntimeHost.conclusion(
                for: OrchestrationResult(
                    plan: plan,
                    reports: [StepReport(step: step, authorization: authorization, status: status)]
                )
            )
        }

        #expect(conclusion(.ran(summary: "did it")) == .completed)
        #expect(conclusion(.failed("operator refused")) == .failed(reason: "operator refused"))
        #expect(conclusion(.blocked, .blocked("not allowed in Observe")) == .blocked(reason: "not allowed in Observe"))
        #expect(conclusion(.pausedForConfirmation, .needsConfirmation("ok?")) == .awaitingConfirmation)
        // An empty plan is a planning failure, not a silent success.
        #expect(RuntimeHost.conclusion(for: OrchestrationResult(plan: plan, reports: [])).plannerFailureReason != nil)
    }

    /// End to end: a cleared step whose governed operator is refused must surface as `.plannerFailed`
    /// on the bus — the event `RuntimePerformanceObserver` turns into a failed planner run.
    @Test("an autopilot run whose governed step is refused publishes plannerFailed")
    func refusedStepPublishesPlannerFailed() async {
        let host = RuntimeHost(
            receiptStore: CapturingReceiptStore(),
            identity: RuntimeIdentityHooks(cryptoModeProvider: { .observe })
        )
        host.autopilotPlannerOverride = DeterministicGoalPlanner(templates: [
            PlanTemplate(
                id: "research-goal",
                keywords: ["research"],
                summary: "Research the subject.",
                steps: [
                    PlanStep(capability: .runPlugin, kind: .observe, title: "Research the subject", rationale: "Gather context.")
                ]
            )
        ])
        host.autopilotStepPerformerOverride = FakeStepPerformer(telemetry: nil)
        await host.bootstrap()
        // A capability restriction is how a cleared step's governed run comes back refused while the
        // runtime is otherwise healthy and running.
        //
        // This used to throw the kill switch instead, which no longer reaches the situation under
        // test: `runAutopilotGoal` now refuses a paused run outright, before a planner exists, so
        // there is no cleared step and no governed refusal to observe. That refusal is the fix for
        // the kill switch not covering autopilot at all (see
        // `RuntimeHostHardeningTests.autopilotGoalIsRefusedWhilePaused`). The behaviour *this* test
        // exists for is unchanged — a denial refuses the step's governed operator, and the run must
        // still surface as `.plannerFailed` rather than `.plannerCompleted`.
        //
        // `.runPlugin` is what `AutopilotStepExecutor.operatorToolID(for:)` maps to a governed
        // operator, so denying it is what makes this step's operator run come back blocked;
        // `grantingLease` honours a denial ahead of any grant the run would otherwise mint.
        await host.denyCapability(
            .capability(.runPlugin),
            reason: "Test denial so the cleared step's operator run is refused"
        )

        await host.runAutopilotGoal("research vitalik.eth", correlationID: "corr-planner-failed")

        let events = await host.recentEvents(limit: 200)
        let sawFailure = events.contains { if case .plannerFailed = $0.event { return true } else { return false } }
        let sawCompletion = events.contains { if case .plannerCompleted = $0.event { return true } else { return false } }
        #expect(sawFailure)
        #expect(sawCompletion == false)
    }

    /// The planning receipt is attributed to the model that produced the plan, with provenance.
    @Test
    func planningReceiptIsAttributedToThePlanningModel() async throws {
        let store = CapturingReceiptStore()
        let host = RuntimeHost(
            receiptStore: store,
            identity: RuntimeIdentityHooks(cryptoModeProvider: { .observe })
        )
        host.autopilotPlannerOverride = TelemetryPlanner(telemetry: fakeLocalTelemetry(prompt: 12, completion: 4))
        host.autopilotStepPerformerOverride = FakeStepPerformer(telemetry: nil)
        await host.bootstrap()

        _ = await host.runAutopilotGoal("inspect my library", correlationID: "corr-plan-actor")

        let receipts = (try? await store.latest(limit: 20)) ?? []
        let planningReceipt = try #require(receipts.first { $0.trigger == "autopilot.planning.model" })
        let detail = try #require(planningReceipt.actorDetail)
        #expect(detail.kind == "model")
        #expect(detail.identifier == "planner.model")
        #expect(detail.inferenceLocality == InferenceLocality.local.rawValue)
        #expect(detail.inferenceProvider == "Apple Foundation Models")
    }

    /// A step receipt reports the posture the app is in *when the step is recorded*, not the one it
    /// was in when the goal started.
    ///
    /// The executor used to capture `cryptoMode.receiptMode` as a value at construction and stamp it
    /// on every step. A goal run is the longest-lived thing in the runtime, so a person switching
    /// Observe → Assist partway through left the remaining steps claiming a mode the app had left —
    /// on the one column whose value is that it records the posture work really ran under.
    @Test("a step receipt follows a mode change that happens mid-run")
    func stepReceiptReadsTheLiveModeNotAStartOfRunSnapshot() async throws {
        let store = CapturingReceiptStore()
        let mode = ModeBox(.observe)
        let executor = AutopilotStepExecutor(
            receiptStore: store,
            eventBus: nil,
            sessionStore: nil,
            correlationID: "corr-mode-change",
            modeProvider: { mode.value },
            goal: PlanningGoal(text: "tidy my library"),
            performer: FakeStepPerformer(telemetry: nil),
            operatorRunner: nil
        )
        let step = PlanStep(
            capability: .musicLibraryClassification,
            kind: .observe,
            title: "Inspect library",
            rationale: "Gather context."
        )

        _ = try await executor.execute(step)
        // The person switches posture between steps, exactly as they can from the Mode Surface.
        mode.value = .assist
        _ = try await executor.execute(step)

        // `latest` is newest-first, so the second step's receipt is the head.
        let receipts = (try? await store.latest(limit: 10)) ?? []
        #expect(receipts.count == 2)
        #expect(receipts.first?.mode == .assist)
        #expect(receipts.last?.mode == .observe)
    }
}

/// A mutable mode holder, so a test can change the posture between two `execute` calls the way a
/// person changes it between two steps of a live run.
@MainActor
private final class ModeBox {
    var value: ReceiptMode
    init(_ value: ReceiptMode) { self.value = value }
}

private actor ToolIDRecorder {
    private(set) var toolID: String?
    private(set) var correlationID: String?

    func record(_ id: String, correlationID: String? = nil) {
        toolID = id
        self.correlationID = correlationID
    }
}

/// A performer that records whether it was asked to do anything, so a test can assert that an
/// unperformable step never reaches inference at all. A class rather than a struct because the flag
/// has to survive the `any AutopilotStepPerforming` existential the executor stores it behind.
@MainActor
private final class RecordingStepPerformer: AutopilotStepPerforming {
    let telemetry: InferenceTelemetry?
    private(set) var didPerform = false

    init(telemetry: InferenceTelemetry?) {
        self.telemetry = telemetry
    }

    func perform(_ step: PlanStep, goal: PlanningGoal) async -> AutopilotStepWork {
        didPerform = true
        return AutopilotStepWork(output: "should not have run", telemetry: telemetry)
    }
}

/// Plans the one shape that used to be mis-receipted: a cleared, non-crypto, state-changing step
/// whose capability has no mapped operator. Mirrors `PlanTemplateCatalog`'s `make-playlist` tail.
private struct UnperformableStepPlanner: GoalPlanning {
    let name = "unperformable"

    func makePlan(for goal: PlanningGoal) async -> Plan {
        Plan(
            goal: goal,
            steps: [
                PlanStep(
                    capability: .playlistManagement,
                    kind: .execute,
                    title: "Create the playlist",
                    rationale: "Save the playlist once you approve it."
                )
            ],
            summary: "Create the playlist.",
            deliberation: PlanDeliberation(
                planner: "unperformable",
                candidates: [
                    PlanCandidate(
                        title: "Create the playlist",
                        capability: .playlistManagement,
                        isSelected: true,
                        rationale: "Selected the write step directly."
                    )
                ]
            )
        )
    }
}
