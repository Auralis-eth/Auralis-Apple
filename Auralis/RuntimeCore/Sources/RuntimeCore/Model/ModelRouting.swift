import Foundation

/// A concrete route to an inference backend. Provider-agnostic on purpose: Apple Foundation Models,
/// a local model, or an API provider all describe themselves the same way.
public struct ModelRoute: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public let provider: String
    public let modelClass: String
    public let locality: InferenceLocality
    /// USD charged per one million prompt (input) tokens on this route. On-device/local routes have no
    /// per-token billing, so they are `0` — cost then falls out of the rate rather than a hardcoded
    /// literal, and a future remote route bills correctly by declaring real rates here.
    public let promptCostPerMillionTokens: Double
    /// USD charged per one million completion (output) tokens on this route.
    public let completionCostPerMillionTokens: Double

    public init(
        id: String,
        provider: String,
        modelClass: String,
        locality: InferenceLocality,
        promptCostPerMillionTokens: Double = 0,
        completionCostPerMillionTokens: Double = 0
    ) {
        self.id = id
        self.provider = provider
        self.modelClass = modelClass
        self.locality = locality
        self.promptCostPerMillionTokens = promptCostPerMillionTokens
        self.completionCostPerMillionTokens = completionCostPerMillionTokens
    }

    // Tolerant decoding: routes persisted before pricing existed decode as free (local) routes.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        provider = try container.decode(String.self, forKey: .provider)
        modelClass = try container.decode(String.self, forKey: .modelClass)
        locality = try container.decode(InferenceLocality.self, forKey: .locality)
        promptCostPerMillionTokens = try container.decodeIfPresent(Double.self, forKey: .promptCostPerMillionTokens) ?? 0
        completionCostPerMillionTokens = try container.decodeIfPresent(Double.self, forKey: .completionCostPerMillionTokens) ?? 0
    }

    /// Estimated USD cost of an inference that used `promptTokens`/`completionTokens` on this route.
    /// Zero for local routes by construction (their rates are zero).
    public func estimatedCost(promptTokens: Int, completionTokens: Int) -> Double {
        let prompt = Double(promptTokens) / 1_000_000 * promptCostPerMillionTokens
        let completion = Double(completionTokens) / 1_000_000 * completionCostPerMillionTokens
        return prompt + completion
    }

    /// The attribution provenance implied by this route, for stamping receipts/worklogs.
    public var provenance: InferenceProvenance {
        InferenceProvenance(locality: locality, provider: provider, modelClass: modelClass)
    }

    /// The trust-facing privacy impact implied by this route's locality (P1-AI-102).
    public var privacyImpact: String { locality.privacyImpact }
}

/// Chooses a ``ModelRoute`` for a task kind. Implementations must not hardwire providers into call
/// sites — that is the whole point of routing through this seam.
public protocol ModelRouting: Sendable {
    func route(forTaskKind taskKind: String) async -> ModelRoute?
}

/// A provider-neutral inference request. Call sites describe the work; provider adapters decide how to
/// execute it for the selected route.
public struct ModelInferenceRequest: Equatable, Sendable {
    public let taskKind: String
    public let instructions: [String]
    public let prompt: String
    /// Context that crossed the same contract gate used by scheduled workflows.
    public let context: GovernedContext

    public init(
        taskKind: String,
        instructions: [String] = [],
        prompt: String,
        context: GovernedContext
    ) {
        self.taskKind = taskKind
        self.instructions = instructions
        self.prompt = prompt
        self.context = context
    }

    /// The single authorizing constructor for provider-routed model inference.
    public static func authorizing(
        taskKind: String,
        instructions: [String] = [],
        bundle: ContextBundle,
        contract: ContextBundleContract,
        validationDate: Date = .now,
        prompt: @Sendable (GovernedContext) -> String
    ) throws -> ModelInferenceRequest {
        let context = try ContextGovernanceBoundary()
            .authorize(bundle, against: contract, at: validationDate)
            .get()
        return ModelInferenceRequest(
            taskKind: taskKind,
            instructions: instructions,
            prompt: prompt(context),
            context: context
        )
    }
}

/// The result of executing one provider-routed inference.
public struct ModelInferenceResponse: Equatable, Sendable {
    public let content: String
    public let telemetry: InferenceTelemetry

    public init(content: String, telemetry: InferenceTelemetry) {
        self.content = content
        self.telemetry = telemetry
    }
}

public enum ModelInferenceError: Error, Equatable, Sendable {
    case unsupportedRoute(String)
    case unavailable(String)
    case providerFailed(String)
}

/// Executes a routed inference. This is the execution seam behind ``ModelRouting``: Apple Foundation
/// Models, local open models, remote APIs, and future agent providers plug in here without changing the
/// runtime surfaces that ask for inference.
public protocol ModelInferring: Sendable {
    func respond(to request: ModelInferenceRequest, using route: ModelRoute) async throws -> ModelInferenceResponse
}

/// Explicit fail-closed default for routes that are declared but have no registered executor yet.
public struct UnsupportedModelInferenceClient: ModelInferring {
    public init() { }

    public func respond(to request: ModelInferenceRequest, using route: ModelRoute) async throws -> ModelInferenceResponse {
        throw ModelInferenceError.unsupportedRoute(route.id)
    }
}

/// Small deterministic token approximation for providers that do not report token usage. It keeps
/// estimates honest by always pairing them with `tokensEstimated == true`.
public enum EstimatedTokenCounter {
    public static func count(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        return max(1, (text.count + 3) / 4)
    }
}

/// Stable task-kind identifiers used by runtime features when asking a ``ModelRouting`` dependency for
/// a backend. Keep provider selection in router data, not in call sites.
public enum ModelTaskKind {
    public static let autopilotPlanning = "autopilot.planning"
    public static let autopilotStep = "autopilot.step"
    public static let searchAssistant = "search.assistant"
    public static let operatorResearchBrief = "operator.research.brief"
    public static let operatorOnChainWatch = "operator.onchain.watch"
    public static let operatorIdentityReview = "operator.identity.review"
    public static let operatorPreparedAction = "operator.onchain.prepareAction"
}

/// Default route entries for Auralis's local-first configuration. Future local model, API provider, or
/// DViances agent routes should be added by composing a ``ModelRouting`` implementation, not by
/// branching at feature call sites.
public enum DefaultModelRoutes {
    public static let localLanguageModel = ModelRoute(
        id: "foundation-models.local.language",
        provider: "Apple Foundation Models",
        modelClass: "local-language-model",
        locality: .local
    )

    public static let localLedgerIndexer = ModelRoute(
        id: "chainproviders.local.watch",
        provider: "Local ledger",
        modelClass: "on-device-indexer",
        locality: .local
    )
}

/// Cost/latency/token telemetry for a single inference. Feeds `AgentSession` cost and Mission
/// Control observability.
public struct InferenceTelemetry: Equatable, Sendable, Codable {
    public let route: ModelRoute
    public let promptTokens: Int
    public let completionTokens: Int
    public let durationSeconds: Double
    public let estimatedCost: Double
    /// True when the token counts are approximated (e.g. derived from content length for on-device
    /// runs) rather than reported by the model. Lets the UI honestly label them as estimates.
    public let tokensEstimated: Bool
    /// True when this telemetry records an actual model inference. Deterministic operators that only
    /// read local data (e.g. the on-chain ledger indexer, `usesInference == false`) still carry a
    /// route for provenance, but must not be counted as a model hop or presented as AI inference —
    /// that would blur "local data read" with "AI ran". Every trust surface (model-hop count,
    /// AI-provenance section) gates on this flag. (P1-AI-102/103)
    public let usesInference: Bool

    public init(
        route: ModelRoute,
        promptTokens: Int,
        completionTokens: Int,
        durationSeconds: Double,
        estimatedCost: Double,
        tokensEstimated: Bool = false,
        usesInference: Bool = true
    ) {
        self.route = route
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.durationSeconds = durationSeconds
        self.estimatedCost = estimatedCost
        self.tokensEstimated = tokensEstimated
        self.usesInference = usesInference
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        route = try container.decode(ModelRoute.self, forKey: .route)
        promptTokens = try container.decode(Int.self, forKey: .promptTokens)
        completionTokens = try container.decode(Int.self, forKey: .completionTokens)
        durationSeconds = try container.decode(Double.self, forKey: .durationSeconds)
        estimatedCost = try container.decode(Double.self, forKey: .estimatedCost)
        tokensEstimated = try container.decodeIfPresent(Bool.self, forKey: .tokensEstimated) ?? false
        // Legacy blobs predate the flag; default to `true` so existing inference records keep counting.
        usesInference = try container.decodeIfPresent(Bool.self, forKey: .usesInference) ?? true
    }

    public var totalTokens: Int { promptTokens + completionTokens }

    public static func estimated(
        route: ModelRoute,
        prompt: String,
        completion: String,
        durationSeconds: Double
    ) -> InferenceTelemetry {
        let promptTokens = EstimatedTokenCounter.count(prompt)
        let completionTokens = EstimatedTokenCounter.count(completion)
        return InferenceTelemetry(
            route: route,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            durationSeconds: durationSeconds,
            estimatedCost: route.estimatedCost(promptTokens: promptTokens, completionTokens: completionTokens),
            tokensEstimated: true
        )
    }

    public var outputFields: [String: String] {
        [
            "modelProvider": route.provider,
            "modelClass": route.modelClass,
            "inferenceLocality": route.locality.rawValue,
            "privacyImpact": route.privacyImpact,
            "promptTokens": "\(promptTokens)",
            "completionTokens": "\(completionTokens)",
            "tokensEstimated": "\(tokensEstimated)",
            "durationSeconds": "\(durationSeconds)",
            "estimatedCost": "\(estimatedCost)",
            "usesInference": "\(usesInference)"
        ]
    }

    public init?(outputFields: [String: String]) {
        guard let provider = outputFields["modelProvider"], !provider.isEmpty,
              let modelClass = outputFields["modelClass"], !modelClass.isEmpty,
              let localityRawValue = outputFields["inferenceLocality"],
              let locality = InferenceLocality(rawValue: localityRawValue) else {
            return nil
        }

        self.init(
            route: ModelRoute(
                id: "\(provider).\(modelClass).\(locality.rawValue)",
                provider: provider,
                modelClass: modelClass,
                locality: locality
            ),
            promptTokens: Int(outputFields["promptTokens"] ?? "") ?? 0,
            completionTokens: Int(outputFields["completionTokens"] ?? "") ?? 0,
            durationSeconds: Double(outputFields["durationSeconds"] ?? "") ?? 0,
            estimatedCost: Double(outputFields["estimatedCost"] ?? "") ?? 0,
            tokensEstimated: Bool(outputFields["tokensEstimated"] ?? "") ?? false,
            // Absent on legacy receipts; default to `true` so pre-flag inference records still parse.
            usesInference: Bool(outputFields["usesInference"] ?? "") ?? true
        )
    }
}

/// A trivial static router that always returns the same route. Useful as a default and in tests.
public struct StaticModelRouter: ModelRouting {
    private let fixedRoute: ModelRoute?

    public init(route: ModelRoute?) {
        self.fixedRoute = route
    }

    public func route(forTaskKind taskKind: String) async -> ModelRoute? {
        fixedRoute
    }
}

/// The real routing layer (P1-AI-101): selects a ``ModelRoute`` per task kind from a *declared*
/// table — Apple Foundation Models, a local model, or an API provider are all just entries — then
/// falls through an ordered chain before landing on a guaranteed default. Providers are data here,
/// never `if provider == …` branches at call sites, which is the whole point of the seam.
///
/// Resolution order for a task kind:
/// 1. An exact entry in this router's `routes` table.
/// 2. The `fallback` router, if any — the extension seam for *future* providers / DViances agents:
///    a remote-provider registry, a per-account override, or a downstream agent router can be chained
///    in without touching this type or any call site.
/// 3. This router's `defaultRoute`, if any — the last-resort floor so a configured system always has
///    somewhere to run (typically the on-device route).
///
/// Every stage is optional, so this composes: routers can be nested to express provider precedence
/// (e.g. task-specific overrides → remote providers → on-device default).
public struct TaskKindModelRouter: ModelRouting {
    public static let localFirstDefault = TaskKindModelRouter(
        routes: [
            ModelTaskKind.operatorResearchBrief: DefaultModelRoutes.localLanguageModel,
            ModelTaskKind.operatorOnChainWatch: DefaultModelRoutes.localLedgerIndexer,
            ModelTaskKind.operatorIdentityReview: DefaultModelRoutes.localLanguageModel,
            ModelTaskKind.operatorPreparedAction: DefaultModelRoutes.localLanguageModel,
            ModelTaskKind.autopilotPlanning: DefaultModelRoutes.localLanguageModel,
            ModelTaskKind.autopilotStep: DefaultModelRoutes.localLanguageModel,
            ModelTaskKind.searchAssistant: DefaultModelRoutes.localLanguageModel
        ],
        defaultRoute: DefaultModelRoutes.localLanguageModel
    )

    private let routes: [String: ModelRoute]
    private let defaultRoute: ModelRoute?
    private let fallback: (any ModelRouting)?

    /// - Parameters:
    ///   - routes: task-kind → route table. Task-kind keys are matched exactly.
    ///   - defaultRoute: the guaranteed floor returned when nothing else matches.
    ///   - fallback: a downstream router consulted before `defaultRoute` — the future-provider hook.
    public init(
        routes: [String: ModelRoute] = [:],
        defaultRoute: ModelRoute? = nil,
        fallback: (any ModelRouting)? = nil
    ) {
        self.routes = routes
        self.defaultRoute = defaultRoute
        self.fallback = fallback
    }

    public func route(forTaskKind taskKind: String) async -> ModelRoute? {
        if let exact = routes[taskKind] {
            return exact
        }
        if let downstream = await fallback?.route(forTaskKind: taskKind) {
            return downstream
        }
        return defaultRoute
    }

    /// Returns a copy that also routes `taskKind` to `route`. Convenient for building a table
    /// incrementally as providers register, without mutating shared state.
    public func routing(_ taskKind: String, to route: ModelRoute) -> TaskKindModelRouter {
        var merged = routes
        merged[taskKind] = route
        return TaskKindModelRouter(routes: merged, defaultRoute: defaultRoute, fallback: fallback)
    }
}
