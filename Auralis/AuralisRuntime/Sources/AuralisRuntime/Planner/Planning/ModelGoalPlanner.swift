import AuralisFoundation
import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// A planner that decomposes novel goals with whichever model `modelRouter` selects.
///
/// The model only *routes*: it proposes steps drawn from the offered capabilities and
/// the fixed kind vocabulary, and everything it returns is re-grounded against the
/// allow-list (``PlannerInstructions/groundedCapabilities(from:allowed:)``) so a
/// hallucinated capability is dropped, never executed. If the model is unavailable, or it
/// returns nothing usable, planning falls back to the deterministic planner — the feature
/// degrades to templates rather than failing.
@available(iOS 26.0, macOS 26.0, *)
public struct ModelGoalPlanner: GoalPlanning {
    /// Identifies this implementation, and is stamped on the deliberation only when a model's own
    /// output produced the steps. When planning degrades to templates the plan keeps the fallback
    /// planner's identity instead, because that is the planner that wrote the steps — see
    /// ``GoalPlanning/name`` for why `name` cannot be the attribution identity of a run.
    public let name = "model"

    private let availableCapabilities: [CapabilityID]
    private let fallback: any GoalPlanning
    private let modelRouter: any ModelRouting
    private let modelInferenceClient: any ModelInferring

    public init(
        availableCapabilities: [CapabilityID] = CapabilityID.allCases,
        fallback: any GoalPlanning = DeterministicGoalPlanner(),
        modelRouter: any ModelRouting = TaskKindModelRouter.localFirstDefault,
        modelInferenceClient: any ModelInferring = UnsupportedModelInferenceClient()
    ) {
        self.availableCapabilities = availableCapabilities
        self.fallback = fallback
        self.modelRouter = modelRouter
        self.modelInferenceClient = modelInferenceClient
    }

    @Generable
    struct GeneratedPlan {
        @Guide(description: "A one-line summary of the overall approach.")
        let summary: String
        @Guide(description: "The ordered steps of the plan.")
        let steps: [GeneratedStep]
    }

    @Generable
    struct GeneratedStep {
        @Guide(description: "The capability identifier for this step, copied verbatim from the allowed list.")
        let capability: String
        @Guide(description: "The step kind: observe, assist, or execute.")
        let kind: String
        @Guide(description: "A short user-facing title for the step.")
        let title: String
        @Guide(description: "One sentence explaining why this step is in the plan.")
        let rationale: String
    }

    public func makePlan(for goal: PlanningGoal) async -> Plan {
        let route = await modelRouter.route(forTaskKind: ModelTaskKind.autopilotPlanning) ?? DefaultModelRoutes.localLanguageModel
        // Branch on route *identity*, not on `route.locality`. Locality answers "do bytes leave the
        // device", which is a privacy fact about a route and not an answer to "which executor runs
        // it": every non-remote route — a registered local open model, a sidecar, anything a
        // `ModelProviderRegistry` entry names — is still `.local`, and a `locality != .remote` test
        // sent all of them to `SystemLanguageModel.default`. The configured provider then never ran,
        // its telemetry was stamped `DefaultModelRoutes.localLanguageModel` ("Apple Foundation
        // Models") because that genuinely is what executed, and on a host without the system model
        // the run degraded to templates without the registered provider ever being tried. That is
        // precisely the hardwiring `ModelRouting` forbids ("implementations must not hardwire
        // providers into call sites"). Only the one route whose executor *is* FoundationModels takes
        // the FoundationModels path; every other route goes through the `ModelInferring` seam, which
        // is the seam that exists to be swapped.
        guard route.id == DefaultModelRoutes.localLanguageModel.id else {
            return await makeRoutedPlan(for: goal, using: route)
        }

        guard case .available = SystemLanguageModel.default.availability else {
            return await unmodeledPlan(for: goal, degradedBecause: "Apple Foundation Models is unavailable on this device.")
        }

        let instructionLines = PlannerInstructions.sessionLines
        guard let request = try? authorizedRequest(for: goal, instructions: instructionLines, at: Date()) else {
            return await unmodeledPlan(for: goal, degradedBecause: "The planning prompt did not clear its context governance contract.")
        }
        let session = LanguageModelSession(
            instructions: Instructions {
                for line in request.instructions {
                    line
                }
            }
        )

        let started = Date()
        guard let generated = try? await session.respond(
            to: request.prompt,
            generating: GeneratedPlan.self
        ) else {
            return await unmodeledPlan(for: goal, degradedBecause: "Apple Foundation Models returned no usable response.")
        }
        let duration = max(0, Date().timeIntervalSince(started))

        let telemetry = Self.telemetry(
            // Record the seam that actually executed, not the table row that selected it. This
            // branch calls `SystemLanguageModel.default` directly, and the guard above only proves
            // the chosen route's *id* is the FoundationModels one — a table entry could carry that
            // id with some other provider string and billing rates attached, and `route.provider`
            // is what lands on the planning receipt and the Mission Control provenance row
            // (AGENTS.md: "Do not stamp remote/provider telemetry unless that provider inference
            // seam actually ran"). The routed branch, which really does call `ModelInferring`,
            // reports the provider's own telemetry instead.
            route: DefaultModelRoutes.localLanguageModel,
            instructions: instructionLines,
            // The prompt that was actually sent, not the bare goal: `request.prompt` is the governed
            // rendering (goal + allowed-capability list), so counting `goal.text` under-reported
            // prompt tokens by the whole capability catalog.
            prompt: request.prompt,
            responseSummary: generated.content.summary,
            duration: duration
        )
        return await plan(for: goal, from: generated.content, telemetry: telemetry)
    }

    /// Assembles the final plan from one model response: ground the proposed steps, and fall back to
    /// templates when nothing survives grounding.
    ///
    /// Split out of ``makePlan(for:)`` because the FoundationModels branch above cannot be driven
    /// from a test: it calls `SystemLanguageModel.default` directly, so what it returns is whatever
    /// the host's system model says that minute — `.unavailable` in CI and the simulator, and an
    /// unpredictable real completion on a machine with Apple Intelligence on. Either way no
    /// assertion about what the planner does *with* a given model response could be written against
    /// it. The all-steps-rejected path is precisely the path that most needs one — it is the path a
    /// hallucinated wallet capability takes.
    ///
    /// Shared by both executors on purpose. The routed path grounds provider output through exactly
    /// this function rather than a parallel copy, so the allow-list check, the `observe`→`execute`
    /// kind clamp, and the rejection record cannot drift between "the model Apple ships" and "the
    /// model someone registered".
    func plan(for goal: PlanningGoal, from generated: GeneratedPlan, telemetry: InferenceTelemetry) async -> Plan {
        let grounded = groundedSteps(from: generated.steps)
        guard !grounded.steps.isEmpty else {
            // Grounding rejected everything, so the steps that ship are the templates' — and
            // `telemetry` is dropped rather than carried over. It is tempting to keep it, because an
            // inference really did run and really did cost something; but `deliberation.telemetry
            // != nil` is the single condition RuntimeHost tests to write an `autopilot.planning
            // .model` receipt — `ActorRef.model(route:)`, "Planned goal with <Provider>" — and on
            // this path no provider planned anything. That receipt is the surface a user audits, so
            // a claim they can catch out is worse than a missing one. The inference is not erased:
            // `grounded.candidates` carries every rejected proposal, which is both the evidence a
            // model was asked and the reason its answer was thrown away.
            return unmodeledPlan(await fallback.makePlan(for: goal), recording: grounded.candidates)
        }

        return Plan(
            goal: goal,
            steps: grounded.steps,
            summary: generated.summary.isEmpty ? "Plan for “\(goal.text)”." : generated.summary,
            // `name`, not a literal: the model's own output produced these steps, so this is the one
            // outcome where this planner is the planner of record.
            deliberation: PlanDeliberation(planner: name, candidates: grounded.candidates, telemetry: telemetry)
        )
    }

    /// Plans a goal on a route whose executor is *not* FoundationModels, through the `ModelInferring`
    /// seam the router exists to select.
    ///
    /// The reply is decoded into the same ``GeneratedPlan`` the on-device path returns and grounded by
    /// the same ``plan(for:from:telemetry:)``, so a registered provider is held to the allow-list and
    /// the kind clamp on identical terms — the seam changes the executor, never the grounding.
    ///
    /// Every exit before grounding yields the template plan with `telemetry: nil`. An earlier version
    /// of this path called the provider, discarded `response.content`, returned the template plan and
    /// then stamped `response.telemetry` on it: the goal egressed, the user was billed, and the
    /// receipt claimed a model planned a goal the templates planned. Reading the content fixes the
    /// waste; refusing the stamp on any outcome that did not produce steps is what keeps the receipt
    /// honest (AGENTS.md: "Do not stamp remote/provider telemetry unless that provider inference seam
    /// actually ran; local fallbacks must remain visibly local or unmodeled").
    private func makeRoutedPlan(for goal: PlanningGoal, using route: ModelRoute) async -> Plan {
        // The routed instructions, not `sessionLines`: a provider reached through `ModelInferring`
        // returns a bare `String` with no schema channel, so the JSON contract has to be asked for.
        guard let request = try? authorizedRequest(
            for: goal,
            instructions: PlannerInstructions.routedSessionLines,
            at: Date()
        ) else {
            return await unmodeledPlan(for: goal, degradedBecause: "The planning prompt did not clear its context governance contract.")
        }

        guard let response = try? await modelInferenceClient.respond(to: request, using: route) else {
            return await unmodeledPlan(for: goal, degradedBecause: "\(route.provider) could not be reached for this goal.")
        }

        guard let generated = try? GeneratedPlan(GeneratedContent(json: response.content)) else {
            return await unmodeledPlan(for: goal, degradedBecause: "\(route.provider) replied with something that is not a plan.")
        }

        return await plan(for: goal, from: generated, telemetry: response.telemetry)
    }

    /// The template plan, left *visibly unmodeled*, with the reason the model did not plan this goal
    /// recorded as a rejected candidate.
    ///
    /// Every degraded exit funnels through here so the "no telemetry on template-derived steps" rule
    /// is one statement rather than a property re-argued at five `return` sites. The reason is kept
    /// because dropping it is what the old `planner: "model-remote-unavailable"` string was really
    /// for, and the candidate list is the right place for it: a rejected option with a rationale is
    /// exactly what ``PlanCandidate`` means, and it survives into the worklog without putting a model
    /// identity in a slot no model earned.
    private func unmodeledPlan(for goal: PlanningGoal, degradedBecause reason: String) async -> Plan {
        let candidate = PlanCandidate(
            title: "model-planning",
            capability: nil,
            isSelected: false,
            rationale: "Dropped: \(reason) The deterministic templates planned this goal instead."
        )
        return unmodeledPlan(await fallback.makePlan(for: goal), recording: [candidate])
    }

    /// Builds the governed request both executors send.
    ///
    /// Internal rather than private so the instruction guardrails can pin the text that is actually
    /// transmitted. The capability list lives in the *prompt*, not the instruction channel, so
    /// asserting on `PlannerInstructions` alone can never see it — and the suite that was supposed
    /// to guarantee "the model is offered every capability by its exact identifier" was asserting on
    /// a dead string builder that nothing sent.
    func authorizedRequest(
        for goal: PlanningGoal,
        instructions: [String],
        at now: Date
    ) throws -> ModelInferenceRequest {
        let allowed = availableCapabilities.map(\.rawValue).joined(separator: ", ")
        return try ModelInferenceRequest.authorizing(
            taskKind: ModelTaskKind.autopilotPlanning,
            instructions: instructions,
            bundle: ContextBundle(fields: [
                ContextField(key: "planner.goal", stringValue: goal.text, dataClass: .userProvided, source: .userProvided, lastRefreshed: now),
                ContextField(key: "planner.allowedCapabilities", stringValue: allowed, dataClass: .derived, source: .runtimeHost, lastRefreshed: now)
            ]),
            contract: ContextBundleContract(
                identifier: "model.autopilot.planning",
                requirements: [
                    ContextFieldRequirement(key: "planner.goal", allowedDataClasses: [.userProvided], maxAge: 60, authoritativeSource: .userProvided, missingFieldBehavior: .fail),
                    ContextFieldRequirement(key: "planner.allowedCapabilities", allowedDataClasses: [.derived], maxAge: 60, authoritativeSource: .runtimeHost, missingFieldBehavior: .fail)
                ]
            ),
            validationDate: now
        ) { context in
            return """
            Goal: \(context.field("planner.goal")?.stringValue ?? "")
            Allowed capabilities: \(context.field("planner.allowedCapabilities")?.stringValue ?? "")
            """
        }
    }

    /// Returns `fallbackPlan`'s steps and *its* planner identity, with `candidates` recorded ahead of
    /// the fallback's own and no telemetry.
    ///
    /// Three decisions, each of which was its own defect:
    ///
    /// `planner` is copied from the fallback rather than set to a `model-…` string. The deliberation
    /// is the one place that decides who planned a run (``GoalPlanning/name`` cannot — it is fixed
    /// before planning starts), and on this path the templates wrote every step. Stamping
    /// `"model-fallback"` or `"model-remote-unavailable"` here put a model identity on template work,
    /// which is what left `JudgeStepAuthorizer` filing proposals under one actor while the worklog
    /// recorded the same run under another.
    ///
    /// `telemetry` is `nil`, unconditionally, because that flag is what makes a provider receipt get
    /// written. See ``plan(for:from:telemetry:)``.
    ///
    /// `candidates` comes first and is not optional. The rejections used to be thrown away here in
    /// favour of `fallbackPlan.deliberation.candidates` alone, so Mission Control showed a planner
    /// "considering" templates it never saw, and the one run where a hallucinated wallet capability
    /// was proposed and dropped was the one run that left no record of it. The rejections are the
    /// reason the candidate list exists; the templates explain what shipped instead. Both, in that
    /// order.
    private func unmodeledPlan(_ fallbackPlan: Plan, recording candidates: [PlanCandidate]) -> Plan {
        Plan(
            goal: fallbackPlan.goal,
            steps: fallbackPlan.steps,
            summary: fallbackPlan.summary,
            deliberation: PlanDeliberation(
                planner: fallbackPlan.deliberation.planner,
                candidates: candidates + fallbackPlan.deliberation.candidates,
                telemetry: nil
            )
        )
    }

    private static func telemetry(
        route: ModelRoute,
        instructions: [String],
        prompt: String,
        responseSummary: String,
        duration: Double
    ) -> InferenceTelemetry {
        let promptText = (instructions + [prompt]).joined(separator: "\n")
        return .estimated(route: route, prompt: promptText, completion: responseSummary, durationSeconds: duration)
    }

    /// Grounds the model's proposed steps against the allow-list, keeping the ones that are real and
    /// permitted and recording *why* each dropped step was rejected. The rejections are the trust
    /// signal: a hallucinated or disallowed capability is dropped here, never executed, and now
    /// visible rather than silently discarded.
    private func groundedSteps(from generated: [GeneratedStep]) -> (steps: [PlanStep], candidates: [PlanCandidate]) {
        let allowed = Set(availableCapabilities)
        var steps: [PlanStep] = []
        var candidates: [PlanCandidate] = []

        for step in generated {
            guard let capability = CapabilityID(rawValue: step.capability) else {
                candidates.append(PlanCandidate(
                    title: step.title.isEmpty ? step.capability : step.title,
                    capability: nil,
                    isSelected: false,
                    rationale: "Dropped: “\(step.capability)” is not a known capability (hallucinated)."
                ))
                continue
            }
            guard allowed.contains(capability) else {
                candidates.append(PlanCandidate(
                    title: step.title.isEmpty ? capability.rawValue : step.title,
                    capability: capability,
                    isSelected: false,
                    rationale: "Dropped: \(capability.rawValue) is not permitted in this context."
                ))
                continue
            }
            guard let kind = PlanStepKind(rawValue: step.kind.lowercased()) else {
                candidates.append(PlanCandidate(
                    title: step.title.isEmpty ? capability.rawValue : step.title,
                    capability: capability,
                    isSelected: false,
                    rationale: "Dropped: “\(step.kind)” is not a valid step kind."
                ))
                continue
            }
            let descriptor = CapabilityRegistry.descriptor(for: capability)
            let title = step.title.isEmpty ? descriptor.title : step.title
            // The capability was grounded; the *kind* has to be too. `kind` arrives as free text
            // from the model, and it decides how much ceremony the step gets — so a step naming
            // `sign_message` while declaring itself `observe` claimed a wallet signature was a
            // read. Reconcile it against the capability's own impact class, which is a fact about
            // the capability rather than a claim about the step.
            let groundedKind = PlannerInstructions.groundedStepKind(declared: kind, for: capability)
            steps.append(PlanStep(
                capability: capability,
                kind: groundedKind,
                title: title,
                rationale: step.rationale
            ))
            // The clamp is recorded, not applied silently: the candidate list is this planner's
            // trust signal, and "the model mislabelled a wallet signature as a read" is exactly the
            // kind of thing it exists to make visible.
            let groundingNote = groundedKind == kind
                ? (step.rationale.isEmpty ? "Grounded against the allowed capability list." : step.rationale)
                : """
                Raised from “\(kind.rawValue)” to “\(groundedKind.rawValue)”: \
                \(capability.rawValue) has no read-only mode — the least any step on it can be is \
                \(CapabilityImpactMapping.minimumImpact(for: capability).rawValue).
                """
            candidates.append(PlanCandidate(
                title: title,
                capability: capability,
                isSelected: true,
                rationale: groundingNote
            ))
        }

        return (steps, candidates)
    }
}
#endif
