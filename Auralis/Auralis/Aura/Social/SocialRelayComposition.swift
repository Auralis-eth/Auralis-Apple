import Foundation
import AuralisOperators
import WalletAdapters

/// A live relay runtime for one shared session: the coordinator (publish/subscribe/handle inbound) plus
/// the inbound pump that feeds it. Start subscribes to saved invites and replays any pending outbound;
/// stop tears down the inbound drain.
struct SocialRelaySessionRuntime {
    let coordinator: SocialRelayCoordinator
    let pump: SocialRelayInboundPump

    /// Begins draining inbound messages, subscribes to the session's relay topic (fetching any messages
    /// queued while offline), and flushes the local outbound queue. Ordered inbound-first so a message
    /// that arrives during subscribe is not missed.
    func start() async throws {
        await pump.start()
        try await coordinator.subscribeToSavedInvites()
        try await coordinator.publishPendingOutbound()
    }

    func stop() async {
        await pump.stop()
    }
}

/// Composition root for Social v1 relay, gated behind `AURALIS_SOCIAL_RELAY_ENABLED`.
///
/// Builds a per-session ``SocialRelaySessionRuntime`` — one coordinator and cipher bound to that
/// session's key (matching the coordinator's topic-less `seal`/`open` contract). When the relay flag is
/// off, `makeSession` returns `nil` so no socket is opened and no payload is ever published.
///
/// **The flag ships on** (`YES` in both Debug and Release xcconfigs), so this path is live in production
/// — see ``SocialAssembly``. Treat every comment about the gate as describing the mechanism, not the
/// current state.
struct SocialRelayComposition {
    let configuration: SocialFeatureConfiguration
    let eventLogStore: SocialEventLogStore
    let diagnostics: any SocialRelayDiagnostics

    init(
        configuration: SocialFeatureConfiguration = SocialFeatureConfiguration(),
        eventLogStore: SocialEventLogStore,
        diagnostics: any SocialRelayDiagnostics = NoopSocialRelayDiagnostics()
    ) {
        self.configuration = configuration
        self.eventLogStore = eventLogStore
        self.diagnostics = diagnostics
    }

    /// Whether relay social is enabled for this build/run.
    var isEnabled: Bool { configuration.relayEnabled }

    /// Builds a session runtime from explicit collaborators — the seam tests drive with fakes. Returns
    /// `nil` when the relay flag is off; throws ``SocialEnvelopeCipherError/invalidKey`` when the
    /// invite's session-key material is malformed (fail closed rather than open an unencryptable session).
    func makeSession(
        for invite: SocialInvite,
        transport: any SocialRelayTransporting,
        inboundSource: any SocialRelayInboundStreaming,
        onInboundProcessed: @escaping @Sendable () async -> Void = { }
    ) throws -> SocialRelaySessionRuntime? {
        guard configuration.relayEnabled else { return nil }
        // Bound to the session and topic so outbound payloads are sealed in the v2 format, whose GCM tag
        // covers both. Inbound still accepts v1 for sessions minted by an earlier build.
        let cipher = try SocialEnvelopeCipher(
            base64EncodedSessionKey: invite.encryptedSessionKey,
            sessionID: invite.sessionID,
            relayTopic: invite.relayTopic
        )
        // The binding the coordinator's single `cipher` has always implied, now stated. This is the
        // layer that owns the keys, so it is the layer that gets to fan out across sessions — one
        // runtime per invite, each scoped to the session it can actually speak for.
        let coordinator = SocialRelayCoordinator(
            configuration: configuration,
            eventLogStore: eventLogStore,
            transport: transport,
            cipher: cipher,
            boundSessionID: invite.sessionID,
            boundTopic: invite.relayTopic,
            diagnostics: diagnostics
        )
        let pump = SocialRelayInboundPump(
            coordinator: coordinator,
            source: inboundSource,
            onProcessed: onInboundProcessed
        )
        return SocialRelaySessionRuntime(coordinator: coordinator, pump: pump)
    }

    /// Production convenience: wires the live WalletConnect/IRN transport and inbound source over one
    /// relay client. `onInboundProcessed` is the reconcile hook for a session's queue coordinator.
    /// - Parameter broadcaster: the shared fan-out over `relayClient`'s unicast event stream. Taken as
    ///   a parameter rather than built here so that every session on one relay client reads from the
    ///   *same* broadcaster — building one per session would reintroduce the competing-iterator bug
    ///   this type exists to avoid. See ``SocialRelayInboundBroadcaster``.
    func makeSession(
        for invite: SocialInvite,
        relayClient: WalletConnectIRNRelayClient,
        broadcaster: SocialRelayInboundBroadcaster,
        onInboundProcessed: @escaping @Sendable () async -> Void = { }
    ) throws -> SocialRelaySessionRuntime? {
        try makeSession(
            for: invite,
            transport: WalletConnectSocialRelayTransport(relayClient: relayClient),
            inboundSource: WalletConnectSocialRelayInboundSource(broadcaster: broadcaster),
            onInboundProcessed: onInboundProcessed
        )
    }
}
