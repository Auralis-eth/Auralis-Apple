import RuntimeCore

/// The app's single composition root for model providers (P1-AI-101).
///
/// This is the one place Auralis decides *which* inference backends exist and how they are routed.
/// Everything downstream — `RuntimeHost` (operators + autopilot) and the search assistant — takes the
/// `ModelRouting` and `ModelInferring` this vends, so no feature hardwires a provider and no call site
/// changes when a provider is added or removed.
///
/// Today the app is local-first: no remote provider is registered, so the router resolves every task
/// kind to on-device Apple Foundation Models and the inference client fails closed. Bringing a remote
/// API provider (or a future DViances agent) online is a single `registry.register(...)` here —
/// declaring its task-kind routes (with real per-token pricing so cost telemetry stays honest) and the
/// `ModelInferring` client that executes them.
@MainActor
enum ModelProviderComposition {
    /// The composed registry. Extend this to bring additional providers online:
    ///
    /// ```swift
    /// registry.register(
    ///     ModelProviderRegistry.Provider(
    ///         id: "acme.api",
    ///         routes: [ModelTaskKind.operatorResearchBrief: acmeRoute],
    ///         client: AcmeInferenceClient(...)
    ///     )
    /// )
    /// ```
    private static let registry: ModelProviderRegistry = {
        // Local-first: Apple Foundation Models serves every task kind through the base router and runs
        // on-device at the call site, so no remote client is registered here yet. When one is, this
        // becomes `var` again and gains `registry.register(...)` calls before the return.
        ModelProviderRegistry()
    }()

    /// The routing layer every runtime feature resolves task kinds through.
    static let router: any ModelRouting = registry.makeRouter()

    /// The inference client remote-routed task kinds execute through.
    static let inferenceClient: any ModelInferring = registry.makeInferenceClient()
}
