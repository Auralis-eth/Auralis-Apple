import Foundation
import PlannerCore
import RuntimeCore
@testable import RuntimeKit
import Testing

#if canImport(FoundationModels)

/// Whether the type under test exists on the host running the suite.
///
/// File-scoped rather than a member of the suite because `@Test`'s availability trait is evaluated
/// from a `Sendable` closure, which cannot reach a `@MainActor`-isolated static property.
private let performerIsSupported: Bool = {
    if #available(iOS 26.0, macOS 26.0, *) { return true }
    return false
}()

/// Routes every task kind to one fixed route, and records which kind it was asked about.
private actor StubModelRouter: ModelRouting {
    private let fixedRoute: ModelRoute?
    private(set) var requestedTaskKinds: [String] = []

    init(route: ModelRoute?) {
        fixedRoute = route
    }

    func route(forTaskKind taskKind: String) async -> ModelRoute? {
        requestedTaskKinds.append(taskKind)
        return fixedRoute
    }
}

/// A routed inference client that either answers or fails, and keeps the request it was handed so
/// the contract-authorized prompt can be inspected.
private actor StubInferenceClient: ModelInferring {
    enum Behaviour: Sendable {
        case answer(content: String, telemetry: InferenceTelemetry)
        case fail
    }

    private let behaviour: Behaviour
    private(set) var received: [ModelInferenceRequest] = []

    init(behaviour: Behaviour) {
        self.behaviour = behaviour
    }

    func respond(to request: ModelInferenceRequest, using route: ModelRoute) async throws -> ModelInferenceResponse {
        received.append(request)
        switch behaviour {
        case let .answer(content, telemetry):
            return ModelInferenceResponse(content: content, telemetry: telemetry)
        case .fail:
            throw ModelInferenceError.providerFailed("stub refused")
        }
    }
}

/// The *shipping* per-step performer — the one `AutopilotStepPerformers.makeDefault` returns on any
/// iOS/macOS 26+ device — had no coverage at all: every autopilot test pins
/// `RuntimeHost.autopilotStepPerformerOverride` to a double, which is right for determinism but
/// leaves the real thing unexercised. So "the suite is green" said nothing about the code that
/// actually runs in production.
///
/// These tests cover the **remote** route, whose inference goes through the injected
/// ``ModelInferring`` seam. That reaches the route-locality branch, the `ContextBundleContract`
/// authorization that builds the prompt, telemetry passthrough on success, and the
/// degrade-to-`fallbackOutput` path on provider failure. The **local** (on-device) route is covered by
/// `OnDeviceRouteTests` below.
///
/// The availability trait is what keeps this honest on an older host: the performer only exists from
/// 26, and a silently-returning test that reports *passed* would claim coverage it did not provide,
/// so the suite reports **skipped** there instead.
@Suite("Model autopilot step performer (remote route)")
@MainActor
struct ModelAutopilotStepPerformerTests {
    private static let remoteRoute = ModelRoute(
        id: "test.remote",
        provider: "Test Provider",
        modelClass: "test-remote-model",
        locality: .remote,
        promptCostPerMillionTokens: 1,
        completionCostPerMillionTokens: 2
    )

    private static let goal = PlanningGoal(text: "Tidy the library", surface: "test")

    private static var step: PlanStep {
        PlanStep(
            capability: .musicLibraryClassification,
            kind: .observe,
            title: "Inspect library",
            rationale: "Gather context first."
        )
    }

    private static func telemetry(route: ModelRoute) -> InferenceTelemetry {
        InferenceTelemetry(
            route: route,
            promptTokens: 11,
            completionTokens: 7,
            durationSeconds: 0.25,
            estimatedCost: route.estimatedCost(promptTokens: 11, completionTokens: 7),
            tokensEstimated: false
        )
    }

    /// A remote route's answer and its telemetry must reach the caller untouched — this is the
    /// provenance the step receipt stamps, so a performer that dropped or re-derived it would put a
    /// wrong provider/locality in the permanent record.
    @Test("a remote route returns the provider's own output and telemetry", .enabled(if: performerIsSupported))
    func remoteRouteReturnsProviderOutputAndTelemetry() async {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let expected = Self.telemetry(route: Self.remoteRoute)
        let performer = ModelAutopilotStepPerformer(
            modelRouter: StubModelRouter(route: Self.remoteRoute),
            modelInferenceClient: StubInferenceClient(
                behaviour: .answer(content: "Reviewed 12 albums.", telemetry: expected)
            )
        )

        let work = await performer.perform(Self.step, goal: Self.goal)

        #expect(work.output == "Reviewed 12 albums.")
        #expect(work.telemetry == expected)
        #expect(work.telemetry?.route.locality == .remote)
        #expect(work.telemetry?.tokensEstimated == false)
    }

    /// The performer routes on the autopilot-step task kind, not some ambient default — otherwise a
    /// host that configured a specific route for steps would silently not get it.
    @Test("routing asks for the autopilot-step task kind", .enabled(if: performerIsSupported))
    func routingUsesTheAutopilotStepTaskKind() async {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let router = StubModelRouter(route: Self.remoteRoute)
        let performer = ModelAutopilotStepPerformer(
            modelRouter: router,
            modelInferenceClient: StubInferenceClient(
                behaviour: .answer(content: "ok", telemetry: Self.telemetry(route: Self.remoteRoute))
            )
        )

        _ = await performer.perform(Self.step, goal: Self.goal)

        #expect(await router.requestedTaskKinds == [ModelTaskKind.autopilotStep])
    }

    /// The request handed to the provider is built by `ModelInferenceRequest.authorizing`, so it has
    /// already passed the step's `ContextBundleContract`. Pinning that the goal and step actually
    /// reach the prompt is what proves the contract was satisfied rather than merely declared — a
    /// drifted contract throws instead, and the step degrades to no-inference output.
    @Test("the provider receives a contract-authorized request carrying the goal and step", .enabled(if: performerIsSupported))
    func providerReceivesAContractAuthorizedRequest() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let client = StubInferenceClient(
            behaviour: .answer(content: "ok", telemetry: Self.telemetry(route: Self.remoteRoute))
        )
        let performer = ModelAutopilotStepPerformer(
            modelRouter: StubModelRouter(route: Self.remoteRoute),
            modelInferenceClient: client
        )

        _ = await performer.perform(Self.step, goal: Self.goal)

        let request = try #require(await client.received.first)
        #expect(request.taskKind == ModelTaskKind.autopilotStep)
        #expect(request.instructions.isEmpty == false)
        #expect(request.prompt.contains(Self.goal.text))
        #expect(request.prompt.contains("Inspect library"))
        // The authorized context is the governed projection, so the contract admitted every field
        // the performer declared.
        #expect(request.context.field("autopilot.goal")?.stringValue == Self.goal.text)
        #expect(request.context.field("autopilot.step.capability")?.stringValue
            == Self.step.capability.rawValue)
    }

    /// A provider failure must degrade to honest no-inference output rather than surfacing as a
    /// crash or an empty result — and it must claim **no** telemetry, because no model produced
    /// anything. This is the branch that makes a failing remote route look identical to a device
    /// with no model, which is why it is logged rather than silent.
    @Test("a failing remote provider degrades to no-inference output with no telemetry", .enabled(if: performerIsSupported))
    func failingRemoteProviderDegradesHonestly() async {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let performer = ModelAutopilotStepPerformer(
            modelRouter: StubModelRouter(route: Self.remoteRoute),
            modelInferenceClient: StubInferenceClient(behaviour: .fail)
        )

        let work = await performer.perform(Self.step, goal: Self.goal)

        #expect(work.telemetry == nil)
        #expect(work.output.contains("Inspect library"))
        #expect(work.output.contains(Self.goal.text))
    }
}

/// A substitutable on-device model, standing in for `SystemLanguageModel` + `LanguageModelSession`.
@MainActor
private final class StubOnDeviceModel: OnDeviceLanguageModeling {
    enum Behaviour {
        /// Ran and reported usage — the iOS/macOS 27 case.
        case answer(content: String, promptTokens: Int, completionTokens: Int)
        /// Ran, but this OS cannot report usage — the iOS/macOS 26 case.
        case answerWithoutUsage(content: String)
        case fail
    }

    let isAvailable: Bool
    private let behaviour: Behaviour
    private(set) var receivedPrompts: [String] = []
    private(set) var receivedInstructions: [[String]] = []

    init(isAvailable: Bool = true, behaviour: Behaviour = .fail) {
        self.isAvailable = isAvailable
        self.behaviour = behaviour
    }

    func respond(to prompt: String, instructions: [String]) async throws -> OnDeviceModelResponse {
        receivedPrompts.append(prompt)
        receivedInstructions.append(instructions)
        switch behaviour {
        case let .answer(content, promptTokens, completionTokens):
            return OnDeviceModelResponse(
                content: content,
                promptTokens: promptTokens,
                completionTokens: completionTokens
            )
        case let .answerWithoutUsage(content):
            return OnDeviceModelResponse(content: content, promptTokens: nil, completionTokens: nil)
        case .fail:
            struct ModelRefused: Error { }
            throw ModelRefused()
        }
    }
}

/// The on-device route, now that ``OnDeviceLanguageModeling`` makes it substitutable.
///
/// This branch previously could not be tested at all — it read `SystemLanguageModel.default.availability`
/// and called `LanguageModelSession.respond` inline, so there was nothing to stand in for. It is also
/// the branch that decides whether the Agent Activity Timeline claims an inference happened and what
/// it cost, so "validate it on a physical device" was leaving the honesty-critical logic uncovered in
/// CI. A real device is still needed to confirm the *system model itself* behaves; what is pinned here
/// is the performer's handling of every answer it can give.
@Suite("Model autopilot step performer (on-device route)")
@MainActor
struct OnDeviceRouteTests {
    private static let localRoute = ModelRoute(
        id: "test.local",
        provider: "Apple",
        modelClass: "test-local-model",
        locality: .local,
        promptCostPerMillionTokens: 0,
        completionCostPerMillionTokens: 0
    )

    private static let goal = PlanningGoal(text: "Tidy the library", surface: "test")

    private static var step: PlanStep {
        PlanStep(
            capability: .musicLibraryClassification,
            kind: .observe,
            title: "Inspect library",
            rationale: "Gather context first."
        )
    }

    /// An unavailable model — unsupported device, Apple Intelligence off, model still downloading —
    /// must produce honest no-inference output and claim **no** telemetry. Fabricating zero-token
    /// telemetry here would put a phantom inference in the permanent record.
    @Test("an unavailable on-device model degrades with no telemetry", .enabled(if: performerIsSupported))
    func unavailableModelDegradesWithNoTelemetry() async throws {
        let model = StubOnDeviceModel(isAvailable: false, behaviour: .answer(content: "unused", promptTokens: 9, completionTokens: 9))
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let performer = ModelAutopilotStepPerformer(
            modelRouter: StubModelRouter(route: Self.localRoute),
            modelInferenceClient: StubInferenceClient(behaviour: .fail),
            onDeviceModel: model
        )

        let work = await performer.perform(Self.step, goal: Self.goal)

        #expect(work.telemetry == nil)
        #expect(work.output.contains("Inspect library"))
        // Never consulted, so no prompt was built for a model that could not run it.
        #expect(await model.receivedPrompts.isEmpty)
    }

    /// The measured case: real counts reach the telemetry the step receipt stamps, and
    /// `tokensEstimated` stays `false` because nothing was estimated.
    @Test("a successful on-device run reports the model's real token usage", .enabled(if: performerIsSupported))
    func successfulRunReportsRealTokenUsage() async throws {
        let model = StubOnDeviceModel(behaviour: .answer(content: "Reviewed 12 albums.", promptTokens: 31, completionTokens: 17))
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let performer = ModelAutopilotStepPerformer(
            modelRouter: StubModelRouter(route: Self.localRoute),
            modelInferenceClient: StubInferenceClient(behaviour: .fail),
            onDeviceModel: model
        )

        let work = await performer.perform(Self.step, goal: Self.goal)

        #expect(work.output == "Reviewed 12 albums.")
        let telemetry = try #require(work.telemetry)
        #expect(telemetry.promptTokens == 31)
        #expect(telemetry.completionTokens == 17)
        #expect(telemetry.tokensEstimated == false)
        #expect(telemetry.route.locality == .local)
        #expect(telemetry.durationSeconds >= 0)
    }

    /// The iOS/macOS 26 case: the model really ran, so telemetry is recorded — but the counts are
    /// unmeasurable, and 0 is the honest value. `tokensEstimated` must still be `false`: nothing was
    /// estimated, the usage is simply absent, and flipping it would claim a guess was made.
    @Test("an on-device run whose usage is unmeasurable records zero rather than an estimate", .enabled(if: performerIsSupported))
    func unmeasurableUsageRecordsZero() async throws {
        let model = StubOnDeviceModel(behaviour: .answerWithoutUsage(content: "Reviewed 12 albums."))
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let performer = ModelAutopilotStepPerformer(
            modelRouter: StubModelRouter(route: Self.localRoute),
            modelInferenceClient: StubInferenceClient(behaviour: .fail),
            onDeviceModel: model
        )

        let work = await performer.perform(Self.step, goal: Self.goal)

        #expect(work.output == "Reviewed 12 albums.")
        let telemetry = try #require(work.telemetry)
        #expect(telemetry.promptTokens == 0)
        #expect(telemetry.completionTokens == 0)
        #expect(telemetry.tokensEstimated == false)
        // The inference did happen, so the route is still recorded — this is what distinguishes it
        // from the unavailable case above, which reports no telemetry at all.
        #expect(telemetry.route.locality == .local)
    }

    /// The unmeasurable case must stay distinguishable from a run that produced no inference at all.
    ///
    /// Both record `0` tokens, so the *only* thing separating them is whether telemetry exists: a
    /// degraded step carries `nil`, an unmeasurable-usage step carries real route provenance. Mission
    /// Control's `tokensLabel` then renders the zero as "Not recorded" for the latter. Pinned from this
    /// side because the sentinel and the display rule live in different packages, and printing the
    /// count literally over there would turn this into a zero-token phantom inference — silently, and
    /// only on iOS 26.
    @Test("unmeasurable usage is still distinguishable from no inference at all", .enabled(if: performerIsSupported))
    func unmeasurableUsageIsDistinctFromNoInference() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let ran = ModelAutopilotStepPerformer(
            modelRouter: StubModelRouter(route: Self.localRoute),
            modelInferenceClient: StubInferenceClient(behaviour: .fail),
            onDeviceModel: StubOnDeviceModel(behaviour: .answerWithoutUsage(content: "Reviewed."))
        )
        let didNotRun = ModelAutopilotStepPerformer(
            modelRouter: StubModelRouter(route: Self.localRoute),
            modelInferenceClient: StubInferenceClient(behaviour: .fail),
            onDeviceModel: StubOnDeviceModel(isAvailable: false)
        )

        let ranWork = await ran.perform(Self.step, goal: Self.goal)
        let didNotRunWork = await didNotRun.perform(Self.step, goal: Self.goal)

        // Same token counts...
        #expect(ranWork.telemetry?.promptTokens == 0)
        #expect(didNotRunWork.telemetry == nil)
        // ...but only the run that happened carries provenance, which is what the timeline keys on.
        #expect(ranWork.telemetry?.route.provider == "Apple")
        #expect(ranWork.telemetry?.usesInference == true)
    }

    /// A refusing model — the simulator's safety-guardrail failure, above all — degrades to honest
    /// output with no telemetry rather than surfacing as a crash or an empty result.
    @Test("a refusing on-device model degrades to no-inference output", .enabled(if: performerIsSupported))
    func refusingModelDegradesHonestly() async throws {
        let model = StubOnDeviceModel(behaviour: .fail)
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let performer = ModelAutopilotStepPerformer(
            modelRouter: StubModelRouter(route: Self.localRoute),
            modelInferenceClient: StubInferenceClient(behaviour: .fail),
            onDeviceModel: model
        )

        let work = await performer.perform(Self.step, goal: Self.goal)

        #expect(work.telemetry == nil)
        #expect(work.output.contains("Inspect library"))
        #expect(work.output.contains(Self.goal.text))
        // It was asked, which is what separates this from the unavailable case.
        #expect(await model.receivedPrompts.count == 1)
    }

    /// The on-device model receives the same contract-authorized prompt and instructions the remote
    /// route does — so the `ContextBundleContract` governs local inference too, rather than only the
    /// routed path where it happened to be observable.
    @Test("the on-device model receives the contract-authorized prompt and instructions", .enabled(if: performerIsSupported))
    func onDeviceModelReceivesAuthorizedRequest() async throws {
        let model = StubOnDeviceModel(behaviour: .answer(content: "ok", promptTokens: 1, completionTokens: 1))
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let performer = ModelAutopilotStepPerformer(
            modelRouter: StubModelRouter(route: Self.localRoute),
            modelInferenceClient: StubInferenceClient(behaviour: .fail),
            onDeviceModel: model
        )

        _ = await performer.perform(Self.step, goal: Self.goal)

        let prompt = try #require(await model.receivedPrompts.first)
        #expect(prompt.contains(Self.goal.text))
        #expect(prompt.contains("Inspect library"))
        let instructions = try #require(await model.receivedInstructions.first)
        #expect(instructions.isEmpty == false)
        // The wallet guardrail belongs in the instructions for local inference as much as remote.
        #expect(instructions.contains { $0.contains("wallet") })
    }
}

#endif
