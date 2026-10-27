import Foundation

/// The single composition root for model providers (P1-AI-101).
///
/// Register Apple Foundation Models, on-device open models, remote API providers, and future DViances
/// agents here — each as *data*: the task-kind routes it claims plus, for anything that isn't executed
/// directly at the call site, the ``ModelInferring`` client that runs those routes. The registry then
/// vends the two protocol values the runtime actually depends on:
///
/// - ``makeRouter()`` — a ``ModelRouting`` deciding *which* backend serves a task kind.
/// - ``makeInferenceClient()`` — a ``ModelInferring`` deciding *how* a routed inference executes.
///
/// Adding a provider is one `register(_:)` call in the app's composition root. No feature call site
/// changes, and nothing branches on `if provider == …` — the whole point of routing through the seam.
///
/// Local-first stays the floor: with no provider registered the router resolves exactly like
/// ``TaskKindModelRouter/localFirstDefault`` and the inference client fails closed, so on-device
/// Foundation Models continues to serve every task kind. Registered providers layer *on top* — their
/// routes take precedence for the task kinds they claim, everything else falls through to local.
public struct ModelProviderRegistry: Sendable {
    /// One registered model provider.
    public struct Provider: Sendable {
        /// Stable identifier, for diagnostics/telemetry (e.g. "apple.foundation-models", "acme.api").
        public let id: String
        /// Task kind → route this provider serves. Layered over the local-first base, so a provider
        /// only overrides the task kinds it declares.
        public let routes: [String: ModelRoute]
        /// Executes this provider's routes. `nil` for providers whose routes run directly at the call
        /// site (Apple Foundation Models on-device inference is invoked through the SDK, not this seam),
        /// so registering them contributes routing without a redundant client.
        public let client: (any ModelInferring)?

        public init(id: String, routes: [String: ModelRoute], client: (any ModelInferring)? = nil) {
            self.id = id
            self.routes = routes
            self.client = client
        }
    }

    private var providers: [Provider] = []
    private let base: any ModelRouting
    private let defaultRoute: ModelRoute?

    /// - Parameters:
    ///   - base: the local-first floor consulted after registered providers. Defaults to the canonical
    ///     ``TaskKindModelRouter/localFirstDefault`` so there is a single source of truth for the
    ///     on-device task-kind table.
    ///   - defaultRoute: last-resort route when neither a provider nor the base matches.
    public init(
        base: any ModelRouting = TaskKindModelRouter.localFirstDefault,
        defaultRoute: ModelRoute? = DefaultModelRoutes.localLanguageModel
    ) {
        self.base = base
        self.defaultRoute = defaultRoute
    }

    /// Registers a provider. Later registrations win for task kinds also claimed by earlier ones, so
    /// callers can express precedence by registration order.
    public mutating func register(_ provider: Provider) {
        providers.append(provider)
    }

    /// The composed router: registered providers' routes first (later registrations override earlier),
    /// then the local-first base, then the guaranteed default floor.
    public func makeRouter() -> TaskKindModelRouter {
        var providerRoutes: [String: ModelRoute] = [:]
        for provider in providers {
            providerRoutes.merge(provider.routes) { _, new in new }
        }
        return TaskKindModelRouter(routes: providerRoutes, defaultRoute: defaultRoute, fallback: base)
    }

    /// The composed inference client: dispatches a routed inference to the provider that declared that
    /// route id. Routes with no registered client (e.g. on-device Foundation Models, or a declared-but-
    /// unwired remote route) fail closed through ``UnsupportedModelInferenceClient``.
    public func makeInferenceClient() -> any ModelInferring {
        var clientsByRouteID: [String: any ModelInferring] = [:]
        for provider in providers {
            guard let client = provider.client else { continue }
            for route in provider.routes.values {
                clientsByRouteID[route.id] = client
            }
        }
        return RoutingInferenceClient(clientsByRouteID: clientsByRouteID)
    }
}

/// Dispatches a routed inference to the ``ModelInferring`` registered for that route id, failing closed
/// for unregistered routes. This is the ``ModelInferring`` half of ``ModelProviderRegistry`` — the
/// single place provider clients are multiplexed, so call sites keep depending only on the protocol.
public struct RoutingInferenceClient: ModelInferring {
    private let clientsByRouteID: [String: any ModelInferring]
    private let fallback: any ModelInferring

    public init(
        clientsByRouteID: [String: any ModelInferring],
        fallback: any ModelInferring = UnsupportedModelInferenceClient()
    ) {
        self.clientsByRouteID = clientsByRouteID
        self.fallback = fallback
    }

    public func respond(to request: ModelInferenceRequest, using route: ModelRoute) async throws -> ModelInferenceResponse {
        let client = clientsByRouteID[route.id] ?? fallback
        return try await client.respond(to: request, using: route)
    }
}
