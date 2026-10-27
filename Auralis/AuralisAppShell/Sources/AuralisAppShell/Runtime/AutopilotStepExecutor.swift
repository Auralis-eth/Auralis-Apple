import AuralisPrimaryModels
import AuralisFoundation
import Foundation
import AuralisOperators
import OSLog
import AuralisRuntime
import AuralisReceipts

#if canImport(FoundationModels)
import FoundationModels
#endif

/// The real work a cleared autopilot step produced, plus the honest inference telemetry behind it.
///
/// `telemetry` is `nil` when no model ran (e.g. no on-device model available). We record the step
/// either way, but we never fabricate token counts for work that never touched a model.
struct AutopilotStepWork: Sendable {
    let output: String
    let telemetry: InferenceTelemetry?
}

/// A cleared autopilot step whose governed operator did not execute — it was blocked, it failed, or
/// it escalated for approval.
///
/// Thrown rather than returned because ``StepExecutionOutcome`` carries only a summary, so a
/// non-throwing return is indistinguishable from success to ``SequentialPlanOrchestrator``. The
/// orchestrator records the throw as `.failed` on this step and reports the remainder as `.skipped`.
struct AutopilotOperatorStepFailure: LocalizedError {
    let stepTitle: String
    let toolID: String
    let outcomeDescription: String

    var errorDescription: String? {
        "Autopilot step “\(stepTitle)” did not complete: \(toolID) \(outcomeDescription)."
    }
}

/// A cleared state-changing step that this executor has no way to carry out.
///
/// Thrown for the same reason ``AutopilotOperatorStepFailure`` is: ``StepExecutionOutcome`` carries
/// only a summary, so a non-throwing return is indistinguishable from success to
/// ``SequentialPlanOrchestrator``, which records the throw as `.failed` on this step and reports the
/// remainder as `.skipped`. Halting is the point — the steps after "Create the playlist" would
/// otherwise build on a playlist that does not exist.
struct AutopilotUnperformableStepFailure: LocalizedError {
    let stepTitle: String
    let capability: String
    let reason: String

    var errorDescription: String? {
        "Autopilot step “\(stepTitle)” could not be performed: \(reason)."
    }
}

/// Performs the real, model-backed work of a cleared observe/assist plan step.
///
/// Injectable so the runtime uses on-device FoundationModels in production while tests supply a
/// deterministic double (no model call, known telemetry).
@MainActor
protocol AutopilotStepPerforming: Sendable {
    func perform(_ step: PlanStep, goal: PlanningGoal) async -> AutopilotStepWork
}

/// The runtime's concrete ``StepExecuting`` for autopilot goal runs.
///
/// Every step that reaches here has already been cleared by ``JudgeStepAuthorizer``. That clearance is
/// **not** limited to observe/assist steps, and this type used to claim it was: ``DomainJudge`` is
/// crypto-scoped by design — the rest of the app is full CRUD — so a non-crypto
/// ``ActionImpactClass/reversibleWrite`` `execute` step is authorized to run unattended. Crypto
/// `execute` steps are blocked in Observe and escalated in Assist, so those genuinely never arrive.
///
/// For each cleared step the executor does *real* work, or refuses:
///
/// - If the step's capability maps to a registered governed operator, it runs that operator through
///   the same governed pipeline the rest of the app uses, producing a real artifact + telemetry, and
///   fails the step if the operator did not execute.
/// - If the step is state-changing and has *no* mapped operator, there is nothing here that can carry
///   it out, so it is receipted as unperformable and thrown. See ``refuseUnperformableStep(_:)``.
/// - Otherwise — a read-only or advisory step — it performs the step with a real on-device inference
///   pass that produces actual output and reports **real** token usage (`InferenceTelemetry`), never
///   estimated or invented.
///
/// Every branch records a correlated receipt carrying the telemetry keys Mission Control's inference
/// snapshot reads, so the Agent Activity Timeline shows what actually ran, what it cost, and what
/// could not be done at all.
@MainActor
struct AutopilotStepExecutor: StepExecuting {
    let receiptStore: any ReceiptStore
    let eventBus: (any RuntimeEventPublishing)?
    let sessionStore: (any AgentSessionStoring)?
    let correlationID: String
    /// The crypto posture to stamp on each step receipt, read at the moment the step is recorded.
    ///
    /// A provider rather than a captured `ReceiptMode` for the same reason ``ReceiptStoreSink`` and
    /// ``RuntimeReceiptObserver`` take one: the mode is live state owned by the host and can change
    /// while work is in flight. An autopilot goal is the longest-running thing in the runtime — a
    /// multi-step plan spans many seconds and the person can switch Observe → Assist partway through —
    /// so this was the one receipt path that snapshotted the posture at run start and then stamped it
    /// on every later step, reporting a mode the app was no longer in.
    let modeProvider: @MainActor @Sendable () -> ReceiptMode
    let goal: PlanningGoal
    let performer: any AutopilotStepPerforming
    /// Runs a governed operator by id with a request, when the step's capability maps to one. Supplied
    /// by ``RuntimeHost`` so the operator flows through the real pipeline (and stamps its own receipt).
    ///
    /// Takes the correlation id as its third argument so the pipeline's trace joins *this* goal's
    /// workflow. Without it the operator run minted its own id, and the governed entries for a
    /// cleared step landed in a different trace than the deliberation that chose it.
    let operatorRunner: (@MainActor (String, OperatorRequest, String) async -> ToolCallOutcome)?
    /// Reports a step receipt that could not be persisted, so the host raises the same
    /// degraded-audit-evidence signal it raises for its own receipts. Supplied by ``RuntimeHost``.
    ///
    /// Without this, both appends below used `try?` and discarded the error: the step returned a
    /// successful ``StepExecutionOutcome`` and Mission Control presented it as fully receipted while
    /// no receipt existed. The governed pipeline's own sink propagates append failures, and
    /// `RuntimeHost.appendRuntimeReceipt` surfaces them on `receiptPersistenceError` — this was the
    /// one write path that stayed quiet.
    var receiptFailureReporter: (@MainActor (ActorRef) async -> Void)?

    func execute(_ step: PlanStep) async throws -> StepExecutionOutcome {
        // 1) Route to a real governed operator when the capability has one registered.
        if let toolID = Self.operatorToolID(for: step.capability), let operatorRunner {
            let outcome = await operatorRunner(toolID, OperatorRequest(query: goal.text), correlationID)
            // The governed outcome decides whether this step succeeded. It previously did not: the
            // outcome was described into the payload and then discarded, so a `.blocked`, `.failed`,
            // or `.needsApproval` operator produced an `isSuccess: true` receipt and a `.ran` step
            // report. The run then continued onto later steps — the "broken foundation" case
            // `SequentialPlanOrchestrator` halts for — and the session closed as `.completed`.
            let didExecute = Self.didExecute(outcome)
            let summary = didExecute
                ? "Autopilot ran “\(step.title)” via \(toolID)"
                : "Autopilot step “\(step.title)” did not complete via \(toolID)"
            // An operator pack did this work — name it (P0.5-602).
            let stepActor = ActorRef(kind: .operatorAgent, identifier: toolID)
            let receiptID = await appendStepReceipt(
                ReceiptDraft(
                    category: "autopilot",
                    kind: "autopilot.step.operator",
                    correlationID: correlationID,
                    payload: ReceiptPayload(values: [
                        "stepTitle": .string(step.title),
                        "capability": .string(step.capability.rawValue),
                        "kind": .string(step.kind.rawValue),
                        "operatorID": .string(toolID),
                        "operatorOutcome": .string(Self.describe(outcome))
                    ]),
                    actorDetail: stepActor.receiptActorDetail,
                    // This is autopilot's own step receipt, not the governed pipeline's. The pipeline
                    // records the lease it resolved on *its* receipt; what permitted autopilot to
                    // dispatch the step at all is the standing autopilot authorization.
                    authorityDetail: ReceiptAuthorityDetail(source: "policyDefault",
                        capability: step.capability.rawValue,
                        reason: "Autopilot step dispatched under standing autopilot authorization."
                    ),
                    mode: modeProvider(),
                    summary: summary,
                    provenance: "autopilot",
                    isSuccess: didExecute
                ),
                actor: stepActor
            )
            await noteReceipt(receiptID, actor: stepActor)
            // Receipt first, then throw: the attempt happened and its evidence belongs in the
            // ledger either way. Throwing is the only channel an executor has for "this step did
            // not do what it was asked" — `StepExecutionOutcome` carries a summary and nothing
            // else — and it is what makes the orchestrator halt instead of building on the failure.
            guard didExecute else {
                throw AutopilotOperatorStepFailure(
                    stepTitle: step.title,
                    toolID: toolID,
                    outcomeDescription: Self.describe(outcome)
                )
            }
            return StepExecutionOutcome(summary: summary)
        }

        // 2) A state-changing step with no mapped operator cannot be carried out here. Refuse it
        //    before the performer runs, rather than describe it.
        if step.kind.isStateChanging {
            try await refuseUnperformableStep(step)
        }

        // 3) Otherwise perform the step with a real inference pass and record its real telemetry.
        let work = await performer.perform(step, goal: goal)
        let summary = "Autopilot ran “\(step.title)” (\(step.kind.rawValue))"

        var values: [String: ReceiptJSONValue] = [
            "stepTitle": .string(step.title),
            "capability": .string(step.capability.rawValue),
            "kind": .string(step.kind.rawValue),
            "rationale": .string(step.rationale),
            "output": .string(work.output)
        ]
        // Only stamp inference telemetry when a model actually ran — otherwise the timeline correctly
        // reads "Not recorded" rather than showing a zero-token phantom inference.
        if let t = work.telemetry {
            values["modelProvider"] = .string(t.route.provider)
            values["modelClass"] = .string(t.route.modelClass)
            values["inferenceLocality"] = .string(t.route.locality.rawValue)
            values["privacyImpact"] = .string(t.route.privacyImpact)
            values["promptTokens"] = .string("\(t.promptTokens)")
            values["completionTokens"] = .string("\(t.completionTokens)")
            values["tokensEstimated"] = .string("\(t.tokensEstimated)")
            values["durationSeconds"] = .string("\(t.durationSeconds)")
            values["estimatedCost"] = .string("\(t.estimatedCost)")
        }

        // When a model actually ran, attribute the step to that model and carry its inference
        // provenance in the structured column (P0.5-602) — the same facts the loose payload keys
        // above expose to the timeline. With no model, the workflow itself is the actor.
        let stepActor: ActorRef = work.telemetry.map {
            ActorRef.model(identifier: $0.route.modelClass, route: $0.route)
        } ?? ActorRef(kind: .workflow, identifier: "autopilot")

        let receiptID = await appendStepReceipt(
            ReceiptDraft(
                category: "autopilot",
                kind: "autopilot.step.ran",
                correlationID: correlationID,
                payload: ReceiptPayload(values: values),
                actorDetail: stepActor.receiptActorDetail,
                authorityDetail: ReceiptAuthorityDetail(source: "policyDefault",
                    capability: step.capability.rawValue,
                    reason: "Autopilot step dispatched under standing autopilot authorization."
                ),
                mode: modeProvider(),
                summary: summary,
                provenance: "autopilot",
                isSuccess: true
            ),
            actor: stepActor
        )
        await noteReceipt(receiptID, actor: stepActor)
        if let telemetry = work.telemetry {
            await noteTelemetry(telemetry, actor: stepActor)
        }
        return StepExecutionOutcome(summary: summary)
    }

    /// Receipts a state-changing step this executor cannot carry out, then throws so the run halts.
    ///
    /// The gap this closes: the operator branch above resolves a step's success from the governed
    /// outcome, but the inference branch below reports `isSuccess: true` unconditionally — it has no
    /// outcome to consult, only prose. That is correct for a read-only or advisory step, where the
    /// prose *is* the work. It was wrong for a state-changing one, and those do reach here: only
    /// ``CapabilityID/runPlugin`` has a mapped operator (see ``operatorToolID(for:)``), while
    /// ``DomainJudge`` clears non-crypto reversible writes to run unattended. So `PlanTemplateCatalog`'s
    /// "Create the playlist" (``CapabilityID/playlistManagement``) and "Apply the organization"
    /// (``CapabilityID/autoOrganization``) fell through to the inference path, produced a paragraph,
    /// and recorded `autopilot.step.ran` with `isSuccess: true`. No playlist was created; the receipt
    /// said the step succeeded, and the orchestrator ran the following steps on top of it.
    ///
    /// That is the same defect the operator branch fixed with its `didExecute` guard, and the one
    /// output this runtime must not produce: a success receipt for work that never happened.
    ///
    /// The performer is deliberately **not** run first. Prose describing a library change that cannot
    /// occur is not evidence of anything, and an inference pass would attach real
    /// ``InferenceTelemetry`` — token counts, cost, a model actor — to a step that did nothing.
    ///
    /// A distinct receipt `kind` rather than a failed `autopilot.step.ran`, for the reason
    /// ``RuntimeHost/PauseOrigin/identifier`` gives: it makes the ledger *queryable* for capabilities
    /// autopilot is cleared for but cannot perform. That gap is a wiring fact worth finding — the fix
    /// is to register an operator for the capability — not merely a run that went wrong.
    private func refuseUnperformableStep(_ step: PlanStep) async throws -> Never {
        let reason = "no governed operator is registered for \(step.capability.rawValue)"
        let summary = "Autopilot could not perform “\(step.title)”: \(reason)"
        // No model ran, so the workflow itself is the actor — the same attribution the no-telemetry
        // branch below uses.
        let stepActor = ActorRef(kind: .workflow, identifier: "autopilot")
        let receiptID = await appendStepReceipt(
            ReceiptDraft(
                category: "autopilot",
                kind: "autopilot.step.unperformable",
                correlationID: correlationID,
                payload: ReceiptPayload(values: [
                    "stepTitle": .string(step.title),
                    "capability": .string(step.capability.rawValue),
                    "kind": .string(step.kind.rawValue),
                    "rationale": .string(step.rationale),
                    "reason": .string(reason)
                ]),
                actorDetail: stepActor.receiptActorDetail,
                // What permitted the *attempt* is unchanged — the step was dispatched under standing
                // autopilot authorization, exactly like the two branches around it. The authority was
                // never the problem here; the missing capability to act on it was.
                authorityDetail: ReceiptAuthorityDetail(source: "policyDefault",
                    capability: step.capability.rawValue,
                    reason: "Autopilot step dispatched under standing autopilot authorization."
                ),
                mode: modeProvider(),
                summary: summary,
                provenance: "autopilot",
                isSuccess: false
            ),
            actor: stepActor
        )
        await noteReceipt(receiptID, actor: stepActor)
        throw AutopilotUnperformableStepFailure(
            stepTitle: step.title,
            capability: step.capability.rawValue,
            reason: reason
        )
    }

    /// Appends a step receipt, reporting a write failure through ``receiptFailureReporter`` rather
    /// than discarding it. The step still reports the work it genuinely did — the effect happened —
    /// but the run is now marked as carrying incomplete audit evidence.
    private func appendStepReceipt(_ draft: ReceiptDraft, actor: ActorRef) async -> UUID? {
        do {
            return try await receiptStore.append(draft).id
        } catch {
            await receiptFailureReporter?(actor)
            return nil
        }
    }

    /// Files a step's receipt onto the goal's session.
    ///
    /// - Important: Read → mutate → upsert with no compare-and-set, across a suspension point — and
    ///   this executor runs it *twice* per step (here, then ``noteTelemetry(_:actor:)``), so the
    ///   second read already sees the first write. What keeps that safe is that
    ///   `SequentialPlanOrchestrator` clears one step at a time and halts at the first that does not,
    ///   so only one step is ever in flight under this `correlationID`.
    ///
    ///   This one genuinely is a property of the orchestrator rather than of the runtime, and remains
    ///   so: ``RuntimeHost/runAutopilotGoal(_:surface:correlationID:)`` is the one governed entry point
    ///   that does *not* take ``CorrelationGate``, because it dispatches its own cleared steps through
    ///   ``RuntimeHost/runOperator(toolID:request:correlationID:)`` under the goal's id and would
    ///   deadlock on itself. Parallelising plan steps would make two steps race for the same session
    ///   and silently drop one's `receiptID` or telemetry; that change needs a merging upsert in
    ///   ``AgentSessionStoring`` first. Same note as
    ///   ``RuntimeHost/noteRuntimeSession(correlationID:goal:actor:_:)``.
    private func noteReceipt(_ receiptID: UUID?, actor: ActorRef) async {
        guard let receiptID else { return }
        await eventBus?.publish(WorkflowEventEnvelope(event: .receiptCreated(id: receiptID), correlationID: correlationID))
        guard let sessionStore else { return }
        var session = await sessionStore.session(correlationID: correlationID)
            ?? AgentSession(correlationID: correlationID, goal: goal.text, actor: actor)
        session.note(receiptID: receiptID)
        await sessionStore.upsert(session)
    }

    private func noteTelemetry(_ telemetry: InferenceTelemetry, actor: ActorRef) async {
        guard let sessionStore else { return }
        var session = await sessionStore.session(correlationID: correlationID)
            ?? AgentSession(correlationID: correlationID, goal: goal.text, actor: actor)
        session.note(telemetry: telemetry)
        await sessionStore.upsert(session)
    }

    /// Maps a plan step's capability to a registered governed operator id, when one exists. Steps whose
    /// capability has no operator fall through to the on-device inference path.
    static func operatorToolID(for capability: CapabilityID) -> String? {
        switch capability {
        case .runPlugin: return OperatorCatalog.researchBriefID
        default: return nil
        }
    }

    /// Whether a governed outcome means the step's work actually happened. Only `.executed` does:
    /// an escalated (`.needsApproval`) step is waiting on a person, and the rest are refusals.
    private static func didExecute(_ outcome: ToolCallOutcome) -> Bool {
        if case .executed = outcome { return true }
        return false
    }

    private static func describe(_ outcome: ToolCallOutcome) -> String {
        switch outcome {
        case let .executed(artifact): return "executed: \(artifact.summary)"
        case let .blocked(reason): return "blocked: \(reason)"
        case let .needsRevision(instructions): return "needs revision: \(instructions)"
        case .needsApproval: return "escalated for approval"
        case let .failed(reason): return "failed: \(reason)"
        case let .evidenceIncomplete(_, failures): return "governance evidence incomplete: \(failures.joined(separator: "; "))"
        }
    }
}

/// The default per-step performer used when no on-device model is available. It records honest output
/// and **no** inference telemetry (no model ran), so nothing is fabricated.
@MainActor
struct DeterministicAutopilotStepPerformer: AutopilotStepPerforming {
    func perform(_ step: PlanStep, goal: PlanningGoal) async -> AutopilotStepWork {
        let output = "Prepared “\(step.title)” for “\(goal.text)”. Recorded without on-device inference "
            + "(no model available on this device)."
        return AutopilotStepWork(output: output, telemetry: nil)
    }
}

/// What one on-device inference produced, in this package's own vocabulary.
///
/// Deliberately not `LanguageModelSession.Response`: that type cannot be constructed outside
/// FoundationModels, so a seam expressed in terms of it would be unsubstitutable and therefore no
/// seam at all.
struct OnDeviceModelResponse: Sendable {
    let content: String
    /// `nil` means *this OS cannot report usage*, which is a different claim from "zero tokens" and is
    /// why it is optional rather than defaulted. `Response.usage` only exists from iOS/macOS 27; on 26
    /// the model genuinely runs and the counts simply are not measurable, so the performer records 0
    /// rather than estimating. Collapsing the two here would have lost the distinction before anyone
    /// could act on it.
    ///
    /// - Important: ``InferenceTelemetry`` has no "not reported" state — `promptTokens` is a plain
    ///   `Int` and `tokensEstimated` only distinguishes *approximated* from *reported*. So the zero the
    ///   performer records is a sentinel, and what keeps it honest is a rule in another package:
    ///   `MissionControlHomeModel.InferenceSnapshot.tokensLabel` renders `totalTokens == 0` as
    ///   "Not recorded" rather than "0 tokens". A change there to print the count literally would turn
    ///   this into the "zero-token phantom inference" that ``AutopilotStepExecutor/execute(_:)`` says it
    ///   refuses to produce — silently, and only on iOS 26. Representing it properly needs an optional
    ///   or an `isReported` flag on `InferenceTelemetry` in `AuralisRuntime`.
    let promptTokens: Int?
    let completionTokens: Int?
}

/// The on-device system model, reduced to the two things ``ModelAutopilotStepPerformer`` asks of it.
///
/// Exists so the *local* inference branch is reachable from a test. It previously read
/// `SystemLanguageModel.default.availability` and called `LanguageModelSession.respond` directly, so
/// there was nothing to substitute: the availability gate, the degrade-to-fallback paths, and the
/// token-usage mapping — the honesty-critical parts, since they decide whether the timeline claims an
/// inference happened — could only be exercised on a physical Apple Intelligence device. On the
/// simulator on-device inference fails a safety guardrail and degrades, so CI validated the fallback
/// and nothing else.
///
/// Narrow on purpose. Widening it to expose sessions or transcripts would pull FoundationModels types
/// back across the boundary and undo the substitutability that is the whole point.
@MainActor
protocol OnDeviceLanguageModeling: Sendable {
    /// Whether the system model can run right now. `false` covers every not-available reason —
    /// unsupported device, Apple Intelligence off, model still downloading — because the performer's
    /// response to all of them is identical: honest no-inference output.
    var isAvailable: Bool { get }

    func respond(to prompt: String, instructions: [String]) async throws -> OnDeviceModelResponse
}

#if canImport(FoundationModels)
/// The production conformer: the real `SystemLanguageModel` and a real `LanguageModelSession`.
///
/// Holds no state between calls — a session is created per request exactly as before, so the
/// extraction changed nothing about how inference runs.
@available(iOS 26.0, macOS 26.0, *)
@MainActor
struct SystemLanguageModelClient: OnDeviceLanguageModeling {
    var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    func respond(to prompt: String, instructions: [String]) async throws -> OnDeviceModelResponse {
        let session = LanguageModelSession(
            instructions: Instructions {
                for instruction in instructions {
                    instruction
                }
            }
        )
        let response = try await session.respond(to: prompt)
        // Real token usage is exposed on `Response.usage` from iOS/macOS 27. On 26 the model still
        // runs (real output, real locality) but the counts aren't measurable, so this reports `nil`
        // and lets the performer record 0 rather than estimate.
        if #available(iOS 27.0, macOS 27.0, *) {
            let usage = response.usage
            return OnDeviceModelResponse(
                content: response.content,
                promptTokens: usage.input.totalTokenCount,
                completionTokens: usage.output.totalTokenCount
            )
        }
        return OnDeviceModelResponse(content: response.content, promptTokens: nil, completionTokens: nil)
    }
}

/// The production performer: runs a bounded on-device inference to carry out an observe/assist step,
/// and reports the model's **real** token usage (`Response.usage`) — the source of the timeline's
/// honest token/model metadata.
@available(iOS 26.0, macOS 26.0, *)
@MainActor
struct ModelAutopilotStepPerformer: AutopilotStepPerforming {
    private let modelRouter: any ModelRouting
    private let modelInferenceClient: any ModelInferring
    /// The on-device model behind the local route. Defaults to the real one, so the shipping path is
    /// unchanged; tests substitute a double. See ``OnDeviceLanguageModeling``.
    private let onDeviceModel: any OnDeviceLanguageModeling

    init(
        modelRouter: any ModelRouting = TaskKindModelRouter.localFirstDefault,
        modelInferenceClient: any ModelInferring = UnsupportedModelInferenceClient(),
        onDeviceModel: any OnDeviceLanguageModeling = SystemLanguageModelClient()
    ) {
        self.modelRouter = modelRouter
        self.modelInferenceClient = modelInferenceClient
        self.onDeviceModel = onDeviceModel
    }

    func perform(_ step: PlanStep, goal: PlanningGoal) async -> AutopilotStepWork {
        let route = await modelRouter.route(forTaskKind: ModelTaskKind.autopilotStep) ?? DefaultModelRoutes.localLanguageModel
        if route.locality == .remote {
            return await performRemote(step, goal: goal, route: route)
        }
        guard route.locality == .local else {
            return AutopilotStepWork(output: Self.fallbackOutput(step, goal), telemetry: nil)
        }
        guard onDeviceModel.isAvailable else {
            return AutopilotStepWork(output: Self.fallbackOutput(step, goal), telemetry: nil)
        }

        let contextNow = Date()
        let request: ModelInferenceRequest
        do {
            request = try Self.authorizedRequest(for: step, goal: goal, at: contextNow)
        } catch {
            Self.logDegradation("the step's context bundle did not satisfy its contract", step, error)
            return AutopilotStepWork(output: Self.fallbackOutput(step, goal), telemetry: nil)
        }

        let started = Date()
        let response: OnDeviceModelResponse
        do {
            response = try await onDeviceModel.respond(to: request.prompt, instructions: request.instructions)
        } catch {
            Self.logDegradation("the on-device model returned no result", step, error)
            return AutopilotStepWork(output: Self.fallbackOutput(step, goal), telemetry: nil)
        }
        let duration = max(0, Date().timeIntervalSince(started))
        // Unmeasurable usage records 0 rather than an estimate, so the timeline never claims a token
        // count the OS did not report. `tokensEstimated: false` below is true either way: nothing here
        // is estimated, it is either measured or absent. See ``OnDeviceModelResponse/promptTokens``.
        let promptTokens = response.promptTokens ?? 0
        let completionTokens = response.completionTokens ?? 0
        let telemetry = InferenceTelemetry(
            route: route,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            durationSeconds: duration,
            estimatedCost: route.estimatedCost(promptTokens: promptTokens, completionTokens: completionTokens),
            tokensEstimated: false
        )
        return AutopilotStepWork(output: response.content, telemetry: telemetry)
    }

    private func performRemote(_ step: PlanStep, goal: PlanningGoal, route: ModelRoute) async -> AutopilotStepWork {
        let request: ModelInferenceRequest
        do {
            request = try Self.authorizedRequest(for: step, goal: goal, at: Date())
        } catch {
            Self.logDegradation("the step's context bundle did not satisfy its contract", step, error)
            return AutopilotStepWork(output: Self.fallbackOutput(step, goal), telemetry: nil)
        }
        do {
            let response = try await modelInferenceClient.respond(to: request, using: route)
            return AutopilotStepWork(output: response.content, telemetry: response.telemetry)
        } catch {
            Self.logDegradation("the routed inference client returned no result", step, error)
            return AutopilotStepWork(output: Self.fallbackOutput(step, goal), telemetry: nil)
        }
    }

    /// Records why a step fell back to no-inference output.
    ///
    /// Every path above degrades to ``fallbackOutput(_:_:)`` with `telemetry: nil`, which is honest —
    /// no model ran, so no tokens are claimed — but it is also indistinguishable from a device that
    /// simply has no model. These were `try?`, so the *reason* was discarded: a build where the
    /// context contract had drifted, or where on-device inference was failing a safety guardrail on
    /// every request, degraded permanently and silently, and the only symptom was autopilot output
    /// that read as templated. The fallback behaviour is unchanged; only the error now survives.
    private static func logDegradation(_ reason: String, _ step: PlanStep, _ error: Error) {
        logger.error(
            """
            Autopilot step “\(step.title, privacy: .public)” fell back to no-inference output because \
            \(reason, privacy: .public): \(error.localizedDescription, privacy: .public)
            """
        )
    }

    private static let logger = Logger(subsystem: "com.auralis.runtime", category: "autopilot-step")

    private static func authorizedRequest(
        for step: PlanStep,
        goal: PlanningGoal,
        at now: Date
    ) throws -> ModelInferenceRequest {
        try ModelInferenceRequest.authorizing(
            taskKind: ModelTaskKind.autopilotStep,
            instructions: [
                "You are Auralis's operator assistant carrying out one cleared observe/assist step.",
                "Produce a concise, concrete result in 2-4 sentences.",
                "Do not ask questions and do not claim to execute wallet actions."
            ],
            bundle: ContextBundle(fields: [
                ContextField(key: "autopilot.goal", stringValue: goal.text, dataClass: .userProvided, source: .userProvided, lastRefreshed: now),
                ContextField(key: "autopilot.step.title", stringValue: step.title, dataClass: .derived, source: .runtimeHost, lastRefreshed: now),
                ContextField(key: "autopilot.step.rationale", stringValue: step.rationale, dataClass: .derived, source: .runtimeHost, lastRefreshed: now),
                ContextField(key: "autopilot.step.kind", stringValue: step.kind.rawValue, dataClass: .derived, source: .runtimeHost, lastRefreshed: now),
                ContextField(key: "autopilot.step.capability", stringValue: step.capability.rawValue, dataClass: .derived, source: .runtimeHost, lastRefreshed: now)
            ]),
            contract: ContextBundleContract(
                identifier: "model.autopilot.step",
                requirements: [
                    ContextFieldRequirement(key: "autopilot.goal", allowedDataClasses: [.userProvided], maxAge: 60, authoritativeSource: .userProvided, missingFieldBehavior: .fail),
                    ContextFieldRequirement(key: "autopilot.step.title", allowedDataClasses: [.derived], maxAge: 60, authoritativeSource: .runtimeHost, missingFieldBehavior: .fail),
                    ContextFieldRequirement(key: "autopilot.step.rationale", allowedDataClasses: [.derived], maxAge: 60, authoritativeSource: .runtimeHost, missingFieldBehavior: .fail),
                    ContextFieldRequirement(key: "autopilot.step.kind", allowedDataClasses: [.derived], maxAge: 60, authoritativeSource: .runtimeHost, missingFieldBehavior: .fail),
                    ContextFieldRequirement(key: "autopilot.step.capability", allowedDataClasses: [.derived], maxAge: 60, authoritativeSource: .runtimeHost, missingFieldBehavior: .fail)
                ]
            ),
            validationDate: now
        ) { context in
            return """
            Goal: \(context.field("autopilot.goal")?.stringValue ?? "")
            Step: \(context.field("autopilot.step.title")?.stringValue ?? "") - \(context.field("autopilot.step.rationale")?.stringValue ?? "")
            Kind: \(context.field("autopilot.step.kind")?.stringValue ?? "")
            """
        }
    }

    private static func fallbackOutput(_ step: PlanStep, _ goal: PlanningGoal) -> String {
        "Prepared “\(step.title)” for “\(goal.text)”. Recorded without on-device inference "
            + "(the on-device model returned no result)."
    }
}
#endif

/// Builds the default per-step performer: on-device FoundationModels when available, otherwise the
/// deterministic (no-inference) performer.
@MainActor
enum AutopilotStepPerformers {
    static func makeDefault(
        modelRouter: any ModelRouting = TaskKindModelRouter.localFirstDefault,
        modelInferenceClient: any ModelInferring = UnsupportedModelInferenceClient()
    ) -> any AutopilotStepPerforming {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return ModelAutopilotStepPerformer(
                modelRouter: modelRouter,
                modelInferenceClient: modelInferenceClient
            )
        }
        #endif
        return DeterministicAutopilotStepPerformer()
    }
}
