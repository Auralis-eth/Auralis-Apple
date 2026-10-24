import CapabilitiesCore
import Foundation
@testable import PlannerCore
import RuntimeCore
import Testing

#if canImport(FoundationModels)

/// Routes every task kind to one fixed route, so a test can put the planner on a chosen route
/// without a registered provider.
private struct FixedModelRouter: ModelRouting {
    let fixedRoute: ModelRoute

    func route(forTaskKind taskKind: String) async -> ModelRoute? { fixedRoute }
}

/// Records whether the provider seam was reached, what the goal text carried with it, and answers
/// with a canned reply. Reaching this seam is the *expected* behaviour for every route that is not
/// Apple's own: the recording is how a test tells "the configured provider ran" apart from "the call
/// site quietly used `SystemLanguageModel` instead".
private actor RecordingInferenceClient: ModelInferring {
    private(set) var requests: [ModelInferenceRequest] = []
    private let reply: String

    init(reply: String = "Step 1: look at the library.") {
        self.reply = reply
    }

    var wasCalled: Bool { !requests.isEmpty }

    func respond(to request: ModelInferenceRequest, using route: ModelRoute) async throws -> ModelInferenceResponse {
        requests.append(request)
        return ModelInferenceResponse(
            content: reply,
            telemetry: .estimated(route: route, prompt: request.prompt, completion: reply, durationSeconds: 0.25)
        )
    }
}

/// A billed, off-device route — nonzero rates on purpose, so a laundered telemetry stamp shows up as
/// a real `estimatedCost` rather than a harmless zero.
private let billedRemoteRoute = ModelRoute(
    id: "test.remote.planner",
    provider: "Test Remote Provider",
    modelClass: "remote-language-model",
    locality: .remote,
    promptCostPerMillionTokens: 3,
    completionCostPerMillionTokens: 15
)

/// A route that is `.local` but is *not* Apple Foundation Models — the exact shape a registered
/// open-model provider has, and the case a `locality != .remote` branch silently swallowed.
private let localOpenModelRoute = ModelRoute(
    id: "test.local.open-model",
    provider: "Test Local Open Model",
    modelClass: "local-language-model",
    locality: .local
)

/// A reply in the shape `GeneratedPlan` decodes from, naming one real, allowed capability.
private let groundableReply = """
{"summary":"Look at the library before changing anything.",\
"steps":[{"capability":"music_library_classification","kind":"observe",\
"title":"Inspect library","rationale":"See what is there first."}]}
"""

private func comparableSteps(_ plan: Plan) -> [String] {
    plan.steps.map { "\($0.capability.rawValue)|\($0.kind.rawValue)|\($0.title)|\($0.rationale)" }
}

/// The planner itself is `@available(iOS 26.0, macOS 26.0, *)`, but Swift Testing refuses `@Test` on
/// an `@available`-annotated function, and the package's deployment floor is macOS 15. So each test
/// gates at runtime instead; the host this suite runs on satisfies the check.
struct ModelGoalPlannerTests {
    // MARK: - The route's identity, not its locality, picks the executor

    /// A `.local` route that is not Apple's must still go through `ModelInferring`. Branching on
    /// `route.locality` sent it to `SystemLanguageModel.default` instead, so a provider registered
    /// for `autopilot.planning` never ran and — on a host without the system model — the run
    /// degraded to templates without the configured provider being tried once.
    @Test("a local route that is not Foundation Models is executed through the inference client")
    func localOpenModelRouteReachesTheInferenceClient() async {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let client = RecordingInferenceClient(reply: groundableReply)
        let planner = ModelGoalPlanner(
            fallback: DeterministicGoalPlanner(),
            modelRouter: FixedModelRouter(fixedRoute: localOpenModelRoute),
            modelInferenceClient: client
        )

        _ = await planner.makePlan(for: PlanningGoal(text: "Please organize my music library"))

        #expect(await client.wasCalled)
        // The governed prompt, not the bare goal: what the provider receives is the audited text.
        let prompt = await client.requests.first?.prompt
        #expect(prompt?.contains("Please organize my music library") == true)
    }

    /// The other half of the seam: a reply that grounds is the plan, and *only* then is the
    /// provider's telemetry attached.
    @Test("a provider reply that grounds produces model-derived steps carrying the route's telemetry")
    func groundedProviderReplyProducesModelDerivedSteps() async {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let goal = PlanningGoal(text: "Please organize my music library")
        let planner = ModelGoalPlanner(
            fallback: DeterministicGoalPlanner(),
            modelRouter: FixedModelRouter(fixedRoute: localOpenModelRoute),
            modelInferenceClient: RecordingInferenceClient(reply: groundableReply)
        )

        let plan = await planner.makePlan(for: goal)
        let templatePlan = await DeterministicGoalPlanner().makePlan(for: goal)

        // The provider's steps, not the catalog's.
        #expect(comparableSteps(plan) != comparableSteps(templatePlan))
        #expect(plan.steps.map(\.title) == ["Inspect library"])
        #expect(plan.steps.map(\.capability) == [.musicLibraryClassification])
        #expect(plan.summary == "Look at the library before changing anything.")
        // Telemetry is earned here, and it names the route that actually ran.
        #expect(plan.deliberation.telemetry?.route == localOpenModelRoute)
        #expect(plan.deliberation.planner == planner.name)
    }

    // MARK: - A reply that does not ground must not launder provider telemetry onto a template plan

    @Test("a provider reply that is not a plan leaves the template plan visibly unmodeled")
    func undecodableProviderReplyReturnsUnmodeledTemplatePlan() async {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let goal = PlanningGoal(text: "Please organize my music library")
        // The default reply is prose, not the JSON object `GeneratedPlan` decodes from.
        let client = RecordingInferenceClient()
        let planner = ModelGoalPlanner(
            fallback: DeterministicGoalPlanner(),
            modelRouter: FixedModelRouter(fixedRoute: billedRemoteRoute),
            modelInferenceClient: client
        )

        let plan = await planner.makePlan(for: goal)
        let templatePlan = await DeterministicGoalPlanner().makePlan(for: goal)

        // The provider was asked — that is the seam working…
        #expect(await client.wasCalled)
        // …but nothing it said survived, so the steps are the templates'…
        #expect(comparableSteps(plan) == comparableSteps(templatePlan))
        #expect(plan.summary == templatePlan.summary)
        // …and no telemetry is stamped. `deliberation.telemetry != nil` is what makes RuntimeHost
        // write an `autopilot.planning.model` receipt claiming a provider planned the goal, on a
        // billed route, and charge for it.
        #expect(plan.deliberation.telemetry == nil)
    }

    /// Fix 3: one run, one planner identity. The steps here came from the template catalog, so the
    /// deliberation must name the template planner — not `model-remote-unavailable`, not `model`.
    /// While it named a model, `JudgeStepAuthorizer` filed proposals under `planner.model` and the
    /// worklog recorded `planner.deterministic` for the same run.
    @Test("a degraded model run is attributed to the planner that actually wrote the steps")
    func degradedRunIsAttributedToTheTemplatePlanner() async {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let goal = PlanningGoal(text: "Please organize my music library")
        let fallback = DeterministicGoalPlanner()
        let planner = ModelGoalPlanner(
            fallback: fallback,
            modelRouter: FixedModelRouter(fixedRoute: billedRemoteRoute),
            modelInferenceClient: RecordingInferenceClient()
        )

        let plan = await planner.makePlan(for: goal)

        #expect(plan.deliberation.planner == fallback.name)
        #expect(plan.deliberation.planner != planner.name)
        // The degradation is not lost by giving up the `model-…` planner string: it moves to the
        // candidate list, which is where a rejected option with a reason belongs.
        let degradation = plan.deliberation.rejected.first { $0.title == "model-planning" }
        #expect(degradation?.rationale.contains(billedRemoteRoute.provider) == true)
    }

    // MARK: - Rejected model steps must survive into the deliberation

    @Test("a model that proposes only unknown capabilities still records why they were dropped")
    func hallucinatedCapabilityIsRecordedWhenEveryStepIsRejected() async {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let planner = ModelGoalPlanner(fallback: DeterministicGoalPlanner())
        let generated = ModelGoalPlanner.GeneratedPlan(
            summary: "Sign whatever is needed.",
            steps: [
                ModelGoalPlanner.GeneratedStep(
                    capability: "wallet_sign_everything",
                    kind: "execute",
                    title: "Sign everything",
                    rationale: "Blanket authority makes the rest easy."
                )
            ]
        )
        let telemetry = InferenceTelemetry.estimated(
            route: DefaultModelRoutes.localLanguageModel,
            prompt: "Goal: tidy things up",
            completion: "Sign whatever is needed.",
            durationSeconds: 0.1
        )

        let plan = await planner.plan(
            for: PlanningGoal(text: "xyzzy nonsense goal"),
            from: generated,
            telemetry: telemetry
        )

        // Nothing the model proposed was executable, so the steps are the template fallback's…
        #expect(plan.steps.map(\.kind) == [.observe])
        // …but the drop is the whole trust signal, and it has to leave the planner.
        let rejection = plan.deliberation.candidates.first { $0.rationale.contains("hallucinated") }
        #expect(rejection != nil)
        #expect(rejection?.title == "Sign everything")
        #expect(rejection?.capability == nil)
        #expect(rejection?.isSelected == false)
        #expect(rejection?.rationale.contains("wallet_sign_everything") == true)
    }

    @Test("rejected model steps are recorded alongside, not instead of, the template deliberation")
    func rejectionsAreConcatenatedWithFallbackCandidates() async {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let goal = PlanningGoal(text: "xyzzy nonsense goal")
        let planner = ModelGoalPlanner(fallback: DeterministicGoalPlanner())
        let generated = ModelGoalPlanner.GeneratedPlan(
            summary: "",
            steps: [
                ModelGoalPlanner.GeneratedStep(
                    capability: "wallet_sign_everything",
                    kind: "execute",
                    title: "Sign everything",
                    rationale: ""
                )
            ]
        )
        let telemetry = InferenceTelemetry.estimated(
            route: DefaultModelRoutes.localLanguageModel,
            prompt: "p",
            completion: "c",
            durationSeconds: 0.1
        )

        let plan = await planner.plan(for: goal, from: generated, telemetry: telemetry)
        let templatePlan = await DeterministicGoalPlanner().makePlan(for: goal)

        #expect(plan.deliberation.candidates.count == templatePlan.deliberation.candidates.count + 1)
        // Grounding rejected every proposed step, so the templates wrote this plan and own its
        // identity — and the inference that produced nothing must not leave a provider receipt
        // behind it.
        #expect(plan.deliberation.planner == DeterministicGoalPlanner().name)
        #expect(plan.deliberation.telemetry == nil)
    }
}
#endif
